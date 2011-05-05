// Copyright 2003-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <tgmath.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/OmniBase.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/NSView.h>
#endif

RCS_ID("$Id$");

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
void OQSetPatternColorReferencePoint(CGPoint point, NSView *view)
{
    CGPoint refPoint = [view convertPoint:point toView:nil];
    CGSize phase = (CGSize){refPoint.x, refPoint.y};
    CGContextSetPatternPhase([[NSGraphicsContext currentContext] graphicsPort], phase);
}
#endif

//
// Rounded rect support.  These both assume a flipped coordinate system (top == CGRectGetMinY, bottom == CGRectGetMaxY)
//
void OQAppendRoundedRect(CGContextRef ctx, CGRect rect, CGFloat radius)
{
    CGPoint topMid      = CGPointMake(CGRectGetMidX(rect), CGRectGetMaxY(rect));
    CGPoint topLeft     = CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect));
    CGPoint topRight    = CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect));
    CGPoint bottomRight = CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect));
    
    CGContextMoveToPoint(ctx, topMid.x, topMid.y);
    CGContextAddArcToPoint(ctx, topLeft.x, topLeft.y, rect.origin.x, rect.origin.y, radius);
    CGContextAddArcToPoint(ctx, rect.origin.x, rect.origin.y, bottomRight.x, bottomRight.y, radius);
    CGContextAddArcToPoint(ctx, bottomRight.x, bottomRight.y, topRight.x, topRight.y, radius);
    CGContextAddArcToPoint(ctx, topRight.x, topRight.y, topLeft.x, topLeft.y, radius);
    CGContextClosePath(ctx);
}

void OQAddRoundedRect(CGMutablePathRef path, CGRect rect, CGFloat radius)
{
    CGPoint topMid      = CGPointMake(CGRectGetMidX(rect), CGRectGetMaxY(rect));
    CGPoint topLeft     = CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect));
    CGPoint topRight    = CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect));
    CGPoint bottomRight = CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect));
    
    CGPathMoveToPoint(path, NULL, topMid.x, topMid.y);
    CGPathAddArcToPoint(path, NULL, topLeft.x, topLeft.y, rect.origin.x, rect.origin.y, radius);
    CGPathAddArcToPoint(path, NULL, rect.origin.x, rect.origin.y, bottomRight.x, bottomRight.y, radius);
    CGPathAddArcToPoint(path, NULL, bottomRight.x, bottomRight.y, topRight.x, topRight.y, radius);
    CGPathAddArcToPoint(path, NULL, topRight.x, topRight.y, topLeft.x, topLeft.y, radius);
    CGPathCloseSubpath(path);
}

void OQAppendRectWithRoundedTop(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeBottom)
{
    CGPoint topLeft     = CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect));
    CGPoint topRight    = CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect));
    CGPoint bottomRight = CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect));
    CGPoint bottomLeft  = CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect));
    
    CGContextMoveToPoint(ctx, bottomLeft.x, bottomLeft.y);
    CGContextAddLineToPoint(ctx, topLeft.x, topLeft.y + radius);
    CGContextAddArcToPoint(ctx, topLeft.x, topLeft.y, topLeft.x + radius, topLeft.y, radius);
    CGContextAddLineToPoint(ctx, topRight.x - radius, topRight.y);
    CGContextAddArcToPoint(ctx, topRight.x, topRight.y, topRight.x, topRight.y + radius, radius);
    CGContextAddLineToPoint(ctx, bottomRight.x, bottomRight.y);
    
    if (closeBottom)
        CGContextClosePath(ctx);
}

void OQAppendRectWithRoundedBottom(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeTop)
{
    CGPoint bottomLeft  = CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect));
    CGPoint bottomRight = CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect));
    CGPoint topRight    = CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect));
    CGPoint topLeft     = CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect));
    
    CGContextMoveToPoint(ctx, topLeft.x, topLeft.y);
    CGContextAddLineToPoint(ctx, bottomLeft.x, bottomLeft.y - radius);
    CGContextAddArcToPoint(ctx, bottomLeft.x, bottomLeft.y, bottomLeft.x + radius, bottomLeft.y, radius);
    CGContextAddLineToPoint(ctx, bottomRight.x - radius, bottomRight.y);
    CGContextAddArcToPoint(ctx, bottomRight.x, bottomRight.y, bottomRight.x, bottomRight.y - radius, radius);
    CGContextAddLineToPoint(ctx, topRight.x, topRight.y);
    
    if (closeTop)
        CGContextClosePath(ctx);
}

void OQAppendRectWithRoundedLeft(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeRight)
{
    CGPoint bottomLeft  = CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect));
    CGPoint bottomRight = CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect));
    CGPoint topRight    = CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect));
    CGPoint topLeft     = CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect));
    
    CGContextMoveToPoint(ctx, topRight.x, topRight.y);
    CGContextAddLineToPoint(ctx, topLeft.x + radius, topLeft.y);
    CGContextAddArcToPoint(ctx, topLeft.x, topLeft.y, topLeft.x, topLeft.y + radius, radius);
    CGContextAddLineToPoint(ctx, bottomLeft.x, bottomLeft.y - radius );
    CGContextAddArcToPoint(ctx, bottomLeft.x, bottomLeft.y, bottomLeft.x + radius, bottomLeft.y, radius);
    CGContextAddLineToPoint(ctx, bottomRight.x, bottomRight.y);
    
    if (closeRight)
        CGContextClosePath(ctx);
}

void OQAppendRectWithRoundedRight(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeLeft)
{
    CGPoint bottomLeft  = CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect));
    CGPoint bottomRight = CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect));
    CGPoint topRight    = CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect));
    CGPoint topLeft     = CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect));
    
    CGContextMoveToPoint(ctx, topLeft.x, topLeft.y);
    CGContextAddLineToPoint(ctx, topRight.x - radius, topRight.y);
    CGContextAddArcToPoint(ctx, topRight.x, topRight.y, topRight.x, topRight.y + radius, radius);
    CGContextAddLineToPoint(ctx, bottomRight.x, bottomRight.y - radius );
    CGContextAddArcToPoint(ctx, bottomRight.x, bottomRight.y, bottomRight.x - radius, bottomRight.y, radius);
    CGContextAddLineToPoint(ctx, bottomLeft.x, bottomLeft.y);
    
    if (closeLeft)
        CGContextClosePath(ctx);
}

CGRect OQCenteredIntegralRectInRect(CGRect enclosingRect, CGSize toCenter)
{
    CGPoint pt;
    
    pt.x = CGRectGetMinX(enclosingRect) + (enclosingRect.size.width - toCenter.width)/2;
    pt.y = CGRectGetMinY(enclosingRect) + (enclosingRect.size.height - toCenter.height)/2;
    
    // TODO: Assuming 1-1 mapping between user and device space
    pt.x = ceil(pt.x);
    pt.y = ceil(pt.y);
    
    return CGRectMake(pt.x, pt.y, toCenter.width, toCenter.height);
}

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED

#if __MAC_OS_X_VERSION_MIN_REQUIRED < 40000 /* Apple recommends using literal numbers here instead of version constants */
/* It's important that the compiler select the CGFloat declaration of -scale instead of the one that returns 'short' ! */
@interface UIImage (OQForwardCompatibility)
@property(nonatomic,readonly) CGFloat scale;
@end
#endif

void OQDrawImageCenteredInRect(CGContextRef ctx, UIImage *image, CGRect rect)
{
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 40000 /* Apple recommends using literal numbers here instead of version constants */
    /* -[UIImage scale] appeared in iOS 4.0 */
    CGFloat scale = [image respondsToSelector:@selector(scale)] ? [image scale] : 1.0;
#else
    CGFloat scale = [image scale];
#endif
    OQDrawCGImageWithScaleCenteredInRect(ctx, [image CGImage], scale, rect);
}
#endif

void OQDrawCGImageWithScaleCenteredInRect(CGContextRef ctx, CGImageRef image, CGFloat scale, CGRect rect)
{
    CGSize imageSize = CGSizeMake(CGImageGetWidth(image) / scale, CGImageGetHeight(image) / scale);
    CGRect imageRect = OQCenteredIntegralRectInRect(rect, imageSize);
    
    CGContextDrawImage(ctx, imageRect, image);
}
