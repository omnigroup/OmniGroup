// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorPresentationController.h>
#import <OmniUI/OUIInspector.h>
#import <OmniAppKit/OAAppearance.h>

RCS_ID("$Id$")

@interface _OUIOverlayInspectorContainerView : UIView
@property UIView *inspectorView;
@end

@implementation _OUIOverlayInspectorContainerView
{
    UIView *_topLine;
}

@synthesize inspectorView = _inspectorView;

- (UIView *)inspectorView;
{
    return _inspectorView;
}

- (void)setInspectorView:(UIView *)inspectorView;
{
    [_inspectorView removeFromSuperview];
    _inspectorView = inspectorView;
    _inspectorView.translatesAutoresizingMaskIntoConstraints = YES;
    [self addSubview:_inspectorView];
    [self setNeedsLayout];
}

- (void)layoutSubviews;
{
    CGRect topLineFrame, inspectorViewFrame;
    
    OBASSERT_IF(self.window != nil, self.window.screen != nil, "We're in a window that doesn't have a screen!");
    UIScreen *screen = self.window.screen;
    CGFloat screenScale = screen ? screen.scale : 1.0f;
    CGFloat hairlineBreadth = 1.0f / screenScale;
    
    CGRectDivide(self.bounds, &topLineFrame, &inspectorViewFrame, hairlineBreadth, CGRectMinYEdge);

    if (_topLine) {
        _topLine.frame = topLineFrame;
    } else {
        _topLine = [[UIView alloc] initWithFrame:topLineFrame];
        _topLine.backgroundColor = [[OAAppearance appearance] overlayInspectorTopSeparatorColor];
        [self addSubview:_topLine];
    }
    
    _inspectorView.frame = inspectorViewFrame;
    
    [super layoutSubviews];
}

@end

@implementation OUIInspectorPresentationController
{
    UIViewTintAdjustmentMode _originalTintAdjustmentMode;
    _OUIOverlayInspectorContainerView *_inspectorAndLineContainerView;
    CGRect _initialDisplayRect;
}

- (instancetype)init{
    if(self = [super init]){
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithPresentedViewController:(UIViewController *)presentedViewController presentingViewController:(UIViewController *)presentingViewController{
    if(self = [super initWithPresentedViewController:presentedViewController presentingViewController:presentingViewController]){
        [self commonInit];
    }
    return self;
}

- (void)commonInit{
    if ([self.presentedViewController isKindOfClass:[OUIInspectorNavigationController class]]) {
        self.gesturePassThroughView = ((OUIInspectorNavigationController*)self.presentedViewController).gesturePassThroughView;
    }
    _initialDisplayRect = CGRectZero;
}

- (void)presentedViewNowNeedsToGrowForKeyboardHeight:(CGFloat)keyboardHeight withAnimationDuration:(CGFloat)duration options:(UIViewAnimationOptions)options completion:(void (^)())completion
{
    if (CGRectEqualToRect(_initialDisplayRect, CGRectZero)) {
        _initialDisplayRect = [self frameOfPresentedViewInContainerView];
    }
    if (keyboardHeight > 0) {
        [UIView animateWithDuration:duration
                              delay:0.0
                            options:options
                         animations:^{
                             CGRect bigFrame = [self presentedView].window.frame;
                             CGFloat minimumNeededHeight = _initialDisplayRect.size.height + keyboardHeight;
                             CGFloat diff = bigFrame.size.height - minimumNeededHeight;
                             if (diff > 300) {
                                 // if there's enough space left to be meaningful, we don't have to go full screen
                                 bigFrame.size.height = minimumNeededHeight;
                                 bigFrame.origin.y += diff;
                             }
                             [self presentedView].frame = bigFrame;
                         }
                         completion:^(BOOL finished) {
                             if (completion) {
                                 completion();
                             }
                         }];
    } else {
        [UIView animateWithDuration:duration
                              delay:0.0
                            options:options
                         animations:^{
                             [self presentedView].frame = _initialDisplayRect;
                         }
                         completion:^(BOOL finished) {
                             if (completion) {
                                 completion();
                             }
                         }];
    }
}

- (void)updateForPresentingViewTransitionToSize:(CGSize)newSize{
    // the inspector needs a new frame and the gesture pass through gets the remaining space
    
    CGRect newFrame = CGRectMake(0, 0, newSize.width, newSize.height);
    CGFloat newInspectorHeight = fmin(self.presentedView.frame.size.height, newSize.height * [[OAAppearance appearance] overlayInspectorWindowHeightFraction]);
    
   newInspectorHeight = fmin(newInspectorHeight, [[OAAppearance appearance] overlayInspectorWindowMaxHeight]);
    
    CGRect newInspectorFrame = CGRectZero;
    CGRect newGesturePassthroughFrame = CGRectZero;
    CGRectDivide(newFrame, &newInspectorFrame, &newGesturePassthroughFrame, newInspectorHeight, CGRectMaxYEdge);
    
    
    [self presentedView].frame = newInspectorFrame;
    self.gesturePassThroughView.frame = newGesturePassthroughFrame;

    // and we have to remember this new rect in case of keyboard stuff later
    _initialDisplayRect = newInspectorFrame;
}

- (void)_setTintAdjustmentMode:(UIViewTintAdjustmentMode)mode forView:(UIView *)view;
{
    void (^setTintAdjustmentMode)(id<UIViewControllerTransitionCoordinatorContext>) = ^(id<UIViewControllerTransitionCoordinatorContext> unused){
        view.tintAdjustmentMode = mode;
    };
    
    id<UIViewControllerTransitionCoordinator> transitionCoordinator = [[self presentedViewController] transitionCoordinator];
    if (transitionCoordinator)
        [transitionCoordinator animateAlongsideTransition:setTintAdjustmentMode completion:nil];
    else
        setTintAdjustmentMode(nil);
}

- (void)presentationTransitionWillBegin
{
    UIWindow *window = self.containerView.window;
    _originalTintAdjustmentMode = window.tintAdjustmentMode;
    [self _setTintAdjustmentMode:UIViewTintAdjustmentModeDimmed forView:window];
    
    UIView *presentedView = self.presentedViewController.view;
    [self _setTintAdjustmentMode:UIViewTintAdjustmentModeNormal forView:presentedView];
    
    [super presentationTransitionWillBegin];
}

- (void)dismissalTransitionWillBegin
{
    [self _setTintAdjustmentMode:_originalTintAdjustmentMode forView:self.containerView.window];
    
    [super dismissalTransitionWillBegin];
}

- (void)dismissalTransitionDidEnd:(BOOL)completed;
{
    // Calling super before nilling out our _inspectorAndLineContainerView in case super's impl calls into -presentedView.
    [super dismissalTransitionDidEnd:completed];
    
    if (completed) {
        [self _setTintAdjustmentMode:UIViewTintAdjustmentModeAutomatic forView:self.presentedViewController.view];
        _inspectorAndLineContainerView = nil;
    } else {
        [self _setTintAdjustmentMode:UIViewTintAdjustmentModeDimmed forView:self.containerView.window];
    }
}

- (UIModalPresentationStyle)adaptivePresentationStyle
{
    return UIModalPresentationOverFullScreen;
}

- (BOOL)shouldPresentInFullscreen
{
    return NO;
}

- (UIView *)presentedView;
{
    if (!_inspectorAndLineContainerView) {
        _inspectorAndLineContainerView = [[_OUIOverlayInspectorContainerView alloc] initWithFrame:self.frameOfPresentedViewInContainerView];
        _inspectorAndLineContainerView.inspectorView = self.presentedViewController.view;
    }
    
    return _inspectorAndLineContainerView;
}

- (CGRect)frameOfPresentedViewInContainerView
{
    CGRect containerBounds = self.containerView.bounds;
    CGRect inspectorAndLineFrame;
    CGRectDivide(containerBounds, &inspectorAndLineFrame, &(CGRect){/*don't care*/}, fmin(containerBounds.size.height * [[OAAppearance appearance] overlayInspectorWindowHeightFraction], [[OAAppearance appearance] overlayInspectorWindowMaxHeight]), CGRectMaxYEdge);
    return inspectorAndLineFrame;
}

@end

@implementation OUIInspectorOverlayTransitioningDelegate

- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source
{
    return [[OUIInspectorPresentationController alloc] initWithPresentedViewController:presented presentingViewController:presenting];
}

@end
