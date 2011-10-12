// Copyright 2003-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#if TARGET_OS_IPHONE
    #import <UIKit/UIKit.h>
#endif

#import <OmniBase/assertions.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern void OQSetPatternColorReferencePoint(CGPoint point, NSView *view);
#else
#import <CoreGraphics/CoreGraphics.h>
#endif

// Rounded rect support.
extern void OQAppendRoundedRect(CGContextRef ctx, CGRect rect, CGFloat radius);
extern void OQAddRoundedRect(CGMutablePathRef path, CGRect rect, CGFloat radius);

// These all assume a flipped coordinate system (top == CGRectGetMinY, bottom == CGRectGetMaxY)
extern void OQAppendRectWithRoundedTop(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeBottom);
extern void OQAppendRectWithRoundedBottom(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeTop);
extern void OQAppendRectWithRoundedLeft(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeRight);
extern void OQAppendRectWithRoundedRight(CGContextRef ctx, CGRect rect, CGFloat radius, BOOL closeLeft);

// Updates the CTM so that the lower/upper edges of the rect are swapped.
static inline void OQFlipVerticallyInRect(CGContextRef ctx, CGRect rect)
{
    CGContextConcatCTM(ctx, (CGAffineTransform){ 1, 0, 0, -1, 0, 2 * rect.origin.y + rect.size.height });
}

extern CGRect OQCenteredIntegralRectInRect(CGRect enclosingRect, CGSize toCenter);
extern CGRect OQLargestCenteredIntegralRectInRectWithAspectRatioAsSize(CGRect enclosingRect, CGSize toCenter);

#if TARGET_OS_IPHONE
extern void OQDrawImageCenteredInRect(CGContextRef ctx, UIImage *image, CGRect rect);
#endif
extern void OQDrawCGImageWithScaleCenteredInRect(CGContextRef ctx, CGImageRef image, CGFloat scale, CGRect rect);

void OQCrosshatchRect(CGContextRef ctxt, CGRect rect, CGFloat lineWidth, CGFloat dx, CGFloat dy);


// Returns the overall dilation of a transformation matrix (may be negative if there's a reflection involved)
// This is the proportional change in area of a figure (rectangle, filled path, etc)
static inline CGFloat OQAffineTransformGetDilation(CGAffineTransform m)
{
    return m.a * m.d - m.b * m.c;
}

// SVG-style paths
CGPathRef OQCGPathCreateFromSVGPath(const unsigned char *d, size_t d_length);
int OQCGContextAddSVGPath(CGContextRef cgContext, const unsigned char *d, size_t d_length);

// SVG-style arcs
struct OQEllipseParameters {
    CGPoint center;              // Computed center of the ellipse.
    unsigned int numSegments;    // At most 4 Bezier segments in the result.
    CGPoint points[ 3 * 4 ];     // Three control points per segment; first segment's currentpoint is (0,0).
};
/*
 Computes the parameters of an elliptical arc as given by the SVG-style arc operator.
 delta is the vector from the start to the end of the arc.
 rMaj and rMin are the major and minor radii of the ellipse.
 theta is the angle of the major radius (0 -> towards positive X, pi/4 -> towards +X,+Y).
 largeSweep and posAngle disambiguate between the four possible fits to the above parameters.
 */
void OQComputeEllipseParameters(CGFloat deltaX, CGFloat deltaY,
                                CGFloat rMaj, CGFloat rMin, CGFloat theta,
                                BOOL largeSweep, BOOL posAngle,
                                struct OQEllipseParameters *result);
