// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSStackView.h>


/*!
 @protocol OAAnimatedSubviewHiding
 @discussion This protocol defines API for animating subviews of a view in or out as they are hidden or unhidden. It is intended for use with "stack view"-style views, where the parent view is responsible for placing (and keeping arranged) some number of subviews which can be hidden or exposed dynamically. This API was factored out into a protocol so that it could be used consistently in multiple places. Specifically, both NSStackView (via a category) and OAConstraintBasedStackView adopt this protocol. Once we require 10.11 we may be able to replace uses of OAConstraintBasedStackView with NSStackView, in which case this will no longer be needed as a protocol.
 @seealso OAConstraintBasedStackView
 @seealso NSStackView
 */
@protocol OAAnimatedSubviewHiding
/*!
 @discussion Hides or unhides a subview, with optional animation. If the subview is already in the requested state, nothing happens.
 @param subview The view to be hidden or unhidden. Must be an immediate subview of the receiver.
 @param shouldBeHidden YES if the subview is to be hidden; NO if it is to be unhidden.
 @param animated YES if the subview should be animated in/out.
 */
- (void)setSubview:(NSView *)subview isHidden:(BOOL)shouldBeHidden animated:(BOOL)animated;

/*!
 @discussion Hides or unhides an array of subviews, with optional animation. Any subviews already in the requested state are unchanged.
 @param subviews The array of views to be hidden or unhidden. All of the views must be immediate subviews of the receiver.
 @param shouldBeHidden YES if the subviews are to be hidden; NO if they are to be unhidden.
 @param animated YES if the subviews should be animated in/out.
 */
- (void)setSubviews:(NSArray *)subviews areHidden:(BOOL)shouldBeHidden animated:(BOOL)animated;

/*!
 @discussion Hides the specified views and unhides all other subviews, with optional animation. Any subviews already in the requested state are unchanged.
 @param hiddenSubviews The array of views to be hidden. All of the views must be immediate subviews of the recipient.
 @param animated YES if the subviews should be animated in/out.
 */
- (void)setHiddenSubviews:(NSArray *)hiddenSubviews animated:(BOOL)animated;

/*!
 @discussion Unhides the specified views and hides all other subviews, with optional animation. Any subviews already in the requested state are unchanged.
 @param unhiddenSubviews The array of views to be unhidden. All of the views must be immediate subviews of the recipient.
 @param animated YES if the subviews should be animated in/out.
 */
- (void)setUnhiddenSubviews:(NSArray *)unhiddenSubviews animated:(BOOL)animated;

@end


/*!
 @category NSStackView (OAAnimatedViewHidingSupport)
 @discussion This category is for use by view classes that want to adopt the OAAnimatedSubviewHiding protocol; it is specifically intended to allow NSStackView(OAAnimatedSubviewHiding) and OAConstraintBasedStackView to share a single implementation of the hiding code. It adds an implementation of hiding/unhiding subviews while animating these subviews in/out. (Animation is optional, but there is no point in this API if you don't actually need animation.)
 The implementation uses a temporary size constraint (per animated view) to animate the height or width of one or more views to achieve a collapsing or expanding effect by "closing" the subviews over their contents. (If animation is disabled, the subview's hidden property is simply set immediately.) Once the animation is complete,the temporary constraint is removed. This has some implications:
 
 1. Someone else (probably the parent view) must be responsible for reclaiming the space of any hidden subviews. This may fall naturally from the design of the parent view class or it may require additional effort.
 
 2. Any subviews to be animated MUST NOT CONFLICT with this temporary size constraint for the specified orientation. (That is: subviews in a vertical stack view must not prevent themselves from shrinking to a zero height, and their contents must not prevent this either.) In practice, this means you probably want the bottom/rightmost [depending on the orientation of the subviews] internal constraint in each subview to have a priority lower than Required. (Say, 725.) (Alternatively, you may want the top/leftmost internal constraint to be the weaker one, if you want the animation to move in the opposite direction.) If, when animating a subview away, you see console errors about conflicting constraints, your internal constraints are probably preventing the parent view from collapsing over the subviews. (This restriction could perhaps be relaxed by changing this implementation to temporarily insert intermediate views as parents of the views being animated, with appropriate layout constraints on the temporary views. Or maybe by grabbing a bitmap of the view, inserting it next to the view being hidden/unhidden, and animating over it before removing it, with appropriate hiding/unhiding of the bitmap and target views.)
 */
@interface NSStackView (OAAnimatedViewHidingSupport)

/*!
 @discussion Hides or unhides an array of views, with optional animation. Any views already in the requested state are unchanged.
 @param subviews The array of views to be hidden or unhidden.
 @param shouldBeHidden YES if the views are to be hidden; NO if they are to be unhidden.
 @param animated YES if the views should be animated in/out.
 @param orientation Specifies whether the animation adjusts the views' horizontal size or their vertical size.
 @param completionBlock An optional block to be called when the animation is complete. If not being animated, this block is called after the hidden state is set as appropriate for all the views.
 */
+ (void)setViews:(NSArray *)views areHidden:(BOOL)shouldBeHidden animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(void (^)(void))completionBlock;

/*!
 @discussion Hides the specified views and unhides all other subviews, with optional animation. Any subviews already in the requested state are unchanged.
 @param hiddenSubviews The array of views to be hidden. All of the views must be immediate subviews of the recipient. If hiddenSubviews is empty or nil, all subviews will be unhidden.
 @param parentView The superview of the views being manipulated. (This cannot be inferred from hiddenSubviews as that might be empty.)
 @param animated YES if the subviews should be animated (collapsed/expanded) in/out.
 @param orientation Specifies whether the animation adjusts the subviews' horizontal size or their vertical size.
 @param completionBlock An optional block to be called when the animation is complete. If not being animated, this block is called after the hidden state is set as appropriate for all the subviews.
 */
+ (void)setHiddenSubviews:(NSArray *)hiddenSubviews ofView:(NSView *)parentView animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(void (^)(void))completionBlock;

/*!
 @discussion Unhides the specified views and hides all other subviews, with optional animation. Any subviews already in the requested state are unchanged.
 @param unhiddenSubviews The array of views to be unhidden. All of the views must be immediate subviews of the recipient. If unhiddenSubviews is empty or nil, all subviews will be hidden.
 @param parentView The superview of the views being manipulated. (This cannot be inferred from unhiddenSubviews as that might be empty.)
 @param animated YES if the subviews should be animated (collapsed/expanded) in/out.
 @param orientation Specifies whether the animation adjusts the subviews' horizontal size or their vertical size.
 @param completionBlock An optional block to be called when the animation is complete. If not being animated, this block is called after the hidden state is set as appropriate for all the subviews.
 */
+ (void)setUnhiddenSubviews:(NSArray *)unhiddenSubviews ofView:(NSView *)parentView animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(void (^)(void))completionBlock;

/*!
 @discussion Hides and unhides the specified views as appropriate, with optional animation. Any views already in the requested state are unchanged.
 @param viewsToHide The array of views to be hidden. Any views already in the requested state are unchanged.
 @param viewsToHide The array of views to be unhidden. Any views already in the requested state are unchanged.
 @param animated YES if the subviews should be animated in/out.
 @param orientation Specifies whether the animation adjusts the subviews' horizontal size or their vertical size.
 @param completionBlock An optional block to be called when the animation is complete. If not being animated, this block is called after the hidden state is set as appropriate for all the views.
 */
+ (void)hideViews:(NSArray *)viewsToHide andUnhideViews:(NSArray *)viewsToUnhide animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(void (^)(void))completionBlock;

@end


/*!
 @category NSStackView (OAAnimatedSubviewHidingExtensions)
 @discussion This category adds support for animating subviews as they are hidden or unhidden. It adopts the OAAnimatedSubviewHiding protocol to that end. Note that the stack view's detachesHiddenViews property must be YES; otherwise the subviews will collapse/expand during animation, but while hidden the space occupied by the subview will simply be empty space.
 */
@interface NSStackView (OAAnimatedSubviewHidingExtensions) <OAAnimatedSubviewHiding>
@end
