// Copyright 2005-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>

#import <math.h>
#include <tgmath.h>

static inline CGFloat OAFastReciprocalSquareRoot(CGFloat x)
{
    return 1.0f / sqrt(x);
}

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

extern BOOL OAPushValueThroughBinding(id self, id objectValue, NSString *binding);

