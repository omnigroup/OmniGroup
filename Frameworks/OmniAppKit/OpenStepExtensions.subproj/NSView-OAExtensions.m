// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
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
#import <OmniBase/macros.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSFont-OAExtensions.h>
#import <OmniAppKit/NSApplication-OAExtensions.h>

RCS_ID("$Id$")

#define DEBUG_CROSSFADE 0
#if DEBUG_CROSSFADE
#define LOG_CROSSFADE(format, ...) NSLog(@"CROSSFADE: " format, ## __VA_ARGS__)
#else
#define LOG_CROSSFADE(format, ...)
#endif


/*!
 @brief A simple class used to store a crossfade request that arrives while a crossfade is already in-progress, until the new request can be handled.
 @discussion Note that the blocks are copied; this is required in order to move them to the heap so they will survive past the scope in which they were created.
 */
@interface OACrossfadeDescriptor : NSObject

@property (nonnull, nonatomic, copy) OACrossfadeLayoutBlock layoutBlock;
@property (nullable, nonatomic, copy) OACrossfadePreAnimationBlock preAnimationBlock;
@property (nullable, nonatomic, copy) OACrossfadeCompletionBlock completionBlock;

+ (instancetype)descriptorWithLayoutBlock:(nonnull OACrossfadeLayoutBlock)layoutBlock preAnimationBlock:(nullable OACrossfadePreAnimationBlock)preAnimationBlock completionBlock:(nullable OACrossfadeCompletionBlock)completionBlock;

@end


@implementation OACrossfadeDescriptor

+ (instancetype)descriptorWithLayoutBlock:(nonnull OACrossfadeLayoutBlock)layoutBlock preAnimationBlock:(nullable OACrossfadePreAnimationBlock)preAnimationBlock completionBlock:(nullable OACrossfadeCompletionBlock)completionBlock;
{
    OACrossfadeDescriptor *newInstance = [[[self class] alloc] init];
    newInstance.layoutBlock = layoutBlock;
    newInstance.preAnimationBlock = preAnimationBlock;
    newInstance.completionBlock = completionBlock;
    return newInstance;
}

@end


@interface OADeferredScrollEntry : NSObject

@property (nonatomic) NSView *view;
@property (nonatomic) CGFloat x;
@property (nonatomic) CGFloat y;

@end

@implementation OADeferredScrollEntry
@end


@implementation NSView (OAExtensions)

#if 0 && defined(DEBUG_kyle)

// Log when views get told to resize to zero width or height. This isn't an error, but it could be a sign of <bug:///83131> (r.12466034: Scroll view gets spurious NSZeroSize, causing constraint violations on 10.7)

static void (*original_setFrameSize)(id self, SEL _cmd, NSSize newSize);

+ (void)performPosing;
{
    original_setFrameSize = (typeof(original_setFrameSize))OBReplaceMethodImplementationWithSelector(self, @selector(setFrameSize:), @selector(OALogging_setFrameSize:));
}

- (void)OALogging_setFrameSize:(NSSize)newSize;
{
    if (newSize.width == 0 || newSize.height == 0)
        NSLog(@"*** -[%@ setFrameSize:%@] (has ambiguous layout=%@)", self.shortDescription, NSStringFromSize(newSize), self.hasAmbiguousLayout ? @"YES" : @"NO");
    
    original_setFrameSize(self, _cmd, newSize);
}

#endif

#if 1 && defined(DEBUG_bungi) && defined(OMNI_ASSERTIONS_ON)

// Log attempts to modify the view hierarchy while drawing, possibly related to <bug:///116473> (Crasher: Crash on launch +[NSGraphicsContext restoreGraphicsState] (in AppKit))

static NSCountedSet *ViewsBeingDrawn = nil;

static void (*original_didAddSubview)(NSView *self, SEL _cmd, NSView *subview) = NULL;
static void (*original_willRemoveSubview)(NSView *self, SEL _cmd, NSView *subview) = NULL;
static void (*original_lockFocus)(NSView *self, SEL _cmd) = NULL;
static void (*original_unlockFocus)(NSView *self, SEL _cmd) = NULL;

static BOOL isDrawing(NSView *view)
{
    return [ViewsBeingDrawn countForObject:view] > 0;
}

static void replacement_didAddSubview(NSView *self, SEL _cmd, NSView *subview)
{
    OBPRECONDITION(ViewsBeingDrawn);
    OBPRECONDITION([NSThread isMainThread]);
    // OBPRECONDITION(!isDrawing(self)); AppKit does this quite a bit.
    
    [subview applyToViewTree:^(NSView *treeView){
        OBPRECONDITION(!isDrawing(treeView));
    }];

    original_didAddSubview(self, _cmd, subview);
}

static void replacement_willRemoveSubview(NSView *self, SEL _cmd, NSView *subview)
{
    OBPRECONDITION(ViewsBeingDrawn);
    OBPRECONDITION([NSThread isMainThread]);

    OBPRECONDITION([NSThread isMainThread]);
    // OBPRECONDITION(!isDrawing(self)); AppKit does this quite a bit.

    [subview applyToViewTree:^(NSView *treeView){
        OBPRECONDITION(!isDrawing(treeView));
    }];

    original_willRemoveSubview(self, _cmd, subview);
}

static void replacement_lockFocus(NSView *self, SEL _cmd)
{
    OBPRECONDITION(ViewsBeingDrawn);
    OBPRECONDITION([NSThread isMainThread]);

    [ViewsBeingDrawn addObject:self];
    
    original_lockFocus(self, _cmd);
}

static void replacement_unlockFocus(NSView *self, SEL _cmd)
{
    OBPRECONDITION(ViewsBeingDrawn);
    OBPRECONDITION([NSThread isMainThread]);

    [ViewsBeingDrawn removeObject:self];

    original_unlockFocus(self, _cmd);
}

+ (void)performPosing;
{
    OBASSERT(ViewsBeingDrawn == nil);
    
    ViewsBeingDrawn = [[NSCountedSet alloc] init];
    
    original_didAddSubview = (typeof(original_didAddSubview))OBReplaceMethodImplementation(self, @selector(didAddSubview:), (IMP)replacement_didAddSubview);
    original_willRemoveSubview = (typeof(original_willRemoveSubview))OBReplaceMethodImplementation(self, @selector(willRemoveSubview:), (IMP)replacement_willRemoveSubview);
    original_lockFocus = (typeof(original_lockFocus))OBReplaceMethodImplementation(self, @selector(lockFocus), (IMP)replacement_lockFocus);
    original_unlockFocus = (typeof(original_unlockFocus))OBReplaceMethodImplementation(self, @selector(unlockFocus), (IMP)replacement_unlockFocus);
}

#endif

- (BOOL)isDescendantOfFirstResponder;
{
    NSResponder *firstResponder = [[self window] firstResponder];
    if (![firstResponder isKindOfClass:[NSView class]])
        return NO;
    
    return (self == (NSView *)firstResponder || [self isDescendantOf:(NSView *)firstResponder]);
}

- (BOOL)isOrContainsFirstResponder;
{
    NSResponder *firstResponder = [[self window] firstResponder];
    if (![firstResponder isKindOfClass:[NSView class]])
        return NO;
    
    return (self == (NSView *)firstResponder || [(NSView *)firstResponder isDescendantOf:self]);
}

- (void)windowDidChangeKeyOrFirstResponder;
{
    if ([self needsDisplayOnWindowDidChangeKeyOrFirstResponder])
        [self setNeedsDisplay:YES];
    
    for (NSView *subview in self.subviews)
        [subview windowDidChangeKeyOrFirstResponder];
}

- (BOOL)needsDisplayOnWindowDidChangeKeyOrFirstResponder;
{
    return NO;
}

#pragma mark Coordinate conversion

- (NSPoint)convertPointFromScreen:(NSPoint)point;
{
    // -[NSWindow convertScreenToBase:] is deprecated, so we have to work with an NSRect
    NSRect screenRect = (NSRect){.origin = point, .size = NSMakeSize(0.0f, 0.0f)};
    NSPoint windowPoint = [[self window] convertRectFromScreen:screenRect].origin;
    return [self convertPoint:windowPoint fromView:nil];
}

- (NSPoint)convertPointToScreen:(NSPoint)point;
{
    // -[NSWindow convertBaseToScreen:] is deprecated, so we have to work with an NSRect
    NSPoint windowPoint = [self convertPoint:point toView:nil];
    NSRect windowRect = (NSRect){.origin = windowPoint, .size = NSMakeSize(0.0f, 0.0f)};
    return [[self window] convertRectToScreen:windowRect].origin;
}

// Drawing

+ (void)drawRoundedRect:(NSRect)rect cornerRadius:(CGFloat)radius color:(nonnull NSColor *)color isFilled:(BOOL)isFilled;
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

- (void)drawRoundedRect:(NSRect)rect cornerRadius:(CGFloat)radius color:(nonnull NSColor *)color;
{
    [[self class] drawRoundedRect:rect cornerRadius:radius color:color isFilled:YES];
}

- (void)drawHorizontalSelectionInRect:(NSRect)rect;
{
    CGFloat height;
    
    [[NSColor selectedControlColor] set];
    NSRectFill(rect);

    [[NSColor controlShadowColor] set];
    height = NSHeight(rect);
    rect.size.height = 1.0f;
    NSRectFill(rect);
    rect.origin.y += height;
    NSRectFill(rect);
}


// Scrolling

static NSMutableArray *scrollEntries = nil;

+ (void)_ensureScrollEntries
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        scrollEntries = [NSMutableArray new];
    });
}

+ (void)_clearScrollEntries
{
    [scrollEntries removeAllObjects];
}

- (OADeferredScrollEntry *)_deferredScrollEntry;
{
    [[self class] _ensureScrollEntries];

    for (NSInteger i = (NSInteger)scrollEntries.count - 1; i >= 0; i--) {
        OADeferredScrollEntry *deferredScrollEntry = scrollEntries[i];
        if (deferredScrollEntry.view == self) {
            return deferredScrollEntry;
        }
    }

    OADeferredScrollEntry *newScrollEntry = [[OADeferredScrollEntry alloc] init];
    newScrollEntry.view = self;
    [scrollEntries addObject:newScrollEntry];
    return newScrollEntry;
}

- (void)_scrollByAdjustedPixelsDown:(CGFloat)downPixels right:(CGFloat)rightPixels;
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
    if (![NSThread isMainThread]) {
        [NSException raise:NSInternalInconsistencyException format:@"+[NSView(OAExtensions) performDeferredScrolling] is not thread-safe"];
    }

    [self _ensureScrollEntries];

    if (scrollEntries.count > 0) {
        for (NSInteger i = (NSInteger)scrollEntries.count - 1; i >= 0; i--) {

            OADeferredScrollEntry *deferredScrollEntry = scrollEntries[i];
            CGFloat x = deferredScrollEntry.x;
            CGFloat y = deferredScrollEntry.y;

            if (x != 0.0 || y != 0.0) {
                [deferredScrollEntry.view _scrollByAdjustedPixelsDown:y right:x];
            }
        }

        [self _clearScrollEntries];
    }
}

- (void)scrollDownByAdjustedPixels:(CGFloat)pixels;
{
    if (![NSThread isMainThread]) {
        [NSException raise:NSInternalInconsistencyException format:@"-[NSView(OAExtensions) scrollDownByAdjustedPixels:] is not thread-safe"];
    }

#ifdef DEBUG_kc0
    NSLog(@"-[%@ scrollDownByAdjustedPixels:%1.1f]", OBShortObjectDescription(self), pixels);
#endif

    OADeferredScrollEntry *deferredScrollEntry = [self _deferredScrollEntry];
    deferredScrollEntry.y = deferredScrollEntry.y + pixels;
    [[self class] queueSelectorOnce:@selector(performDeferredScrolling)];
}

- (void)scrollRightByAdjustedPixels:(CGFloat)pixels;
{
    if (![NSThread isMainThread]) {
        [NSException raise:NSInternalInconsistencyException format:@"-[NSView(OAExtensions) scrollRightByAdjustedPixels:] is not thread-safe"];
    }

#ifdef DEBUG_kc0
    NSLog(@"-[%@ scrollRightByAdjustedPixels:%1.1f]", OBShortObjectDescription(self), pixels);
#endif

    OADeferredScrollEntry *deferredScrollEntry = [self _deferredScrollEntry];
    deferredScrollEntry.x = deferredScrollEntry.x + pixels;
    [[self class] queueSelectorOnce:@selector(performDeferredScrolling)];
}

- (void)scrollToTop;
{
    [self setFraction:0.0f];
}

- (void)scrollToEnd;
{
    [self setFraction:1.0f];
}

- (void)scrollDownByPages:(CGFloat)pagesToScroll;
{
    CGFloat pageScrollAmount = NSHeight([self visibleRect]) - [[self enclosingScrollView] verticalPageScroll];
    if (pageScrollAmount < 1.0f)
        pageScrollAmount = 1.0f;
    [self scrollDownByAdjustedPixels:pagesToScroll * pageScrollAmount];
}

- (void)scrollDownByLines:(CGFloat)linesToScroll;
{
    CGFloat lineScrollAmount = [[self enclosingScrollView] verticalLineScroll];
    [self scrollDownByAdjustedPixels:linesToScroll * lineScrollAmount];
}

- (void)scrollDownByPercentage:(CGFloat)percentage;
{
    [self scrollDownByAdjustedPixels:percentage * NSHeight([self visibleRect])];
}

- (void)scrollRightByPages:(CGFloat)pagesToScroll;
{
    CGFloat pageScrollAmount;
    
    pageScrollAmount = NSWidth([self visibleRect]) - [[self enclosingScrollView] horizontalPageScroll];
    if (pageScrollAmount < 1.0f)
        pageScrollAmount = 1.0f;
    [self scrollRightByAdjustedPixels:pagesToScroll * pageScrollAmount];
}

- (void)scrollRightByLines:(CGFloat)linesToScroll;
{
    CGFloat lineScrollAmount = [[self enclosingScrollView] horizontalLineScroll];
    [self scrollRightByAdjustedPixels:linesToScroll * lineScrollAmount];
}

- (void)scrollRightByPercentage:(CGFloat)percentage;
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
        scrollPosition.y = CLAMP(scrollPosition.y, 0, 1);
    }

    // Horizontal position
    if (NSWidth(documentVisibleRect) >= NSWidth(bounds)) {
        scrollPosition.x = 0.0f; // We're completely visible
    } else {
        scrollPosition.x = (NSMinX(documentVisibleRect) - NSMinX(bounds)) / (NSWidth(bounds) - NSWidth(documentVisibleRect));
        scrollPosition.x = CLAMP(scrollPosition.x, 0, 1);
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
        scrollPosition.y = CLAMP(scrollPosition.y, 0, 1);
        if (![self isFlipped])
            scrollPosition.y = 1.0f - scrollPosition.y;
        desiredRect.origin.y = (CGFloat)rint(NSMinY(bounds) + scrollPosition.y * (NSHeight(bounds) - NSHeight(desiredRect)));
        if (NSMinY(desiredRect) < NSMinY(bounds))
            desiredRect.origin.y = NSMinY(bounds);
        else if (NSMaxY(desiredRect) > NSMaxY(bounds))
            desiredRect.origin.y = NSMaxY(bounds) - NSHeight(desiredRect);
    }

    // Horizontal position
    if (NSWidth(desiredRect) < NSWidth(bounds)) {
        scrollPosition.x = CLAMP(scrollPosition.x, 0, 1);
        desiredRect.origin.x = (CGFloat)rint(NSMinX(bounds) + scrollPosition.x * (NSWidth(bounds) - NSWidth(desiredRect)));
        if (NSMinX(desiredRect) < NSMinX(bounds))
            desiredRect.origin.x = NSMinX(bounds);
        else if (NSMaxX(desiredRect) > NSMaxX(bounds))
            desiredRect.origin.x = NSMaxX(bounds) - NSHeight(desiredRect);
    }

    [self scrollPoint:desiredRect.origin];
}


- (CGFloat)fraction;
{
    NSRect bounds = [self bounds];
    NSRect visibleRect = [self visibleRect];
    if (NSHeight(visibleRect) >= NSHeight(bounds))
        return 0.0f; // We're completely visible
    
    CGFloat fraction = (NSMinY(visibleRect) - NSMinY(bounds)) / (NSHeight(bounds) - NSHeight(visibleRect));
    if (![self isFlipped])
        fraction = 1.0f - fraction;
    return CLAMP(fraction, 0, 1);
}

- (void)setFraction:(CGFloat)fraction;
{
    NSRect bounds = [self bounds];
    NSRect desiredRect = [self visibleRect];
    if (NSHeight(desiredRect) >= NSHeight(bounds))
        return; // We're entirely visible

    fraction = CLAMP(fraction, 0, 1);
    if (![self isFlipped])
        fraction = 1.0f - fraction;
    desiredRect.origin.y = NSMinY(bounds) + fraction * (NSHeight(bounds) - NSHeight(desiredRect));
    if (NSMinY(desiredRect) < NSMinY(bounds))
        desiredRect.origin.y = NSMinY(bounds);
    else if (NSMaxY(desiredRect) > NSMaxY(bounds))
        desiredRect.origin.y = NSMaxY(bounds) - NSHeight(desiredRect);
    [self scrollPoint:desiredRect.origin];
}

// Finding views

// Will return self if it is of the specified class.
- (nullable id)enclosingViewOfClass:(nonnull Class)cls;
{
    OBPRECONDITION(OBClassIsSubclassOfClass(cls, [NSView class]));
    
    NSView *view = self;
    while (view) {
        if ([view isKindOfClass:cls])
            return view;
        view = [view superview];
    }
    
    return nil;
}

- anyViewOfClass:(Class)cls;
{
    if ([self isKindOfClass:cls])
        return self;
    
    for (NSView *view in [self subviews]) {
        NSView *found = [view anyViewOfClass:cls];
        if (found)
            return found;
    }
    
    return nil;
}

- (nonnull NSView *)lastChildKeyView;
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

- (nullable NSView *)subviewContainingView:(nonnull NSView *)subSubView;
{
    for (;;) {
        NSView *ssParent = [subSubView superview];
        if (ssParent == self)
            return subSubView;
        if (ssParent == nil)
            return nil;
        subSubView = ssParent;
    }
}

// Dragging

- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(CGFloat)dragSlop finalEvent:(NSEvent **)finalEventPointer timeoutDate:(NSDate *)timeoutDate;
{
    NSEvent *currentEvent;
    NSPoint eventLocation;
    NSRect slopRect;

    OBPRECONDITION([event type] == NSLeftMouseDown);

    currentEvent = [[NSApplication sharedApplication] currentEvent];
    if (currentEvent != event) {
        // We've already processed this once, let's try to return the same answer as before.  (This lets you call this method more than once for the same event without it pausing to wait for a whole new set of drag / mouse up events.)
        return [currentEvent type] == NSLeftMouseDragged;
    }

    eventLocation = [event locationInWindow];
    slopRect = NSInsetRect(NSMakeRect(eventLocation.x, eventLocation.y, 0.0f, 0.0f), -dragSlop, -dragSlop);

    while (1) {
        NSEvent *nextEvent;

        nextEvent = [[NSApplication sharedApplication] nextEventMatchingMask:NSLeftMouseDraggedMask | NSLeftMouseUpMask untilDate:timeoutDate inMode:NSEventTrackingRunLoopMode dequeue:YES];
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

- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(CGFloat)dragSlop finalEvent:(NSEvent **)finalEventPointer timeoutInterval:(NSTimeInterval)timeoutInterval;
{
    return [self shouldStartDragFromMouseDownEvent:event dragSlop:dragSlop finalEvent:finalEventPointer timeoutDate:[NSDate dateWithTimeIntervalSinceNow:timeoutInterval]];
}

- (BOOL)shouldStartDragFromMouseDownEvent:(NSEvent *)event dragSlop:(CGFloat)dragSlop finalEvent:(NSEvent **)finalEventPointer;
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
    maxWidth = (CGFloat)ceil(maxWidth);
    
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

/*
 This uses -[NSView cacheDisplayInRect:toBitmapImageRep:], which does not support all features of layer-backed/hosted views, such as layer filters. It does support some features such as layer background color and border radius; I *speculate* that it supports what -[CALayer renderInContext:] supports, but I do not know. It covers what we need at the moment, but it's possible that in the future we will need more from it.
 
 Other things I've tried in order to be able to snapshot the fully-rendered content of a layer-hosting view:
 
 - CGWindowListCreateImage(NSRectToCGRect(viewBoundsInScreenCoordinatesWithOriginAtBottomLeft), kCGWindowListOptionIncludingWindow, (CGWindowID)[view.window windowNumber], kCGWindowImageBoundsIgnoreFraming)
 
 This perfectly captures the fully-rendered content and works for views with or without layers. Unfortunately, the content must have been fully flushed to the screen (+[CATransaction flush], for views using layers), resulting in very obvious flickering in one of our use cases, which is to grab a snapshot post-layout as the crossfade destination. Tried disabling screen updates around this, but 1) the redraw was still visible (especially when the window frame is changin), and 2) the resulting snapshot was just a block (the appropriate size) of completely transparent pixels.
 
 - CGBitmapContextCreate() + [layer.presentationLayer renderInContext:] + CGBitmapContextCreateImage()
 
 This doesn't support all layer features; I suspect it doesn't support any more than cacheDisplayInRect:toBitmapImagRep:. Plus it doesn't work for views without layers, so would (at a minimum) require a great deal of extra effort to generate and piece together all the elements in the view and all its subviews.
 
 - -[NSView displayRectIgnoringOpacity:inContext:] to an NSImage that has been lockFocused.
 
 In modest testing, this worked fine, but it's unclear if it has any benefit or drawback vs cacheDisplayInRect:toBitmapImageRep:. If some problem is found with *that* approach, this would be a possible alternate.
 */
static NSImage * _Nonnull _snapshotImageForView(NSView * _Nonnull view)
{
    OBASSERT(view != nil);
    NSRect bounds = view.bounds;
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:bounds];
    [view cacheDisplayInRect:bounds toBitmapImageRep:bitmap];
    OBASSERT(bitmap != nil);
    NSImage *image = [[NSImage alloc] initWithSize:bounds.size];
    [image addRepresentation:bitmap];
    OBASSERT(image != nil);
    return image;
}

static NSImageView * _Nonnull _snapshotImageViewForView(NSView * _Nonnull view)
{
    NSImage *image = _snapshotImageForView(view);
    NSRect frame = view.frame;
    frame.origin = NSZeroPoint;
    NSImageView *imageView = [[NSImageView alloc] initWithFrame:frame];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.imageScaling = NSImageScaleNone;
    imageView.imageAlignment = NSImageAlignTopLeft;
    imageView.image = image;
    
    return imageView;
}

+ (void)crossfadeView:(nonnull NSView *)view afterPerformingLayout:(nonnull OACrossfadeLayoutBlock)layoutBlock preAnimationBlock:(nullable OACrossfadePreAnimationBlock)preAnimationBlock completionBlock:(nullable OACrossfadeCompletionBlock)completionBlock;
{
    OBASSERT(layoutBlock != nil);
    
    LOG_CROSSFADE(@"Crossfade requested for view %p", view);
    static NSMutableArray *CrossfadingViews = nil;
    static NSMapTable *QueuedCrossfadesByView = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CrossfadingViews = [[NSMutableArray alloc] init];
        QueuedCrossfadesByView = [NSMapTable strongToStrongObjectsMapTable];
    });
    
    // Clear out any queued layout change
#if DEBUG_CROSSFADE
    if ([QueuedCrossfadesByView objectForKey:view] != nil) {
        LOG_CROSSFADE(@"  Discarding previously-queued crossfade for view %p", view);
    }
#endif
    [QueuedCrossfadesByView removeObjectForKey:view];
    
    // If we're already animating, just queue this change up to be handled when the current animation is complete
    if ([CrossfadingViews indexOfObjectIdenticalTo:view] != NSNotFound) {
        LOG_CROSSFADE(@"  In the midst of a crossfade for view %p; queueing new request", view);
        OACrossfadeDescriptor *crossfade = [OACrossfadeDescriptor descriptorWithLayoutBlock:layoutBlock preAnimationBlock:preAnimationBlock completionBlock:completionBlock];
        [QueuedCrossfadesByView setObject:crossfade forKey:view];
        return;
    }
    
    // If we're not visible, don't bother to animate
    if (view.hidden || (view.superview == nil) || !view.window.visible) {
        LOG_CROSSFADE(@"  Not visible, view %p; executing layout and completion blocks without animation", view);
        layoutBlock();
        if (completionBlock != nil) {
            completionBlock();
        }
        return;
    }
    
    [CrossfadingViews addObject:view];
    
    // Snapshot our old visual
    [view.window layoutIfNeeded];
    NSImageView *oldImageView = _snapshotImageViewForView(view);
    
    // Execute the layout block
    layoutBlock();
    
    // Snapshot our new visual
    [view.window layoutIfNeeded];
    NSImageView *newImageView = _snapshotImageViewForView(view);
    
    // If the new visual appearance is identical to the old visual appearance; don't animate (it's not needed, and in fact it looks wrong: during the transition the view just looks like it fades out and back in a bit)
    if ([oldImageView.image.TIFFRepresentation isEqual:newImageView.image.TIFFRepresentation]) {
        LOG_CROSSFADE(@"  No change in visual appearance for view %p; skipping the animation", view);
        [CrossfadingViews removeObject:view];
        if (completionBlock != nil) {
            completionBlock();
        }
        return;
    }
    
    // Do any work the caller needs done before we actually animate
    if (preAnimationBlock != nil) {
        preAnimationBlock();
    }
    
    // Hide our content views so they don't display over/through the transition animation (this is also why we need both old and new snapshots: so that we get full crossfade with no unintended bleeding through during the transition)
    view.hidden = YES;
    
    NSMutableArray *tempConstraints = [NSMutableArray array];
    
    // Prepare to fade out the snapshot of the old state
    newImageView.alphaValue = 1.0;
    [view.superview addSubview:oldImageView];
    [NSView appendConstraints:tempConstraints forView:view toHaveSameFrameAsView:oldImageView];
    
    // Prepare to fade in the snapshot of the new state
    newImageView.alphaValue = 0.0;
    [view.superview addSubview:newImageView];
    [NSView appendConstraints:tempConstraints forView:view toHaveSameFrameAsView:newImageView];
    
    // Use some temporary constraints to animate from the old view size to the new view size
    NSLayoutConstraint *widthConstraint = [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:oldImageView.image.size.width];
    widthConstraint.identifier = @"animating width (temp)";
    [tempConstraints addObject:widthConstraint];
    NSLayoutConstraint *heightConstraint = [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:oldImageView.image.size.height];
    heightConstraint.identifier = @"animating height (temp)";
    [tempConstraints addObject:heightConstraint];
    
    [NSLayoutConstraint activateConstraints:tempConstraints];
    [view.window layoutIfNeeded];
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        LOG_CROSSFADE(@"  Starting crossfade for view %p", view);
        context.allowsImplicitAnimation = YES; // So the window frame change will animate
        context.duration = 0.1;
        
        // Animate to the new size
        widthConstraint.animator.constant = newImageView.image.size.width;
        heightConstraint.animator.constant = newImageView.image.size.height;
        
        // Crossfade from the old snapshot to the new snapshot
        oldImageView.animator.alphaValue = 0.0;
        newImageView.animator.alphaValue = 1.0;
        
    } completionHandler:^{
        LOG_CROSSFADE(@"  Finished crossfade for view %p", view);
        // Unhide the subject view now that the transition is complete
        view.hidden = NO;
        
        // Get rid of the old snapshots and the temporary constraints now that we're through with them
        [oldImageView removeFromSuperview];
        [newImageView removeFromSuperview];
        [NSLayoutConstraint deactivateConstraints:tempConstraints];
        
        [CrossfadingViews removeObjectIdenticalTo:view];
        
        if (completionBlock != nil) {
            completionBlock();
        }
        
        // If a new transition was queued up during our animation, start it going
        OACrossfadeDescriptor *queuedCrossfade = [QueuedCrossfadesByView objectForKey:view];
        if (queuedCrossfade != nil) {
            LOG_CROSSFADE(@"  Initiating previously-queued crossfade for view %p", view);
            [self crossfadeView:view afterPerformingLayout:queuedCrossfade.layoutBlock preAnimationBlock:queuedCrossfade.preAnimationBlock completionBlock:queuedCrossfade.completionBlock];
        }
    }];
}

#pragma mark - Constraints

#define EQUAL_CONSTRAINT(attr) [NSLayoutConstraint constraintWithItem:self attribute:attr relatedBy:NSLayoutRelationEqual toItem:view attribute:attr multiplier:1 constant:0]
#define EQUAL_CONSTRAINT2(v1,v2,attr) [NSLayoutConstraint constraintWithItem:v1 attribute:attr relatedBy:NSLayoutRelationEqual toItem:v2 attribute:attr multiplier:1 constant:0]

+ (void)appendConstraints:(NSMutableArray *)constraints forView:(NSView *)view toHaveSameFrameAsView:(NSView *)otherView;
{
    [constraints addObject:EQUAL_CONSTRAINT2(view, otherView, NSLayoutAttributeLeft)];
    [constraints addObject:EQUAL_CONSTRAINT2(view, otherView, NSLayoutAttributeRight)];
    [constraints addObject:EQUAL_CONSTRAINT2(view, otherView, NSLayoutAttributeTop)];
    [constraints addObject:EQUAL_CONSTRAINT2(view, otherView, NSLayoutAttributeBottom)];
}

+ (void)appendConstraints:(NSMutableArray *)constraints forView:(NSView *)view toHaveSameHorizontalExtentAsView:(NSView *)otherView;
{
    [constraints addObject:EQUAL_CONSTRAINT2(view, otherView, NSLayoutAttributeLeft)];
    [constraints addObject:EQUAL_CONSTRAINT2(view, otherView, NSLayoutAttributeRight)];
}

+ (void)appendConstraints:(NSMutableArray *)constraints forView:(NSView *)view toHaveSameVerticalExtentAsView:(NSView *)otherView;
{
    [constraints addObject:EQUAL_CONSTRAINT2(view, otherView, NSLayoutAttributeTop)];
    [constraints addObject:EQUAL_CONSTRAINT2(view, otherView, NSLayoutAttributeBottom)];
}

- (void)addConstraintsToHaveSameFrameAsView:(NSView *)view;
{
    [self addConstraint:EQUAL_CONSTRAINT(NSLayoutAttributeLeft)];
    [self addConstraint:EQUAL_CONSTRAINT(NSLayoutAttributeRight)];
    [self addConstraint:EQUAL_CONSTRAINT(NSLayoutAttributeTop)];
    [self addConstraint:EQUAL_CONSTRAINT(NSLayoutAttributeBottom)];
}

- (void)addConstraintsToHaveSameHorizontalExtentAsView:(NSView *)view;
{
    [self addConstraint:EQUAL_CONSTRAINT(NSLayoutAttributeLeft)];
    [self addConstraint:EQUAL_CONSTRAINT(NSLayoutAttributeRight)];
}

- (void)addConstraintsToHaveSameVerticalExtentAsView:(NSView *)view;
{
    [self addConstraint:EQUAL_CONSTRAINT(NSLayoutAttributeTop)];
    [self addConstraint:EQUAL_CONSTRAINT(NSLayoutAttributeBottom)];
}

- (void)appendConstraintsToArray:(NSMutableArray *)constraints toHaveSameFrameAsView:(NSView *)view;
{
    [constraints addObject:EQUAL_CONSTRAINT(NSLayoutAttributeLeft)];
    [constraints addObject:EQUAL_CONSTRAINT(NSLayoutAttributeRight)];
    [constraints addObject:EQUAL_CONSTRAINT(NSLayoutAttributeTop)];
    [constraints addObject:EQUAL_CONSTRAINT(NSLayoutAttributeBottom)];
}

- (void)appendConstraintsToArray:(NSMutableArray *)constraints toHaveSameHorizontalExtentAsView:(NSView *)view;
{
    [constraints addObject:EQUAL_CONSTRAINT(NSLayoutAttributeLeft)];
    [constraints addObject:EQUAL_CONSTRAINT(NSLayoutAttributeRight)];
}

- (void)appendConstraintsToArray:(NSMutableArray *)constraints toHaveSameVerticalExtentAsView:(NSView *)view;
{
    [constraints addObject:EQUAL_CONSTRAINT(NSLayoutAttributeTop)];
    [constraints addObject:EQUAL_CONSTRAINT(NSLayoutAttributeBottom)];
}

- (void)applyToViewTree:(void (^)(NSView *view))applier;
{
    applier(self);
    for (NSView *view in self.subviews)
        [view applyToViewTree:applier];
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
        [debugDictionary setObject:[[self subviews] arrayByPerformingSelector:_cmd] forKey:@"subviews"];

    return debugDictionary;
}

- (NSString *)descriptionWithLocale:(id)locale indent:(NSUInteger)level;
{
    if (level < NSViewMaxDebugDepth)
        return [[self debugDictionary] descriptionWithLocale:locale indent:level];
    else
        return [self shortDescription];
}

// [TAB] I believe this is a false positive?
#pragma clang diagnostic push ignored 
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
- (NSString *)description;
{
    return [self descriptionWithLocale:nil indent:0];
}
#pragma clang diagnostic pop

- (NSString *)shortDescription;
{
    return [super description];
}

- (void)logViewHierarchy:(int)level;
{
    NSLog(@"%@<%@: %p> frame: %@, bounds: %@ children:",
          [NSString spacesOfLength:level * 2], NSStringFromClass([self class]), self,
          NSStringFromRect([self frame]), NSStringFromRect([self bounds]));

    for (NSView *view in [self subviews])
        [view logViewHierarchy:level + 1];
}

- (void)logViewHierarchy;
{
    [self logViewHierarchy:0];
}

- (void)_appendConstraintsInvolvingView:(NSView *)aView toString:(NSMutableString *)string level:(int)level recurse:(BOOL)recurse;
{
    NSString *spaces = [NSString spacesOfLength:level * 2];
    [string appendFormat:@"%@%@\n", spaces, self.shortDescription];
    
    for (NSLayoutConstraint *constraint in self.constraints) {
        if (constraint.firstItem == aView || constraint.secondItem == aView)
            [string appendFormat:@"%@   + %@\n", spaces, constraint];
    }
    
    if (recurse) {
        for (NSView *subview in self.subviews)
            [subview _appendConstraintsInvolvingView:aView toString:string level:(level + 1) recurse:YES];
    }
}

- (void)logConstraintsInvolvingView;
{
    NSMutableString *string = [[NSMutableString alloc] init];
    int level = 0;
    
    NSMutableArray *ancestors = [[NSMutableArray alloc] init];
    NSView *superview = self.superview;
    while (superview != nil) {
        [ancestors addObject:superview];
        superview = superview.superview;
    }
    
    for (NSView *ancestor in ancestors.reverseObjectEnumerator) {
        [ancestor _appendConstraintsInvolvingView:self toString:string level:level recurse:NO];
        level++;
    }
    
    [self _appendConstraintsInvolvingView:self toString:string level:level recurse:YES];
    
    NSLog(@"Constraints involving %@:\n%@", self.shortDescription, string);
}

static NSString *_vibrancyInfo(NSView *view, NSUInteger level)
{
    NSMutableArray *infos = [NSMutableArray array];
    
    for (NSView *subview in view.subviews) {
        NSString *subInfo = _vibrancyInfo(subview, level + 1);
        if (subInfo) {
            [infos addObject:subInfo];
        }
    }
    
    if ([infos count] > 0 || [view isKindOfClass:[NSVisualEffectView class]] || view.allowsVibrancy) {
        NSString *localInfo = [NSString stringWithFormat:@"%@<%@:%p allowsVibrancy:%d>", [NSString spacesOfLength:level * 2], NSStringFromClass([view class]), view, view.allowsVibrancy];
        [infos insertObject:localInfo atIndex:0];
        return [infos componentsJoinedByString:@"\n"];
    }
    
    return nil;
}

- (void)logVibrantViews;
{
    NSLog(@"Vibrancy info for view tree starting at %@:\n%@", [self shortDescription], _vibrancyInfo(self, 0));
}

#ifdef DEBUG
- (void)expectDeallocationOfViewTreeSoon;
{
    [self applyToViewTree:^(NSView *treeView) {
        OBExpectDeallocationWithPossibleFailureReason(treeView, ^NSString *(NSView *remainingView){
            if (remainingView.superview)
                return @"still has superview";
            return nil;
        });
    }];
}
#endif

@end

#if OF_TRANSIENT_OBJECTS_TRACKER_ENABLED
@implementation NSView (OATrackTransientViews)

+ (void)trackTransientViewAllocationsIn:(void (^)(void))block;
{
    OFTransientObjectsTracker *tracker = [OFTransientObjectsTracker transientObjectsTrackerForClass:[NSView class] addInitializers:^(OFTransientObjectsTracker *tracker) {
        SEL initWithFrame = @selector(initWithFrame:);
        [tracker addInitializerWithSelector:initWithFrame action:^id(NSView *view, CGRect frame){
            id (*original)(NSView *view, SEL sel, CGRect frame) = (typeof(original))[tracker originalImplementationForSelector:initWithFrame];
            id result = original(view, initWithFrame, frame);
            [tracker registerInstance:result];
            return result;
        }];
        
        SEL initWithCoder = @selector(initWithCoder:);
        [tracker addInitializerWithSelector:initWithCoder action:^id(NSView *view, NSCoder *coder){
            id (*original)(NSView *view, SEL sel, NSCoder *coder) = (typeof(original))[tracker originalImplementationForSelector:initWithCoder];
            id result = original(view, initWithCoder, coder);
            [tracker registerInstance:result];
            return result;
        }];
    }];
    
    [tracker trackAllocationsIn:block];
}

@end
#endif

