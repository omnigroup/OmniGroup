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

#import "OUIParameters.h"

RCS_ID("$Id$");

OBDEPRECATED_METHODS(OUIInspectorDelegate)
- (NSString *)inspectorTitle:(OUIInspector *)inspector; // --> inspector:titleForPane:, taking an OUIInspectorPane
- (NSArray *)inspectorSlices:(OUIInspector *)inspector; // --> inspector:slicesForStackedSlicesPane:, taking an OUIStackedSlicesInspectorPane
@end

@interface OUIInspector (/*Private*/) <UIPopoverControllerDelegate, UINavigationControllerDelegate>
- (void)_configureTitleForPane:(OUIInspectorPane *)pane;
- (BOOL)_configureSlicesForPane:(OUIInspectorPane *)pane;
- (BOOL)_prepareToInspectObjects:(NSSet *)objects;
- (void)_makeInterface;
- (void)_startObserving;
- (void)_stopObserving;
- (void)_keyboardDidHide:(NSNotification *)note;
- (void)_configurePopoverSize;
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

+ (UIColor *)labelTextColor;
{
    return [UIColor colorWithHue:kOUIInspectorLabelTextColor.h saturation:kOUIInspectorLabelTextColor.s brightness:kOUIInspectorLabelTextColor.v alpha:kOUIInspectorLabelTextColor.a];
}

+ (UIFont *)labelFont;
{
    return [UIFont boldSystemFontOfSize:20];
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

- (BOOL)inspectObjects:(NSSet *)objects fromBarButtonItem:(UIBarButtonItem *)item;
{    
    if (![self _prepareToInspectObjects:objects])
        return NO;

    // In the embedding case, the 'from whatever' arguments are irrelevant. We assumed the embedding navigation controller is going to be made visibiel somehow.
    if ([self isEmbededInOtherNavigationController] == NO) {
        if (![[OUIAppController controller] presentPopover:_popoverController fromBarButtonItem:item permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES])
            return NO;
            
        [self _configurePopoverSize]; // Hack. w/o this the first time we display we can end up the wrong size.
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInspectorDidPresentNotification object:self];
    return YES;
}

- (BOOL)inspectObjects:(NSSet *)objects fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections;
{    
    if (![self _prepareToInspectObjects:objects])
        return NO;
    
    // In the embedding case, the 'from whatever' arguments are irrelevant. We assumed the embedding navigation controller is going to be made visibiel somehow.
    if ([self isEmbededInOtherNavigationController] == NO) {
        if (![[OUIAppController controller] presentPopover:_popoverController fromRect:rect inView:view permittedArrowDirections:arrowDirections animated:YES])
            return NO;
    
        [self _configurePopoverSize]; // Hack. w/o this the first time we display we can end up the wrong size.
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInspectorDidPresentNotification object:self];
    return YES;
}

- (void)updateInterfaceFromInspectedObjects
{
    [self.topVisiblePane updateInterfaceFromInspectedObjects];
}

- (void)dismiss;
{
    [self dismissAnimated:YES];
}

- (void)dismissAnimated:(BOOL)animated;
{
    if (!_popoverController)
        return;
    [_popoverController dismissPopoverAnimated:NO];
    [_popoverController release];
    _popoverController = nil;
    
    [_nonretained_delegate inspectorDidDismiss:self];
}

- (NSArray *)slicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane;
{
    NSArray *slices = nil;
    
    if ([_nonretained_delegate respondsToSelector:@selector(inspector:slicesForStackedSlicesPane:)])
        slices = [_nonretained_delegate inspector:self slicesForStackedSlicesPane:pane];
    if (!slices)
        slices = pane.slices; // manually configured slices?
    return slices;
}

- (OUIStackedSlicesInspectorPane *)mainPane;
{
    if (!_mainPane)
        [self _makeInterface];

    return _mainPane;
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

- (void)pushPane:(OUIInspectorPane *)pane inspectingObjects:(NSSet *)inspectedObjects;
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
    
    if (![self _configureSlicesForPane:pane])
        return;
    
    [navigationController pushViewController:pane animated:YES];
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

- (void)inspectorSizeChanged;
{
    OBFinishPortingLater("Avoid the class check here by adding some API to OUIInspectorPane?");
    OUIInspectorPane *topVisiblePane = self.topVisiblePane;
    if ([topVisiblePane isKindOfClass:[OUIStackedSlicesInspectorPane class]])
        [(OUIStackedSlicesInspectorPane *)topVisiblePane inspectorSizeChanged];
    
    [self _configurePopoverSize];
}

- (void)willBeginChangingInspectedObjects;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInspectorWillBeginChangingInspectedObjectsNotification object:self];
}

- (void)didEndChangingInspectedObjects;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInspectorDidEndChangingInspectedObjectsNotification object:self];
}

- (void)beginChangeGroup;
{
    
}

- (void)endChangeGroup;
{
    
}

#pragma mark -
#pragma mark UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    // Make sure the popover sizes back down when navigating away from a tall details view (it seems to grow correctly). Doing this in the 'will' hook doesn't make it the right size, clipping off some of the bottom.
    if (viewController)
        [self _configurePopoverSize];
}

#pragma mark -
#pragma mark UIPopoverControllerDelegate

- (BOOL)popoverControllerShouldDismissPopover:(UIPopoverController *)popoverController;
{
    // You'd think this would always return YES, but the second time it is run, it returns NO, unless you've tapped in a text field in the inspector or something.
    // Presumably if the first responder isn't in the view at all, it returns NO instead of returning "YES, whatever".
    [popoverController.contentViewController.view endEditing:YES/*force*/];
    return YES;
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController;
{
    [_popoverController release];
    _popoverController = nil;
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
    if (!title) {
        OBASSERT_NOT_REACHED("Either need to manually set a title on the inspector pane or provide one with the delegate.");
    }
    pane.title = title;
}
- (BOOL)_configureSlicesForPane:(OUIInspectorPane *)pane;
{
    if (![pane isKindOfClass:[OUIStackedSlicesInspectorPane class]])
        return YES; // nothing to do.
    
    OUIStackedSlicesInspectorPane *stackedPane = (OUIStackedSlicesInspectorPane *)pane;
    
    NSArray *slices = [self slicesForStackedSlicesPane:stackedPane];
    if ([slices count] == 0) {
        OBASSERT_NOT_REACHED("No slices found for stacked pane.");
        return NO;
    }
    stackedPane.slices = slices;
    return YES;
}

- (BOOL)_prepareToInspectObjects:(NSSet *)objects;
{
    OBPRECONDITION([objects count] > 0);
    
    BOOL embedded = [self isEmbededInOtherNavigationController];
    
    if (embedded == NO && _popoverController.isPopoverVisible) {
        [self dismiss];
        return NO;
    }
    
    [self _makeInterface];
    
    _mainPane.inspectedObjects = objects;
    
    [self _configureTitleForPane:_mainPane];
    
    if (![self _configureSlicesForPane:_mainPane]) {
        [self dismiss];
        return NO;
    }

    [self updateInterfaceFromInspectedObjects];
    
    // We cannot reuse popovers, as far as I can tell. It caches the old -contentSizeForViewInPopover and doesn't requery the next time it is presented.
    if (embedded == NO) {
        // TODO: Assuming we aren't on screen.
        [_navigationController popToRootViewControllerAnimated:NO];
        
        [self dismiss];
        
        _popoverController = [[UIPopoverController alloc] initWithContentViewController:_navigationController];
        _popoverController.delegate = self;

        [self _startObserving]; // Inside the embedded check since this just signs up for notifications that will fix our popover size, but that isn't our problem if we are embedded
        [self _configurePopoverSize];
    } else {
        OBASSERT(_navigationController == nil);
    }

    return YES;
}

- (void)_makeInterface;
{
    if (_mainPane)
        return;
    
    _mainPane = [[OUIStackedSlicesInspectorPane alloc] init];
    _mainPane.inspector = self;
    
    if ([self isEmbededInOtherNavigationController] == NO) {
        _navigationController = [[UINavigationController alloc] initWithRootViewController:_mainPane];
        _navigationController.delegate = self;
    }
    
    _mainPane.view.frame = CGRectMake(0, 0, OUIInspectorContentWidth, 16);
}

- (void)_startObserving;
{
    if (!_isObservingNotifications) {
        _isObservingNotifications = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    }
}

- (void)_stopObserving;
{
    if (_isObservingNotifications) {
        _isObservingNotifications = NO;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidHideNotification object:nil];
    }
}

- (void)_keyboardDidHide:(NSNotification *)note;
{
    // If we got squished, try to grow back to the right size.
    [self _configurePopoverSize];
}

- (void)_configurePopoverSize;
{
    // If you return an -alternateNavigationController, you need to fix *your* popover controller's size
    OBPRECONDITION([self isEmbededInOtherNavigationController] == NO);
    
    const CGFloat titleHeight = 37;
    
    // If a detail changes its view's height, adjusts its contentSizeForViewInPopover and then we call this, the nav controller still reports the same height.
    CGSize size = _navigationController.topViewController.contentSizeForViewInPopover;
    size.height += titleHeight;
    
    [_popoverController setPopoverContentSize:size animated:NO];
}

@end

@implementation NSObject (OUIInspectable)

- (BOOL)shouldBeInspectedByInspectorSlice:(OUIInspectorSlice *)inspector protocol:(Protocol *)protocol;
{
    return [self conformsToProtocol:protocol];
}

@end
