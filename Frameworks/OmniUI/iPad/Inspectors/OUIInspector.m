// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspector.h>

#import <OmniUI/OmniUI-Swift.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIInspectorPresentationController.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/UIViewController-OUIExtensions.h>

#import "OUIInspectorNavigationController.h"
#import "OUIParameters.h"

RCS_ID("$Id$");

// OUIInspectorDelegate
OBDEPRECATED_METHOD(-inspectorTitle:); // --> inspector:titleForPane:, taking an OUIInspectorPane
OBDEPRECATED_METHOD(-inspectorSlices:); // --> inspector:makeAvailableSlicesForStackedSlicesPane:, taking an OUIStackedSlicesInspectorPane
OBDEPRECATED_METHOD(-inspector:slicesForStackedSlicesPane:); // -> -inspector:makeAvailableSlicesForStackedSlicesPane:
OBDEPRECATED_METHOD(-updateInterfaceFromInspectedObjects); // -> -updateInterfaceFromInspectedObjects:

OBDEPRECATED_METHOD(-inspectObjects:withViewController:useFullScreenOnHorizontalCompact:useFullScreenOnHorizontalCompact fromBarButtonItem:); // --> -inspectObjects:
OBDEPRECATED_METHOD(-inspectObjects:withViewController:fromBarButtonItem:); // --> -inspectObjects:
OBDEPRECATED_METHOD(-inspectObjects:withViewController:fromRect:inView:useFullScreenOnHorizontalCompact:permittedArrowDirections:); // --> -inspectObjects:
OBDEPRECATED_METHOD(-inspectObjects:withViewController:fromRect:inView:permittedArrowDirections:); // --> -inspectObjects:
OBDEPRECATED_METHOD(-redisplayInspectorForNewTraitCollection:); // Methods dealing with presentation should be redirected to -[OUIInspector viewController]
OBDEPRECATED_METHOD(-dismissImmediatelyIfVisible); // Methods dealing with presentation should be redirected to -[OUIInspector viewController]
OBDEPRECATED_METHOD(-dismiss); // Methods dealing with presentation should be redirected to -[OUIInspector viewController]
OBDEPRECATED_METHOD(-dismissAnimated:); // Methods dealing with presentation should be redirected to -[OUIInspector viewController]

OBDEPRECATED_METHOD(-useFullScreenOnHorizontalCompact); // OUIInspector has been decoupled from its presentation style. To get the half-height inspector, assign an instance of OUIInspectorPresentationController as the presented view controller's transitioningDelegate.
OBDEPRECATED_METHOD(-setUseFullScreenOnHorizontalCompact:); // OUIInspector has been decoupled from its presentation style. To get the half-height inspector, assign an instance of OUIInspectorPresentationController as the presented view controller's transitioningDelegate.

@interface OUIInspector (/*Private*/) <UINavigationControllerDelegate, UIPopoverPresentationControllerDelegate>
- (void)_configureTitleForPane:(OUIInspectorPane *)pane;
- (void)_startObserving;
- (void)_stopObserving;
- (void)_keyboardDidHide:(NSNotification *)note;

@property(nonatomic, strong) OUIInspectorNavigationController *navigationController;

@property (readonly,retain) id <UIViewControllerAnimatedTransitioning> transition;
@property (readonly,retain) NSMutableArray *popTransitions;
@property (nonatomic,weak) UIBarButtonItem *popoverPresentingItem;
@property (nonatomic,weak) UIView *popoverSourceView;
@property (nonatomic,assign) CGRect popoverSourceRect;
@property (nonatomic,assign) UIPopoverArrowDirection popoverArrowDirections;
@end

// Variable now, should really be turned into an accessor instead of this global. Popovers are required to be between 320 and 600; let's shoot for the minimum.
// MT 8/20/15
const CGFloat OUIConstantInspectorWidth = 320;
CGFloat OUIInspectorContentWidth = OUIConstantInspectorWidth;

const NSTimeInterval OUICrossFadeDuration = 0.2;

NSString * const OUIInspectorWillBeginChangingInspectedObjectsNotification = @"OUIInspectorWillBeginChangingInspectedObjectsNotification";
NSString * const OUIInspectorDidEndChangingInspectedObjectsNotification = @"OUIInspectorDidEndChangingInspectedObjectsNotification";

@implementation OUIInspector
{
    // We hold onto this in case we don't have a _navigationController to retain it on our behalf (if we have -isEmbededInOtherNavigationController subclassed to return YES).
    OUIInspectorPane *_mainPane;
    CGFloat _height;
    BOOL _alwaysShowToolbar;
    
    OUIInspectorNavigationController *_navigationController;

    BOOL _isObservingNotifications;
    BOOL _keyboardShownWhilePopoverVisible;
}

+ (UIBarButtonItem *)inspectorBarButtonItemWithTarget:(id)target action:(SEL)action;
{
    UIImage *image = [UIImage imageNamed:@"OUIToolbarInfo" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    OBASSERT(image);
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:target action:action];
    return item;
}

+ (UIBarButtonItem *)inspectorOUIBarButtonItemWithTarget:(id)target action:(SEL)action;
{
    UIImage *image = [UIImage imageNamed:@"OUIToolbarInfo" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    OBASSERT(image);
    UIBarButtonItem *item = [[OUIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:target action:action];
    return item;
}

+ (UIColor *)backgroundColor;
{
    return [UIColor groupTableViewBackgroundColor];
}

+ (UIColor *)disabledLabelTextColor;
{
    return [UIColor colorWithHue:kOUIInspectorLabelTextColor.h saturation:kOUIInspectorLabelTextColor.s brightness:kOUIInspectorLabelTextColor.v alpha:kOUIInspectorLabelDisabledTextColorAlphaScale * kOUIInspectorLabelTextColor.a];
}

+ (UIColor *)labelTextColor;
{
    return [UIColor blackColor];
}

+ (UIFont *)labelFont;
{
    return [UIFont systemFontOfSize:[UIFont labelFontSize]];
}

+ (UIColor *)valueTextColor;
{
    return [UIColor blackColor];
}

+ (UIColor *)indirectValueTextColor;
{
    return [UIColor grayColor];
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
        _mainPane = mainPane;
    else
        _mainPane = [[OUIStackedSlicesInspectorPane alloc] init];

    _mainPane.inspector = self;
    
    // Avoid loading the view until it is needed. The inspectors themselves should do this.
    //_mainPane.view.frame = CGRectMake(0, 0, OUIInspectorContentWidth, 16);
    
    _navigationController = [[OUIInspectorNavigationController alloc] initWithRootViewController:_mainPane];
    _navigationController.delegate = self;
    _navigationController.toolbarHidden = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_multiPaneControllerWillShowPane:) name:OUIMultiPaneControllerWillShowPaneNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_multiPaneControllerWillPresentPane:) name:OUIMultiPaneControllerWillPresentPaneNotification object:nil];
    
    
    return self;
}

- (void)_multiPaneControllerWillShowPane:(NSNotification *)notification {
    NSNumber *paneLocationNumber = (NSNumber *)notification.userInfo[OUIMultiPaneControllerPaneLocationUserInfoKey];
    OUIMultiPaneLocation paneLocation = (OUIMultiPaneLocation)paneLocationNumber.integerValue;

    if (paneLocation == OUIMultiPaneLocationRight) {
        [self forceUpdateInspectedObjects];
    }
}
- (void)_multiPaneControllerWillPresentPane:(NSNotification *)notification {
    NSNumber *paneLocationNumber = (NSNumber *)notification.userInfo[OUIMultiPaneControllerPaneLocationUserInfoKey];
    OUIMultiPaneLocation paneLocation = (OUIMultiPaneLocation)paneLocationNumber.integerValue;
    
    if (paneLocation == OUIMultiPaneLocationRight) {
        [self forceUpdateInspectedObjects];
    }
}

- (UIViewController<OUIInspectorPaneContaining> *)viewController {
    return self.navigationController;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    _navigationController.delegate = nil;

    // Attempting to fix ARC weak reference cleanup crasher in <bug:///93163> (Crash after setting font color on Level 1 style)
    for (OUIInspectorPane *pane in _navigationController.viewControllers)
        pane.inspector = nil;
}

static CGFloat _currentDefaultInspectorContentWidth = 320;

+ (CGFloat)defaultInspectorContentWidth;
{
    return _currentDefaultInspectorContentWidth;
}

- (void)setDefaultInspectorContentWidth:(CGFloat)defaultInspectorContentWidth;
{
    _currentDefaultInspectorContentWidth = defaultInspectorContentWidth;
}

- (CGFloat)defaultInspectorContentWidth;
{
    return _currentDefaultInspectorContentWidth;
}

- (OUIInspectorPane *)mainPane;
{
    OBPRECONDITION(_mainPane);
    return _mainPane;
}

- (void)setShowDoneButton:(BOOL)shouldShow;
{
    [self _setShowDoneButton:shouldShow];
}

- (void)updateInspectedObjects {
    [self _updateInspectedObjects:NO];
}

- (void)forceUpdateInspectedObjects {
    [self _updateInspectedObjects:YES];
}

/// Updates the inspected objects only if self.viewController.view is visibly on screen, or if shouldForce is YES.
- (void)_updateInspectedObjects:(BOOL)shouldForce {
    UIViewController *viewController = self.viewController;
    UIView *inspectorView = (viewController.isViewLoaded) ? viewController.view : nil;
    UIWindow *window = inspectorView.window;
    
    if (!shouldForce && window == nil) {
        return;
    }
    
    CGRect translatedRect = [window convertRect:inspectorView.bounds fromView:inspectorView];
    BOOL isViewInWindow = CGRectIntersectsRect(translatedRect, window.bounds);
    
    // We only update the inspectedObjects if we are forcing an update or if the view is visually in the window.
    if (shouldForce || isViewInWindow) {
        NSArray *objects = [self.delegate objectsToInspectForInspector:self];
        self.mainPane.inspectedObjects = objects;
        
        if (!([self.delegate respondsToSelector:@selector(inspectorShouldMaintainStateWhileReopening:)] && [self.delegate inspectorShouldMaintainStateWhileReopening:self])) {
            [self.navigationController popToRootViewControllerAnimated:NO];
        }
    }
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [self.topVisiblePane updateInterfaceFromInspectedObjects:reason];
}

- (void)_setShowDoneButton:(BOOL)shouldShow;
{
    UIViewController *topController = [self.navigationController topViewController];
    NSMutableArray *items = [NSMutableArray arrayWithArray:topController.navigationItem.rightBarButtonItems];
    UIBarButtonItem *doneButton = nil;
    for (UIBarButtonItem *item in items) {
        if (item.action == @selector(_doneButtonTapped:)) {
            doneButton = item;
            break;
        }
    }
    if (shouldShow) {
        if (!doneButton) {
            doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(_doneButtonTapped:)];
            [items insertObject:doneButton atIndex:0];
            topController.navigationItem.rightBarButtonItems = items;
        }
    } else {
        if (doneButton) {
            [items removeObjectIdenticalTo:doneButton];
            topController.navigationItem.rightBarButtonItems = items;
        }
    }
}

- (void)_doneButtonTapped:(id)sender {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (NSArray *)makeAvailableSlicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane;
{
    id <OUIInspectorDelegate> delegate = self.delegate;
    
    if ([delegate respondsToSelector:@selector(inspector:makeAvailableSlicesForStackedSlicesPane:)])
        return [delegate inspector:self makeAvailableSlicesForStackedSlicesPane:pane];
    return nil;
}

- (void)pushPane:(OUIInspectorPane *)pane inspectingObjects:(NSArray *)inspectedObjects animated:(BOOL)animated;
{
    OBPRECONDITION(pane);
    OBASSERT(self.navigationController);
    
    if (!inspectedObjects)
        inspectedObjects = self.topVisiblePane.inspectedObjects;
    OBASSERT([inspectedObjects count] > 0);
    
    pane.inspector = self;
    pane.inspectedObjects = inspectedObjects;

    [self _configureTitleForPane:pane];
    
    [self.navigationController pushViewController:pane animated:animated];
}

- (void)pushPane:(OUIInspectorPane *)pane inspectingObjects:(NSArray *)inspectedObjects animated:(BOOL)animated withPushTransition:(id <UIViewControllerAnimatedTransitioning>)pushTransition popTransition:(id <UIViewControllerAnimatedTransitioning>)popTransition;
{
    _transition = pushTransition;
    [self pushPane:pane inspectingObjects:inspectedObjects animated:animated];
    _transition = nil;
    
    if (!_popTransitions)
        _popTransitions = [[NSMutableArray alloc] init];
    
    if (popTransition)
        [_popTransitions addObject:popTransition];
    else
        [_popTransitions addObject:[NSNull null]];
}

- (void)pushPane:(OUIInspectorPane *)pane inspectingObjects:(NSArray *)inspectedObjects;
{
    [self pushPane:pane inspectingObjects:inspectedObjects animated:YES withPushTransition:nil popTransition:nil];
}

- (void)pushPane:(OUIInspectorPane *)pane;
{
    [self pushPane:pane inspectingObjects:nil];
}

- (void)popToPane:(OUIInspectorPane *)pane;
{
    OBASSERT(self.navigationController);

    if (pane)
        [self.navigationController popToViewController:pane animated:YES];
    else
        [self.navigationController popToRootViewControllerAnimated:YES];
}

- (OUIInspectorPane *)topVisiblePane;
{
    // We give this navigation controller a rootViewController at creation and the pop API don't allow you to pop the root view controller. We should always have a view controller to return from here so we don't need to fall back to _mainPane.
    UIViewController *topViewController = self.navigationController.topViewController;
    OBASSERT([topViewController isKindOfClass:[OUIInspectorPane class]]);
    
    return (OUIInspectorPane *)topViewController;
}

- (void)willBeginChangingInspectedObjects;
{
    [self.topVisiblePane.view endEditing:YES];
    
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

#pragma mark UINavigationControllerDelegate
- (BOOL)_shouldShowDoneButton;
{
    UIViewController *mostDistantAncestor = [self.navigationController mostDistantAncestorViewController];
    BOOL isCurrentlyPresented = mostDistantAncestor.presentingViewController != nil;
    
    
    if (!isCurrentlyPresented) {
        return NO;
    }
    else {
        // View controllers seem to cache their presentationController/popoverPresentationController until the next time the presentation has been dismissed. Because of this, we guard the presentationController check until after we know the view controller is being presented.
        
        // By the time we get here, we know for sure we are currently being presented, so we just need to return wether we are using our custom presentation controller.
        BOOL shouldShowDoneButton = NO;
        
        UIViewController *presentingViewController = mostDistantAncestor.presentingViewController;
        
        BOOL isCustomPresentation = (mostDistantAncestor.modalPresentationStyle == UIModalPresentationCustom && [mostDistantAncestor.presentationController isKindOfClass:[OUIInspectorPresentationController class]]);
        
        BOOL isHorizontallyCompactPresentation = (presentingViewController.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact);
        
        BOOL isVerticallyCompactPresentation = (presentingViewController.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact);
        
        
        shouldShowDoneButton = isCustomPresentation ||
                            ([mostDistantAncestor.presentationController isKindOfClass:[UIPopoverPresentationController class]] &&(isHorizontallyCompactPresentation || isVerticallyCompactPresentation));
        
        return shouldShowDoneButton;
    }
}

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated NS_EXTENSION_UNAVAILABLE_IOS("");
{
    // This delegate method gets called before the pane is queried for its popover content size but before -viewWillAppear: is called.
    // Need to make sure that the content size is correct, and as part of that, we send the pane -inspectorWillShow: to let it configure toolbar items.
    
    // Let the pane configure toolbar items based on the selection, or whatever
    if ([viewController isKindOfClass:[OUIInspectorPane class]])
        [(OUIInspectorPane *)viewController inspectorWillShow:self];
    
    BOOL wantsToolbar = ([viewController.toolbarItems count] > 0);
    [navigationController setToolbarHidden:!wantsToolbar animated:animated];
    
    [self _setShowDoneButton:[self _shouldShowDoneButton]];
}

- (id <UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
                                   animationControllerForOperation:(UINavigationControllerOperation)operation
                                                fromViewController:(UIViewController *)fromVC
                                                  toViewController:(UIViewController *)toVC;
{
    if (operation == UINavigationControllerOperationPop) {
        id transition = [_popTransitions lastObject];
        if (transition == [NSNull null])
            transition = nil;
        [_popTransitions removeLastObject];
        return transition;
    }
    
    return self.transition;
}


- (void)_configureTitleForPane:(OUIInspectorPane *)pane;
{
    id <OUIInspectorDelegate> delegate = self.delegate;

    NSString *title = nil;
    if ([delegate respondsToSelector:@selector(inspector:titleForPane:)])
        title = [delegate inspector:self titleForPane:pane];
    if (!title)
        title = pane.title;
    if (!title)
        title = pane.parentSlice.title;
    if (!title) {
        OBASSERT_NOT_REACHED("Either need to manually set a title on the inspector pane or provide one with the delegate.");
    }
    pane.title = title;
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

#pragma mark - NSObject (OUIInspectable)
@implementation NSObject (OUIInspectable)

- (BOOL)shouldBeInspectedByInspectorSlice:(OUIInspectorSlice *)inspector protocol:(Protocol *)protocol;
{
    return [self conformsToProtocol:protocol];
}

@end
