// Copyright 2010-2012 The Omni Group. All rights reserved.
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

typedef enum {
    OUIViewVisitorResultStop,
    OUIViewVisitorResultSkipSubviews,
    OUIViewVisitorResultContinue
} OUIViewVisitorResult;

typedef OUIViewVisitorResult(^OUIViewVisitorBlock)(UIView *view);

@interface UIView (OUIExtensions)

- (UIImage *)snapshotImageWithSize:(CGSize)imageSize;
- (UIImage *)snapshotImageWithScale:(CGFloat)scale;
- (UIImage *)snapshotImage;

- (id)containingViewOfClass:(Class)cls; // can return self
- (id)containingViewMatching:(OFPredicateBlock)predicate;
- (OUIViewVisitorResult)applyToViewTree:(OUIViewVisitorBlock)block; // in-order traversal

// Defaults to zeros, but subclasses can return spacing offsets for where their border appears to be relative to where their actual view edge is.
// Edge borders: Used by the inspector system to help build seemingly contsistent spacing between controls.

// This view and all its subviews will be completely skipped. Defaults to YES if the receiver is hidden or has alpha of zero.
@property(nonatomic,readonly) BOOL skipWhenComputingBorderEdgeInsets;

// This view will not be considered, but its subviews will. Defaults to YES for UIView instances, but no for all other subclasses.
@property(nonatomic,readonly) BOOL recurseWhenComputingBorderEdgeInsets;

@property(readonly,nonatomic) UIEdgeInsets borderEdgeInsets;

@end

#ifdef DEBUG // Uses private API
extern UIResponder *OUIWindowFindFirstResponder(UIWindow *window);
extern void OUILogViewTree(UIView *root);
#endif

extern NSArray *OUIViewAddShadowEdges(UIView *self);
extern void OUIViewLayoutShadowEdges(UIView *self, NSArray *shadowEdges, BOOL flipped);

// There is no documentation on this, but experimentation implies that the enabled flag is not saved/restored by a begin/commit block.
#define OUIBeginWithoutAnimating do { \
    BOOL _wasAnimating = [UIView areAnimationsEnabled]; \
    if (_wasAnimating) \
        [UIView setAnimationsEnabled:NO]; \
    {

#define OUIEndWithoutAnimating \
    } \
    OBASSERT(![UIView areAnimationsEnabled]); /* Make sure something hasn't turned it on again, like -[UIToolbar setItem:] (Radar 8496247) */ \
    if (_wasAnimating) \
        [UIView setAnimationsEnabled:YES]; \
} while (0)

#ifdef NS_BLOCKS_AVAILABLE

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

#endif
