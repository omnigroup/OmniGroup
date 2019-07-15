// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITransition.h>

typedef enum {
    FadedPortionSlidesInFromTop,
    FadedPortionFadesInPlace,
    // a FadedPortionSlidesInFromBottom would be good, but not needed so far and hasn't been implemented yet
} OUIVerticalSplitFadeType;

@interface OUIVerticalSplitTransition : OUITransition

@property (nonatomic, copy) CGRect (^splitExcludingRectProvider)(void); // in the fromView if pushing, in the toView if popping
@property (nonatomic, copy) CGFloat (^destinationRectHeightProvider)(void);

@property (nonatomic, assign) OUIVerticalSplitFadeType fadeType;

- (void)insertToViewIntoContainer:(id<UIViewControllerContextTransitioning>)transitionContext;
- (void)didInsertViewIntoContainer:(id<UIViewControllerContextTransitioning>)transitionContext NS_REQUIRES_SUPER;

@property (nonatomic, strong) UIView *topSnapshot;
@property (nonatomic, strong) UIView *bottomSnapshot;

@end

#pragma mark -

@interface OUIVerticalSplitTransition (Subclass)

@property (nonatomic, readonly) UIColor *snapshotBackgroundColor;
@property (nonatomic, readonly) CGFloat backdropOpacity;
@property (nonatomic, readonly) CGFloat shadowOpacity;

@end
