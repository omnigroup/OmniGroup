// Copyright 2006-2008, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIButtonMatrixBackgroundView.h"
#import "OIInspectorController.h"
#import "OIInspectorHeaderView.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OIButtonMatrixBackgroundView

- (void)setBackgroundColor:(NSColor *)aColor;
{
    color = aColor;
    [self setNeedsDisplay:YES];
}

- (BOOL)isOpaque;
{
    return (color != nil && [color alphaComponent] == 1.0);
}

- (BOOL)isFlipped;
{
    return YES;
}

- (void)drawRect:(NSRect)rect;
{
    if (color != nil) {
        [color setFill];
        NSRectFill(rect);
    }
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;
{
    return YES;
}

- (void)mouseDown:(NSEvent *)theEvent;
{
    NSWindow *window = [self window];
   OIInspectorHeaderView *windowHeader = [(OIInspectorController *)[window delegate] headingButton];
    if (windowHeader)
        [windowHeader mouseDown:theEvent];
    return;
}

@end
