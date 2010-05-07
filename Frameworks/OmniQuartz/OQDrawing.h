// Copyright 2003-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

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

extern void OQDrawImageCenteredInRect(CGContextRef ctx, CGImageRef image, CGRect rect);

void OQCrosshatchRect(CGContextRef ctxt, CGRect rect, CGFloat lineWidth, CGFloat dx, CGFloat dy);


// Returns the overall dilation of a transformation matrix (may be negative if there's a reflection involved)
// This is the proportional change in area of a figure (rectangle, filled path, etc)
static inline CGFloat OQAffineTransformGetDilation(CGAffineTransform m)
{
    return m.a * m.d - m.b * m.c;
}
