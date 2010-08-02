// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "PlainCGShadowDemo.h"

RCS_ID("$Id$")

@implementation PlainCGShadowDemo

- (NSString *)name;
{
    return @"CoreGraphics, resampled";
}

- (void)willMoveToWindow:(UIWindow *)newWindow;
{
    if (newWindow) {
        self.opaque = NO;
        self.clearsContextBeforeDrawing = YES;
        self.backgroundColor = nil;
    }
    
    [super willMoveToWindow:newWindow];
}

- (void)drawRect:(CGRect)rect;
{
    NSLog(@"draw");
    
    CGRect bounds = self.bounds;

    const CGFloat kShadowOffset = 2;
    const CGFloat kShadowRadius = 4;
    const CGFloat kShadowInset = fabs(kShadowOffset) + fabs(kShadowRadius);
    
    CGRect boxRect = CGRectInset(bounds, kShadowInset, kShadowInset);

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    {
        CGContextSetShadow(ctx, CGSizeMake(0, kShadowOffset), kShadowRadius);
        
        [[UIColor grayColor] set];
        CGContextFillRect(ctx, boxRect);
    }
    CGContextRestoreGState(ctx);
}

@end
