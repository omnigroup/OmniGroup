// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAChasingArrowsProgressIndicator.h>

#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <OmniBase/OmniBase.h>

#import <OmniAppKit/NSImage-OAExtensions.h>


RCS_ID("$Id$")

#define FRAMES_PER_CYCLE  (16)

static NSImage *ChasingArrows = nil;

@implementation OAChasingArrowsProgressIndicator

+ (void)initialize;
{
    OBINITIALIZE;
    
    ChasingArrows = OAImageNamed(@"OAChasingArrows", OMNI_BUNDLE);
}

// Init and dealloc

- initWithFrame:(NSRect)newFrame;
{
    if (!(self = [super initWithFrame:newFrame]))
        return nil;

    [self setIndeterminate:YES];
    
    return self;
}


// API

+ (NSSize)minSize;
{
    return NSMakeSize(16.0f, 16.0f);
}

+ (NSSize)maxSize;
{
    return NSMakeSize(16.0f, 16.0f);
}

+ (NSSize)preferredSize;
{
    return NSMakeSize(16.0f, 16.0f);
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
    [[NSApplication sharedApplication] sendAction:action to:nonretainedTarget from:self];
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
    // If we're not animating and there is no action, don't draw, because clicking will do nothing
    if (!animating && (!action || [[NSUserDefaults standardUserDefaults] boolForKey:@"OAStandardChasingArrowsBehavior"]))
        return;

    CGFloat angle, opacity;
    if (!animating) {
        counter = 0;
        angle = 0;
        opacity = 0.6f;
    } else {
        counter++;
        angle = (CGFloat)(counter % FRAMES_PER_CYCLE) * (CGFloat)((2.0 * M_PI) / FRAMES_PER_CYCLE);
        opacity = 1.0f;
    }

    NSRect bounds = [self bounds];

    NSGraphicsContext *currentContext = [NSGraphicsContext currentContext];
    CGContextRef graphicsContext = [currentContext CGContext];
    if (angle != 0) {
        CGContextTranslateCTM(graphicsContext, NSWidth(bounds) / 2, NSHeight(bounds) / 2);
        CGContextRotateCTM(graphicsContext, -angle);
        CGContextTranslateCTM(graphicsContext, -NSWidth(bounds) / 2, -NSHeight(bounds) / 2);
    }

    NSImageInterpolation imageInterpolation = [currentContext imageInterpolation];
    [currentContext setImageInterpolation:NSImageInterpolationHigh];
    [ChasingArrows drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:opacity];
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
