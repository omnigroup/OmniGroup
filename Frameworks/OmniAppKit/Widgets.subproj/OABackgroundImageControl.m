// Copyright 2003-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OABackgroundImageControl.h>

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

// Init

- (id)initWithFrame:(NSRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
        
    [self _backgroundImageControlInit];
    
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    
    [self _backgroundImageControlInit];
    
    return self;
}

// NSView subclass

- (BOOL)needsDisplay;
{
    BOOL shouldDrawFocusRing = [self _shouldDrawFocusRing];
    BOOL isDrawingFocusRing = (backgroundImageControlFlags.drawingFocusRing != 0);
    if (isDrawingFocusRing ^ shouldDrawFocusRing) {
        backgroundImageControlFlags.drawingFocusRing = shouldDrawFocusRing ? 1 : 0;
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
    BOOL drawsFocusRing = (backgroundImageControlFlags.shouldDrawFocusRing != 0);
    if (flag == drawsFocusRing)
        return;
        
    backgroundImageControlFlags.shouldDrawFocusRing = (flag ? 1 : 0);
    
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
        backgroundImage = [[NSImage alloc] initWithSize:bounds.size];
    }
    
    [backgroundImage lockFocus];
    [self drawBackgroundImageForBounds:bounds];
    [backgroundImage unlockFocus];
    
    backgroundImageControlFlags.backgroundIsValid = YES;
}

- (void)_drawBackgroundImage;
{
    [backgroundImage drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0f];
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
