// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSView.h>

#import <Foundation/NSDate.h>

@class NSBitmapImageRep, NSFont;

@interface NSView (OAExtensions)

- (BOOL)isDescendantOfFirstResponder;
- (BOOL)isOrContainsFirstResponder;
- (void)windowDidChangeKeyOrFirstResponder; // calls -setNeedsDisplay: if -needsDisplayOnWindowDidChangeKeyOrFirstResponder returns YES; then sends -windowDidChangeKeyOrFirstResponder to subviews
- (BOOL)needsDisplayOnWindowDidChangeKeyOrFirstResponder; // returns NO by default

// Coordinate conversion
- (NSPoint)convertPointFromScreen:(NSPoint)point;
- (NSPoint)convertPointToScreen:(NSPoint)point;

// Drawing
+ (void)drawRoundedRect:(NSRect)rect cornerRadius:(CGFloat)radius color:(NSColor *)color isFilled:(BOOL)isFilled;
- (void)drawRoundedRect:(NSRect)rect cornerRadius:(CGFloat)radius color:(NSColor *)color;
- (void)drawHorizontalSelectionInRect:(NSRect)rect;

// Scrolling (deferred)
+ (void)performDeferredScrolling;
    // Scheduled automatically, can call to scroll immediately
- (void)scrollDownByAdjustedPixels:(CGFloat)pixels;
- (void)scrollRightByAdjustedPixels:(CGFloat)pixels;

// Scrolling (convenience)
- (void)scrollToTop;
- (void)scrollToEnd;

- (void)scrollDownByPages:(CGFloat)pagesToScroll;
- (void)scrollDownByLines:(CGFloat)linesToScroll;
- (void)scrollDownByPercentage:(CGFloat)percentage;

- (void)scrollRightByPages:(CGFloat)pagesToScroll;
- (void)scrollRightByLines:(CGFloat)linesToScroll;
- (void)scrollRightByPercentage:(CGFloat)percentage;

- (NSPoint)scrollPosition;
- (void)setScrollPosition:(NSPoint)scrollPosition;

- (NSPoint)scrollPositionAsPercentage;
- (void)setScrollPositionAsPercentage:(NSPoint)scrollPosition;

- (CGFloat)fraction;
    // Deprecated:  Use -scrollPositionAsPercentage
- (void)setFraction:(CGFloat)fraction;
    // Deprecated:  Use -setScrollPositionAsPercentage:

// Finding views
- (id)enclosingViewOfClass:(Class)cls NS_REFINED_FOR_SWIFT;
- anyViewOfClass:(Class)cls;
- (NSView *)lastChildKeyView;
- (NSView *)subviewContainingView:(NSView *)subSubView;

// Dragging
- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(CGFloat)dragSlop finalEvent:(NSEvent **)finalEventPointer timeoutDate:(NSDate *)timeoutDate;
- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(CGFloat)dragSlop finalEvent:(NSEvent **)finalEventPointer timeoutInterval:(NSTimeInterval)timeoutInterval;
- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(CGFloat)dragSlop finalEvent:(NSEvent **)finalEventPointer;

// Transforms
- (NSAffineTransformStruct)transformToView:(NSView *)otherView;
- (NSAffineTransformStruct)transformFromView:(NSView *)otherView;

// A convenience method for animating layout
- (NSMutableArray *)animationsToStackSubviews:(NSArray *)newContent finalFrameSize:(NSSize *)outNewFrameSize;

// Autolayout-compatible support for a crossfade animation between two states of the same view
typedef void (^OACrossfadeLayoutBlock)(void);
typedef void (^OACrossfadePreAnimationBlock)(void);
typedef void (^OACrossfadeCompletionBlock)(void);

/*!
 @discussion This method performs an autolayout-compatible crossfade between two states of the specified view: the state of the view when the method is called, and the state after the layout block is executed. The caller must provide a layout block. If the view is not visible, or if the visual appearance is not changed by the layout block, the animation is skipped.
 
 The crossfade is accomplished by taking snapshots of the target view before and after executing the layout block, layering the snapshots over the target view (as NSImageViews, with the "after" snapshot initially set to transparent), hiding the target view so that it can't appear through the image views as they are animated (but will still occupy the appropriate space in its superview), then animating the alpha values of the two image views as well as the target view's size (and thus the image views' size as well), and finally unhiding the target view and discarding the snapshots. If the superview of the target view does any special handling of subviews when they are added, that may be incompatible with this crossfade support. (For instance, as of this writing OAConstraintBasedStackView automatically tiles any subviews that are added. This causes conflicts with the image views that get layered over the target view; so while you can use this method *on* an OAConstraintBasedStackView, you cannot use it on a direct subview of an OAConstraintBasedStackView.)
 
 The crossfade animation is non-blocking but is brief and is not designed to be interrupted: if one crossfade is in progress and a second crossfade request is received, the second one is queued to be performed when the first completes (after the first one's completion block is executed). If a request is received and there is already one queued, the queued request is discarded without being executed (including its completion block) in favor of the newer request.
 
 @param layoutBlock The block that updates the stack view to its desired layout. This block is required. This block will NOT be executed if there is already a crossfade being performed AND a subsequent crossfade request is made before the earlier crossfade completes.
 @param preAnimationBlock An optional block which will be executed after capturing the view snapshots; it will not be executed if the animation does not take place (for instance, because the view is not visible). This is intended to allow temporary reconfiguration of the target view if necessary to avoid conflicts with the size constraints used to animate any change in size of the view. For example, you may need to temporarily remove certain subviews, relax the priority of certain layout constraints, etc. If the target view's size changes and it has layout conflicts which can not be temporarily bypassed here (and reinstated in the completion block), then you will need to embed the primary view in another view that you animate instead, with constraints that allow clipping the primary view.
 @param completionBlock An optional block which will be executed when the transition is complete, even if the transition is not animated (for instance, if the window is hidden, so there is no point is performing an animated transition). The completion block will NOT be executed if the layout block is not executed. (See the description of the layoutBlock parameter for details on when that can happen.) If you supplied a pre-animation block, you will probably need a completion block that reverses whatever the pre-animation block did.
 */
+ (void)crossfadeView:(NSView *)view afterPerformingLayout:(OACrossfadeLayoutBlock)layoutBlock preAnimationBlock:(OACrossfadePreAnimationBlock)preAnimationBlock completionBlock:(OACrossfadeCompletionBlock)completionBlock;

// Constraints
+ (void)appendConstraints:(NSMutableArray *)constraints forView:(NSView *)view toHaveSameFrameAsView:(NSView *)otherView;
+ (void)appendConstraints:(NSMutableArray *)constraints forView:(NSView *)view toHaveSameHorizontalExtentAsView:(NSView *)otherView;
+ (void)appendConstraints:(NSMutableArray *)constraints forView:(NSView *)view toHaveSameVerticalExtentAsView:(NSView *)otherView;

- (void)addConstraintsToHaveSameFrameAsView:(NSView *)view;
- (void)addConstraintsToHaveSameHorizontalExtentAsView:(NSView *)view;
- (void)addConstraintsToHaveSameVerticalExtentAsView:(NSView *)view;

- (void)appendConstraintsToArray:(NSMutableArray *)constraints toHaveSameFrameAsView:(NSView *)view;
- (void)appendConstraintsToArray:(NSMutableArray *)constraints toHaveSameHorizontalExtentAsView:(NSView *)view;
- (void)appendConstraintsToArray:(NSMutableArray *)constraints toHaveSameVerticalExtentAsView:(NSView *)view;

//
- (void)applyToViewTree:(void (^)(NSView *view))applier; // Must not modify the view hierarchy

// Debugging
- (void)logViewHierarchy;
- (void)logConstraintsInvolvingView;
- (void)logVibrantViews;

- (void)expectDeallocationOfViewTreeSoon;

#ifdef DEBUG
// Slightly easier to remember wrappers for -constraintsAffectingLayoutForOrientation:
@property(nonatomic,readonly) NSArray <NSLayoutConstraint *> *horizontalConstraints;
@property(nonatomic,readonly) NSArray <NSLayoutConstraint *> *verticalConstraints;
#endif

@end

#import <OmniFoundation/OFTransientObjectsTracker.h>
#if OF_TRANSIENT_OBJECTS_TRACKER_ENABLED
@interface NSView (OATrackTransientViews)
+ (void)trackTransientViewAllocationsIn:(void (^)(void))block;
@end
#endif
