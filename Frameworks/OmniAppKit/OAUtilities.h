// Copyright 2005-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <AppKit/NSLayoutConstraint.h> // for NSEdgeInsets
#import <Foundation/NSGeometry.h> // for NSInsetRect
#import <Foundation/NSString.h> // for +stringWithFormat:


#import <math.h>
#import <tgmath.h>

// Used to have a ppc frsqrte version, but don't have an x86_64 version right now
static inline CGFloat OAFastReciprocalSquareRoot(CGFloat x)
{
    return (CGFloat)(1.0f / sqrt(x));
}

#if !defined(TARGET_OS_IPHONE) ||!TARGET_OS_IPHONE
#import <Foundation/NSAffineTransform.h>

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

/*
 These have to live here because NSEdgeInsets lives in <AppKit/NSLayoutConstraint.h> instead of in <Foundation/NSGeometry.h> for no good reason
*/

// Slices an NSRect into subrects based on edge inset values. To get three-way slicing, set either top/bottom or left/right insets to zero. All arguments are required. (If you don't care about a value, pass in `&(NSRect){}`.) If isFlipped=YES, top is NSMinYEdge, otherwise it is NSMaxYEdge.
extern void OASliceRectByEdgeInsets(NSRect rect, BOOL isFlipped, NSEdgeInsets insets, NSRect *topLeft, NSRect *midLeft, NSRect *bottomLeft, NSRect *topCenter, NSRect *midCenter, NSRect *bottomCenter, NSRect *topRight, NSRect *midRight, NSRect *bottomRight);

// Insets an NSRect on each side by the amount specified in `insets`. If isFlipped=YES, top is NSMinYEdge, otherwise it is NSMaxYEdge.
static inline NSRect OAInsetRectByEdgeInsets(NSRect rect, NSEdgeInsets insets, BOOL isFlipped)
{
    rect.origin.x += insets.left;
    rect.size.width -= insets.left + insets.right;
    rect.size.height -= insets.top + insets.bottom;
    
    if (isFlipped)
        rect.origin.y += insets.top;
    else
        rect.origin.y += insets.bottom;
    
    return rect;
}

static inline NSRect OAInsetRectBySize(NSRect rect, NSSize size)
{
    return NSInsetRect(rect, size.width, size.height);
}

static inline NSString * __attribute__((overloadable)) OAToString(NSEdgeInsets insets)
{
    return [NSString stringWithFormat:@"{top=%f, left=%f, bottom=%f, right=%f}", insets.top, insets.left, insets.bottom, insets.right];
}
