// Copyright 2005-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>

#ifdef __ppc__

// Vanilla PPC code, but since PPC has a reciprocal square root estimate instruction,
// runs *much* faster than calling sqrt().  We'll use one Newton-Raphson
// refinement step to get bunch more precision in the 1/sqrt() value for very little cost.
// it returns fairly accurate results (error below 1.0e-5 up to 100000.0 in 0.1 increments).

// added -force_cpusubtype_ALL to get this to compile
static inline float OAFastReciprocalSquareRoot(float x)
{
    const float half = 0.5;
    const float one  = 1.0;
    float B, est_y0, est_y1;
    
    // This'll NaN if it hits frsqrte.  Handle both +0.0 and -0.0
    if (fabsf(x) == 0.0)
        return x;
        
    B = x;
    asm("frsqrte %0,%1" : "=f" (est_y0) : "f" (B));

    /* First refinement step */
    est_y1 = est_y0 + half*est_y0*(one - B*est_y0*est_y0);

    return est_y1;
}

#else

#import <math.h>

static inline float OAFastReciprocalSquareRoot(float x)
{
    return 1.0f / sqrtf(x);
}

#endif


#if defined(__COREGRAPHICS__) && !defined(__cplusplus)

/*
 AppKit and CoreGraphics both use the good old PostScript six-element homogeneous coordinate transform matrix, but they name the elements differently ...
*/

static inline CGAffineTransform CGAffineTransformFromNS(NSAffineTransformStruct m)
{
    return (CGAffineTransform){
        .a = m.m11,
        .b = m.m12,
        .c = m.m21,
        .d = m.m22,
        .tx = m.tX,
        .ty = m.tY
    };
}

static inline NSAffineTransformStruct NSAffineTransformFromCG(CGAffineTransform c)
{
    return (NSAffineTransformStruct){
        .m11 = c.a,
        .m12 = c.b,
        .m21 = c.c,
        .m22 = c.d,
        .tX = c.tx,
        .tY = c.ty
    };
}

#endif

