// Copyright 1997-2006, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSWindow-OAExtensions.h>

#import "OAConstructionTimeView.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")


static void (*oldMakeKeyAndOrderFront)(id self, SEL _cmd, id sender);
static id (*oldSetFrameDisplayAnimateIMP)(id self, SEL _cmd, NSRect newFrame, BOOL shouldDisplay, BOOL shouldAnimate);
static NSWindow *becomingKeyWindow = nil;

@interface NSWindow (CarbonControl)
- (WindowRef)_windowRef;
@end

@implementation NSWindow (OAExtensions)

+ (void)performPosing;
{
    oldMakeKeyAndOrderFront = (void *)OBReplaceMethodImplementationWithSelector(self, @selector(makeKeyAndOrderFront:), @selector(replacement_makeKeyAndOrderFront:));
    oldSetFrameDisplayAnimateIMP = (typeof(oldSetFrameDisplayAnimateIMP))OBReplaceMethodImplementationWithSelector(self, @selector(setFrame:display:animate:), @selector(replacement_setFrame:display:animate:));
}

static NSMutableArray *zOrder;

- (id)_addToZOrderArray;
{
    [zOrder addObject:self];
    return nil;
}

// Note that this will not return miniaturized windows (or any other ordered out window)
+ (NSArray *)windowsInZOrder;
{
    zOrder = [[NSMutableArray alloc] init];
    [NSApp makeWindowsPerform:@selector(_addToZOrderArray) inOrder:YES];
    NSArray *result = zOrder;
    zOrder = nil;
    return [result autorelease];
}

- (NSPoint)frameTopLeftPoint;
{
    NSRect windowFrame;

    windowFrame = [self frame];
    return NSMakePoint(NSMinX(windowFrame), NSMaxY(windowFrame));
}

#define MIN_MORPH_DIST (5.0)

- (void)morphToFrame:(NSRect)newFrame overTimeInterval:(NSTimeInterval)morphInterval;
{
    NSRect currentFrame, deltaFrame;
    NSTimeInterval start, current, elapsed;
    
    currentFrame = [self frame];
    deltaFrame.origin.x = newFrame.origin.x - currentFrame.origin.x;
    deltaFrame.origin.y = newFrame.origin.y - currentFrame.origin.y;
    deltaFrame.size.width = newFrame.size.width - currentFrame.size.width;
    deltaFrame.size.height = newFrame.size.height - currentFrame.size.height;
    
    // If nothing interesting is going on, just jump to the end state
    if (deltaFrame.origin.x < MIN_MORPH_DIST &&
        deltaFrame.origin.y < MIN_MORPH_DIST &&
        deltaFrame.size.width < MIN_MORPH_DIST &&
        deltaFrame.size.height < MIN_MORPH_DIST) {
        [self setFrame:newFrame display:YES];
        return;
    }

    start = [NSDate timeIntervalSinceReferenceDate];    
    while (YES) {
        float  ratio;
        NSRect stepFrame;
        
        current = [NSDate timeIntervalSinceReferenceDate];
        elapsed = current - start;
        if (elapsed >  morphInterval)
            break;

        ratio = elapsed / morphInterval;
        stepFrame.origin.x = currentFrame.origin.x + ratio * deltaFrame.origin.x;
        stepFrame.origin.y = currentFrame.origin.y + ratio * deltaFrame.origin.y;
        stepFrame.size.width = currentFrame.size.width + ratio * deltaFrame.size.width;
        stepFrame.size.height = currentFrame.size.height + ratio * deltaFrame.size.height;
        
        [self setFrame:stepFrame display:YES];
    }
    
    // Make sure we don't end up with round off errors
    [self setFrame:newFrame display:YES];
}

/*" We occasionally want to draw differently based on whether we are in the key window or not (for example, OAAquaButton).  This method allows us to draw correctly the first time we get drawn, when the window is coming on screen due to -makeKeyAndOrderFront:.  The window is not key at that point, but we would like to draw as if it is so that we don't have to redraw later, wasting time and introducing flicker. "*/

- (void)replacement_makeKeyAndOrderFront:(id)sender;
{
    becomingKeyWindow = self;
    oldMakeKeyAndOrderFront(self, _cmd, sender);
    becomingKeyWindow = nil;
}

/*" There is an elusive crasher (at least in 10.2.x) related to animated frame changes that we believe happens only when the new and old frames are very close in position and size. This method disables the animation if the frame change is below a certain threshold, in an attempt to work around the crasher. "*/
- (void)replacement_setFrame:(NSRect)newFrame display:(BOOL)shouldDisplay animate:(BOOL)shouldAnimate;
{
    NSRect currentFrame = [self frame];

    // Calling this with equal rects prevents any display from actually happening.
    if (NSEqualRects(currentFrame, newFrame))
        return;

    // Don't bother animating if we're not visible
    if (shouldAnimate && ![self isVisible])
        shouldAnimate = NO;

#ifdef OMNI_ASSERTIONS_ON
    // The AppKit method is synchronous, but it can cause timers, etc, to happen that may cause other app code to try to start animating another window (or even the SAME one).  This leads to crashes when AppKit cleans up its animation timer.
    static NSMutableSet *animatingWindows = nil;
    if (!animatingWindows)
        animatingWindows = OFCreateNonOwnedPointerSet();
    OBASSERT([animatingWindows member:self] == nil);
    [animatingWindows addObject:self];
#endif
    
    oldSetFrameDisplayAnimateIMP(self, _cmd, newFrame, shouldDisplay, shouldAnimate);

#ifdef OMNI_ASSERTIONS_ON
    OBASSERT([animatingWindows member:self] == self);
    [animatingWindows removeObject:self];
#endif
}

- (BOOL)isBecomingKey;
{
    return self == becomingKeyWindow;
}

- (BOOL)shouldDrawAsKey;
{
    return [self isKeyWindow];
}

- (void *)carbonWindowRef;
{
    WindowRef windowRef;
    extern void _SetWindowCGOrderingEnabled(WindowRef, Boolean);

    if (![self respondsToSelector:@selector(_windowRef)]) {
        NSLog(@"-[NSWindow(OAExtensions) carbonWindowRef]: _windowRef private API no longer exists, returning NULL");
        return NULL;
    }

    windowRef = [self _windowRef];
    _SetWindowCGOrderingEnabled(windowRef, false);
    return windowRef;
}

- (void)addConstructionWarning;
{
    // This is hacky, but you should only be calling this in alpha/beta builds of an app anyway.
    NSView *borderView = [self valueForKey:@"borderView"];
    
    NSRect borderBounds = [borderView bounds];
    const CGFloat constructionHeight = 21.0f;
    NSRect contructionFrame = NSMakeRect(NSMinX(borderBounds), NSMaxY(borderBounds) - constructionHeight, NSWidth(borderBounds), constructionHeight);
    OAConstructionTimeView *contructionView = [[OAConstructionTimeView alloc] initWithFrame:contructionFrame];
    [contructionView setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];
    [borderView addSubview:contructionView positioned:NSWindowBelow relativeTo:nil];
    [contructionView release];
}

/*" Convert a point from a window's base coordinate system to the CoreGraphics global ("screen") coordinate system. "*/
- (CGPoint)convertBaseToCGScreen:(NSPoint)windowPoint;
{
    // This isn't documented anywhere (sigh...), but it's borne out by experimentation and by a posting to quartz-dev by Mike Paquette.
    // Cocoa and CG both use a single global coordinate system for "screen coordinates" (even in a multi-monitor setup), but they use slightly different ones.
    // Cocoa uses a coordinate system whose origin is at the lower-left of the "origin" or "zero" screen, with Y values increasing upwards; CG has its coordinate system at the upper-left of the "origin" screen, with +Y downwards.
    // The screen in question here is the screen containing the origin, which is not necessarily the same as +[NSScreen mainScreen] (documented to be the screen containing the key window). However, the CG main display (CGMainDisplayID()) is documented to be a display at the origin.
    // Coordinates continue across other screens according to how the screens are arranged logically.

    // We assume here that both Quartz and CG have the same idea about the height (Y-extent) of the main screen; we should check whether this holds in 10.5 with resolution-independent UI.
    
    NSPoint cocoaScreenCoordinates = [self convertBaseToScreen:windowPoint];
    CGRect mainScreenSize = CGDisplayBounds(CGMainDisplayID());
    
    // It's the main screen, so we expect its origin to be at the global origin. If that's not true, our conversion will presumably fail...
    OBASSERT(mainScreenSize.origin.x == 0);
    OBASSERT(mainScreenSize.origin.y == 0);
    
    return (CGPoint){
        x: cocoaScreenCoordinates.x,
        y: ( mainScreenSize.size.height - cocoaScreenCoordinates.y )
    };
}

// NSCopying protocol

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

@end
