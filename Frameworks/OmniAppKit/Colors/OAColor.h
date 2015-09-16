// Copyright 2003-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <Availability.h>

#import <OmniBase/assertions.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Foundation/NSGeometry.h>
@class NSColor;
@class NSAppleEventDescriptor;
#else
#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CGColor.h>
@class OAColor;
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#define OA_PLATFORM_COLOR_CLASS UIColor
#else
#define OA_PLATFORM_COLOR_CLASS NSColor
#endif
@class OA_PLATFORM_COLOR_CLASS;

typedef struct {
    CGFloat r, g, b, a;
} OALinearRGBA;

typedef struct {
    CGFloat w, a;
} OAWhiteAlpha;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern OALinearRGBA OAGetColorComponents(NSColor *c);
#else
extern OALinearRGBA OAGetColorComponents(OAColor *c);
#endif
extern BOOL OAColorComponentsEqual(OALinearRGBA x, OALinearRGBA y);

extern OALinearRGBA OAGetColorRefComponents(CGColorRef c);
extern CGFloat OAGetRGBAColorLuma(OALinearRGBA c);
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern CGFloat OAGetColorLuma(NSColor *c, CGFloat *outAlpha);
#endif

extern OALinearRGBA OACompositeLinearRGBA(OALinearRGBA T, OALinearRGBA B);

static inline OALinearRGBA OABlendLinearRGBAColors(OALinearRGBA A, OALinearRGBA B, CGFloat fractionOfB)
{
    OBPRECONDITION(fractionOfB >= 0.0);
    OBPRECONDITION(fractionOfB <= 1.0);
    
    CGFloat fractionOfA = 1.0f - fractionOfB;
    
    // 0 = A, 1 = B
    return (OALinearRGBA){
        A.r * fractionOfA + B.r * fractionOfB,
        A.g * fractionOfA + B.g * fractionOfB,
        A.b * fractionOfA + B.b * fractionOfB,
        A.a * fractionOfA + B.a * fractionOfB,
    };
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern BOOL OACompositeColors(NSColor **ioTopColor, NSColor *bottomColor);
#else
extern BOOL OACompositeColors(OAColor **ioTopColor, OAColor *bottomColor);
#endif

extern CGColorRef OACreateCompositeColorRef(CGColorRef topColor, CGColorRef bottomColor, BOOL *isOpaque) CF_RETURNS_RETAINED;

CGColorRef OACreateCompositeColorFromColors(CGColorSpaceRef destinationColorSpace, NSArray *colors) CF_RETURNS_RETAINED; // Bottom-most color goes first and must be opaque

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern CGColorRef OACreateColorRefFromColor(CGColorSpaceRef destinationColorSpace, NSColor *c) CF_RETURNS_RETAINED;
extern NSColor *OAColorFromColorRef(CGColorRef c);

extern CGColorRef OACreateGrayColorRefFromColor(NSColor *c) CF_RETURNS_RETAINED;
#endif

typedef enum {
    OAColorSpaceRGB,
    OAColorSpaceWhite, // 0=black, 1=white
    OAColorSpaceCMYK,
    OAColorSpaceHSV,
    OAColorSpacePattern,
    OAColorSpaceNamed,
} OAColorSpace;

typedef struct {
    CGFloat h, s, v, a;
} OAHSV;

extern OAHSV OARGBToHSV(OALinearRGBA c);
extern OALinearRGBA OAHSVToRGB(OAHSV c);

@interface OAColor : OFObject <NSCopying>
{
    OA_PLATFORM_COLOR_CLASS *_platformColor;
}

+ (OAColor *)colorWithCGColor:(CGColorRef)cgColor;
+ (OAColor *)colorWithPlatformColor:(OA_PLATFORM_COLOR_CLASS *)color;

+ (OAColor *)colorFromRGBAString:(NSString *)rgbaString;
- (NSString *)rgbaString;

+ (OAColor *)colorForPreferenceKey:(NSString *)preferenceKey;
+ (void)setColor:(OAColor *)color forPreferenceKey:(NSString *)preferenceKey;

+ (OAColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
+ (OAColor *)colorWithHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness alpha:(CGFloat)alpha;
+ (OAColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;

// All OAColors are supposedly in the calibrated color space, but add these for API compatibility with NSColor
+ (OAColor *)colorWithCalibratedRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
+ (OAColor *)colorWithCalibratedHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness alpha:(CGFloat)alpha;
+ (OAColor *)colorWithCalibratedWhite:(CGFloat)white alpha:(CGFloat)alpha;

+ (OAColor *)clearColor;
+ (OAColor *)whiteColor;
+ (OAColor *)blackColor;
+ (OAColor *)blueColor;
+ (OAColor *)purpleColor;
+ (OAColor *)redColor;
+ (OAColor *)yellowColor;
+ (OAColor *)grayColor;

+ (OAColor *)keyboardFocusIndicatorColor;
+ (OAColor *)selectedTextBackgroundColor;

- (void)set;

- (BOOL)isEqual:(id)otherObject;

@end

// Concrete subclases, and claim that all instances should conform.
@protocol OAColor
- (OAColorSpace)colorSpace;

- (OAColor *)colorUsingColorSpace:(OAColorSpace)colorSpace;
- (OAColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(OAColor *)otherColor;
- (OAColor *)colorWithAlphaComponent:(CGFloat)fraction;

- (CGFloat)whiteComponent;
- (CGFloat)redComponent;
- (CGFloat)greenComponent;
- (CGFloat)blueComponent;
- (OALinearRGBA)toRGBA;

- (CGFloat)hueComponent;
- (CGFloat)saturationComponent;
- (CGFloat)brightnessComponent;
- (CGFloat)alphaComponent;
- (OAHSV)toHSV;

// Caller guarantees that color is non-nil and in the same colorspace as the receiver.
- (BOOL)isEqualToColorInSameColorSpace:(OAColor *)color;
- (NSUInteger)hash;

@property(readonly,nonatomic) OA_PLATFORM_COLOR_CLASS *toColor;
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (NSAppleEventDescriptor *)scriptingColorDescriptor;
#endif

@end
@interface OAColor (OAColor) <OAColor>
@end

#ifndef __has_feature
#define __has_feature(x) 0
#endif
#if __has_feature(attribute_overloadable)

static inline OAColor * __attribute__((overloadable)) OAMakeColor(OALinearRGBA c)
{
    return [OAColor colorWithRed:c.r green:c.g blue:c.b alpha:c.a];
}
static inline OAColor * __attribute__((overloadable)) OAMakeColor(OAHSV c)
{
    return [OAColor colorWithHue:c.h saturation:c.s brightness:c.v alpha:c.a];
}
static inline OAColor * __attribute__((overloadable)) OAMakeColor(OAWhiteAlpha c)
{
    return [OAColor colorWithWhite:c.w alpha:c.a];
}

static inline OAColor * __attribute__((overloadable)) OAMakeColorWithAlpha(OALinearRGBA c, CGFloat a)
{
    return [OAColor colorWithRed:c.r green:c.g blue:c.b alpha:a];
}
static inline OAColor * __attribute__((overloadable)) OAMakeColorWithAlpha(OAHSV c, CGFloat a)
{
    return [OAColor colorWithHue:c.h saturation:c.s brightness:c.v alpha:a];
}
static inline OAColor * __attribute__((overloadable)) OAMakeColorWithAlpha(OAWhiteAlpha c, CGFloat a)
{
    return [OAColor colorWithWhite:c.w alpha:a];
}

static inline BOOL __attribute__((overloadable)) OAColorsEqual(OALinearRGBA c1, OALinearRGBA c2)
{
    return c1.r == c2.r && c1.g == c2.g && c1.b == c2.b && c1.a == c2.a;
}
static inline BOOL __attribute__((overloadable)) OAColorsEqual(OAHSV c1, OAHSV c2)
{
    return c1.h == c2.h && c1.s == c2.s && c1.v == c2.v && c1.a == c2.a;
}
static inline BOOL __attribute__((overloadable)) OAColorsEqual(OAWhiteAlpha c1, OAWhiteAlpha c2)
{
    return c1.w == c2.w && c1.a == c2.a;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIColor.h>
static inline UIColor * __attribute__((overloadable)) OAMakeUIColor(OALinearRGBA c)
{
    return [UIColor colorWithRed:c.r green:c.g blue:c.b alpha:c.a];
}
static inline UIColor * __attribute__((overloadable)) OAMakeUIColor(OAHSV c)
{
    return [UIColor colorWithHue:c.h saturation:c.s brightness:c.v alpha:c.a];
}
static inline UIColor * __attribute__((overloadable)) OAMakeUIColor(OAWhiteAlpha c)
{
    return [UIColor colorWithWhite:c.w alpha:c.a];
}
#endif

#endif

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
typedef struct {
    OALinearRGBA color1, color2;
} OARGBAColorPair;

extern void OAFillRGBAColorPair(OARGBAColorPair *pair, NSColor *color1, NSColor *color2);

extern const CGFunctionCallbacks OALinearFunctionCallbacks;

#endif
