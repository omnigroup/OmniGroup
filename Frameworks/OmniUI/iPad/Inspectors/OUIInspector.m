// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspector.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

OBDEPRECATED_METHODS(OUIInspectorDelegate)
- (NSString *)inspectorTitle:(OUIInspector *)inspector; // --> inspector:titleForPane:, taking an OUIInspectorPane
- (NSArray *)inspectorSlices:(OUIInspector *)inspector; // --> inspector:makeAvailableSlicesForStackedSlicesPane:, taking an OUIStackedSlicesInspectorPane
- (NSArray *)inspector:(OUIInspector *)inspector slicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane; // -> -inspector:makeAvailableSlicesForStackedSlicesPane:
- (void)updateInterfaceFromInspectedObjects; // -> -updateInterfaceFromInspectedObjects:
@end

@interface OUIInspectorPopoverController : UIPopoverController
@property(nonatomic,assign) BOOL lockContentSize;
@end
@implementation OUIInspectorPopoverController

// Allow the inspector to prevent extra animation resizing passes when toggling the toolbar on/off.
// This doesn't look great either (some of the popover's dark background can show through), but it is less bad.
@synthesize lockContentSize = _lockContentSize;

- (void)setPopoverContentSize:(CGSize)popoverContentSize animated:(BOOL)animated;
{
    if (!_lockContentSize)
        [super setPopoverContentSize:popoverContentSize animated:animated];
}
- (void)setPopoverContentSize:(CGSize)popoverContentSize;
{
    if (!_lockContentSize)
        [super setPopoverContentSize:popoverContentSize];
}
@end

@interface OUIInspectorNavigationController : UINavigationController
@end

@implementation OUIInspectorNavigationController
- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];
    
    // Clear the selection from all the panes we've pushed. The objects in question could go away at any time and there is no reason for us to be observing or holding onto them! Clear stuff in reverse order (tearing down the opposite of setup).
    for (OUIInspectorPane *pane in [self.viewControllers reverseObjectEnumerator]) {
        pane.inspectedObjects = nil;
        [pane updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
    }
}
@end


@interface OUIInspector (/*Private*/) <UIPopoverControllerDelegate, UINavigationControllerDelegate>
- (void)_configureTitleForPane:(OUIInspectorPane *)pane;
- (BOOL)_prepareToInspectObjects:(NSArray *)objects;
- (void)_startObserving;
- (void)_stopObserving;
- (void)_keyboardDidHide:(NSNotification *)note;
@end

// Might want to make this variable, but at least let's only hardcode it in one spot. Popovers are required to be between 320 and 600; let's shoot for the minimum.
const CGFloat OUIInspectorContentWidth = 320;

NSString * const OUIInspectorDidPresentNotification = @"OUIInspectorDidPresentNotification";

NSString * const OUIInspectorWillBeginChangingInspectedObjectsNotification = @"OUIInspectorWillBeginChangingInspectedObjectsNotification";
NSString * const OUIInspectorDidEndChangingInspectedObjectsNotification = @"OUIInspectorDidEndChangingInspectedObjectsNotification";

@implementation OUIInspector

+ (UIBarButtonItem *)inspectorBarButtonItemWithTarget:(id)target action:(SEL)action;
{
    UIImage *image = [UIImage imageNamed:@"OUIToolbarInfo.png"];
    OBASSERT(image);
    return [[[OUIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:target action:action] autorelease];
}

+ (UIColor *)disabledLabelTextColor;
{
    return [UIColor colorWithHue:kOUIInspectorLabelTextColor.h saturation:kOUIInspectorLabelTextColor.s brightness:kOUIInspectorLabelTextColor.v alpha:kOUIInspectorLabelDisabledTextColorAlphaScale * kOUIInspectorLabelTextColor.a];
}

+ (UIColor *)labelTextColor;
{
    return [UIColor colorWithHue:kOUIInspectorLabelTextColor.h saturation:kOUIInspectorLabelTextColor.s brightness:kOUIInspectorLabelTextColor.v alpha:kOUIInspectorLabelTextColor.a];
}

+ (UIFont *)labelFont;
{
    return [UIFont boldSystemFontOfSize:20];
}

- init;
{
    return [self initWithMainPane:nil height:400];
}

- initWithMainPane:(OUIInspectorPane *)mainPane height:(CGFloat)height;
{
    if (!(self = [super init]))
        return nil;
    
    _height = height;
    
    if (mainPane)
        _mainPane = [mainPane retain];
    else
        _mainPane = [[OUIStackedSlicesInspectorPane alloc] init];

    _mainPane.inspector = self;
    
    // Avoid loading the view until it is needed. The inspectors themselves should do this.
    //_mainPane.view.frame = CGRectMake(0, 0, OUIInspectorContentWidth, 16);
        
    if (!_navigationController && [self isEmbededInOtherNavigationController] == NO) {
        _navigationController = [[OUIInspectorNavigationController alloc] initWithRootViewController:_mainPane];
        _navigationController.delegate = self;
        _navigationController.toolbarHidden = NO;
    }

    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    _popoverController.delegate = nil;
    [_popoverController release];

    // Trying to fix a (possible) retain cycle but this doesn't help.
//    [_navigationController.view removeFromSuperview];
//    _navigationController.view = nil;
    _navigationController.delegate = nil;
    [_navigationController release];
    
    _mainPane.inspector = nil;
    [_mainPane release];
    [super dealloc];
}

- (OUIInspectorPane *)mainPane;
{
    OBPRECONDITION(_mainPane);
    return _mainPane;
}

@synthesize height = _height;
@synthesize delegate = _nonretained_delegate;

// Subclass to return YES if you intend to embed the inspector into a your own navigation controller.
- (BOOL)isEmbededInOtherNavigationController;
{
    return NO;
}

- (UINavigationController *)embeddingNavigationController;
{
    return nil;
}

- (BOOL)isVisible;
{
    OBPRECONDITION([self isEmbededInOtherNavigationController] == NO); // need to be smarter here if we are embedded
    
    return _popoverController.isPopoverVisible;
}

- (BOOL)inspectObjects:(NSArray *)objects fromBarButtonItem:(UIBarButtonItem *)item;
{    
    if (![self _prepareToInspectObjects:objects])
        return NO;

    // In the embedding case, the 'from whatever' arguments are irrelevant. We assumed the embedding navigation controller is going to be made visibiel somehow.
    if ([self isEmbededInOtherNavigationController] == NO) {
        if (![[OUIAppController controller] presentPopover:_popoverController fromBarButtonItem:item permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES])
            return NO;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInspectorDidPresentNotification object:self];
    return YES;
}

- (BOOL)inspectObjects:(NSArray *)objects fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections;
{    
    if (![self _prepareToInspectObjects:objects])
        return NO;
    
    // In the embedding case, the 'from whatever' arguments are irrelevant. We assumed the embedding navigation controller is going to be made visibiel somehow.
    if ([self isEmbededInOtherNavigationController] == NO) {
        if (![[OUIAppController controller] presentPopover:_popoverController fromRect:rect inView:view permittedArrowDirections:arrowDirections animated:YES])
            return NO;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInspectorDidPresentNotification object:self];
    return YES;
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [self.topVisiblePane updateInterfaceFromInspectedObjects:reason];
}

- (void)dismiss;
{
    [self dismissAnimated:YES];
}

- (void)dismissAnimated:(BOOL)animated;
{
    if (!_popoverController)
        return;
    
    [[OUIAppController controller] dismissPopover:_popoverController animated:animated];
}

- (NSArray *)makeAvailableSlicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane;
{
    if ([_nonretained_delegate respondsToSelector:@selector(inspector:makeAvailableSlicesForStackedSlicesPane:)])
        return [_nonretained_delegate inspector:self makeAvailableSlicesForStackedSlicesPane:pane];
    return nil;
}

static UINavigationController *_getNavigationController(OUIInspector *self)
{
    if (self->_navigationController) {
        OBASSERT([self isEmbededInOtherNavigationController] == NO);
        return self->_navigationController;
    } else {
        OBASSERT([self isEmbededInOtherNavigationController] == YES);
        
        // Can't use the _mainPane's navigationController (at least in the one embedding case we have now in OmniGraffle). The issue is that the mainPane doesn't get pushed on the nav controller stack owned by OmniGraffle in all cases. In some cases, its view is stolen and combined with other views (not great, but that's the way it is now).
        //UINavigationController *nc = [self->_mainPane navigationController];
        UINavigationController *nc = [self embeddingNavigationController];
        return nc;
    }
}

static void _configureContentSize(OUIInspector *self, UIViewController *vc, CGFloat height, BOOL animated)
{
    const CGFloat toolbarHeight = 38;

    BOOL wantsToolbar = ([[vc toolbarItems] count] > 0);
    if (wantsToolbar)
        height -= toolbarHeight;
    
    self->_popoverController.lockContentSize = YES;
    {
        vc.contentSizeForViewInPopover = CGSizeMake(OUIInspectorContentWidth, height);
        
        [self->_navigationController setToolbarHidden:!wantsToolbar animated:animated];
    }
    self->_popoverController.lockContentSize = NO;
    
    // This is necessary to reset the popover size if it is dismissed while the keyboard is up. It doesn't automatically fix this on itself. See <bug:///71703> (Popover doesn't restore size when closed with keyboard up)
    // Actually, this makes the popover content controller by 1 border width (~8px) w/o being clipped by the popover. <bug:///71895> (Inspector grows slightly 2nd time opening it and background doesn't fill in the space)
    // Instead, we now track keyboard visibility and avoid closing if we are editing text (see the life of the _keyboardShownWhilePopoverVisible ivar).
    //[self->_popoverController setPopoverContentSize:self->_navigationController.contentSizeForViewInPopover animated:animated];    
}

- (void)pushPane:(OUIInspectorPane *)pane inspectingObjects:(NSArray *)inspectedObjects animated:(BOOL)animated;
{
    OBPRECONDITION(pane);
    
    UINavigationController *navigationController = _getNavigationController(self);
    OBASSERT(navigationController);
    
    if (!inspectedObjects)
        inspectedObjects = self.topVisiblePane.inspectedObjects;
    OBASSERT([inspectedObjects count] > 0);
    
    pane.inspector = self;
    pane.inspectedObjects = inspectedObjects;
    
    [self _configureTitleForPane:pane];
    
    [navigationController pushViewController:pane animated:animated];
}

- (void)pushPane:(OUIInspectorPane *)pane inspectingObjects:(NSArray *)inspectedObjects;
{
    [self pushPane:pane inspectingObjects:inspectedObjects animated:YES];
}

- (void)pushPane:(OUIInspectorPane *)pane;
{
    [self pushPane:pane inspectingObjects:nil];
}

- (OUIInspectorPane *)topVisiblePane;
{
    UINavigationController *navigationController = _getNavigationController(self);
    if (!navigationController) {
        return _mainPane; // This can happen when we are called to update the inspected objects in the embedded case (OmniGraffle).
    }
    
    for (UIViewController *vc in [navigationController.viewControllers reverseObjectEnumerator]) {
        if ([vc isKindOfClass:[OUIInspectorPane class]])
            return (OUIInspectorPane *)vc;
    }
    
    // This can happen when we are on the main pane, but it isn't pushed on the embedding navigation controller's stack. OmniGraffle just steals its view and combines it with other views in its view controller. Not great, but that's how it is currently (would be nicer if it just used an OUIInspectorPane or not for each view controller).
    return _mainPane;
}

- (void)willBeginChangingInspectedObjects;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInspectorWillBeginChangingInspectedObjectsNotification object:self];
}

- (void)didEndChangingInspectedObjects;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInspectorDidEndChangingInspectedObjectsNotification object:self];
    
    // Update the inspector for these changes. In particular if the current pane is a stacked slices inspector, we want the other slices to be able to react to this change.
    [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonObjectsEdited];
}

- (void)beginChangeGroup;
{
    
}

- (void)endChangeGroup;
{
    
}

#pragma mark -
#pragma mark UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    // This delegate method gets called before the pane is queried for its popover content size but before -viewWillAppear: is called.
    // Need to make sure that the content size is correct, and as part of that, we send the pane -inspectorWillShow: to let it configure toolbar items.
    
    // Let the pane configure toolbar items based on the selection, or whatever
    if ([viewController isKindOfClass:[OUIInspectorPane class]])
        [(OUIInspectorPane *)viewController inspectorWillShow:self];
    
    _configureContentSize(self, viewController, _height, animated);
}

#pragma mark -
#pragma mark UIPopoverControllerDelegate

- (BOOL)popoverControllerShouldDismissPopover:(UIPopoverController *)popoverController;
{
    // If we started editing a text field in the popover, the first tap out of the popover should just stop editing that field.
    // Also, closing the keyboard and the popover at the same time leads to terrible sizing problems.
    if (_keyboardShownWhilePopoverVisible) {
        // You'd think this would always return YES, but the second time it is run, it returns NO, unless you've tapped in a text field in the inspector or something.
        // Presumably if the first responder isn't in the view at all, it returns NO instead of returning "YES, whatever".
        [popoverController.contentViewController.view endEditing:YES/*force*/];
        
        // This *should* get cleared by the keyboard closing, but let's just be sure we don't get stuck with the popover open.
        _keyboardShownWhilePopoverVisible = NO;
        
        return NO;
    }
    
    return YES;
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController;
{
    // NOTE: This method gets called when the dismisal animation starts, not when it is done. So, we defer clearing the inspected objects/views/slices until our UINavigationController's -viewDidDisappear:. Otherwise we'll animate out an empty background.
    
    [self _stopObserving];

    [_nonretained_delegate inspectorDidDismiss:self];
}

#pragma mark -
#pragma mark Private

- (void)_configureTitleForPane:(OUIInspectorPane *)pane;
{
    NSString *title = nil;
    if ([_nonretained_delegate respondsToSelector:@selector(inspector:titleForPane:)])
        title = [_nonretained_delegate inspector:self titleForPane:pane];
    if (!title)
        title = pane.title;
    if (!title)
        title = pane.parentSlice.title;
    if (!title) {
        OBASSERT_NOT_REACHED("Either need to manually set a title on the inspector pane or provide one with the delegate.");
    }
    pane.title = title;
}

- (BOOL)_prepareToInspectObjects:(NSArray *)objects;
{
    OBPRECONDITION([objects count] > 0);
    OBPRECONDITION(_mainPane);
    
    BOOL embedded = [self isEmbededInOtherNavigationController];
    
    if (embedded == NO && _popoverController.isPopoverVisible) {
        [self dismissAnimated:YES]; // Like iWork, pop inspectors in, but fade them out.
        return NO;
    }
    
    _mainPane.inspectedObjects = objects;
    
    [self _configureTitleForPane:_mainPane];
    
    [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
    
    // We *MUST* reuse our popover currently. In the past we've not been able to reuse them due to sizing oddities, but we no longer resize our popovers. Also, since we can potentially reuse our panes/slices, if you open an inspector, then quickly tap it closed and reopen, the old popover could not be done animating out before the new one tried to steal the panes/slices. This left them in a confused state. This all seems to work fine if we reuse our popover. See <bug:///71345> (Tapping between the two popover quickly can give you a blank inspector).
    if (embedded == NO) {
        // TODO: Assuming we aren't on screen.
        [_navigationController popToRootViewControllerAnimated:NO];
        
        [self dismiss];
        
        // The popover controller will read the nav controller's contentSizeForViewInPopover as soon as it is created (and it will read the top view controller's)
        _configureContentSize(self, _mainPane, _height, NO);
        
        if (_popoverController == nil) {
            _popoverController = [[OUIInspectorPopoverController alloc] initWithContentViewController:_navigationController];
            _popoverController.delegate = self;
        }
         
        [self _startObserving]; // Inside the embedded check since this just signs up for notifications that will fix our popover size, but that isn't our problem if we are embedded
    } else {
        OBASSERT(_navigationController == nil);
    }

    return YES;
}

- (void)_startObserving;
{
    if (!_isObservingNotifications) {
        _isObservingNotifications = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    }
}

- (void)_stopObserving;
{
    if (_isObservingNotifications) {
        _isObservingNotifications = NO;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidHideNotification object:nil];
    }
}

- (void)_keyboardDidShow:(NSNotification *)note;
{
    _keyboardShownWhilePopoverVisible = YES;
    
}
- (void)_keyboardDidHide:(NSNotification *)note;
{
    _keyboardShownWhilePopoverVisible = NO;
}

@end

@implementation NSObject (OUIInspectable)

- (BOOL)shouldBeInspectedByInspectorSlice:(OUIInspectorSlice *)inspector protocol:(Protocol *)protocol;
{
    return [self conformsToProtocol:protocol];
}

@end
