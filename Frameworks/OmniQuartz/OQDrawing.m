// Copyright 2003-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <tgmath.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFExtent.h>

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
    CGContextSetPatternPhase([[NSGraphicsContext currentContext] CGContext], phase);
}
#endif

#define CGPathClosePath(p, x) CGPathCloseSubpath(p)
#define PathOp(func, ...) do{ if (isPath) CGPath ## func((CGMutablePathRef)ctxtOrPath, NULL, ## __VA_ARGS__); else CGContext ## func((CGContextRef)ctxtOrPath, ## __VA_ARGS__); }while(0)

#define PickPathOps     BOOL isPath; do { \
    CFTypeID specialization = CFGetTypeID(ctxtOrPath); \
    if (specialization == CGPathGetTypeID()) \
    isPath = YES; \
    else if (specialization == CGContextGetTypeID()) { \
        isPath = NO; \
    } else { \
        OBASSERT_NOT_REACHED("Wrong type passed"); \
        return; \
    } \
} while(0)

//
// Rounded rect support.
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

// These assume a flipped coordinate system (top == CGRectGetMinY, bottom == CGRectGetMaxY)

void OQAppendRectWithRoundedCornerMask(CGContextRef ctx, CGRect rect, CGFloat radius, NSUInteger cornerMask)
{
    CGPoint topMid      = CGPointMake(CGRectGetMidX(rect), CGRectGetMinY(rect));
    CGPoint topLeft     = CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect));
    CGPoint topRight    = CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect));
    CGPoint bottomRight = CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect));
    CGPoint bottomLeft  = CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect));

    CGContextMoveToPoint(ctx, topMid.x, topMid.y);
    
    if (cornerMask & OQRoundedRectCornerTopRight) {
        CGContextAddLineToPoint(ctx, topRight.x - radius, topRight.y);
        CGContextAddArcToPoint(ctx, topRight.x, topRight.y, topRight.x, topRight.y + radius, radius);
    } else {
        CGContextAddLineToPoint(ctx, topRight.x, topRight.y);
        CGContextAddLineToPoint(ctx, topRight.x, topRight.y + radius);
    }
    
    if (cornerMask & OQRoundedRectCornerBottomRight) {
        CGContextAddLineToPoint(ctx, bottomRight.x, bottomRight.y - radius);
        CGContextAddArcToPoint(ctx, bottomRight.x, bottomRight.y, bottomRight.x - radius, bottomRight.y, radius);
    } else {
        CGContextAddLineToPoint(ctx, bottomRight.x, bottomRight.y);
        CGContextAddLineToPoint(ctx, bottomRight.x - radius, bottomRight.y);
    }
    
    if (cornerMask & OQRoundedRectCornerBottomLeft) {
        CGContextAddLineToPoint(ctx, bottomLeft.x + radius, bottomLeft.y);
        CGContextAddArcToPoint(ctx, bottomLeft.x, bottomLeft.y, bottomLeft.x, bottomLeft.y - radius, radius);
    } else {
        CGContextAddLineToPoint(ctx, bottomLeft.x, bottomLeft.y);
        CGContextAddLineToPoint(ctx, bottomLeft.x, bottomLeft.y - radius);
    }
    
    if (cornerMask & OQRoundedRectCornerTopLeft) {
        CGContextAddLineToPoint(ctx, topLeft.x, topLeft.y + radius);
        CGContextAddArcToPoint(ctx, topLeft.x, topLeft.y, topLeft.x + radius, topLeft.y, radius);
    } else {
        CGContextAddLineToPoint(ctx, topLeft.x, topLeft.y);
        CGContextAddLineToPoint(ctx, topLeft.x + radius, topLeft.y);
    }
    
    CGContextClosePath(ctx);
}

// This does not depend no the flippedness of the coordinate system.

void OQAppendRectWithMask(CFTypeRef ctxtOrPath, CGRect rect, unsigned int edgeMask)
{
    PickPathOps;
    
    edgeMask &= OQRectAllEdges;
    if (edgeMask == OQRectAllEdges) {
        PathOp(AddRect, rect);
    } else {
        CGPoint points[7];
        /* Place corners into an array; the edges between the corners are:
           MinX MaxY MaxX MinY MinX MaxY MaxX
        */
        points[0].x = points[1].x = points[4].x = points[5].x = CGRectGetMinX(rect);
        points[2].x = points[3].x = points[6].x =               CGRectGetMaxX(rect);
        points[0].y = points[3].y = points[4].y =               CGRectGetMinY(rect);
        points[1].y = points[2].y = points[5].y = points[6].y = CGRectGetMaxY(rect);
        
        /* This array tells us which edges we need to pass to CGContextAddLines(), based on the edges mask. */
        static const struct { uint_fast8_t start, run; } ph[15] = {
        /*    none      MinX      MinY     MinXY   */
            { 0, 0 }, { 0, 2 }, { 3, 2 }, { 3, 3 },      /* !MaxX   !MaxY */
            { 2, 2 }, { 2, 2 }, { 2, 3 }, { 2, 4 },      /*  MaxX   !MaxY */
            { 1, 2 }, { 0, 3 }, { 3, 2 }, { 3, 4 },      /* !MaxX    MaxY */
            { 1, 3 }, { 0, 4 }, { 1, 4 }
        };
        edgeMask >>= _OQRectAllEdgesShift;
        PathOp(AddLines, points + (ph[edgeMask].start), ph[edgeMask].run);
        
        /* There are two possibilities where there's more than one run of edges. Handle them here. */
        if (edgeMask == ( (OQRectMinXEdge|OQRectMaxXEdge) >> _OQRectAllEdgesShift)) {
            PathOp(AddLines, points + 0, 2);
        } else if (edgeMask == ( (OQRectMinYEdge|OQRectMaxYEdge) >> _OQRectAllEdgesShift)) {
            PathOp(AddLines, points + 1, 2);
        }
    }
}

/* This is the workhorse implementation of OQAppendRoundedRectWithMask(). Simplified cases are passed off to other functions by the inline, but this function can actually handle all cases. */
void OQAppendRoundedRectWithMask_c(CFTypeRef ctxtOrPath, CGRect rect, CGFloat radius, unsigned int mask)
{
    PickPathOps;

    CGPoint points[4];
    points[0].x = points[3].x = CGRectGetMinX(rect);
    points[1].x = points[2].x = CGRectGetMaxX(rect);
    points[0].y = points[1].y = CGRectGetMinY(rect);
    points[2].y = points[3].y = CGRectGetMaxY(rect);
    
    /* bitForCorner[] and edgeAfterCorner[] are unrolled once so that they can be indexed directly by 'corner' */
    static const uint_fast8_t bitForCorner[8] = {
        OQRectMinXMinYCorner, OQRectMaxXMinYCorner, OQRectMaxXMaxYCorner, OQRectMinXMaxYCorner,
        OQRectMinXMinYCorner, OQRectMaxXMinYCorner, OQRectMaxXMaxYCorner, OQRectMinXMaxYCorner,
    };    
    static const uint_fast8_t edgeAfterCorner[8] = {
        OQRectMinYEdge, OQRectMaxXEdge, OQRectMaxYEdge, OQRectMinXEdge,
        OQRectMinYEdge, OQRectMaxXEdge, OQRectMaxYEdge, OQRectMinXEdge,
    };
    
    /* Control points for squircle corners, normalized to the radius */
    const CGFloat k1 = 0.074911, k2 = 0.169060, k3 = 0.372824, k4 = 0.631494, k5 = 0.868407, k6 = 1.088493, k7 = 1.528665;
    
    /* firstCorners[] computes the first corner we want to draw, based on the contents of the edges bitmap.
       We draw any corner that is adjacent to a drawn edge, and we draw them in the order they appear in points[].
       If there are any gaps (i.e., anything other than OQRectAllEdges), we need to start at the beginning of a run of edges--- the first 1-bit that follows a 0-bit. */
    static const uint_fast8_t firstCorners[16] = { 0, 3, 0, 3,
                                                   1, 1, 0, 3,
                                                   2, 2, 0, 2,
                                                   1, 1, 0, 0 };
    
    int firstCorner = firstCorners[ (mask & OQRectAllEdges) >> _OQRectAllEdgesShift ];
    BOOL penUp = 1;
    for(int corner = firstCorner; corner < 4+firstCorner; corner ++) {
        if (penUp && !( mask & edgeAfterCorner[corner] )) {
            continue;
        }
        int cornum = corner % 4;
        CGFloat px = points[cornum].x;
        CGFloat py = points[cornum].y;
        /* Draw this corner, depending on whether the mask indicates it should be rounded, or not. */
        if (mask & bitForCorner[corner]) {
            /* Also draw the edge leading from the last corner to this one (CGContextAddArcToPoint() does this implicitly, but if we're doing squircle corners, we need to do it ourselves). */
            CGFloat ux, uy;
            switch (cornum) {
                case 0: ux =        0; uy =   radius; break;
                case 1: ux = - radius; uy =        0; break;
                case 2: ux =        0; uy = - radius; break;
                case 3: ux =   radius; uy =        0; break;
                default:
                    OBASSERT_NOT_REACHED("only four corners in a square.");
                    return;
            }
            if (penUp || (mask & OQRectIveCorners)) {
                CGFloat approachx = ux, approachy = uy;
                if (mask & OQRectIveCorners) {
                    approachx *= k7;
                    approachy *= k7;
                }
                approachx += px;
                approachy += py;
                if (penUp) {
                    PathOp(MoveToPoint, approachx, approachy);
                    penUp = 0;
                } else {
                    PathOp(AddLineToPoint, approachx, approachy);
                }
            }
            int nextcorner = ( corner + 1 ) % 4;
            if (!(mask & OQRectIveCorners)) {
                PathOp(AddArcToPoint, px, py, points[nextcorner].x, points[nextcorner].y, radius);
            } else {
                /* Our basis vectors are <ux,uy> and <uy,-ux> (since we always go the same direction around the rectangle, we can simply rotate u by 90 degrees) */
                PathOp(AddCurveToPoint, px + ux * k6,           py + uy * k6,           px + ux * k5,           py + uy * k5,           px + ux * k4 + uy * k1, py + uy * k4 - ux * k1);
                PathOp(AddCurveToPoint, px + ux * k3 + uy * k2, py + uy * k3 - ux * k2, px + ux * k2 + uy * k3, py + uy * k2 - ux * k3, px + ux * k1 + uy * k4, py + uy * k1 - ux * k4);
                PathOp(AddCurveToPoint, px           + uy * k5, py           - ux * k5, px           + uy * k6, py           - ux * k6, px           + uy * k7, py           - ux * k7);
            }
        } else {
            /* For a square corner, we can just do a moveto or lineto, as appropriate. */
            if (penUp) {
                PathOp(MoveToPoint, px, py);
                penUp = 0;
            } else {
                PathOp(AddLineToPoint, px, py);
            }
        }
        
        if (!( mask & edgeAfterCorner[corner] )) {
            penUp = 1;
        }
    }
    
    /* As a special case, we want to closepath if all the edges were drawn */
    if ((mask & OQRectAllEdges) == OQRectAllEdges) {
        PathOp(ClosePath);
    } else {
        OBASSERT(penUp);
    }
}

void OQPathAddIveCorner(CGMutablePathRef path, CGPoint from, CGPoint corner, CGFloat radius, BOOL handedness, BOOL lineto)
{
    /* Un-normalized vectors for drawing the shape; f is a normalization factor */
    CGFloat ux = from.x - corner.x;
    CGFloat uy = from.y - corner.y;
    CGFloat vx = handedness? uy : -uy;
    CGFloat vy = handedness? -ux : ux;
    CGFloat f = radius / hypot(ux, uy);
    
    /* Use the basis vectors to construct a transform from (u,v)-space to caller's space */
    CGAffineTransform b = (CGAffineTransform){
        .a  = f*ux,     .b  = f*uy,
        .c  = f*vx,     .d  = f*vy,
        .tx = corner.x, .ty = corner.y
    };
    
    /* Arguments are aligned below so that the symmetry of the figure is more obvious */
    if (lineto) {
        CGPathAddLineToPoint(path, &b,                                      1.528665, 0.000000);
    } else {
        CGPathMoveToPoint(path, &b,                                         1.528665, 0.000000);
    }
    CGPathAddCurveToPoint(path, &b, 1.088493, 0.000000, 0.868407, 0.000000, 0.631494, 0.074911);
    CGPathAddCurveToPoint(path, &b, 0.372824, 0.169060, 0.169060, 0.372824, 0.074911, 0.631494);
    CGPathAddCurveToPoint(path, &b, 0.000000, 0.868407, 0.000000, 1.088493, 0.000000, 1.528665);
}

#if TARGET_OS_IPHONE
void OQDrawImageCenteredInRect(CGContextRef ctx, UIImage *image, CGRect rect)
{
    OQDrawCGImageWithScaleCenteredInRect(ctx, [image CGImage], [image scale], rect);
}
#endif

void OQDrawCGImageWithScaleCenteredInRect(CGContextRef ctx, CGImageRef image, CGFloat scale, CGRect rect)
{
    CGSize imageSize = CGSizeMake(CGImageGetWidth(image) / scale, CGImageGetHeight(image) / scale);
    CGRect imageRect = OQCenteredIntegralRectInRect(rect, imageSize);
    
    CGContextDrawImage(ctx, imageRect, image);
}

void OQPreflightImage(CGImageRef image)
{
    // Force decoding of the image data up front. This can be useful when we want to ensure that UI interaction isn't slowed down the first time a image comes on screen.
    // If we keep the decoded image around, we can end up running out of memory pretty quickly, though.
    // Drawing into a 1x1 image doesn't seem to be enough to decode the image...
#if 1
    CGImageRef flattenedImage = OQCopyFlattenedImage(image);
    CFRelease(flattenedImage);
#else
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, 1, 1, 8/*bitsPerComponent*/, 4/*bytesPerRow*/, colorSpace, kCGImageAlphaNoneSkipFirst);
    CGColorSpaceRelease(colorSpace);
    
    OBASSERT(ctx);
    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), image);
        CGContextRelease(ctx);
    }
#endif
}

CGImageRef OQCopyFlattenedImage(CGImageRef image)
{
    return OQCreateImageWithSize(image, CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image)), kCGInterpolationNone);
}

CGImageRef OQCreateImageWithSize(CGImageRef image, CGSize size, CGInterpolationQuality interpolationQuality)
{
    OBPRECONDITION(image);
    OBPRECONDITION(size.width == floor(size.width));
    OBPRECONDITION(size.height == floor(size.height));
    OBPRECONDITION(size.width >= 1);
    OBPRECONDITION(size.height >= 1);
    
    size_t pixelsWide = (size_t)floor(size.width);
    size_t pixelsHigh = (size_t)floor(size.height);

    if (pixelsWide == CGImageGetWidth(image) && pixelsHigh == CGImageGetHeight(image))
        return CGImageRetain(image);

    // Try building a bitmap context with the same settings as the input image.
    // We can cast CGImageAlphaInfo to CGBitmapInfo here because the lower 0x1F of the latter are an alpha-info mask
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image);
    size_t bytesPerPixel = CGImageGetBitsPerPixel(image) / 8; OBASSERT((CGImageGetBitsPerPixel(image) % 8) == 0);
    CGContextRef ctx = CGBitmapContextCreate(NULL, pixelsWide, pixelsHigh, CGImageGetBitsPerComponent(image), bytesPerPixel*pixelsWide, colorSpace, (CGBitmapInfo)CGImageGetAlphaInfo(image));
    if (!ctx) {
        // Fall back to something that CGBitmapContext actually understands
        CGColorSpaceRef fallbackColorSpace = CGColorSpaceCreateDeviceRGB();

        ctx = CGBitmapContextCreate(NULL, pixelsWide, pixelsHigh, 8/*bitsPerComponent*/, 4*pixelsWide, fallbackColorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedFirst);
        CGColorSpaceRelease(fallbackColorSpace);
    }

    CGContextSetInterpolationQuality(ctx, interpolationQuality);
    CGContextDrawImage(ctx, CGRectMake(0, 0, size.width, size.height), image);
    CGImageRef newImage = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    
    return newImage;
}

