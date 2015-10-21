// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspector.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIInspectorPresentationController.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

// OUIInspectorDelegate
OBDEPRECATED_METHOD(-inspectorTitle:); // --> inspector:titleForPane:, taking an OUIInspectorPane
OBDEPRECATED_METHOD(-inspectorSlices:); // --> inspector:makeAvailableSlicesForStackedSlicesPane:, taking an OUIStackedSlicesInspectorPane
OBDEPRECATED_METHOD(-inspector:slicesForStackedSlicesPane:); // -> -inspector:makeAvailableSlicesForStackedSlicesPane:
OBDEPRECATED_METHOD(-updateInterfaceFromInspectedObjects); // -> -updateInterfaceFromInspectedObjects:

@implementation OUIInspectorNavigationController

- (UIViewController *)childViewControllerForStatusBarHidden;
{
    return nil;
}

// We really only want to hide the status bar if we're not in a popover, but the system doesn't even ask if we are being presented in a popover. So we can just return YES unconditionally here.
- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidChangeFrame:) name:UIKeyboardDidChangeFrameNotification object:nil];
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];
    // Clear the selection from all the panes we've pushed. The objects in question could go away at any time and there is no reason for us to be observing or holding onto them! Clear stuff in reverse order (tearing down the opposite of setup).
    for (OUIInspectorPane *pane in [self.viewControllers reverseObjectEnumerator]) {
        if ([pane isKindOfClass:[OUIInspectorPane class]]) { // not all view controllers are panes - the image picker isn't!
            pane.inspectedObjects = nil;
            [pane updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDismissed];
        }
    }
}

- (void)keyboardWillShow:(NSNotification*)note
{
    if ([self _isCurrentlyPresentedWithCustomInspectorPresentation]) {
        // we might be in a partial height presentation and need to get taller
        OUIInspectorPresentationController *presentationController = (OUIInspectorPresentationController *)self.presentationController;
        NSNumber *duration = note.userInfo[UIKeyboardAnimationDurationUserInfoKey];
        NSNumber *curve = note.userInfo[UIKeyboardAnimationCurveUserInfoKey];
        NSValue *frame = note.userInfo[UIKeyboardFrameEndUserInfoKey];
        CGFloat height = [frame CGRectValue].size.height;
        UIViewAnimationOptions options = (curve.integerValue << 16) | UIViewAnimationOptionBeginFromCurrentState;  // http://macoscope.com/blog/working-with-keyboard-on-ios/  (Dec 20, 2013)
        __weak OUIInspectorNavigationController *weakSelf = self;
        if (!self.willDismissInspector){
            [presentationController presentedViewNowNeedsToGrowForKeyboardHeight:height withAnimationDuration:duration.floatValue options:options completion:^{
                OUIInspectorNavigationController *strongSelf = weakSelf;
                if (strongSelf) {
                    if ([strongSelf.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
                        [(OUIStackedSlicesInspectorPane*)strongSelf.topViewController updateContentInsetsForKeyboard];
                    }
                    [strongSelf adjustHeightOfGesturePassThroughView];
                }
            }];
        }
    } else {
        if ([self.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
            [(OUIStackedSlicesInspectorPane*)self.topViewController updateContentInsetsForKeyboard];
        }
    }
}

- (void)adjustHeightOfGesturePassThroughView
{
    CGRect frameOfGesturePassThrough = self.gesturePassThroughView.frame;
    frameOfGesturePassThrough.size.height = self.view.window.frame.size.height - self.view.frame.size.height;
    self.gesturePassThroughView.frame = frameOfGesturePassThrough;
}

- (void)keyboardWillHide:(NSNotification*)note
{
    if ([self _isCurrentlyPresentedWithCustomInspectorPresentation]) {
        // we might have been in a partial height presentation and need to get shorter
        OUIInspectorPresentationController *presentationController = (OUIInspectorPresentationController *)self.presentationController;
        NSNumber *duration = note.userInfo[UIKeyboardAnimationDurationUserInfoKey];
        NSNumber *curve = note.userInfo[UIKeyboardAnimationCurveUserInfoKey];
        UIViewAnimationOptions options = (curve.integerValue << 16) | UIViewAnimationOptionBeginFromCurrentState;  // http://macoscope.com/blog/working-with-keyboard-on-ios/  (Dec 20, 2013)
        self.gesturePassThroughView.hidden = NO;
        __weak OUIInspectorNavigationController *weakSelf = self;
        [presentationController presentedViewNowNeedsToGrowForKeyboardHeight:0 withAnimationDuration:duration.integerValue options:options completion:^{
            OUIInspectorNavigationController *strongSelf = weakSelf;
            if (strongSelf) {
                if ([strongSelf.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
                    [(OUIStackedSlicesInspectorPane*)strongSelf.topViewController updateContentInsetsForKeyboard];
                    [strongSelf adjustHeightOfGesturePassThroughView];
                }
            }
        }];
    } else {
        if ([self.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
            [(OUIStackedSlicesInspectorPane*)self.topViewController updateContentInsetsForKeyboard];
        }
    }
}

- (void)keyboardDidChangeFrame:(NSNotification*)note
{
    if ([self.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
        [(OUIStackedSlicesInspectorPane*)self.topViewController updateContentInsetsForKeyboard];
    }
}

- (BOOL)_isCurrentlyPresentedWithCustomInspectorPresentation;
{
    BOOL isCurrentlyPresented = self.presentingViewController != nil;
    
    if (!isCurrentlyPresented) {
        return NO;
    }
    else {
        // View controllers seem to cache their presentationController/popoverPresentationController until the next time the presentation has been dismissed. Because of this, we guard the presentationController check until after we know the view controller is being presented.
        
        // By the time we get here, we know for sure we are currently being presented, so we just need to return wether we are using our custom presentation controller.
        return (self.modalPresentationStyle == UIModalPresentationCustom && [self.presentationController isKindOfClass:[OUIInspectorPresentationController class]]);
    }
}

@end


@interface OUIInspector (/*Private*/) <UINavigationControllerDelegate, UIPopoverPresentationControllerDelegate>
- (void)_configureTitleForPane:(OUIInspectorPane *)pane;
- (void)_startObserving;
- (void)_stopObserving;
- (void)_keyboardDidHide:(NSNotification *)note;

@property (readonly,retain) id <UIViewControllerAnimatedTransitioning> transition;
@property (readonly,retain) NSMutableArray *popTransitions;
@property (nonatomic,strong) OUIInspectorOverlayTransitioningDelegate *inspectorTransitionDelegate;
@property (nonatomic,weak) UIViewController *viewController;
@property (nonatomic,weak) UIBarButtonItem *popoverPresentingItem;
@property (nonatomic,weak) UIView *popoverSourceView;
@property (nonatomic,assign) CGRect popoverSourceRect;
@property (nonatomic,assign) UIPopoverArrowDirection popoverArrowDirections;

@property (nonatomic, assign) BOOL shouldShowDoneButton;
@end

// Variable now, should really be turned into an accessor instead of this global. Popovers are required to be between 320 and 600; let's shoot for the minimum.
// MT 8/20/15
const CGFloat OUIConstantInspectorWidth = 320;
CGFloat OUIInspectorContentWidth = OUIConstantInspectorWidth;

const NSTimeInterval OUICrossFadeDuration = 0.2;

NSString * const OUIInspectorWillBeginChangingInspectedObjectsNotification = @"OUIInspectorWillBeginChangingInspectedObjectsNotification";
NSString * const OUIInspectorDidEndChangingInspectedObjectsNotification = @"OUIInspectorDidEndChangingInspectedObjectsNotification";
NSString * const OUIInspectorPopoverDidDismissNotification = @"OUIInspectorPopoverDidDismissNotification";

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

@synthesize navigationController = _navigationController;

+ (UIBarButtonItem *)inspectorBarButtonItemWithTarget:(id)target action:(SEL)action;
{
    UIImage *image = [UIImage imageNamed:@"OUIToolbarInfo.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    OBASSERT(image);
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:target action:action];
    return item;
}

+ (UIBarButtonItem *)inspectorOUIBarButtonItemWithTarget:(id)target action:(SEL)action;
{
    UIImage *image = [UIImage imageNamed:@"OUIToolbarInfo.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
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
    
    _shouldShowDoneButton = YES;
    _height = height;
    
    if (mainPane)
        _mainPane = mainPane;
    else
        _mainPane = [[OUIStackedSlicesInspectorPane alloc] init];

    _mainPane.inspector = self;
    
    // Avoid loading the view until it is needed. The inspectors themselves should do this.
    //_mainPane.view.frame = CGRectMake(0, 0, OUIInspectorContentWidth, 16);
        
    if (!_navigationController && [self isEmbededInOtherNavigationController] == NO) {
        _navigationController = [[OUIInspectorNavigationController alloc] initWithRootViewController:_mainPane];
        _navigationController.delegate = self;
        _navigationController.toolbarHidden = YES;
    }
    return self;
}

- (void)setGesturePassThroughView:(UIView *)gesturePassThroughView{
    _gesturePassThroughView = gesturePassThroughView;
    _navigationController.gesturePassThroughView = gesturePassThroughView;
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

- (void)_useDefaultInspectorContentWidth;
{
    UITraitCollection *traitCollection = self.viewController.traitCollection;

    if (traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular && traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact) {
        [self setDefaultInspectorContentWidth:414.0f];
    } else {
        [self setDefaultInspectorContentWidth:320.0f];
    }
}

- (OUIInspectorPane *)mainPane;
{
    OBPRECONDITION(_mainPane);
    return _mainPane;
}

@synthesize height = _height;
@synthesize delegate = _weak_delegate;
@synthesize alwaysShowToolbar = _alwaysShowToolbar;

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

    return self.navigationController.presentingViewController != nil;
}

/*
- (UIStatusBarStyle)preferredStatusBarStyle;
{
    return UIStatusBarStyleDefault;
}*/

- (BOOL)inspectObjects:(NSArray *)objects withViewController:(UIViewController *)viewController useFullScreenOnHorizontalCompact:(BOOL)useFullScreenOnHorizontalCompact traitCollection:(UITraitCollection *)traitCollection fromBarButtonItem:(UIBarButtonItem *)item NS_EXTENSION_UNAVAILABLE_IOS("Inspection is not available in extensions.");
{
    OBASSERT(viewController, @"Must provide a valid viewController");
    if (!viewController) {
        return NO;
    }
    
    self.viewController = viewController;
    self.popoverSourceView = nil;
    self.popoverPresentingItem = item;
    self.useFullScreenOnHorizontalCompact = useFullScreenOnHorizontalCompact;
    OBASSERT(viewController.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassUnspecified);
    
    self.mainPane.inspectedObjects = objects;
    self.shouldShowDoneButton = YES;
    
    [self updateInspectorWithTraitCollection:traitCollection];
    self.navigationController.popoverPresentationController.barButtonItem = item;
    self.navigationController.popoverPresentationController.delegate = self;
    
    if (!([self.delegate respondsToSelector:@selector(inspectorShouldMaintainStateWhileReopening:)] && [self.delegate inspectorShouldMaintainStateWhileReopening:self])) {
        [self.navigationController popToRootViewControllerAnimated:NO];
    }
    
    
    [viewController presentViewController:self.navigationController animated:YES completion:^{
        self.navigationController.popoverPresentationController.passthroughViews = nil;
        if (_presentInspectorCompletion) {
            _presentInspectorCompletion();
        }
    }];
    if (_animationsToPerformAlongsidePresentation) {
        [self.navigationController.transitionCoordinator animateAlongsideTransition:_animationsToPerformAlongsidePresentation completion:nil];
    }
    
    return YES;
}

- (BOOL)inspectObjects:(NSArray *)objects withViewController:(UIViewController *)viewController useFullScreenOnHorizontalCompact:(BOOL)useFullScreenOnHorizontalCompact fromBarButtonItem:(UIBarButtonItem *)item;
{
    return [self inspectObjects:objects withViewController:viewController useFullScreenOnHorizontalCompact:useFullScreenOnHorizontalCompact traitCollection:viewController.traitCollection fromBarButtonItem:item];
}

- (BOOL)inspectObjects:(NSArray *)objects withViewController:(UIViewController *)viewController fromBarButtonItem:(UIBarButtonItem *)item;
{
    return [self inspectObjects:objects withViewController:viewController useFullScreenOnHorizontalCompact:NO fromBarButtonItem:item];
}

- (void)_dismissInspectorAnimated:(BOOL)animated completion:(void (^)(void))completion;
{
    _navigationController.willDismissInspector = YES;
    if (self.animatingPushOrPop) {
        return;  // hack to prevent dismissing when a navigation controller transition animation is in progress because if we do, the _animationsToPerformAlongsideDismissal will be ignored and they are crucial to the app's functioning
    }
    OBASSERT(self.navigationController.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact);
    
    void (^totalCompletion)(void) = ^(void){
        if (_dismissInspectorCompletion)
        {
            _dismissInspectorCompletion();
        }
        if (completion) {
            completion();
        }
        _navigationController.willDismissInspector = NO;
    };
    [self.navigationController dismissViewControllerAnimated:animated completion: totalCompletion];

    if (animated && _animationsToPerformAlongsideDismissal) {
        id<UIViewControllerTransitionCoordinator> coordinator = self.navigationController.transitionCoordinator;
        if (coordinator) {
            [coordinator animateAlongsideTransition:_animationsToPerformAlongsideDismissal completion:nil];
        }
        else {
            _animationsToPerformAlongsideDismissal(nil /* we actually have no transitionCoordinator to pass in */);
        }
    }
}

- (void)_dismissInspector:(id)sender;
{
    [self dismissAnimated:YES];
}

- (BOOL)inspectObjects:(NSArray *)objects withViewController:(UIViewController *)viewController fromRect:(CGRect)rect inView:(UIView *)view useFullScreenOnHorizontalCompact:(BOOL)useFullScreenOnHorizontalCompact permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections;
{
    if ([self isEmbededInOtherNavigationController] == NO) {
        self.popoverSourceView = view;
        self.viewController = viewController;
        self.popoverSourceRect = rect;
        self.popoverArrowDirections = arrowDirections;
        self.useFullScreenOnHorizontalCompact = useFullScreenOnHorizontalCompact;
        OBASSERT(view.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassUnspecified);

        self.mainPane.inspectedObjects = objects;

        [self updateInspectorWithTraitCollection:view.traitCollection];
        self.navigationController.popoverPresentationController.sourceView = view;
        self.navigationController.popoverPresentationController.sourceRect = rect;
        
        if (!([self.delegate respondsToSelector:@selector(inspectorShouldMaintainStateWhileReopening:)] && [self.delegate inspectorShouldMaintainStateWhileReopening:self])) {
            [self.navigationController popToRootViewControllerAnimated:NO];
        }
        
        [viewController presentViewController:self.navigationController animated:YES completion:^{
            self.navigationController.popoverPresentationController.passthroughViews = nil;
        }];
    }
    return YES;
}

- (BOOL)inspectObjects:(NSArray *)objects withViewController:(UIViewController *)viewController fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections;
{
    return [self inspectObjects:objects withViewController:viewController fromRect:rect inView:view useFullScreenOnHorizontalCompact:NO permittedArrowDirections:arrowDirections];
}

- (void)redisplayInspectorForNewTraitCollection:(UITraitCollection *)traitCollection;
{
    NSArray *inspectedObjects = self.mainPane.inspectedObjects;
    [self _dismissInspectorAnimated:NO completion:^{
        UIViewController *strong_viewController = self.viewController;
        UIView *strong_popoverSourceView = self.popoverSourceView;

        if (strong_popoverSourceView && strong_viewController) {
            [self inspectObjects:inspectedObjects withViewController:strong_viewController fromRect:self.popoverSourceRect inView:strong_popoverSourceView useFullScreenOnHorizontalCompact:self.useFullScreenOnHorizontalCompact permittedArrowDirections:self.popoverArrowDirections];
        } else if (strong_viewController) {
            [self inspectObjects:inspectedObjects withViewController:strong_viewController useFullScreenOnHorizontalCompact:self.useFullScreenOnHorizontalCompact traitCollection:traitCollection fromBarButtonItem:self.popoverPresentingItem];
        } else {
            OBASSERT_NOT_REACHED(@"Inspector muast have either a view controller or an optional UIView defined.");
        }
    }];
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [self.topVisiblePane updateInterfaceFromInspectedObjects:reason];
}

- (void)dismissImmediatelyIfVisible;
{
    if (self.isVisible)
        [self dismissAnimated:NO];
}

- (void)dismiss;
{
    [self _dismissInspector:nil];
}

- (void)dismissAnimated:(BOOL)animated;
{
    if ([self.delegate respondsToSelector:@selector(inspectorWillDismiss:)]) {
        [self.delegate inspectorWillDismiss:self];
    }
    [self _dismissInspectorAnimated:animated completion:^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(inspectorDidDismiss:)]) {
            [self.delegate inspectorDidDismiss:self];
        }
    }];
}

- (void)_setShowDoneButton:(BOOL)shouldShow;
{
    UIViewController *topController = [self.navigationController topViewController];
    NSMutableArray *items = [NSMutableArray arrayWithArray:topController.navigationItem.rightBarButtonItems];
    UIBarButtonItem *doneButton = nil;
    for (UIBarButtonItem *item in items) {
        if (item.action == @selector(_dismissInspector:)) {
            doneButton = item;
            break;
        }
    }
    if (shouldShow) {
        if (!doneButton) {
            doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(_dismissInspector:)];
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

- (void)updateInspectorWithTraitCollection:(UITraitCollection *)traitsCollection;
{
    [self createFreshNavigationController];  // because iOS 9 doesn't correctly handle switching presentation styles, see related <bug:///116856> (Bug: Half-height inspector with selected text can appear in landscape on the 6+) and jake's rdar:///21189053 (Asking a view controller for its presentationController before changing it causes it to cache and use the 'old' one.)
    
    if (traitsCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact && !_useFullScreenOnHorizontalCompact) {
        self.inspectorTransitionDelegate = [[OUIInspectorOverlayTransitioningDelegate alloc] init];
        self.navigationController.transitioningDelegate = self.inspectorTransitionDelegate;
        self.navigationController.modalPresentationStyle = UIModalPresentationCustom;
    } else {
        self.navigationController.modalPresentationStyle = UIModalPresentationPopover;
        self.navigationController.popoverPresentationController.barButtonItem = self.popoverPresentingItem;
        self.navigationController.popoverPresentationController.delegate = self;
    }
    [self _setShowDoneButton:self.shouldShowDoneButton];
}

- (void)createFreshNavigationController {
    // THIS IS A HACK required to get the presentation to switch properly between popover style and half-height inspector in beta iOS 9
    OUIInspector *freshInspector = [[[self class] alloc] init];
    NSArray *existingNavStack = [self.navigationController.viewControllers copy];
    self.navigationController.viewControllers = @[];
    for (OUIInspectorPane *pane in existingNavStack) {
        pane.inspector = self;
    }
    freshInspector.navigationController.delegate = self;
    freshInspector.gesturePassThroughView = self.gesturePassThroughView;
    if ([freshInspector.navigationController isKindOfClass:[OUIInspectorNavigationController class]]) {
        ((OUIInspectorNavigationController*)freshInspector.navigationController).gesturePassThroughView = self.gesturePassThroughView;
    }
    self.navigationController = freshInspector.navigationController;
    freshInspector.navigationController = nil;
    self.navigationController.viewControllers = existingNavStack;
}

- (NSArray *)makeAvailableSlicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane;
{
    id <OUIInspectorDelegate> delegate = _weak_delegate;
    
    if ([delegate respondsToSelector:@selector(inspector:makeAvailableSlicesForStackedSlicesPane:)])
        return [delegate inspector:self makeAvailableSlicesForStackedSlicesPane:pane];
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

static void _configureContentSize(OUIInspector *self, UIViewController *vc, CGFloat height, BOOL animated) NS_EXTENSION_UNAVAILABLE_IOS("")
{
    const CGFloat toolbarHeight = 38;
    
    BOOL wantsToolbar = self->_alwaysShowToolbar || ([vc.toolbarItems count] > 0);
    if (wantsToolbar)
        height -= toolbarHeight;
    
    UIWindow *window = [[OUIAppController controller] window];
    if ([[window traitCollection] horizontalSizeClass] == UIUserInterfaceSizeClassCompact) {
        [self setDefaultInspectorContentWidth:CGRectGetWidth([window frame])];
    } else {
        [self _useDefaultInspectorContentWidth];
    }
    
    vc.preferredContentSize = CGSizeMake(self.defaultInspectorContentWidth, height);
    [self->_navigationController setToolbarHidden:!wantsToolbar animated:animated];
    
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
    UINavigationController *navigationController = _getNavigationController(self);
    OBASSERT(navigationController);

    if (pane)
        [navigationController popToViewController:pane animated:YES];
    else
        [navigationController popToRootViewControllerAnimated:YES];
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

#pragma mark - UIPopoverPresentationControllerDelegate
- (void)prepareForPopoverPresentation:(UIPopoverPresentationController *)popoverPresentationController;
{
    if (popoverPresentationController.presentedViewController != self.navigationController) {
        return;
    }

    self.shouldShowDoneButton = NO;
    [self _setShowDoneButton:NO];
}

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller;
{
    if (controller.presentedViewController != self.navigationController) {
        return controller.presentedViewController.modalPresentationStyle;
    }
    
    return UIModalPresentationFullScreen;
}

- (UIViewController *)presentationController:(UIPresentationController *)controller viewControllerForAdaptivePresentationStyle:(UIModalPresentationStyle)style;
{
    if (controller.presentedViewController != self.navigationController) {
        return nil;
    }
    
    // Currently, there is no way to adapt __into__ a popover; A popover is something you adapt out of. So _style_ should never be Popover.
    OBASSERT(style != UIModalPresentationPopover);
    self.shouldShowDoneButton = YES;
    [self _setShowDoneButton:YES];
    
    return nil;
}

- (void)popoverPresentationControllerDidDismissPopover:(UIPopoverPresentationController *)popoverPresentationController{
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIInspectorPopoverDidDismissNotification object:popoverPresentationController];
}

#pragma mark -
#pragma mark UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated NS_EXTENSION_UNAVAILABLE_IOS("");
{
    // This delegate method gets called before the pane is queried for its popover content size but before -viewWillAppear: is called.
    // Need to make sure that the content size is correct, and as part of that, we send the pane -inspectorWillShow: to let it configure toolbar items.
    
    // Let the pane configure toolbar items based on the selection, or whatever
    if ([viewController isKindOfClass:[OUIInspectorPane class]])
        [(OUIInspectorPane *)viewController inspectorWillShow:self];
    
    _configureContentSize(self, viewController, _height, animated);
    [self _setShowDoneButton:self.shouldShowDoneButton];
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
    id <OUIInspectorDelegate> delegate = _weak_delegate;

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

@implementation NSObject (OUIInspectable)

- (BOOL)shouldBeInspectedByInspectorSlice:(OUIInspectorSlice *)inspector protocol:(Protocol *)protocol;
{
    return [self conformsToProtocol:protocol];
}

@end
