// Copyright 2001-2005,2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OADottedLine.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OADottedLine

- (void)drawRect:(NSRect)rect {
    NSBezierPath *dottedLinePath;
    const CGFloat lineDash[2] = {1.0, 2.0};

    [[NSColor grayColor] set];
    dottedLinePath = [NSBezierPath bezierPath];
    if ([self bounds].size.width <= [self bounds].size.height) {
        [dottedLinePath moveToPoint:NSMakePoint(NSMinX(_bounds) + 0.5, NSMinY(_bounds) + 3.0)];
        [dottedLinePath lineToPoint:NSMakePoint(NSMinX(_bounds) + 0.5, NSMaxY(_bounds) - 3.0)];
    } else {
        [dottedLinePath moveToPoint:NSMakePoint(NSMinX(_bounds) + 3.0, NSMinY(_bounds) + 0.5)];
        [dottedLinePath lineToPoint:NSMakePoint(NSMaxX(_bounds) - 3.0, NSMinY(_bounds) + 0.5)];
    }
    [dottedLinePath setLineWidth:1.0];
    [dottedLinePath setLineDash:lineDash count:2 phase:0];
    [dottedLinePath stroke];
}

@end
