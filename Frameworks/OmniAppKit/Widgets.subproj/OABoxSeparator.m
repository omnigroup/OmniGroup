// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
//  OABoxSeparator.m
//  OmniAppKit
//
// Copyright 2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import "OABoxSeparator.h"
#import <AppKit/NSColor.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@implementation OABoxSeparator

- (void)drawRect:(NSRect)rect
{
    if ([self boxType] != NSBoxSeparator) {
	OBASSERT_NOT_REACHED("This subclass can only draw separators.");
	[super drawRect:rect];
        return;
    }
    
    if (![self lineColor]) {
        [self setLineColor:[NSColor colorWithCalibratedWhite:(CGFloat)0.7 alpha:1]];
    }
    
    NSRect bounds = [self bounds];
    CGFloat y = bounds.size.height / 2;
    
    [[self lineColor] set];
    NSRectFill((NSRect){
        .origin = { bounds.origin.x, y - (CGFloat)0.5 },
        .size = { bounds.size.width, 1 }
    });
}

@synthesize lineColor;

@end
