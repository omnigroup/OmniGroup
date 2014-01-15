// Copyright 2003-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <Availability.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Foundation/NSGeometry.h>
@class NSColor;
@class NSAppleEventDescriptor;
#else
#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CGColor.h>
@class OQColor;
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#define OQ_PLATFORM_COLOR_CLASS UIColor
#else
#define OQ_PLATFORM_COLOR_CLASS NSColor
#endif
@class OQ_PLATFORM_COLOR_CLASS;

typedef struct {
    CGFloat r, g, b, a;
} OQLinearRGBA;

typedef struct {
    CGFloat w, a;
} OQWhiteAlpha;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern OQLinearRGBA OQGetColorComponents(NSColor *c);
#else
extern OQLinearRGBA OQGetColorComponents(OQColor *c);
#endif
extern BOOL OQColorComponentsEqual(OQLinearRGBA x, OQLinearRGBA y);

extern OQLinearRGBA OQGetColorRefComponents(CGColorRef c);
extern CGFloat OQGetRGBAColorLuma(OQLinearRGBA c);
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern CGFloat OQGetColorLuma(NSColor *c, CGFloat *outAlpha);
#endif

extern OQLinearRGBA OQCompositeLinearRGBA(OQLinearRGBA T, OQLinearRGBA B);

static inline OQLinearRGBA OQBlendLinearRGBAColors(OQLinearRGBA A, OQLinearRGBA B, CGFloat fractionOfB)
{
    OBPRECONDITION(fractionOfB >= 0.0);
    OBPRECONDITION(fractionOfB <= 1.0);
    
    CGFloat fractionOfA = 1.0f - fractionOfB;
    
    // 0 = A, 1 = B
    return (OQLinearRGBA){
        A.r * fractionOfA + B.r * fractionOfB,
        A.g * fractionOfA + B.g * fractionOfB,
        A.b * fractionOfA + B.b * fractionOfB,
        A.a * fractionOfA + B.a * fractionOfB,
    };
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern BOOL OQCompositeColors(NSColor **ioTopColor, NSColor *bottomColor);
#else
extern BOOL OQCompositeColors(OQColor **ioTopColor, OQColor *bottomColor);
#endif

extern CGColorRef OQCreateCompositeColorRef(CGColorRef topColor, CGColorRef bottomColor, BOOL *isOpaque);

CGColorRef OQCreateCompositeColorFromColors(CGColorSpaceRef destinationColorSpace, NSArray *colors); // Bottom-most color goes first and must be opaque

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern CGColorRef OQCreateColorRefFromColor(CGColorSpaceRef destinationColorSpace, NSColor *c);
extern NSColor *OQColorFromColorRef(CGColorRef c);

extern CGColorRef OQCreateGrayColorRefFromColor(NSColor *c);
#endif

typedef enum {
    OQColorSpaceRGB,
    OQColorSpaceWhite, // 0=black, 1=white
    OQColorSpaceCMYK,
    OQColorSpaceHSV,
    OQColorSpacePattern,
    OQColorSpaceNamed,
} OQColorSpace;

typedef struct {
    CGFloat h, s, v, a;
} OSHSV;

extern OSHSV OSRGBToHSV(OQLinearRGBA c);
extern OQLinearRGBA OQHSVToRGB(OSHSV c);

@interface OQColor : OFObject <NSCopying>
{
    OQ_PLATFORM_COLOR_CLASS *_platformColor;
}

+ (OQColor *)colorWithCGColor:(CGColorRef)cgColor;
+ (OQColor *)colorWithPlatformColor:(OQ_PLATFORM_COLOR_CLASS *)color;

+ (OQColor *)colorFromRGBAString:(NSString *)rgbaString;
- (NSString *)rgbaString;

+ (OQColor *)colorForPreferenceKey:(NSString *)preferenceKey;
+ (void)setColor:(OQColor *)color forPreferenceKey:(NSString *)preferenceKey;

+ (OQColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
+ (OQColor *)colorWithHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness alpha:(CGFloat)alpha;
+ (OQColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;

// All OQColors are supposedly in the calibrated color space, but add these for API compatibility with NSColor
+ (OQColor *)colorWithCalibratedRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
+ (OQColor *)colorWithCalibratedHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness alpha:(CGFloat)alpha;
+ (OQColor *)colorWithCalibratedWhite:(CGFloat)white alpha:(CGFloat)alpha;

+ (OQColor *)clearColor;
+ (OQColor *)whiteColor;
+ (OQColor *)blackColor;
+ (OQColor *)blueColor;
+ (OQColor *)purpleColor;
+ (OQColor *)redColor;
+ (OQColor *)yellowColor;
+ (OQColor *)grayColor;

+ (OQColor *)keyboardFocusIndicatorColor;
+ (OQColor *)selectedTextBackgroundColor;

- (void)set;

- (BOOL)isEqual:(id)otherObject;

@end

// Concrete subclases, and claim that all instances should conform.
@protocol OQColor
- (OQColorSpace)colorSpace;

- (OQColor *)colorUsingColorSpace:(OQColorSpace)colorSpace;
- (OQColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(OQColor *)otherColor;
- (OQColor *)colorWithAlphaComponent:(CGFloat)fraction;

- (CGFloat)whiteComponent;
- (CGFloat)redComponent;
- (CGFloat)greenComponent;
- (CGFloat)blueComponent;
- (OQLinearRGBA)toRGBA;

- (CGFloat)hueComponent;
- (CGFloat)saturationComponent;
- (CGFloat)brightnessComponent;
- (CGFloat)alphaComponent;
- (OSHSV)toHSV;

// Caller guarantees that color is non-nil and in the same colorspace as the receiver.
- (BOOL)isEqualToColorInSameColorSpace:(OQColor *)color;
- (NSUInteger)hash;

@property(readonly,nonatomic) OQ_PLATFORM_COLOR_CLASS *toColor;
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (NSAppleEventDescriptor *)scriptingColorDescriptor;
#endif

@end
@interface OQColor (OQColor) <OQColor>
@end

#ifndef __has_feature
#define __has_feature(x) 0
#endif
#if __has_feature(attribute_overloadable)

static inline OQColor * __attribute__((overloadable)) OQMakeColor(OQLinearRGBA c)
{
    return [OQColor colorWithRed:c.r green:c.g blue:c.b alpha:c.a];
}
static inline OQColor * __attribute__((overloadable)) OQMakeColor(OSHSV c)
{
    return [OQColor colorWithHue:c.h saturation:c.s brightness:c.v alpha:c.a];
}
static inline OQColor * __attribute__((overloadable)) OQMakeColor(OQWhiteAlpha c)
{
    return [OQColor colorWithWhite:c.w alpha:c.a];
}

static inline OQColor * __attribute__((overloadable)) OQMakeColorWithAlpha(OQLinearRGBA c, CGFloat a)
{
    return [OQColor colorWithRed:c.r green:c.g blue:c.b alpha:a];
}
static inline OQColor * __attribute__((overloadable)) OQMakeColorWithAlpha(OSHSV c, CGFloat a)
{
    return [OQColor colorWithHue:c.h saturation:c.s brightness:c.v alpha:a];
}
static inline OQColor * __attribute__((overloadable)) OQMakeColorWithAlpha(OQWhiteAlpha c, CGFloat a)
{
    return [OQColor colorWithWhite:c.w alpha:a];
}

static inline BOOL __attribute__((overloadable)) OQColorsEqual(OQLinearRGBA c1, OQLinearRGBA c2)
{
    return c1.r == c2.r && c1.g == c2.g && c1.b == c2.b && c1.a == c2.a;
}
static inline BOOL __attribute__((overloadable)) OQColorsEqual(OSHSV c1, OSHSV c2)
{
    return c1.h == c2.h && c1.s == c2.s && c1.v == c2.v && c1.a == c2.a;
}
static inline BOOL __attribute__((overloadable)) OQColorsEqual(OQWhiteAlpha c1, OQWhiteAlpha c2)
{
    return c1.w == c2.w && c1.a == c2.a;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIColor.h>
static inline UIColor * __attribute__((overloadable)) OQMakeUIColor(OQLinearRGBA c)
{
    return [UIColor colorWithRed:c.r green:c.g blue:c.b alpha:c.a];
}
static inline UIColor * __attribute__((overloadable)) OQMakeUIColor(OSHSV c)
{
    return [UIColor colorWithHue:c.h saturation:c.s brightness:c.v alpha:c.a];
}
static inline UIColor * __attribute__((overloadable)) OQMakeUIColor(OQWhiteAlpha c)
{
    return [UIColor colorWithWhite:c.w alpha:c.a];
}
#endif

#endif

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
typedef struct {
    OQLinearRGBA color1, color2;
} OQRGBAColorPair;

extern void OQFillRGBAColorPair(OQRGBAColorPair *pair, NSColor *color1, NSColor *color2);

extern const CGFunctionCallbacks OQLinearFunctionCallbacks;

#endif
