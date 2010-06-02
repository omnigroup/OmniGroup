// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspector.h>

#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspectorDetailSlice.h>
#import "OUIInspectorStack.h"
#import <UIKit/UIKit.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OUIInspector (/*Private*/) <UIPopoverControllerDelegate, UINavigationControllerDelegate>
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
    UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    infoButton.frame = CGRectMake(0, 0, 44, 44); // TODO: -sizeToFit makes this too small. No luck making a UIButton subclass that implements the various sizing methods
    [infoButton addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return [[[UIBarButtonItem alloc] initWithCustomView:infoButton] autorelease];
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_inspectedObjects release];
    
    _popoverController.delegate = nil;
    [_popoverController release];

    // Trying to fix a (possible) retain cycle but this doesn't help.
//    [_navigationController.view removeFromSuperview];
//    _navigationController.view = nil;
    _navigationController.delegate = nil;
    [_navigationController release];
    
    _stack.inspector = nil;
    [_stack release];
    [super dealloc];
}

@synthesize delegate = _nonretained_delegate;
@synthesize inspectedObjects = _inspectedObjects;
@synthesize hasDismissButton = _shouldShowDismissButton;

- (BOOL)isEmbededInOtherNavigationController;
{
    return NO;
}

- (BOOL)isVisible;
{
    return _popoverController.isPopoverVisible;
}

- (void)inspectObjects:(NSSet *)objects fromBarButtonItem:(UIBarButtonItem *)item;
{
    _shouldShowDismissButton = NO;
    
    if (![self _prepareToInspectObjects:objects])
        return;

    [_popoverController presentPopoverFromBarButtonItem:item permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
    
    [self _configurePopoverSize]; // Hack. w/o this the first time we display we can end up the wrong size.
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInspectorDidPresentNotification object:self];
}

- (void)inspectObjects:(NSSet *)objects fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections;
{
    _shouldShowDismissButton = YES;
    
    if (![self _prepareToInspectObjects:objects])
        return;
    
    [_popoverController presentPopoverFromRect:rect inView:view permittedArrowDirections:arrowDirections animated:YES];
    
    [self _configurePopoverSize]; // Hack. w/o this the first time we display we can end up the wrong size.
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInspectorDidPresentNotification object:self];
}

- (void)updateInterfaceFromInspectedObjects
{
    [_stack.slices makeObjectsPerformSelector:@selector(updateInterfaceFromInspectedObjects)];
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

- (void)pushDetailSlice:(OUIInspectorDetailSlice *)detail;
{
    OBPRECONDITION(detail);
    
    [_navigationController pushViewController:detail animated:YES];
    [detail wasPushed];
}

- (void)popDetailSlice;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)inspectorSizeChanged;
{
    [_stack layoutSlices];
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

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    // Coming back to a main inspector after having changed something in details. This is implemented by details too, might be useful in that case if we stop sending update requests to details that aren't visible (which seems good, really).
    [(OUIInspectorStack *)viewController updateInterfaceFromInspectedObjects];
}

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
    return [popoverController.contentViewController.view endEditing:YES/*force*/];
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

- (BOOL)_prepareToInspectObjects:(NSSet *)objects
{
    if (_popoverController.isPopoverVisible) {
        [self dismiss];
        return NO;
    }
    
    [self _makeInterface];
    
    [_inspectedObjects release];
    _inspectedObjects = [[NSSet alloc] initWithSet:objects];
    
    _stack.title = [_nonretained_delegate inspectorTitle:self];
    NSArray *slices = [_nonretained_delegate inspectorSlices:self];
    if ([slices count] == 0) {
        [self dismiss];
        return NO;
    }
    _stack.slices = slices;
    [self updateInterfaceFromInspectedObjects];
    
    // TODO: Assuming we aren't on screen.
    [_navigationController popToRootViewControllerAnimated:NO];
    
    // We cannot reuse popovers, as far as I can tell. It caches the old -contentSizeForViewInPopover and doesn't requery the next time it is presented.
    if (![self isEmbededInOtherNavigationController]) {
        [self dismiss];
        
        _popoverController = [[UIPopoverController alloc] initWithContentViewController:_navigationController];
        _popoverController.delegate = self;
    }
    
    [self _startObserving];
    
    [self _configurePopoverSize];
    
    return YES;
}

- (void)_makeInterface;
{
    if (_navigationController)
        return;
    
    _stack = [[OUIInspectorStack alloc] init];
    _stack.inspector = self;
    
    if (![self isEmbededInOtherNavigationController]) {
        _navigationController = [[UINavigationController alloc] initWithRootViewController:_stack];
        _navigationController.delegate = self;
    }
    
    _stack.view.frame = CGRectMake(0, 0, OUIInspectorContentWidth, 16);
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
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    }
}

- (void)_keyboardDidHide:(NSNotification *)note;
{
    // If we got squished, try to grow back to the right size.
    [self _configurePopoverSize];
}

- (void)_configurePopoverSize;
{
    // If you return YES to this, you need to override this method too to fix *your* popover controller's size
    OBPRECONDITION(![self isEmbededInOtherNavigationController]);
    
    
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
