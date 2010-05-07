// Copyright 2007-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUThinBorderView.h"
#import <OmniBase/rcsid.h>
#import <AppKit/NSColor.h>

RCS_ID("$Id$");

#define BORDER_WIDTH (1.0f)

@implementation OSUThinBorderView

- (void)awakeFromNib;
{
    // This is hard to get right in nib
    NSView *subview = [[self subviews] lastObject];
    NSRect bounds = [self bounds];
    NSRect inset = NSInsetRect(bounds, BORDER_WIDTH, BORDER_WIDTH);
    [subview setFrame:inset];
}

- (void)drawRect:(NSRect)rect
{
    NSRect bounds = [self bounds];
    [[NSColor lightGrayColor] set];
    NSFrameRectWithWidth(bounds, BORDER_WIDTH);
}

@end
