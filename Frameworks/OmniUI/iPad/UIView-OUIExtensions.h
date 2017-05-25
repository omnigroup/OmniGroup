// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>
#import <UIKit/UIGeometry.h>
#import <OmniFoundation/OFUtilities.h>

@class UIView, UIImage;

NS_ASSUME_NONNULL_BEGIN;

typedef enum {
    OUIViewVisitorResultStop,
    OUIViewVisitorResultSkipSubviews,
    OUIViewVisitorResultContinue
} OUIViewVisitorResult;

typedef OUIViewVisitorResult(^OUIViewVisitorBlock)(UIView *view);

@interface UIView (OUIExtensions)

/*!
 @discussion Instantiates the nib with the given name from the main bundle. Then asserts that there is only 1 top-level item and that it is a UIView (or subclass) and returns is.
 @param nibName Name of the nib, in the main bundle.
 @return The single top-level UIView inside the nib.
 */
+ (UIView *)topLevelViewFromNibNamed:(NSString *)nibName;

- (UIImage *)snapshotImageWithRect:(CGRect)rect;
- (UIImage *)snapshotImageWithSize:(CGSize)imageSize;
- (UIImage *)snapshotImageWithScale:(CGFloat)scale;
- (UIImage *)snapshotImage;

- (UIMotionEffect *)tiltMotionEffectWithMaxTilt:(CGFloat)maxTilt;
- (void)addMotionMaxTilt:(CGFloat)maxTilt;

- (nullable __kindof UIView *)containingViewOfClass:(Class)cls; // can return self
- (nullable __kindof UIView *)containingViewMatching:(OFPredicateBlock)predicate;
- (OUIViewVisitorResult)applyToViewTree:(OUIViewVisitorBlock)block; // in-order traversal

// Defaults to zeros, but subclasses can return spacing offsets for where their border appears to be relative to where their actual view edge is.
// Edge borders: Used by the inspector system to help build seemingly contsistent spacing between controls.

// This view and all its subviews will be completely skipped. Defaults to YES if the receiver is hidden or has alpha of zero.
@property(nonatomic,readonly) BOOL skipWhenComputingBorderEdgeInsets;

// This view will not be considered, but its subviews will. Defaults to YES for UIView instances, but no for all other subclasses.
@property(nonatomic,readonly) BOOL recurseWhenComputingBorderEdgeInsets;

@property(readonly,nonatomic) UIEdgeInsets borderEdgeInsets;

- (void)expectDeallocationOfViewTreeSoon;

@end

#ifdef DEBUG // Uses private API
extern UIResponder *OUIWindowFindFirstResponder(UIWindow *window);
extern void OUILogViewTree(UIView *root);
#endif

// Fiddles the UIView animation enabledness
extern void OUIWithAnimationsDisabled(BOOL disabled, void (^actions)(void));
extern void OUIWithoutAnimating(void (^actions)(void));

// Fiddles the CALayer animation enabledness
extern void OUIWithoutLayersAnimating(void (^actions)(void));
extern void OUIWithLayerAnimationsDisabled(BOOL disabled, void (^actions)(void));

// Need a better name for this. This checks if +[UIView areAnimationsEnabled]. If not, then it performs the block inside a CATransation that disables implicit animations.
// Useful for when a setter on your UI view adjusts animatable properties on its layer.
extern void OUIWithAppropriateLayerAnimations(void (^actions)(void));

extern void OUIDisplayNeededViews(void);

#ifdef OMNI_ASSERTIONS_ON
extern BOOL OUICheckValidFrame(CGRect rect);
#endif

NS_ASSUME_NONNULL_END;
