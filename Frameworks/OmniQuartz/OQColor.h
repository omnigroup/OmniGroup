// Copyright 2003-2010 Omni Development, Inc.  All rights reserved.
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
#else
#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CGColor.h>
@class OQColor;
#endif

typedef struct {
    CGFloat r, g, b, a;
} OQLinearRGBA;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern OQLinearRGBA OQGetColorComponents(NSColor *c);
#else
extern OQLinearRGBA OQGetColorComponents(OQColor *c);
#endif

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern OQLinearRGBA OQGetColorRefComponents(CGColorRef c);
#endif

extern CGFloat OQGetRGBAColorLuma(OQLinearRGBA c);
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern CGFloat OQGetColorLuma(NSColor *c, CGFloat *outAlpha);
#endif

extern OQLinearRGBA OQCompositeLinearRGBA(OQLinearRGBA T, OQLinearRGBA B);

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern BOOL OQCompositeColors(NSColor **ioTopColor, NSColor *bottomColor);
#else
extern BOOL OQCompositeColors(OQColor **ioTopColor, OQColor *bottomColor);
#endif

extern CGColorRef OQCreateCompositeColorRef(CGColorRef topColor, CGColorRef bottomColor, BOOL *isOpaque);

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern CGColorRef OQCreateColorRefFromColor(NSColor *c);

extern CGColorRef OQCreateGrayColorRefFromColor(NSColor *c);
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
@class UIColor;
#else
@class NSColor;
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
    id _platformColor;
}

+ (OQColor *)colorWithCGColor:(CGColorRef)cgColor;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (OQColor *)colorWithPlatformColor:(UIColor *)color;
#else
+ (OQColor *)colorWithPlatformColor:(NSColor *)color;
#endif

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

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
@property(readonly,nonatomic) UIColor *toColor;
#else
@property(readonly,nonatomic) NSColor *toColor;
#endif
@end
@interface OQColor (OQColor) <OQColor>
@end
