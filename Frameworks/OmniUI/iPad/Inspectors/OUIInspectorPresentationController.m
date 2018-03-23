// Copyright 2010-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorPresentationController.h>
#import <OmniUI/OUIInspector.h>
#import <OmniAppKit/OAAppearance.h>

#import "OUIInspectorNavigationController.h"

RCS_ID("$Id$")

#pragma mark - _OUIOverlayInspectorContainerView

typedef NS_ENUM(NSUInteger, _OUIOverlayInspectorLayout) {
    _OUIOverlayInspectorLayoutHalfHeight,
    _OUIOverlayInspectorLayoutFullSize
};

@interface _OUIOverlayInspectorContainerView : UIView

@property (nonatomic, strong) UIView *seeThroughView;
@property (nonatomic, strong) UIView *topLineView;
@property (nonatomic, strong) UIView *inspectorView;

@property (nonatomic, assign) _OUIOverlayInspectorLayout inspectorLayout;

- (CGRect)inspectorFrameWithLayout:(_OUIOverlayInspectorLayout)inspectorLayout rect:(CGRect)layoutRect;

@end

@implementation _OUIOverlayInspectorContainerView

- (void)_commonInit {
    self.inspectorLayout = _OUIOverlayInspectorLayoutHalfHeight;
    
    self.topLineView = [[UIView alloc] init];
    self.topLineView.backgroundColor = [[OAAppearance appearance] overlayInspectorTopSeparatorColor];
    [self addSubview:self.topLineView];
    
    self.seeThroughView = [[UIView alloc] init];
    [self addSubview:self.seeThroughView];
    
#if IPAD_PRIVATE_TEST || IPAD_PUBLIC_TEST
    if ([OFPreference preferenceForKey:@"SooperSekritVisibleGestureView"].boolValue){ // <omnigraffle:///change-preference?SooperSekritVisibleGestureView=true>
        self.seeThroughView.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.3];
    }
#endif
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self _commonInit];
    }
    
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self _commonInit];
    }
    
    return self;
}


- (void)setInspectorView:(UIView *)inspectorView;
{
    [_inspectorView removeFromSuperview];
    _inspectorView = inspectorView;
    _inspectorView.translatesAutoresizingMaskIntoConstraints = YES;
    [self addSubview:_inspectorView];
    [self setNeedsLayout];
}

- (CGRect)inspectorFrameWithLayout:(_OUIOverlayInspectorLayout)inspectorLayout rect:(CGRect)layoutRect {
    CGRect inspectorAndLineFrame = CGRectZero;
    switch (inspectorLayout) {
        case _OUIOverlayInspectorLayoutHalfHeight:
        {
            CGRect containerBounds = layoutRect;
            CGRectDivide(containerBounds, &inspectorAndLineFrame, &(CGRect){/*don't care*/}, fmin(containerBounds.size.height * [[OAAppearance appearance] overlayInspectorWindowHeightFraction], [[OAAppearance appearance] overlayInspectorWindowMaxHeight]), CGRectMaxYEdge);
            
        }
            break;
        case _OUIOverlayInspectorLayoutFullSize:
            inspectorAndLineFrame = layoutRect;
            break;
    }
    return inspectorAndLineFrame;
}

- (void)layoutSubviews;
{
    // Layout inspectorView
    CGRect inspectorAndLineFrame = [self inspectorFrameWithLayout:self.inspectorLayout rect:self.bounds];
    self.inspectorView.frame = inspectorAndLineFrame;
    
    
    // Layout topLineView
    OBASSERT_IF(self.window != nil, self.window.screen != nil, "We're in a window that doesn't have a screen!");
    UIScreen *screen = self.window.screen;
    CGFloat screenScale = screen ? screen.scale : 1.0f;
    CGFloat hairlineBreadth = 1.0f / screenScale;
    
    CGRect topLineViewFrame = CGRectMake(0, inspectorAndLineFrame.origin.y-hairlineBreadth, self.bounds.size.width, hairlineBreadth);
    self.topLineView.frame = topLineViewFrame;
    
    // Layout seeThroughView
    CGRect seeThroughViewFrame = CGRectMake(0, 0, self.bounds.size.width, CGRectGetMinY(topLineViewFrame));
    self.seeThroughView.frame = seeThroughViewFrame;

    [super layoutSubviews];
}

@end

#pragma mark - OUIInspectorPresentationController
@interface OUIInspectorPresentationController ()

@property (nonatomic, strong) _OUIOverlayInspectorContainerView *viewToPresent;

@property (nonatomic, assign) UIViewTintAdjustmentMode originalTintAdjustmentMode;
@property (nonatomic, assign) CGRect initialDisplayRect;

@end

@implementation OUIInspectorPresentationController

- (instancetype)initWithPresentedViewController:(UIViewController *)presentedViewController presentingViewController:(nullable UIViewController *)presentingViewController {
    self = [super initWithPresentedViewController:presentedViewController presentingViewController:presentingViewController];
    if (self) {
        _viewToPresent = [[_OUIOverlayInspectorContainerView alloc] initWithFrame:self.frameOfPresentedViewInContainerView];
        _viewToPresent.inspectorView = presentedViewController.view;
    }
    
    return self;
}


- (UIView *)seeThroughView {
    return self.viewToPresent.seeThroughView;
}

- (UIView *)presentedView;
{
    return _viewToPresent;
}

- (void)presentationTransitionWillBegin
{
    // Grabbing stack variables to the blocks that are about to be captured by the block below so that we don't capture `self`. We don't need to call `copy` on these because they are declared `copy` via the property.
    OUIInspectorPresentationControllerAlongsidePresentationBlock alongsidePresentation = self.animationsToPerformAlongsidePresentation;
    OUIInspectorPresentationControllerTransitionBlock presentationComplete = self.presentInspectorCompletion;
    
    CGRect inspectorFrame = [self.viewToPresent inspectorFrameWithLayout:_OUIOverlayInspectorLayoutHalfHeight rect:self.frameOfPresentedViewInContainerView];
    
    // Make sure the blocks are called even if we don't have a transitionCoordinator
    id<UIViewControllerTransitionCoordinator> transitionCoordinator = self.presentedViewController.transitionCoordinator;
    if (transitionCoordinator) {
        [transitionCoordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
            if (alongsidePresentation) {
                alongsidePresentation(inspectorFrame.size.height);
            }
        } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
            if (presentationComplete) {
                presentationComplete();
            }
        }];
    }
    else {
        if (alongsidePresentation) {
            alongsidePresentation(inspectorFrame.size.height);
        }
        if (presentationComplete) {
            presentationComplete();
        }
    }
    
    UIWindow *window = self.containerView.window;
    _originalTintAdjustmentMode = window.tintAdjustmentMode;
    [self _setTintAdjustmentMode:UIViewTintAdjustmentModeDimmed forView:window];
    
    UIView *presentedView = self.presentedViewController.view;
    [self _setTintAdjustmentMode:UIViewTintAdjustmentModeNormal forView:presentedView];
    
    [super presentationTransitionWillBegin];
}

- (void)presentationTransitionDidEnd:(BOOL)completed {
    [super presentationTransitionDidEnd:completed];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dismissalTransitionWillBegin
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];

    id <OUIInspectorPresentationControllerDismissalDelegate> dismissalDelegate = self.dismissalDelegate;
    if ([dismissalDelegate respondsToSelector:@selector(inspectorWillDismiss:)]) {
        [dismissalDelegate inspectorWillDismiss:self];
    }
    
    // Grabbing stack variables to the blocks that are about to be captured by the block below so that we don't capture `self`. We don't need to call `copy` on these because they are declared `copy` via the property.
    OUIInspectorPresentationControllerTransitionBlock alongsideDismissal = self.animationsToPerformAlongsideDismissal;
    OUIInspectorPresentationControllerTransitionBlock dismissalComplete = self.dismissInspectorCompletion;
    
    // Make sure the blocks are called even if we don't have a transitionCoordinator
    id<UIViewControllerTransitionCoordinator> transitionCoordinator = self.presentedViewController.transitionCoordinator;
    if (transitionCoordinator) {
        [transitionCoordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
            if (alongsideDismissal) {
                alongsideDismissal();
            }
        } completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
            if (dismissalComplete) {
                dismissalComplete();
            }
        }];
    }
    else {
        if (alongsideDismissal) {
            alongsideDismissal();
        }
        if (dismissalComplete) {
            dismissalComplete();
        }
    }
    
    [self _setTintAdjustmentMode:_originalTintAdjustmentMode forView:self.containerView.window];
    
    [super dismissalTransitionWillBegin];
}

- (void)dismissalTransitionDidEnd:(BOOL)completed;
{
    // Calling super before nilling out our _viewToPresent in case super's impl calls into -presentedView.
    [super dismissalTransitionDidEnd:completed];
    
    if (completed) {
        [self _setTintAdjustmentMode:UIViewTintAdjustmentModeAutomatic forView:self.presentedViewController.view];
        _viewToPresent = nil;
    } else {
        [self _setTintAdjustmentMode:UIViewTintAdjustmentModeDimmed forView:self.containerView.window];
    }
    
    self.animationsToPerformAlongsidePresentation = nil;
    self.presentInspectorCompletion = nil;
    self.animationsToPerformAlongsideDismissal = nil;
    self.dismissInspectorCompletion = nil;
    
    id <OUIInspectorPresentationControllerDismissalDelegate> dismissalDelegate = self.dismissalDelegate;
    if ([dismissalDelegate respondsToSelector:@selector(inspectorDidDismiss:)]) {
        [dismissalDelegate inspectorDidDismiss:self];
    }
}

- (UIModalPresentationStyle)adaptivePresentationStyle
{
    return UIModalPresentationOverFullScreen;
}

#pragma mark Private Helpers
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

#pragma mark Keyboard Handlers
- (void)_keyboardWillShow:(NSNotification*)note
{
    NSNumber *duration = note.userInfo[UIKeyboardAnimationDurationUserInfoKey];
    NSNumber *curve = note.userInfo[UIKeyboardAnimationCurveUserInfoKey];
    UIViewAnimationOptions options = (curve.integerValue << 16) | UIViewAnimationOptionBeginFromCurrentState;  // http://macoscope.com/blog/working-with-keyboard-on-ios/  (Dec 20, 2013)
    
    if (!self.presentedViewController.isBeingDismissed) {
        [UIView animateWithDuration:duration.floatValue
                              delay:0.0
                            options:options
                         animations:^{
                             self.viewToPresent.inspectorLayout = _OUIOverlayInspectorLayoutFullSize;
                             [self.viewToPresent setNeedsLayout];
                             [self.viewToPresent layoutIfNeeded];
                         }
                         completion:nil];
        
    }
}

- (void)_keyboardWillHide:(NSNotification*)note
{
    NSNumber *duration = note.userInfo[UIKeyboardAnimationDurationUserInfoKey];
    NSNumber *curve = note.userInfo[UIKeyboardAnimationCurveUserInfoKey];
    UIViewAnimationOptions options = (curve.integerValue << 16) | UIViewAnimationOptionBeginFromCurrentState;  // http://macoscope.com/blog/working-with-keyboard-on-ios/  (Dec 20, 2013)
    [UIView animateWithDuration:duration.floatValue
                          delay:0.0
                        options:options
                     animations:^{
                         self.viewToPresent.inspectorLayout = _OUIOverlayInspectorLayoutHalfHeight;
                         [self.viewToPresent setNeedsLayout];
                         [self.viewToPresent layoutIfNeeded];
                     }
                     completion:nil];
}

@end

#pragma mark - OUIInspectorOverlayTransitioningDelegate
@implementation OUIInspectorOverlayTransitioningDelegate

- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source
{
    return [[OUIInspectorPresentationController alloc] initWithPresentedViewController:presented presentingViewController:presenting];
}

@end
