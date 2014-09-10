// Copyright 2006, 2008, 2010, 2014 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAConstructionTitlebarAccessoryViewController.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>
#import <OmniAppKit/NSColor-OAExtensions.h>

RCS_ID("$Id$");

@interface _OAConstructionTimeView : NSView
@end

#define CONSTRUCTION_WARNING_HEIGHT (14)

@implementation _OAConstructionTimeView

- (BOOL)isOpaque;
{
    return NO;
}

- (void)drawRect:(NSRect)rect;
{
    NSRect bounds = [self bounds];
    
    [OARGBA(1.0, 0.0, 1.0, 0.5) set];
    
    const CGFloat stripeWidth = 10.0f;
    CGFloat height = bounds.size.height;
    
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(ctx);
    {
	CGContextSetBlendMode(ctx, kCGBlendModeDarken);
	CGContextSetAlpha(ctx, 0.075f);
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

- (CGSize)intrinsicContentSize;
{
    return CGSizeMake(NSViewNoInstrinsicMetric, CONSTRUCTION_WARNING_HEIGHT);
}

@end

@implementation OAConstructionTitlebarAccessoryViewController

- (void)loadView;
{
    self.view = [[[_OAConstructionTimeView alloc] initWithFrame:CGRectMake(0, 0, 1, CONSTRUCTION_WARNING_HEIGHT)] autorelease];
    self.layoutAttribute = NSLayoutAttributeBottom;
    self.fullScreenMinHeight = CONSTRUCTION_WARNING_HEIGHT;
}

@end
