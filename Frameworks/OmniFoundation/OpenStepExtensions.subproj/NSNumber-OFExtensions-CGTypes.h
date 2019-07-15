// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Foundation/NSGeometry.h>  // This seems to be the most parsimonious way to include CGBase.h for the CGFloat typedef
#else
#import <CoreGraphics/CGBase.h>
#endif

@interface NSNumber (OFCGTypeExtensions)

+ (NSNumber *)numberWithCGFloat:(CGFloat)value;
- (id)initWithCGFloat:(CGFloat)value;
- (CGFloat)cgFloatValue;

@end

@interface NSString (OFCGTypeExtensions)

- (CGFloat)cgFloatValue;

@end


#if defined(CGFLOAT_DEFINED) && CGFLOAT_DEFINED

// Floats and doubles are always promoted to double in variadic args, so we don't need to handle them differently here.
#define PRIaCG "a"
#define PRIeCG "e"
#define PRIfCG "f"
#define PRIgCG "g"

#if defined(CGFLOAT_IS_DOUBLE)
#if CGFLOAT_IS_DOUBLE

// Specify that the arg pointer points to a double.
#define SCNaCG "la"
#define SCNeCG "le"
#define SCNfCG "lf"
#define SCNgCG "lg"

#else

// By default, scanf(3) scans into float pointers, not double pointers.
#define SCNaCG "a"
#define SCNeCG "e"
#define SCNfCG "f"
#define SCNgCG "g"

#endif

#else
#error CGFLOAT_IS_DOUBLE is not defined
#endif
#endif

