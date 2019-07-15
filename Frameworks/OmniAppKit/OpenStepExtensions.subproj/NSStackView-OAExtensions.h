// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSStackView.h>
#import <OmniAppKit/NSView-OAExtensions.h>


NS_ASSUME_NONNULL_BEGIN

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
- (void)setSubviews:(NSArray <NSView *> *)subviews areHidden:(BOOL)shouldBeHidden animated:(BOOL)animated;

/*!
 @discussion Hides the specified views and unhides all other subviews, with optional animation. Any subviews already in the requested state are unchanged.
 @param hiddenSubviews The array of views to be hidden. All of the views must be immediate subviews of the recipient.
 @param animated YES if the subviews should be animated in/out.
 */
- (void)setHiddenSubviews:(NSArray <NSView *> *)hiddenSubviews animated:(BOOL)animated;

/*!
 @discussion Unhides the specified views and hides all other subviews, with optional animation. Any subviews already in the requested state are unchanged.
 @param unhiddenSubviews The array of views to be unhidden. All of the views must be immediate subviews of the recipient.
 @param animated YES if the subviews should be animated in/out.
 */
- (void)setUnhiddenSubviews:(NSArray <NSView *> *)unhiddenSubviews animated:(BOOL)animated;

@end


@interface NSStackView (OAExtentions)

- (void)removeAllArrangedSubviews;

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
 @param views The array of views to be hidden or unhidden.
 @param shouldBeHidden YES if the views are to be hidden; NO if they are to be unhidden.
 @param animated YES if the views should be animated in/out.
 @param orientation Specifies whether the animation adjusts the views' horizontal size or their vertical size.
 @param completionBlock An optional block to be called when the animation is complete. If not being animated, this block is called after the hidden state is set as appropriate for all the views.
 */
+ (void)setViews:(nullable NSArray <NSView *> *)views areHidden:(BOOL)shouldBeHidden animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(nullable void (^)(void))completionBlock;

/*!
 @discussion Hides the specified views and unhides all other subviews, with optional animation. Any subviews already in the requested state are unchanged.
 @param hiddenSubviews The array of views to be hidden. All of the views must be immediate subviews of the recipient. If hiddenSubviews is empty or nil, all subviews will be unhidden.
 @param parentView The superview of the views being manipulated. (This cannot be inferred from hiddenSubviews as that might be empty.)
 @param animated YES if the subviews should be animated (collapsed/expanded) in/out.
 @param orientation Specifies whether the animation adjusts the subviews' horizontal size or their vertical size.
 @param completionBlock An optional block to be called when the animation is complete. If not being animated, this block is called after the hidden state is set as appropriate for all the subviews.
 */
+ (void)setHiddenSubviews:(nullable NSArray <NSView *> *)hiddenSubviews ofView:(NSView *)parentView animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(nullable void (^)(void))completionBlock;

/*!
 @discussion Unhides the specified views and hides all other subviews, with optional animation. Any subviews already in the requested state are unchanged.
 @param unhiddenSubviews The array of views to be unhidden. All of the views must be immediate subviews of the recipient. If unhiddenSubviews is empty or nil, all subviews will be hidden.
 @param parentView The superview of the views being manipulated. (This cannot be inferred from unhiddenSubviews as that might be empty.)
 @param animated YES if the subviews should be animated (collapsed/expanded) in/out.
 @param orientation Specifies whether the animation adjusts the subviews' horizontal size or their vertical size.
 @param completionBlock An optional block to be called when the animation is complete. If not being animated, this block is called after the hidden state is set as appropriate for all the subviews.
 */
+ (void)setUnhiddenSubviews:(nullable NSArray <NSView *> *)unhiddenSubviews ofView:(NSView *)parentView animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(nullable void (^)(void))completionBlock;

/*!
 @discussion Hides and unhides the specified views as appropriate, with optional animation. Any views already in the requested state are unchanged.
 @param viewsToHide The array of views to be hidden. Any views already in the requested state are unchanged.
 @param viewsToUnhide The array of views to be unhidden. Any views already in the requested state are unchanged.
 @param animated YES if the subviews should be animated in/out.
 @param orientation Specifies whether the animation adjusts the subviews' horizontal size or their vertical size.
 @param completionBlock An optional block to be called when the animation is complete. If not being animated, this block is called after the hidden state is set as appropriate for all the views.
 */
+ (void)hideViews:(nullable NSArray <NSView *> *)viewsToHide andUnhideViews:(nullable NSArray <NSView *> *)viewsToUnhide animated:(BOOL)animated byCollapsingOrientation:(NSUserInterfaceLayoutOrientation)orientation completionBlock:(nullable void (^)(void))completionBlock;

@end


/*!
 @category NSStackView (OAAnimatedSubviewHidingExtensions)
 @discussion This category adds support for animating subviews as they are hidden or unhidden. It adopts the OAAnimatedSubviewHiding protocol to that end. Note that the stack view's detachesHiddenViews property must be YES; otherwise the subviews will collapse/expand during animation, but while hidden the space occupied by the subview will simply be empty space.
 */
@interface NSStackView (OAAnimatedSubviewHidingExtensions) <OAAnimatedSubviewHiding>
@end


@interface NSStackView (OACrossfadeSupport)

/*!
 @discussion This is a convenience method to perform an autolayout-compatible crossfade animation between two configurations of the receiver. It uses the crossfade animation support provided in NSView(OAExtensions), while providing the bit of extra logic required to avoid layout constraint conflicts during the animation.
 @param layoutBlock The block that updates the stack view to its desired layout. This block is required. This block will NOT be executed if there is already a crossfade being performed AND a subsequent crossfade request is made before the earlier crossfade completes.
 @param completionBlock An optional block which will be executed when the layout transition is complete. The completion block will be executed even if the transition is not animated (for instance, if the window is hidden, so there is no point is performing an animated transition). The completion block will NOT be executed if the layout block is not executed. (See the description of the layoutBlock parameter for details on when that can happen.)
 @see +[NSView(OAExtensions) crossfadeView:afterPerformingLayout:preAnimationBlock:completionBlock:
 */
- (void)crossfadeAfterPerformingLayout:(OACrossfadeLayoutBlock)layoutBlock completionBlock:(nullable OACrossfadeCompletionBlock)completionBlock;

@end

NS_ASSUME_NONNULL_END
