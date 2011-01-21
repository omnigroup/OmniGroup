// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class UIView, UIImage;

@interface UIView (OUIExtensions)
- (UIImage *)snapshotImage;
- (id)containingViewOfClass:(Class)cls; // can return self
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
extern void OUIWithoutAnimating(void (^actions)(void));

// Need a better name for this. This checks if +[UIView areAnimationsEnabled]. If not, then it performs the block inside a CATransation that disables implicit animations.
// Useful for when a setter on your UI view adjusts animatable properties on its layer.
extern void OUIWithAppropriateLayerAnimations(void (^actions)(void));

#endif
