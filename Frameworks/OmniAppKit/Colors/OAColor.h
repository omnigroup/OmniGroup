// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <Availability.h>

#import <OmniBase/assertions.h>

#if OMNI_BUILDING_FOR_MAC
#import <Foundation/NSGeometry.h>
#import <CoreGraphics/CGColor.h>
@class NSColor;
@class NSAppleEventDescriptor;
#endif

#if OMNI_BUILDING_FOR_IOS
#import <UIKit/UIColor.h>
#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CGColor.h>
@class OAColor;
#endif

#if OMNI_BUILDING_FOR_SERVER
#import <OmniFoundation/OFGeometry.h> // For CGFloat
@class OAColor;
#endif

#if 0 && defined(DEBUG_bungi)
    #define OA_SUPPORT_PATTERN_COLOR 1
#else
    #define OA_SUPPORT_PATTERN_COLOR 0
#endif

NS_ASSUME_NONNULL_BEGIN

#if OMNI_BUILDING_FOR_IOS
#define OA_PLATFORM_COLOR_CLASS UIColor
#endif

#if OMNI_BUILDING_FOR_MAC
#define OA_PLATFORM_COLOR_CLASS NSColor
#endif

#ifdef OA_PLATFORM_COLOR_CLASS
@class OA_PLATFORM_COLOR_CLASS;

// To expose to Swift:
typedef OA_PLATFORM_COLOR_CLASS *OAPlatformColorClass;
#endif

typedef struct {
    CGFloat r, g, b, a;
} OALinearRGBA;

typedef struct {
    CGFloat w, a;
} OAWhiteAlpha;

#if OMNI_BUILDING_FOR_MAC
extern OALinearRGBA OAGetColorComponents(NSColor *c);
#endif

#if OMNI_BUILDING_FOR_IOS
extern OALinearRGBA OAGetColorComponents(OAColor *c);
#endif

extern BOOL OAColorComponentsEqual(OALinearRGBA x, OALinearRGBA y);

#if OMNI_BUILDING_FOR_MAC || OMNI_BUILDING_FOR_IOS
extern OALinearRGBA OAGetColorRefComponents(CGColorRef c);
#endif

extern CGFloat OAGetRGBAColorLuma(OALinearRGBA c);

#if OMNI_BUILDING_FOR_MAC
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

#if OMNI_BUILDING_FOR_MAC
extern NSColor * _Nullable OACompositeColors(NSColor * _Nullable topColor, NSColor * _Nullable bottomColor, BOOL * _Nullable isOpaque);
#else
extern OAColor * _Nullable OACompositeColors(OAColor * _Nullable topColor, OAColor * _Nullable bottomColor, BOOL * _Nullable isOpaque);
#endif

#if OMNI_BUILDING_FOR_MAC || OMNI_BUILDING_FOR_IOS
extern CGColorRef OACreateCompositeColorRef(CGColorRef topColor, CGColorRef bottomColor, BOOL * _Nullable isOpaque) CF_RETURNS_RETAINED;
CGColorRef OACreateCompositeColorFromColors(CGColorSpaceRef destinationColorSpace, NSArray *colors) CF_RETURNS_RETAINED; // Bottom-most color goes first and must be opaque
#endif


#if OMNI_BUILDING_FOR_MAC
extern CGColorRef __nullable OACreateColorRefFromColor(CGColorSpaceRef destinationColorSpace, NSColor *c) CF_RETURNS_RETAINED;
extern NSColor * __nullable OAColorFromColorRef(CGColorRef c);

extern CGColorRef __nullable OACreateGrayColorRefFromColor(NSColor *c) CF_RETURNS_RETAINED;
#endif

typedef NS_CLOSED_ENUM(NSInteger, OAColorSpace) {
    OAColorSpaceRGB,
    OAColorSpaceWhite, // 0=black, 1=white
    OAColorSpaceCMYK,
    OAColorSpaceHSB,
    OAColorSpacePattern,
    OAColorSpaceNamed,
};
#define OAColorSpaceHSV OAColorSpaceHSB

typedef struct {
    CGFloat h, s, v, a;
} OAHSV;

extern OAHSV OARGBToHSV(OALinearRGBA c);
extern OALinearRGBA OAHSVToRGB(OAHSV c);

@interface OAColor : NSObject <NSCopying>

#if OMNI_BUILDING_FOR_MAC || OMNI_BUILDING_FOR_IOS
+ (OAColor *)colorWithCGColor:(CGColorRef)cgColor;
#endif

#ifdef OA_PLATFORM_COLOR_CLASS
+ (OAColor *)colorWithPlatformColor:(OA_PLATFORM_COLOR_CLASS *)color;
#endif

#if OA_SUPPORT_PATTERN_COLOR
+ (OAColor *)colorWithPatternImageData:(NSData *)imageData;
#endif

+ (nullable OAColor *)colorFromRGBAString:(NSString *)rgbaString;
@property(nonatomic,readonly) NSString *rgbaString;

+ (nullable OAColor *)colorForPreferenceKey:(NSString *)preferenceKey;
+ (void)setColor:(OAColor *)color forPreferenceKey:(NSString *)preferenceKey;

+ (OAColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
+ (OAColor *)colorWithHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness alpha:(CGFloat)alpha;
+ (OAColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;

@property(class,readonly,nonatomic) OAColor *blackColor;
@property(class,readonly,nonatomic) OAColor *darkGrayColor;
@property(class,readonly,nonatomic) OAColor *lightGrayColor;
@property(class,readonly,nonatomic) OAColor *whiteColor;
@property(class,readonly,nonatomic) OAColor *grayColor;
@property(class,readonly,nonatomic) OAColor *redColor;
@property(class,readonly,nonatomic) OAColor *greenColor;
@property(class,readonly,nonatomic) OAColor *blueColor;
@property(class,readonly,nonatomic) OAColor *cyanColor;
@property(class,readonly,nonatomic) OAColor *yellowColor;
@property(class,readonly,nonatomic) OAColor *magentaColor;
@property(class,readonly,nonatomic) OAColor *orangeColor;
@property(class,readonly,nonatomic) OAColor *purpleColor;
@property(class,readonly,nonatomic) OAColor *brownColor;
@property(class,readonly,nonatomic) OAColor *clearColor;

@property(class,readonly,nonatomic) OAColor *keyboardFocusIndicatorColor;
@property(class,readonly,nonatomic) OAColor *selectedTextBackgroundColor;

#ifdef OA_PLATFORM_COLOR_CLASS
@property(nonatomic,readonly) OA_PLATFORM_COLOR_CLASS *toColor;

- (void)set;
#endif

@end

// Concrete subclases, and claim that all instances should conform.
@protocol OAColor

@property(nonatomic, readonly) OAColorSpace colorSpace;

- (OAColor *)colorUsingColorSpace:(OAColorSpace)colorSpace;
- (nullable OAColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(OAColor *)otherColor;
- (OAColor *)colorWithAlphaComponent:(CGFloat)fraction;

@property(nonatomic, readonly) CGFloat whiteComponent;
@property(nonatomic, readonly) CGFloat redComponent;
@property(nonatomic, readonly) CGFloat greenComponent;
@property(nonatomic, readonly) CGFloat blueComponent;
@property(nonatomic, readonly) OALinearRGBA toRGBA;

@property(nonatomic, readonly) CGFloat hueComponent;
@property(nonatomic, readonly) CGFloat saturationComponent;
@property(nonatomic, readonly) CGFloat brightnessComponent;
@property(nonatomic, readonly) CGFloat alphaComponent;

- (OAHSV)toHSV;

// Caller guarantees that color is non-nil and in the same colorspace as the receiver.
- (BOOL)isEqualToColorInSameColorSpace:(OAColor *)color;
- (NSUInteger)hash;

#ifdef OA_PLATFORM_COLOR_CLASS
- (OA_PLATFORM_COLOR_CLASS *)makePlatformColor; // This is cached in the -platformColor property and should otherwise not be called.
#endif

#if OMNI_BUILDING_FOR_MAC
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

#if OMNI_BUILDING_FOR_MAC
typedef struct {
    OALinearRGBA color1, color2;
} OARGBAColorPair;

extern void OAFillRGBAColorPair(OARGBAColorPair *pair, NSColor *color1, NSColor *color2);

extern const CGFunctionCallbacks OALinearFunctionCallbacks;

#endif

NS_ASSUME_NONNULL_END

