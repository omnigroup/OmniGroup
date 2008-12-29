// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSView-OAExtensions.h 104581 2008-09-06 21:18:23Z kc $

#import <AppKit/NSView.h>

#import <Foundation/NSDate.h>

@class NSBitmapImageRep, NSFont;

@interface NSView (OAExtensions)

// Drawing
+ (void)drawRoundedRect:(NSRect)rect cornerRadius:(float)radius color:(NSColor *)color isFilled:(BOOL)isFilled;
- (void)drawRoundedRect:(NSRect)rect cornerRadius:(float)radius color:(NSColor *)color;
- (void)drawHorizontalSelectionInRect:(NSRect)rect;

#if 0 // Obsolete, probably not used anywhere any more
- (void)drawSelfAndSubviewsInRect:(NSRect)rect;
#endif

// Scrolling (deferred)
+ (void)performDeferredScrolling;
    // Scheduled automatically, can call to scroll immediately
- (void)scrollDownByAdjustedPixels:(float)pixels;
- (void)scrollRightByAdjustedPixels:(float)pixels;

// Scrolling (convenience)
- (void)scrollToTop;
- (void)scrollToEnd;

- (void)scrollDownByPages:(float)pagesToScroll;
- (void)scrollDownByLines:(float)linesToScroll;
- (void)scrollDownByPercentage:(float)percentage;

- (void)scrollRightByPages:(float)pagesToScroll;
- (void)scrollRightByLines:(float)linesToScroll;
- (void)scrollRightByPercentage:(float)percentage;

- (NSPoint)scrollPosition;
- (void)setScrollPosition:(NSPoint)scrollPosition;

- (NSPoint)scrollPositionAsPercentage;
- (void)setScrollPositionAsPercentage:(NSPoint)scrollPosition;

- (float)fraction;
    // Deprecated:  Use -scrollPositionAsPercentage
- (void)setFraction:(float)fraction;
    // Deprecated:  Use -setScrollPositionAsPercentage:

// Finding views
- anyViewOfClass:(Class)cls;

// Dragging
- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(float)dragSlop finalEvent:(NSEvent **)finalEventPointer timeoutDate:(NSDate *)timeoutDate;
- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(float)dragSlop finalEvent:(NSEvent **)finalEventPointer timeoutInterval:(NSTimeInterval)timeoutInterval;
- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(float)dragSlop finalEvent:(NSEvent **)finalEventPointer;

// Transforms
- (NSAffineTransformStruct)transformToView:(NSView *)otherView;
- (NSAffineTransformStruct)transformFromView:(NSView *)otherView;

// Debugging
- (void)logViewHierarchy;

@end
