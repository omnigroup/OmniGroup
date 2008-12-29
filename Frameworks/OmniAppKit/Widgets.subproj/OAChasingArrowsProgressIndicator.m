// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAChasingArrowsProgressIndicator.h"

#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <OmniBase/OmniBase.h>

#import "NSImage-OAExtensions.h"


RCS_ID("$Id$")

#define FRAMES_PER_CYCLE  (16)

static NSImage *ChasingArrows = nil;

@implementation OAChasingArrowsProgressIndicator

+ (void)initialize;
{
    OBINITIALIZE;
    
    ChasingArrows = [[NSImage imageNamed:@"OAChasingArrows" inBundleForClass:[OAChasingArrowsProgressIndicator class]] retain];
}

// Init and dealloc

- initWithFrame:(NSRect)newFrame;
{
    if ([super initWithFrame:newFrame] == nil)
        return nil;

    [self setIndeterminate:YES];
    
    return self;
}


// API

+ (NSSize)minSize;
{
    return NSMakeSize(16.0, 16.0);
}

+ (NSSize)maxSize;
{
    return NSMakeSize(16.0, 16.0);
}

+ (NSSize)preferredSize;
{
    return NSMakeSize(16.0, 16.0);
}

+ (NSImage *)staticImage;
{
    return ChasingArrows;
}

- (void)setTarget:(id)aTarget;
{
    nonretainedTarget = aTarget;
}

- (void)setAction:(SEL)newAction;
{
    action = newAction;
}

// NSResponder

- (void)mouseUp:(NSEvent *)theEvent;
{
    [NSApp sendAction:action to:nonretainedTarget from:self];
}

// NSView

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;
{
    return YES;
}

- (BOOL)isFlipped;
{
    return NO;
}

- (void)drawRect:(NSRect)rect;
{
    float angle;
    float opacity;
    NSGraphicsContext *currentContext;
    CGContextRef graphicsContext;
    NSRect bounds;
    NSImageInterpolation imageInterpolation;
    
    // If we're not animating and there is no action, don't draw, because clicking will do nothing
    if (!animating && (!action || [[NSUserDefaults standardUserDefaults] boolForKey:@"OAStandardChasingArrowsBehavior"]))
        return;

    if (!animating) {
        counter = 0;
        angle = 0;
        opacity = 0.6;
    } else {
        counter++;
        angle = ((counter % FRAMES_PER_CYCLE) / (float)FRAMES_PER_CYCLE)  * (2.0 * M_PI);
        opacity = 1.0;
    }

    bounds = [self bounds];

    currentContext = [NSGraphicsContext currentContext];
    graphicsContext = (CGContextRef)[currentContext graphicsPort];
    if (angle != 0) {
        CGContextTranslateCTM(graphicsContext, NSWidth(bounds) / 2.0, NSHeight(bounds) / 2.0);
        CGContextRotateCTM(graphicsContext, -angle);
        CGContextTranslateCTM(graphicsContext, -NSWidth(bounds) / 2.0, -NSHeight(bounds) / 2.0);
    }

    imageInterpolation = [currentContext imageInterpolation];
    [currentContext setImageInterpolation:NSImageInterpolationHigh];
    [ChasingArrows drawInRect:bounds fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:opacity];
    [currentContext setImageInterpolation:imageInterpolation];
}

- (BOOL)isOpaque;
{
    return NO;
}

// NSProgressIndicator

- (void)startAnimation:(id)sender;
{
    animating = YES;
    [super startAnimation:sender];
}

- (void)stopAnimation:(id)sender;
{
    animating = NO;
    [super stopAnimation:sender];
    [self setNeedsDisplay:YES];
}

- (void)_windowChangedKeyState;
{
    // Unlike NSProgressIndicator, we don't need to redraw just because our window changed its key state (and doing so tickles an AppKit bug when we're being displayed in the toolbar).
}

@end
