// Copyright 2006-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIButtonMatrixBackgroundView.h>

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniInspector/OIInspectorController.h>
#import <OmniInspector/OIInspectorHeaderView.h>

RCS_ID("$Id$");

@implementation OIButtonMatrixBackgroundView
{
    NSColor *color;
}

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
    id windowDelegate = [[self window] delegate];
    if ([windowDelegate isKindOfClass:[OIInspectorController class]]) {
        OIInspectorHeaderView *windowHeader = [(OIInspectorController *)windowDelegate headingButton];
        if (windowHeader)
            [windowHeader mouseDown:theEvent];
    }
}

@end
