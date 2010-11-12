// Copyright 2010 The Omni Group.  All rights reserved.
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
    if (_wasAnimating) \
        [UIView setAnimationsEnabled:YES]; \
} while (0)

#ifdef NS_BLOCKS_AVAILABLE
extern void OUIWithoutAnimating(void (^actions)(void));

// Takes a time interval, an action and then a list of NSNumbers containing time intervals and action blocks. Numbers change the interval to be used for any remaining blocks. All animations are run with user interaction off. Of an action doesn't actually cause any animations, UIView will complete the action without waiting for the specified delay.
extern void OUISequenceAnimations(NSTimeInterval ti, void (^action)(void), ...) NS_REQUIRES_NIL_TERMINATION;

#endif
