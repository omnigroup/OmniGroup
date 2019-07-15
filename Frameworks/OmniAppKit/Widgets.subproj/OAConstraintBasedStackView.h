// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSView.h>
#import <OmniAppKit/NSStackView-OAExtensions.h> // for OAAnimatedSubviewHiding
#import <OmniAppKit/NSView-OAExtensions.h>


NS_ASSUME_NONNULL_BEGIN

@interface OAConstraintBasedStackView : NSView <OAAnimatedSubviewHiding>

/*!
 @discussion This method removes the existing subviews and replaces them with the new views, performing an autolayout-compatible crossfade animation between the two states.
 @param views The new views to be stacked inside the receiver, replacing any existing views. The state change will not occur until any existing crossfade for this stack view has completed, and if a subsequent crossfade request arrives before this crossfade has a chance to begin, this crossfade will be skipped in favor of crossfading directly to the newer state.
 @param completionBlock An optional block which will be executed when the crossfade is complete. The completion block will be executed even if the transition is not animated (for instance, if the window is hidden, so there is no point is performing an animated transition). The completion block will NOT be executed if these views never get swapped in. (See the description of the views parameter for details on when that can happen.)
 @see +[NSView(OAExtensions) crossfadeView:afterPerformingLayout:preAnimationBlock:completionBlock:
 */
- (void)crossfadeToViews:(NSArray <NSView *>*)views completionBlock:(nullable OACrossfadeCompletionBlock)completionBlock;

/*!
 @discussion This is a convenience method to perform an autolayout-compatible crossfade animation between two configurations of the receiver. It uses the crossfade animation support provided in NSView(OAExtensions), while providing the bit of extra logic required to avoid layout constraint conflicts during the animation.
 @param layoutBlock The block that updates the stack view to its desired layout. This block is required. This block will NOT be executed if there is already a crossfade being performed AND a subsequent crossfade request is made before the earlier crossfade completes.
 @param completionBlock An optional block which will be executed when the layout transition is complete. The completion block will be executed even if the transition is not animated (for instance, if the window is hidden, so there is no point is performing an animated transition). The completion block will NOT be executed if the layout block is not executed. (See the description of the layoutBlock parameter for details on when that can happen.)
 @see +[NSView(OAExtensions) crossfadeView:afterPerformingLayout:preAnimationBlock:completionBlock:
 */
- (void)crossfadeAfterPerformingLayout:(OACrossfadeLayoutBlock)layoutBlock completionBlock:(nullable OACrossfadeCompletionBlock)completionBlock;

@end


@interface OAConstraintBasedStackView (OAConstraintBasedStackViewArrangedSubviews)

/// The list of views that are arranged in a stack by the receiver. They are a subset of \c -subviews, with potential difference in ordering. (Unlike NSStackView, this property is not read-only.)
@property (copy) NSArray<__kindof NSView *> *arrangedSubviews;

/*!
 * Adds a view to the end of the arrangedSubviews list. If the view is not a subview of the receiver, it will be added as one.
 */
- (void)addArrangedSubview:(NSView *)view;

/*!
 * Adds a view to the arrangedSubviews list at a specific index.
 * If the view is already in the arrangedSubviews list, it will move the view to the specified index (but not change the subview index).
 * If the view is not a subview of the receiver, it will be added as one (not necessarily at the same index).
 */
- (void)insertArrangedSubview:(NSView *)view atIndex:(NSInteger)insertionIndex;

/*!
 * Removes a subview from the list of arranged subviews. Unlike NSStackView, also removes it as a subview of the receiver.
 * Removing the view as a subview (either by -[view removeFromSuperview] or setting the receiver's subviews) will automatically remove it as an arranged subview.
 */
- (void)removeArrangedSubview:(NSView *)view;

@end

NS_ASSUME_NONNULL_END
