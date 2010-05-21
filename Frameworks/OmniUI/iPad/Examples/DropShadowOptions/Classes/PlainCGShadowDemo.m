//
//  PlainCGShadowDemo.m
//  DropShadowOptions
//
//  Created by Timothy J. Wood on 4/2/10.
//  Copyright 2010 The Omni Group. All rights reserved.
//

#import "PlainCGShadowDemo.h"


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
