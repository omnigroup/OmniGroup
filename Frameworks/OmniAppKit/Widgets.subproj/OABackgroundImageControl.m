// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OABackgroundImageControl.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OABackgroundImageControl (Private)
- (void)_backgroundImageControlInit;
- (void)_rebuildBackgroundImage;
- (void)_drawBackgroundImage;
- (BOOL)_shouldDrawFocusRing;
@end

@implementation OABackgroundImageControl

// Init and dealloc

- (id)initWithFrame:(NSRect)frame;
{
    if ([super initWithFrame:frame] == nil)
        return nil;
        
    [self _backgroundImageControlInit];
    
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    if ([super initWithCoder:coder] == nil)
        return nil;
    
    [self _backgroundImageControlInit];
    
    return self;
}

- (void)dealloc;
{
    [backgroundImage release];
    
    [super dealloc];
}

// NSView subclass

- (BOOL)needsDisplay;
{
    BOOL shouldDrawFocusRing = [self _shouldDrawFocusRing];
    if (backgroundImageControlFlags.drawingFocusRing != shouldDrawFocusRing) {
        backgroundImageControlFlags.drawingFocusRing = shouldDrawFocusRing;
        [self setKeyboardFocusRingNeedsDisplayInRect:[self bounds]];

        return YES;
    }
   
    return [super needsDisplay];
}

- (void)setFrameSize:(NSSize)newFrameSize;
{
    NSSize oldFrameSize = newFrameSize;
    
    [super setFrameSize:newFrameSize];
    
    if (NSEqualSizes(oldFrameSize, newFrameSize))
        [self rebuildBackgroundImage];
}

- (void)drawRect:(NSRect)rect;
{    
    if (!backgroundImageControlFlags.backgroundIsValid)
        [self _rebuildBackgroundImage];
        
    // Draw background
    [self _drawBackgroundImage];
    
    // Draw foreground
    [self drawForegroundRect:rect];

    [super drawRect:rect];
    
    // Draw the focus ring (as determined by the -needsDisplay method)
    if (backgroundImageControlFlags.drawingFocusRing) {
        NSSetFocusRingStyle(NSFocusRingOnly);
	[self _drawBackgroundImage];
    }
}


// API

- (void)rebuildBackgroundImage;
{
    backgroundImageControlFlags.backgroundIsValid = NO;
    [self setNeedsDisplay:YES];
}

- (BOOL)drawsFocusRing;
{
    return backgroundImageControlFlags.shouldDrawFocusRing;
}

- (void)setDrawsFocusRing:(BOOL)flag;
{
    if (flag == backgroundImageControlFlags.shouldDrawFocusRing)
        return;
        
    backgroundImageControlFlags.shouldDrawFocusRing = flag;
    
    [self setNeedsDisplay:YES];
}

// Subclasses only

- (void)drawBackgroundImageForBounds:(NSRect)bounds;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)drawForegroundRect:(NSRect)bounds;
{
    // Don't request a concrete implementation here, because subclasses might not want to draw anything on top of the background image
}

@end

@implementation OABackgroundImageControl (NotificationsDelegatesDatasources)
@end

@implementation OABackgroundImageControl (Private)

- (void)_backgroundImageControlInit;
{
    backgroundImageControlFlags.shouldDrawFocusRing = YES;
}

- (void)_rebuildBackgroundImage;
{
    NSRect bounds;
    
    OBASSERT(!backgroundImageControlFlags.backgroundIsValid);
    
    bounds = [self bounds];
    
    // Only reallocate the background image if it's nil or if it's a different size than the view
    if (backgroundImage == nil || !NSEqualSizes([backgroundImage size], bounds.size)) {
        [backgroundImage release];
        backgroundImage = [[NSImage alloc] initWithSize:bounds.size];
    }
    
    [backgroundImage lockFocus];
    [self drawBackgroundImageForBounds:bounds];
    [backgroundImage unlockFocus];
    
    backgroundImageControlFlags.backgroundIsValid = YES;
}

- (void)_drawBackgroundImage;
{
    [backgroundImage compositeToPoint:NSMakePoint(0, 0) operation:NSCompositeSourceOver];
}

- (BOOL)_shouldDrawFocusRing;
    // Draw the focus ring when a subview of this view is the first responder and the window is key
{
    if (!backgroundImageControlFlags.shouldDrawFocusRing)
        return NO;

    NSWindow *window = [self window];
    id firstResponder = [window firstResponder];
    return [firstResponder isKindOfClass:[NSView class]] && [firstResponder isDescendantOf:self] && [window isKeyWindow];
}

@end
