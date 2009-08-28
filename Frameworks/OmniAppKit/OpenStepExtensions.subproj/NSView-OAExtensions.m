// Copyright 1997-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSView-OAExtensions.h>

#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSFont-OAExtensions.h>
#import <OmniAppKit/NSApplication-OAExtensions.h>

RCS_ID("$Id$")

@implementation NSView (OAExtensions)

#pragma mark Snapping to base coordinates.

// Might want floor, truncate, or rint, but at least we say what we are doing.
- (NSPoint)floorSnappedPoint:(NSPoint)point;
{
    point = [self convertPointToBase:point];
    point.x = floor(point.x);
    point.y = floor(point.y);
    return [self convertPointFromBase:point];
}

- (NSSize)floorSnappedSize:(NSSize)size;
{
    size = [self convertSizeToBase:size];
    size.width = floor(size.width);
    size.height = floor(size.height);
    return [self convertSizeFromBase:size];
}

// Rects are likely be more tricky since we may want to floor the origin and extent, or maybe we want to floor the origin and ceil the extent.  This will floor the origin and extent.
- (NSRect)floorSnappedRect:(NSRect)rect;
{
    rect = [self convertRectToBase:rect];
    NSPoint extent = NSMakePoint(NSMaxX(rect), NSMaxY(rect));
    
    rect.origin.x = floor(rect.origin.x);
    rect.origin.y = floor(rect.origin.y);
    
    extent.x = floor(extent.x);
    extent.y = floor(extent.y);
    
    rect.size.width = extent.x - rect.origin.x;
    rect.size.height = extent.y - rect.origin.y;
    
    return [self convertRectFromBase:rect];
}

// Drawing

+ (void)drawRoundedRect:(NSRect)rect cornerRadius:(float)radius color:(NSColor *)color isFilled:(BOOL)isFilled;
{
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    [color set];

    CGContextBeginPath(context);
    CGContextMoveToPoint(context, NSMinX(rect), NSMinY(rect) + radius);
    CGContextAddLineToPoint(context, NSMinX(rect), NSMaxY(rect) - radius);
    CGContextAddArcToPoint(context, NSMinX(rect), NSMaxY(rect), NSMinX(rect) + radius, NSMaxY(rect), radius);
    CGContextAddLineToPoint(context, NSMaxX(rect) - radius, NSMaxY(rect));
    CGContextAddArcToPoint(context, NSMaxX(rect), NSMaxY(rect), NSMaxX(rect), NSMaxY(rect) - radius, radius);
    CGContextAddLineToPoint(context, NSMaxX(rect), NSMinY(rect) + radius);
    CGContextAddArcToPoint(context, NSMaxX(rect), NSMinY(rect), NSMaxX(rect) - radius, NSMinY(rect), radius);
    CGContextAddLineToPoint(context, NSMinX(rect) + radius, NSMinY(rect));
    CGContextAddArcToPoint(context, NSMinX(rect), NSMinY(rect), NSMinX(rect), NSMinY(rect) + radius, radius);
    CGContextClosePath(context);
    if (isFilled) {
        CGContextFillPath(context);
    } else {
        CGContextStrokePath(context);
    }
}

- (void)drawRoundedRect:(NSRect)rect cornerRadius:(float)radius color:(NSColor *)color;
{
    [isa drawRoundedRect:rect cornerRadius:radius color:color isFilled:YES];
}

- (void)drawHorizontalSelectionInRect:(NSRect)rect;
{
    double height;
    
    [[NSColor selectedControlColor] set];
    NSRectFill(rect);

    [[NSColor controlShadowColor] set];
    height = NSHeight(rect);
    rect.size.height = 1.0;
    NSRectFill(rect);
    rect.origin.y += height;
    NSRectFill(rect);
}

#if 0  // Obsolete & unused
- (void) drawSelfAndSubviewsInRect: (NSRect) rect;
{
    [self drawRect: rect];
    for(NSView *subview in [self subviews]) {
        NSRect subviewRect;
        
        subviewRect = [self convertRect: rect toView: subview];
        subviewRect = NSIntersectionRect(subviewRect, [subview bounds]);
        if (NSWidth(subviewRect) > 0.0) {
            [subview lockFocus];
            [subview drawSelfAndSubviewsInRect: subviewRect];
            [subview unlockFocus];
        }
    }
}
#endif


// Scrolling

typedef struct {
    NSView *view;
    float x;
    float y;
} OADeferredScrollEntry;

static OADeferredScrollEntry *scrollEntries;
static unsigned int scrollEntriesAllocated = 0;
static unsigned int scrollEntriesCount = 0;

- (OADeferredScrollEntry *)_deferredScrollEntry;
{
    OADeferredScrollEntry *deferredScrollEntry;

    if (scrollEntriesAllocated == 0) {
        scrollEntriesAllocated = 8;
        scrollEntries = malloc(scrollEntriesAllocated * sizeof(*scrollEntries));
    }
    deferredScrollEntry = scrollEntries + scrollEntriesCount;
    while (deferredScrollEntry-- > scrollEntries)
        if (deferredScrollEntry->view == self)
            return deferredScrollEntry;

    // We didn't find an existing entry, let's make a new one
    if (scrollEntriesCount == scrollEntriesAllocated) {
        scrollEntriesAllocated = scrollEntriesCount + scrollEntriesCount;
        scrollEntries = realloc(scrollEntries, scrollEntriesAllocated * sizeof(*scrollEntries));
    }
    deferredScrollEntry = scrollEntries + scrollEntriesCount;
    deferredScrollEntry->view = [self retain];
    deferredScrollEntry->x = 0.0;
    deferredScrollEntry->y = 0.0;
    scrollEntriesCount++;
    return deferredScrollEntry;
}

- (void)_scrollByAdjustedPixelsDown:(float)downPixels right:(float)rightPixels;
{
    NSRect visibleRect;

#ifdef DEBUG_kc0
    NSLog(@"-[%@ _scrollByAdjustedPixelsDown:%1.1f right:%1.1f]", OBShortObjectDescription(self), downPixels, rightPixels);
#endif

    visibleRect = [self visibleRect];
    if ([self isFlipped])
        visibleRect.origin.y += downPixels;
    else
        visibleRect.origin.y -= downPixels;
    visibleRect.origin.x += rightPixels;
    [self scrollPoint:[self adjustScroll:visibleRect].origin];
}

+ (void)performDeferredScrolling;
{
    OADeferredScrollEntry *deferredScrollEntry;

    if (![NSThread isMainThread])
        [NSException raise:NSInternalInconsistencyException format:@"+[NSView(OAExtensions) performDeferredScrolling] is not thread-safe"];

    deferredScrollEntry = scrollEntries + scrollEntriesCount;
    while (deferredScrollEntry-- > scrollEntries) {
        NSView *view;
        float x, y;

        view = deferredScrollEntry->view;
        x = deferredScrollEntry->x;
        y = deferredScrollEntry->y;
	if (x != 0.0 || y != 0.0)
	    [view _scrollByAdjustedPixelsDown:y right:x];
        [view release];
    }
    scrollEntriesCount = 0;
}

- (void)scrollDownByAdjustedPixels:(float)pixels;
{
    OADeferredScrollEntry *deferredScrollEntry;

    if (![NSThread isMainThread])
        [NSException raise:NSInternalInconsistencyException format:@"-[NSView(OAExtensions) scrollDownByAdjustedPixels:] is not thread-safe"];

#ifdef DEBUG_kc0
    NSLog(@"-[%@ scrollDownByAdjustedPixels:%1.1f]", OBShortObjectDescription(self), pixels);
#endif

    deferredScrollEntry = [self _deferredScrollEntry];
    deferredScrollEntry->y += pixels;
    [isa queueSelectorOnce:@selector(performDeferredScrolling)];
}

- (void)scrollRightByAdjustedPixels:(float)pixels;
{
    OADeferredScrollEntry *deferredScrollEntry;

    if (![NSThread isMainThread])
        [NSException raise:NSInternalInconsistencyException format:@"-[NSView(OAExtensions) scrollRightByAdjustedPixels:] is not thread-safe"];

#ifdef DEBUG_kc0
    NSLog(@"-[%@ scrollRightByAdjustedPixels:%1.1f]", OBShortObjectDescription(self), pixels);
#endif

    deferredScrollEntry = [self _deferredScrollEntry];
    deferredScrollEntry->x += pixels;
    [isa queueSelectorOnce:@selector(performDeferredScrolling)];
}

- (void)scrollToTop;
{
    [self setFraction:0.0];
}

- (void)scrollToEnd;
{
    [self setFraction:1.0];
}

- (void)scrollDownByPages:(float)pagesToScroll;
{
    float pageScrollAmount;
    
    pageScrollAmount = NSHeight([self visibleRect]) - [[self enclosingScrollView] verticalPageScroll];
    if (pageScrollAmount < 1.0)
        pageScrollAmount = 1.0;
    [self scrollDownByAdjustedPixels:pagesToScroll * pageScrollAmount];
}

- (void)scrollDownByLines:(float)linesToScroll;
{
    float lineScrollAmount;
    
    lineScrollAmount = [[self enclosingScrollView] verticalLineScroll];
    [self scrollDownByAdjustedPixels:linesToScroll * lineScrollAmount];
}

- (void)scrollDownByPercentage:(float)percentage;
{
    [self scrollDownByAdjustedPixels:percentage * NSHeight([self visibleRect])];
}

- (void)scrollRightByPages:(float)pagesToScroll;
{
    float pageScrollAmount;
    
    pageScrollAmount = NSWidth([self visibleRect]) - [[self enclosingScrollView] horizontalPageScroll];
    if (pageScrollAmount < 1.0)
        pageScrollAmount = 1.0;
    [self scrollRightByAdjustedPixels:pagesToScroll * pageScrollAmount];
}

- (void)scrollRightByLines:(float)linesToScroll;
{
    float lineScrollAmount;
    
    lineScrollAmount = [[self enclosingScrollView] horizontalLineScroll];
    [self scrollRightByAdjustedPixels:linesToScroll * lineScrollAmount];
}

- (void)scrollRightByPercentage:(float)percentage;
{
    [self scrollRightByAdjustedPixels:percentage * NSHeight([self visibleRect])];
}

- (NSPoint)scrollPosition;
{
    NSScrollView *enclosingScrollView = [self enclosingScrollView];
    NSClipView *clipView = [enclosingScrollView contentView];
    if (clipView == nil)
        return NSZeroPoint;

    NSRect clipViewBounds = [clipView bounds];
    return clipViewBounds.origin;
}

- (void)setScrollPosition:(NSPoint)scrollPosition;
{
    [self scrollPoint:scrollPosition];
}

- (NSPoint)scrollPositionAsPercentage;
{
    NSRect bounds = [self bounds];
    NSScrollView *enclosingScrollView = [self enclosingScrollView];
    NSRect documentVisibleRect = [enclosingScrollView documentVisibleRect];

    NSPoint scrollPosition;
    
    // Vertical position
    if (NSHeight(documentVisibleRect) >= NSHeight(bounds)) {
        scrollPosition.y = 0.0f; // We're completely visible
    } else {
        scrollPosition.y = (NSMinY(documentVisibleRect) - NSMinY(bounds)) / (NSHeight(bounds) - NSHeight(documentVisibleRect));
        if (![self isFlipped])
            scrollPosition.y = 1.0f - scrollPosition.y;
        scrollPosition.y = MIN(MAX(scrollPosition.y, 0.0f), 1.0f);
    }

    // Horizontal position
    if (NSWidth(documentVisibleRect) >= NSWidth(bounds)) {
        scrollPosition.x = 0.0f; // We're completely visible
    } else {
        scrollPosition.x = (NSMinX(documentVisibleRect) - NSMinX(bounds)) / (NSWidth(bounds) - NSWidth(documentVisibleRect));
        scrollPosition.x = MIN(MAX(scrollPosition.x, 0.0f), 1.0f);
    }

    return scrollPosition;
}

- (void)setScrollPositionAsPercentage:(NSPoint)scrollPosition;
{
    NSRect bounds = [self bounds];
    NSScrollView *enclosingScrollView = [self enclosingScrollView];
    NSRect desiredRect = [enclosingScrollView documentVisibleRect];

    // Vertical position
    if (NSHeight(desiredRect) < NSHeight(bounds)) {
        scrollPosition.y = MIN(MAX(scrollPosition.y, 0.0f), 1.0f);
        if (![self isFlipped])
            scrollPosition.y = 1.0f - scrollPosition.y;
        desiredRect.origin.y = rintf(NSMinY(bounds) + scrollPosition.y * (NSHeight(bounds) - NSHeight(desiredRect)));
        if (NSMinY(desiredRect) < NSMinY(bounds))
            desiredRect.origin.y = NSMinY(bounds);
        else if (NSMaxY(desiredRect) > NSMaxY(bounds))
            desiredRect.origin.y = NSMaxY(bounds) - NSHeight(desiredRect);
    }

    // Horizontal position
    if (NSWidth(desiredRect) < NSWidth(bounds)) {
        scrollPosition.x = MIN(MAX(scrollPosition.x, 0.0f), 1.0f);
        desiredRect.origin.x = rintf(NSMinX(bounds) + scrollPosition.x * (NSWidth(bounds) - NSWidth(desiredRect)));
        if (NSMinX(desiredRect) < NSMinX(bounds))
            desiredRect.origin.x = NSMinX(bounds);
        else if (NSMaxX(desiredRect) > NSMaxX(bounds))
            desiredRect.origin.x = NSMaxX(bounds) - NSHeight(desiredRect);
    }

    [self scrollPoint:desiredRect.origin];
}


- (float)fraction;
{
    NSRect bounds, visibleRect;
    float fraction;

    bounds = [self bounds];
    visibleRect = [self visibleRect];
    if (NSHeight(visibleRect) >= NSHeight(bounds))
        return 0.0; // We're completely visible
    fraction = (NSMinY(visibleRect) - NSMinY(bounds)) / (NSHeight(bounds) - NSHeight(visibleRect));
    if (![self isFlipped])
        fraction = 1.0 - fraction;
    return MIN(MAX(fraction, 0.0), 1.0);
}

- (void)setFraction:(float)fraction;
{
    NSRect bounds, desiredRect;

    bounds = [self bounds];
    desiredRect = [self visibleRect];
    if (NSHeight(desiredRect) >= NSHeight(bounds))
        return; // We're entirely visible

    fraction = MIN(MAX(fraction, 0.0), 1.0);
    if (![self isFlipped])
        fraction = 1.0 - fraction;
    desiredRect.origin.y = NSMinY(bounds) + fraction * (NSHeight(bounds) - NSHeight(desiredRect));
    if (NSMinY(desiredRect) < NSMinY(bounds))
        desiredRect.origin.y = NSMinY(bounds);
    else if (NSMaxY(desiredRect) > NSMaxY(bounds))
        desiredRect.origin.y = NSMaxY(bounds) - NSHeight(desiredRect);
    [self scrollPoint:desiredRect.origin];
}

// Finding views

- anyViewOfClass:(Class)cls;
{
    if ([self isKindOfClass:cls])
        return self;
    
    NSArray *subviews = [self subviews];
    unsigned int subviewIndex = [subviews count];
    while (subviewIndex--) {
        NSView *found = [[subviews objectAtIndex:subviewIndex] anyViewOfClass:cls];
        if (found)
            return found;
    }
    
    return nil;
}

- (NSView *)lastChildKeyView;
{
    NSView *cursor = self;
    for(;;) {
        NSView *after = [cursor nextKeyView];
        
        // If there's no key view after the cursor, stop.
        if (!after)
            return cursor;
        
        // If we've looped around to ourself, stop.
        if (after == self)
            return cursor;
        
        // Follow "after"'s superview chain up; if we reach the end before reaching ourselves, stop.
        NSView *supra = after;
        for(;;) {
            supra = [supra superview];
            if (supra == self)
                break;
            if (supra == nil)
                return cursor;
        }
        
        // "after" is still in the chain we want to follow.
        cursor = after;
    }
}

// Dragging

- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(float)dragSlop finalEvent:(NSEvent **)finalEventPointer timeoutDate:(NSDate *)timeoutDate;
{
    NSEvent *currentEvent;
    NSPoint eventLocation;
    NSRect slopRect;

    OBPRECONDITION([event type] == NSLeftMouseDown);

    currentEvent = [NSApp currentEvent];
    if (currentEvent != event) {
        // We've already processed this once, let's try to return the same answer as before.  (This lets you call this method more than once for the same event without it pausing to wait for a whole new set of drag / mouse up events.)
        return [currentEvent type] == NSLeftMouseDragged;
    }

    eventLocation = [event locationInWindow];
    slopRect = NSInsetRect(NSMakeRect(eventLocation.x, eventLocation.y, 0.0, 0.0), -dragSlop, -dragSlop);

    while (1) {
        NSEvent *nextEvent;

        nextEvent = [NSApp nextEventMatchingMask:NSLeftMouseDraggedMask | NSLeftMouseUpMask untilDate:timeoutDate inMode:NSEventTrackingRunLoopMode dequeue:YES];
        if (finalEventPointer != NULL)
            *finalEventPointer = nextEvent;
        if (nextEvent == nil) { // Timeout date reached
            return NO;
        } else if ([nextEvent type] == NSLeftMouseUp) {
            return NO;
        } else if (!NSMouseInRect([nextEvent locationInWindow], slopRect, NO)) {
            return YES;
        }
    }
}

- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(float)dragSlop finalEvent:(NSEvent **)finalEventPointer timeoutInterval:(NSTimeInterval)timeoutInterval;
{
    return [self shouldStartDragFromMouseDownEvent:event dragSlop:dragSlop finalEvent:finalEventPointer timeoutDate:[NSDate dateWithTimeIntervalSinceNow:timeoutInterval]];
}

- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(float)dragSlop finalEvent:(NSEvent **)finalEventPointer;
{
    return [self shouldStartDragFromMouseDownEvent:event dragSlop:dragSlop finalEvent:finalEventPointer timeoutDate:[NSDate distantFuture]];
}

// Getting view transforms

static inline NSAffineTransformStruct computeTransformFromExamples(NSPoint origin, NSPoint dx, NSPoint dy)
{
    return (NSAffineTransformStruct){
        .m11 = dx.x - origin.x,
        .m12 = dx.y - origin.y,
        .m21 = dy.x - origin.x,
        .m22 = dy.y - origin.y,
        .tX = origin.x,
        .tY = origin.y
    };
}

- (NSAffineTransformStruct)transformToView:(NSView *)otherView;
{
    return computeTransformFromExamples([self convertPoint:(NSPoint){0, 0} toView:otherView],
                                        [self convertPoint:(NSPoint){1, 0} toView:otherView],
                                        [self convertPoint:(NSPoint){0, 1} toView:otherView]);
}

- (NSAffineTransformStruct)transformFromView:(NSView *)otherView;
{
    return computeTransformFromExamples([self convertPoint:(NSPoint){0, 0} fromView:otherView],
                                        [self convertPoint:(NSPoint){1, 0} fromView:otherView],
                                        [self convertPoint:(NSPoint){0, 1} fromView:otherView]);
}

// Laying out

/*"
 
 This method helps lay out views which have a varying set of subviews arranged in a vertical stack. The passed-in views are made subviews and arranged vertically. A list of NSViewAnimation dictionaries is returned which will fade in any new subviews, fade out any old subviews, and move subviews which were already there. (Old subviews are not removed, but are marked hidden.)
 
 The receiver is not resized, but it returns in *outNewFrameSize the frame size it should have in order to exactly contain the new stack of subviews. The caller is responsible for running the returned animations (if any) and for arranging for the receiver to have the specified size. If there are no views in newContent, *outNewFrameSize is unchanged, so you can simply initialize it to a default/fallback value.
 
 This is only useful for rigid layouts with no resizable content views. For more flexible stacks, see OAStackView.
 
 Right now this method requires that the receiver be flipped. We might want to extend this to handle horizontal stacks, width-resizeable content views, or the like (maybe add an options: parameter).
 
"*/
- (NSMutableArray *)animationsToStackSubviews:(NSArray *)newContent finalFrameSize:(NSSize *)outNewFrameSize;
{
    // Our stacking calculations assume we're flipped.
    // We could make them adapt to either orientation, if we need to.
    OBASSERT([self isFlipped]);
    
    NSMutableArray *animations = [NSMutableArray array];
    NSArray *oldContent = [self subviews];
    NSUInteger oldContentCount = [oldContent count], newContentCount = [newContent count];
    
    // If the first responder is a child of ours but not one of the views in the new content list, tell it to resign
    NSResponder *currentFirstResponder = [[self window] firstResponder];
    if (currentFirstResponder && [currentFirstResponder isKindOfClass:[NSView class]]) {
        NSView *responderView = (NSView *)currentFirstResponder;
        while(responderView) {
            if (responderView == self) {
                // We've reached ourselves without going through a view that we are keeping.
                [[self window] makeFirstResponder:nil];
                break;
            }
            if ([newContent containsObjectIdenticalTo:responderView]) {
                // It's in the new display list, so everything's fine.
                break;
            }
            responderView = [responderView superview];
        }
    }
    
    // Fade out any views that are no longer wanted
    for(NSUInteger contentIndex = 0; contentIndex < oldContentCount; contentIndex ++) {
        NSView *old = [oldContent objectAtIndex:contentIndex];
        if (![old isHidden] && ![newContent containsObjectIdenticalTo:old]) {
            [animations addObject:[NSDictionary dictionaryWithObjectsAndKeys:old, NSViewAnimationTargetKey, NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey, nil]];
        }
    }
    
    // Compute the new width of the view stack.
    CGFloat maxWidth = 0;
    for(NSUInteger contentIndex = 0; contentIndex < newContentCount; contentIndex ++) {
        CGFloat w = [[newContent objectAtIndex:contentIndex] frame].size.width;
        maxWidth = MAX(maxWidth, w);
    }
    maxWidth = ceil(maxWidth);
    
    // Compute locations for all the new content within _bottomView
    // Starting at the top (y=0, since it's flipped) and working downwards
    NSPoint placementPoint = [self bounds].origin;
    
    for(NSUInteger contentIndex = 0; contentIndex < newContentCount; contentIndex ++) {
        NSView *newView = [newContent objectAtIndex:contentIndex];
        
        NSRect newViewFrame = [newView frame];
        newViewFrame.origin.y = placementPoint.y;
        newViewFrame.origin.x = placementPoint.x;
        placementPoint.y += newViewFrame.size.height;
        
        if ([oldContent containsObjectIdenticalTo:newView] && ![newView isHidden]) {
            // Just changing the view frame.
            if (!NSEqualRects(newViewFrame, [newView frame]))
                [animations addObject:[NSDictionary dictionaryWithObjectsAndKeys:newView, NSViewAnimationTargetKey, [NSValue valueWithRect:newViewFrame], NSViewAnimationEndFrameKey, nil]];
        } else {
            // Adding a new view.
            if ([newView superview] != self) {
                [newView setHidden:YES];
                [self addSubview:newView];
            }
            [newView setFrame:newViewFrame];
            NSValue *frameValue = [NSValue valueWithRect:newViewFrame];
            NSString *keys[4] = { NSViewAnimationTargetKey, NSViewAnimationStartFrameKey, NSViewAnimationEndFrameKey, NSViewAnimationEffectKey };
            id values[4] = { newView, frameValue, frameValue, NSViewAnimationFadeInEffect };
            [animations addObject:[NSDictionary dictionaryWithObjects:values forKeys:keys count:4]];
        }
    }
    
    if (newContentCount == 0) {
        // As a special case, use the passed-in frame as the default frame if we have no content now.
    } else {
        *outNewFrameSize = [self convertSize:(NSSize){ .width = maxWidth, .height = placementPoint.y } toView:[self superview]];
    }
    
    return animations;
}

// Debugging

unsigned int NSViewMaxDebugDepth = 10;

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [NSMutableDictionary dictionary];
    [debugDictionary setObject:OBShortObjectDescription(self) forKey:@"__self__"];
    [debugDictionary setObject:NSStringFromRect([self frame]) forKey:@"01_frame"];
    if (!NSEqualSizes([self bounds].size, [self frame].size) || !NSEqualPoints([self bounds].origin, NSZeroPoint))
        [debugDictionary setObject:NSStringFromRect([self bounds]) forKey:@"02_bounds"];
    if ([[self subviews] count] > 0)
        [debugDictionary setObject:[self subviews] forKey:@"subviews"];
    return debugDictionary;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(unsigned int)level;
{
    if (level < NSViewMaxDebugDepth)
        return [[self debugDictionary] descriptionWithLocale:locale indent:level];
    else
        return [self shortDescription];
}

- (NSString *)description;
{
    return [self descriptionWithLocale:nil indent:0];
}

- (NSString *)shortDescription;
{
    return [super description];
}

- (void)logViewHierarchy:(int)level;
{
    NSArray *subviews;
    int count, index;

    subviews = [self subviews];
    count = [subviews count];

    NSLog(@"%@<%@: %p> frame: %@, bounds: %@, %d children:",
          [NSString spacesOfLength:level * 2], NSStringFromClass([self class]), self,
          NSStringFromRect([self frame]), NSStringFromRect([self bounds]), count);

    for (index = 0; index < count; index++)
        [(NSView *)[subviews objectAtIndex:index] logViewHierarchy:level + 1];
}

- (void)logViewHierarchy;
{
    [self logViewHierarchy:0];
}

@end
