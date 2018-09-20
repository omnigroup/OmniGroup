// Copyright 2000-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAWindowCascade.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

// #define DEBUG_CASCADE
#define WINDOW_TILE_STEP (20.0f)
#define AVOID_INSET (8.0f)
#define MAXIMUM_TRIES (200)

@implementation OAWindowCascade
{
    NSRect lastStartingFrame;
    NSPoint lastWindowOrigin;
}

+ (instancetype)sharedInstance;
{
    static OAWindowCascade *sharedInstance = nil;

    if (sharedInstance == nil) {
        sharedInstance = [[OAWindowCascade alloc] init];
    }
    return sharedInstance;
}

static NSMutableArray *dataSources = nil;

+ (void)addDataSource:(id <OAWindowCascadeDataSource>)newValue;
{
    if (dataSources == nil) {
        dataSources = (NSMutableArray *)OFCreateNonOwnedPointerArray();
    }
    [dataSources addObject:newValue];
}

+ (void)removeDataSource:(id <OAWindowCascadeDataSource>)oldValue;
{
    CFIndex idx = [dataSources indexOfObjectIdenticalTo:oldValue];
    CFArrayRemoveValueAtIndex((CFMutableArrayRef)dataSources, idx);
}

static BOOL avoidFontPanel = NO;

+ (void)avoidFontPanel;
{
    avoidFontPanel = YES;
}

static BOOL avoidColorPanel = NO;

+ (void)avoidColorPanel;
{
    avoidColorPanel = YES;
}

+ (NSScreen *)screenForPoint:(NSPoint)aPoint;
{
    return [self _screenForPoint:aPoint];
}

+ (NSRect)unobscuredWindowFrameFromStartingFrame:(NSRect)startingFrame avoidingWindows:(nullable NSArray <NSWindow *> *)windowsToAvoid;
{
    windowsToAvoid = [self _windowsToAvoidIncluding:windowsToAvoid];
    NSRect availableRect = [self _screen:[self _screenForPoint:startingFrame.origin] closestRectTo:startingFrame avoidingWindows:windowsToAvoid];
    if (NSMaxX(startingFrame) > NSMaxX(availableRect)) {
        startingFrame.origin.x = NSMaxX(availableRect) - NSWidth(startingFrame);
    }
    if (NSMinX(startingFrame) < NSMinX(availableRect)) {
        startingFrame.origin.x = NSMinX(availableRect);
    }
    if (NSMinY(startingFrame) < NSMinY(availableRect)) {
        startingFrame.origin.y = NSMinY(availableRect);
    }
    if (NSMaxY(startingFrame) > NSMaxY(availableRect)) {
        startingFrame.origin.y = NSMaxY(availableRect) - NSHeight(startingFrame);
    }
    return startingFrame;
}

// We want the rect with the largest margin in order to give the cascading logic room to work in.
static NSRect _OALargestMarginRectInRectAvoidingRectAndFitSize(NSRect containingRect, NSRect avoidRect, NSSize fitSize)
{
    avoidRect = NSIntersectionRect(containingRect, avoidRect);
    if (NSIsEmptyRect(avoidRect))
        // If the avoid rect doesn't intersect the containing rect, we are done., then all of the
        return containingRect;

    // Build up the four rects we'll try (left, right, top, bottom)
    NSRect rects[4];
    
    rects[0] = (NSRect){containingRect.origin, {NSMinX(avoidRect) - NSMinX(containingRect), NSHeight(containingRect)}}; // left
    rects[1] = (NSRect){{NSMaxX(avoidRect), NSMinY(containingRect)}, {NSMaxX(containingRect) - NSMaxX(avoidRect), NSHeight(containingRect)}}; // right
    rects[2] = (NSRect){{NSMinX(containingRect), NSMaxY(avoidRect)}, {NSWidth(containingRect), NSMaxY(containingRect) - NSMaxY(avoidRect)}}; // top
    rects[3] = (NSRect){containingRect.origin, {NSWidth(containingRect), NSMinY(avoidRect) - NSMinY(containingRect)}}; // bottom
    
    // Initialize the result so that if the two rects are equal, we'll
    // return a zero rect.
    NSRect bestRect = NSZeroRect;
    CGFloat  bestMargin = 0.0f;
    unsigned int rectIndex;
    
    for (rectIndex = 0; rectIndex < 4; rectIndex++) {
	NSRect rect = rects[rectIndex];
	
	// Either of these might be negative
	CGFloat heightMargin = rect.size.height - fitSize.height;
	CGFloat widthMargin = rect.size.width - fitSize.width;

	CGFloat minMargin = MIN(heightMargin, widthMargin);
	if (minMargin > bestMargin) {
	    bestMargin = minMargin;
	    bestRect = rect;
	}
    }

    return bestRect;
}


- (NSRect)nextWindowFrameFromStartingFrame:(NSRect)startingFrame avoidingWindows:(nullable NSArray <NSWindow *> *)windowsToAvoid;
{
    NSScreen *screen;
    NSRect screenRect;
    NSRect firstFrame, nextWindowFrame;
    NSRect avoidRect, availableRect;
    BOOL restartedAlready = NO;
    unsigned int triesRemaining = MAXIMUM_TRIES; // Let's just be absolutely certain we can't loop forever

    windowsToAvoid = [[self class] _windowsToAvoidIncluding:windowsToAvoid];

    // Is the starting frame the same as last time?  If so, tile
    if (!NSEqualRects(startingFrame, lastStartingFrame)) {
        lastStartingFrame = startingFrame;
        firstFrame = startingFrame;
    } else {
        firstFrame.size = lastStartingFrame.size;
        firstFrame.origin = lastWindowOrigin;
        firstFrame.origin.x += WINDOW_TILE_STEP;
        firstFrame.origin.y -= WINDOW_TILE_STEP;
    }
#ifdef DEBUG_CASCADE
    NSLog(@"Avoiding %ld windows; starting frame %@", [windowsToAvoid count], NSStringFromRect(startingFrame));
    NSLog(@"  first frame %@", NSStringFromRect(firstFrame));
#endif

    screen = [OAWindowCascade _screenForPoint:startingFrame.origin];
    screenRect = [screen visibleFrame];
    // Adjust the starting frame to fit on the screen
    startingFrame = [[self class] _adjustWindowRect:startingFrame forScreenRect:screenRect];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"OAWindowCascadeDisabled"])
        return startingFrame;

    // Trim the available rect down based on the windows to avoid
    availableRect = screenRect;
    for (NSWindow *window in windowsToAvoid) {
        if (![window isVisible] || [window screen] != screen)
            continue;
        avoidRect = [window frame];
        availableRect = _OALargestMarginRectInRectAvoidingRectAndFitSize(availableRect, avoidRect, startingFrame.size);
#ifdef DEBUG_CASCADE
        NSLog(@"Avoid rect = %@", NSStringFromRect(avoidRect));
        NSLog(@"Available rect = %@", NSStringFromRect(availableRect));
#endif
    }

    // If we have room to fit our rect AND avoid being up against the edge of the rect, inset it.  This also will help us avoid the edge of the screen when we can.
    if (NSWidth(startingFrame) + 2*AVOID_INSET <= NSWidth(availableRect) &&
	NSHeight(startingFrame) + 2*AVOID_INSET <= NSHeight(availableRect))
	availableRect = NSInsetRect(availableRect, AVOID_INSET, AVOID_INSET);

    // If we can't avoid them all, let's not bother trying to avoid any
    if (NSHeight(availableRect) < NSHeight(startingFrame) || NSWidth(availableRect) < NSWidth(startingFrame)) {
#ifdef DEBUG_CASCADE
        NSLog(@"Rect too small -- don't avoid anything");
#endif
        availableRect = screenRect;
    }
    
    // Tile inside the available rect.  Two calls to this function across movement of the windows to avoid might produce discontinuous tilings.  That should be pretty rare, though.

#ifdef DEBUG_CASCADE
    NSLog(@"availableRect = %@", NSStringFromRect(availableRect));
#endif
    nextWindowFrame = firstFrame;
#ifdef DEBUG_CASCADE
    NSLog(@"Start rect = %@", NSStringFromRect(nextWindowFrame));
#endif
    while (!NSContainsRect(availableRect, nextWindowFrame)) {
        if (triesRemaining-- == 0) {
            // Reset and abort
            nextWindowFrame = firstFrame;
            break;
        }

        // If we're too far to the right, start at the left
        if (NSMaxX(nextWindowFrame) > NSMaxX(availableRect)) {
            // Too far to the right, start over
            if (restartedAlready) {
                // No good options, so let's just go back to the first frame
                nextWindowFrame = firstFrame;
#ifdef DEBUG_CASCADE
                NSLog(@"Restarted already, abort: %@", NSStringFromRect(nextWindowFrame));
#endif
                break;
            } else {
                // Try again from the start
                restartedAlready = YES;
                nextWindowFrame.origin.x = availableRect.origin.x;
                nextWindowFrame.origin.y = startingFrame.origin.y;
#ifdef DEBUG_CASCADE
                NSLog(@"Back to start: %@", NSStringFromRect(nextWindowFrame));
#endif
            }
        } else if (NSMinY(nextWindowFrame) < NSMinY(availableRect)) {
            // Too far down: start from the top
            nextWindowFrame.origin.y = startingFrame.origin.y;
#ifdef DEBUG_CASCADE
            NSLog(@"Back to top: %@", NSStringFromRect(nextWindowFrame));
#endif
        } else {
            // Move down and to the right, then try again
            nextWindowFrame.origin.x += WINDOW_TILE_STEP;
            nextWindowFrame.origin.y -= WINDOW_TILE_STEP;
#ifdef DEBUG_CASCADE
            NSLog(@"Step: %@", NSStringFromRect(nextWindowFrame));
#endif
        }
    }
    nextWindowFrame = [[self class] _adjustWindowRect:nextWindowFrame forScreenRect:screenRect];
#ifdef DEBUG_CASCADE
    NSLog(@"Result rect = %@", NSStringFromRect(nextWindowFrame));
#endif
    lastWindowOrigin = nextWindowFrame.origin;
    return nextWindowFrame;
}

- (void)reset;
{
    lastStartingFrame = NSZeroRect;
}

- (void)resetWithStartingFrame:(NSRect)startingFrame;
{
#ifdef DEBUG_CASCADE
    NSLog(@"Reset with frame %@", NSStringFromRect(startingFrame));
#endif
    lastStartingFrame = startingFrame;
    lastWindowOrigin = startingFrame.origin;
}

#pragma mark - Private

+ (NSRect)_adjustWindowRect:(NSRect)windowRect forScreenRect:(NSRect)screenRect;
{
    // Adjust the window rect to fit on the screen
    if (NSHeight(windowRect) > NSHeight(screenRect))
        windowRect.size.height = NSHeight(screenRect);
    if (NSMinY(windowRect) < NSMinY(screenRect))
        windowRect.origin.y = NSMinY(screenRect);
    if (NSMaxY(windowRect) > NSMaxY(screenRect))
        windowRect.origin.y = NSMaxY(screenRect) - NSHeight(windowRect);
    if (NSWidth(windowRect) > NSWidth(screenRect))
        windowRect.size.width = NSWidth(screenRect);
    if (NSMaxX(windowRect) > NSMaxX(screenRect))
        windowRect.origin.x = NSMaxX(screenRect) - NSWidth(windowRect);
    if (NSMinX(windowRect) < NSMinX(screenRect))
        windowRect.origin.x = NSMinX(screenRect);
    return windowRect;
}

+ (NSRect)_screen:(NSScreen *)screen closestRectTo:(NSRect)originalRect avoidingWindows:(NSArray <NSWindow *> *)windows;
{
    NSRect visibleRect = [screen visibleFrame];
    BOOL needsToMove = NO;

    NSMutableArray *availableRects = [NSMutableArray arrayWithObject:[NSValue valueWithRect:visibleRect]];
    for (NSWindow *window in windows) {
        if (![window isVisible] || [window screen] != screen)
            continue;
        NSRect rectToAvoid = NSInsetRect([window frame], -AVOID_INSET, -AVOID_INSET);
        needsToMove |= NSIntersectsRect(originalRect, rectToAvoid);
        OFUpdateRectsToAvoidRectGivenMinimumSize(availableRects, rectToAvoid, originalRect.size);
    }
    if (!needsToMove || ([availableRects count] == 0)) {
        return originalRect;
    }
    return OFClosestRectToRect(originalRect, availableRects);
}

+ (NSScreen *)_screenForPoint:(NSPoint)aPoint;
{
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSPointInRect(aPoint, [screen frame]))
            return screen;
    }
    return [NSScreen mainScreen];
}

+ (NSArray <NSWindow *> *)_windowsToAvoidIncluding:(nullable NSArray <NSWindow *> *)additionalWindows;
{
    NSMutableArray *windows = [NSMutableArray array];
    if (additionalWindows != nil)
        [windows addObjectsFromArray:additionalWindows];
    
    for (NSObject <OAWindowCascadeDataSource> *dataSource in dataSources)
        [windows addObjectsFromArray:[dataSource windowsThatShouldBeAvoided]];

    if (avoidColorPanel && [NSColorPanel sharedColorPanelExists] && [[NSColorPanel sharedColorPanel] isVisible])
        [windows addObject:[NSColorPanel sharedColorPanel]];
    if (avoidFontPanel && [NSFontPanel sharedFontPanelExists] && [[NSFontPanel sharedFontPanel] isVisible])
        [windows addObject:[NSFontPanel sharedFontPanel]];

    return windows;
}

@end

NS_ASSUME_NONNULL_END
