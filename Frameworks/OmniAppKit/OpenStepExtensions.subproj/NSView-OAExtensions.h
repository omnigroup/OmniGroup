// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

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
- (id)enclosingViewOfClass:(Class)cls;
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

// Debugging
- (void)logViewHierarchy;
- (void)logConstraintsInvolvingView;
- (void)logVibrantViews;

@end

#import <OmniFoundation/OFTransientObjectsTracker.h>
#if OF_TRANSIENT_OBJECTS_TRACKER_ENABLED
@interface NSView (OATrackTransientViews)
+ (void)trackTransientViewAllocationsIn:(void (^)(void))block;
@end
#endif
