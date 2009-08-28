// Copyright 2006, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAConstructionTimeView.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>

RCS_ID("$Id$");

@implementation OAConstructionTimeView

- (BOOL)isOpaque;
{
    return NO;
}

- (void)drawRect:(NSRect)rect;
{
    NSRect bounds = [self bounds];
    
    [[NSColor colorWithCalibratedRed:1.0 green:0.0 blue:1.0 alpha:0.5] set];
    
    const float stripeWidth = 10.0f;
    float height = bounds.size.height;
    
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(ctx);
    {
	CGContextSetBlendMode(ctx, kCGBlendModeDarken);
	CGContextSetAlpha(ctx, 0.075);
	CGContextBeginTransparencyLayer(ctx, NULL);
	{
	    [[NSColor blackColor] setFill];
	    NSRectFill(bounds);
	    
	    CGPoint p = CGPointMake(bounds.origin.x - bounds.size.height, bounds.origin.y); // start far enough to the left that we'll cover the title area
	    
	    [[NSColor yellowColor] setFill];
	    while (p.x <= NSMaxX(bounds)) {
		CGContextMoveToPoint(ctx, p.x, p.y);
		CGContextAddLineToPoint(ctx, p.x + height, p.y + height);
		CGContextAddLineToPoint(ctx, p.x + height + stripeWidth, p.y + height);
		CGContextAddLineToPoint(ctx, p.x + stripeWidth, p.y);
		CGContextClosePath(ctx);
		p.x += 2*stripeWidth;
	    }
	    CGContextFillPath(ctx);
	}
	CGContextEndTransparencyLayer(ctx);
    }
    CGContextRestoreGState(ctx);
}

- (NSView *)hitTest:(NSPoint)aPoint;
{
    return nil;
}

@end
