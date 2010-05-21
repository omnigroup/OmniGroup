// Copyright 2003-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQColor.h>

#import <OmniBase/OmniBase.h>
#import <tgmath.h>

#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFPreference.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#define USE_UIKIT 1
#else
#define USE_UIKIT 0
#endif

#if USE_UIKIT
#import <UIKit/UIColor.h>
#else
#import <AppKit/NSColor.h>
#import <OmniAppKit/NSUserDefaults-OAExtensions.h>
#endif

RCS_ID("$Id$");

/*
 Conceptually, we want to draw the opaque outline background color and then layer on colors based on other styles until we have filled the cell.  But, we need to provide a single color for the layer background color and we start from the deepest nesting. So, instead we want to compute start from the top color and work our way back until we hit an opaque color (hopefully quickly). As we work, we need to either composite a top translucent color and a bottom color that may be opaque or translucent.
 */


#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
OQLinearRGBA OQGetColorComponents(NSColor *c)
{
    OQLinearRGBA l;
    if (c)
        [[c colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getRed:&l.r green:&l.g blue:&l.b alpha:&l.a];
    else
        memset(&l, 0, sizeof(l)); // Treat nil as clear.
    return l;
}
#else
OQLinearRGBA OQGetColorComponents(OQColor *c)
{
    if (c)
        return [c toRGBA];

    OQLinearRGBA l;
    memset(&l, 0, sizeof(l)); // Treat nil as clear.
    return l;
}
#endif

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
OQLinearRGBA OQGetColorRefComponents(CGColorRef c)
{
    OQLinearRGBA l;
    if (c != NULL) {
        CFStringRef colorSpaceName = CGColorSpaceCopyName(CGColorGetColorSpace(c));
        if (CFStringCompare(colorSpaceName, kCGColorSpaceGenericRGB, 0) == kCFCompareEqualTo) {
            const CGFloat *components = CGColorGetComponents(c);
            l.r = components[0];
            l.g = components[1];
            l.b = components[2];
            l.a = components[3];
        } else if (CFStringCompare(colorSpaceName, kCGColorSpaceGenericGray, 0) == kCFCompareEqualTo) {
            const CGFloat *components = CGColorGetComponents(c);
            l.r = l.g = l.b =  components[0];
            l.a = components[1];
        } else {
            OBASSERT_NOT_REACHED("OQGetColorRefComponents() passed CGColorRefs in an unsupported colorspace.");
        }
        
        CFRelease(colorSpaceName);
    } else
        memset(&l, 0, sizeof(l)); // Treat nil as clear.
    return l;
}
#endif

CGFloat OQGetRGBAColorLuma(OQLinearRGBA c)
{
    return (CGFloat)(0.3*c.r + 0.59*c.g + 0.11*c.b);
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
CGFloat OQGetColorLuma(NSColor *c, CGFloat *outAlpha)
{
    OQLinearRGBA components = OQGetColorComponents(c);
    if (outAlpha)
        *outAlpha = components.a;
    return OQGetRGBAColorLuma(components);
}
#endif

OQLinearRGBA OQCompositeLinearRGBA(OQLinearRGBA T, OQLinearRGBA B)
{
    if (T.a >= 1.0) {
        // Top is opaque; just use it.
        return T;
    }
    
    if (T.a <= 0.0) {
        // Top is totally transparent, so return the bottom color (which may itself be opaque or not).
        return B;
    }
    
    if (B.a <= 0.0) {
        // Bottom is clear, return the top color.  We know the top isn't opaque here since we checked above, so we just return NO.
        return T;
    }
    
    // At this point, we know that 0 < top.a < 1 and bottom.a > 0 (and hopefully <= 1 or something funky is afoot).
    
    /*
     Now, we know we don't have an easy out and we need to come up with a color R that when composited on top of some unknown background X will have the same results as compositing B (bottom) on X and then T (top) on that.  Alpha compositing in a linear color space looks like C = a*A + (1-a)*B, so using the notation that C = C_a C_c (an alpha and color component) we have:
     
     T_a T_c + (1-T_a)(B_a B_c + (1-B_a)X_c)   (1)
     
     Our problem is to find R_a and R_c such that this is the same as R_a R_c + (1 - R_a) X_c.
     
     Multiplying the out the expressoin above, we get:
     
     T_a T_c + (1-T_a) B_a B_c + (1-T_a)(1-B_a)X_c (2)
     
     Looking at the format for compositing, we can see that we have in the latter half all the undercolor contribution and so we need:
     
     1-R_a = (1-T_a)(1-B_a)
     
     and thus:
     
     R_a = (T_a-1)(1-B_a) + 1
     = T_a + B_a - T_a B_a (3)
     
     Finally, we need to compute a R_c based on T_c and B_c.  Taking the first two terms of expression (2), which are those using T_c and B_c, we need:
     
     R_a R_c = T_a T_c + (1-T_a) B_a B_c
     
     or:
     
     R_c = T_a / R_a T_c + (1-T_a) B_a / R_a B_c
     
     Dividing by R_a means we need to be sure it isn't zero, but looking at (3) this can only happen if both T_a and B_a are zero.  We've handled both of these special cases by this point and neither of them are zero.
     
     Splitting this up we get:
     
     R_c = f_T T_c + f_B B_c
     f_T = T_a / R_a
     f_B = (1-T_a) B_a / R_a
     
     */
    
    OQLinearRGBA R;
    
    R.a = T.a + B.a - T.a * B.a;
    
    CGFloat f_T = T.a / R.a;
    CGFloat f_B = (1-T.a) * B.a / R.a;
    
    R.r = f_T * T.r + f_B * B.r;
    R.g = f_T * T.g + f_B * B.g;
    R.b = f_T * T.b + f_B * B.b;
    
    return R;
}

// Composites *ioTop on bottom and puts it back in *ioTop, using the calibrated RGB color space. Return YES if the output is opaque.  A nil input is interpreted as clear.
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
BOOL OQCompositeColors(NSColor **ioTopColor, NSColor *bottomColor)
#else
BOOL OQCompositeColors(OQColor **ioTopColor, OQColor *bottomColor)
#endif
{
    OQLinearRGBA T = OQGetColorComponents(*ioTopColor);
    if (T.a >= 1.0) {
        // Top is opaque; just use it.
        return YES;
    }
    OQLinearRGBA B = OQGetColorComponents(bottomColor);
    if (T.a <= 0.0) {
        // Top is totally transparent, so return the bottom color (which may itself be opaque or not).
        *ioTopColor = bottomColor;
        return (B.a >= 1.0);
    }
    if (B.a <= 0.0) {
        // Bottom is clear, return the top color.  We know the top isn't opaque here since we checked above, so we just return NO.
        return NO;
    }
    
    OQLinearRGBA R = OQCompositeLinearRGBA(T, B);
    
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    *ioTopColor = [NSColor colorWithCalibratedRed:R.r green:R.g blue:R.b alpha:R.a];
#else
    *ioTopColor = [OQColor colorWithCalibratedRed:R.r green:R.g blue:R.b alpha:R.a];
#endif
    
    return R.a >= 1.0; // Might be fully opaque now if T was translucent and B was opaque.
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
CGColorRef OQCreateCompositeColorRef(CGColorRef topColor, CGColorRef bottomColor, BOOL *isOpaque)
{
    OQLinearRGBA T = OQGetColorRefComponents(topColor);
    if (T.a >= 1.0) {
        // Top is opaque; just use it.
        if (isOpaque)
            *isOpaque = YES;
        CGColorRetain(topColor);
        return topColor;
    }
    
    OQLinearRGBA B = OQGetColorRefComponents(bottomColor);
    if (T.a <= 0.0) {
        // Top is totally transparent, so return the bottom color (which may itself be opaque or not).
        if (bottomColor)
            CGColorRetain(bottomColor);
        if (isOpaque)
            *isOpaque = B.a >= 1.0;
        return bottomColor;
    }
    if (B.a <= 0.0) {
        // Bottom is clear, return the top color.  We know the top isn't opaque here since we checked above, so we just return NO.
        if (isOpaque)
            *isOpaque = NO;
        CGColorRetain(topColor);
        return topColor;
    }
    
    OQLinearRGBA R = OQCompositeLinearRGBA(T, B);
    
    if (isOpaque)
        *isOpaque = R.a >= 1.0; // Might be fully opaque now if T was translucent and B was opaque.
    
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    return CGColorCreateGenericRGB(R.r, R.g, R.b, R.a);
#else
    // Seriously, there are no calibrated color spaces at all? Nice.
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGColorRef result = CGColorCreate(colorSpace, &R.r);
    CFRelease(colorSpace);
    return result;
#endif
}
#endif

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
CGColorRef OQCreateColorRefFromColor(NSColor *c)
{
    OQLinearRGBA C = OQGetColorComponents(c);
    return CGColorCreateGenericRGB(C.r, C.g, C.b, C.a);
}

CGColorRef OQCreateGrayColorRefFromColor(NSColor *c)
{
    CGFloat alpha;
    CGFloat luma = OQGetColorLuma(c, &alpha);
    return CGColorCreateGenericGray(luma, alpha);
}
#endif

// 0 and -0 are == but have a different bit pattern.  So, we must hash them the same or make sure that passed in inputs are never -0.
// We also don't want less than zero or greater than 1 (though there are uses for these in things like OpenGL...)
static CGFloat _clampComponent(CGFloat x)
{
    if (x < 0)
        return 0;
    if (x > 1)
        return 1;
    return fabs(x); // kill -0.
}

static NSUInteger _hashComponents(const CGFloat *components, NSUInteger componentCount)
{
    // 0 and -0 are == but have a different bit pattern.  So, we must hash them the same or make sure that passed in inputs are never -0.
    // We take the clamping approach.
    
    OBPRECONDITION(sizeof(NSUInteger) == sizeof(CGFloat));
    
    NSUInteger hash = 0;
    for (NSUInteger componentIndex = 0; componentIndex < componentCount; componentIndex++) {
        // Play nice with alaising.
        union {
            NSUInteger i;
            CGFloat f;
        } x;
        x.f = components[componentIndex];
        hash ^= x.i;
    }
    
    return hash;
}

OSHSV OSRGBToHSV(OQLinearRGBA c)
{
    CGFloat r = c.r, g = c.g, b = c.b;
    CGFloat min_c = MIN(r, MIN(g, b));
    CGFloat max_c = MAX(r, MAX(g, b));
    CGFloat h, s, v;
    
    //    NSLog(@"r:%f g:%f b:%f", r, g, b);
    //    NSLog(@"min_c:%f", min_c);
    //    NSLog(@"max_c:%f", max_c);
    
    if (max_c == min_c) {
        h = 0.0f;
        //        NSLog(@"1");
    } else if (max_c == r) {
        h = 60.0f/360.0f * (g - b) / (max_c - min_c) + 1.0f;
        //        NSLog(@"2");
    } else if (max_c == g) {
        h = 60.0f/360.0f * (b - r) / (max_c - min_c) + 120.0f/360.0f;
        //        NSLog(@"3");
    } else if (max_c == b) {
        h = 60.0f/360.0f * (r - g) / (max_c - min_c) + 240.0f/360.0f;
        //        NSLog(@"4");
    } else {
        NSCAssert(NO, @"not reached");
        h = 0.0f;
        //        NSLog(@"5");
    }
    
    if (h < 0.0f)
        h += 1.0f;
    else if (h > 1.0f)
        h -= 1.0f;
    
    NSCAssert(h >= 0.0f, @"h range");
    NSCAssert(h <= 1.0f, @"h range");
    
    if (max_c == 0.0f)
        s = 0.0f;
    else
        s = (1 - min_c/max_c);
    
    v = max_c;
    
    return (OSHSV){h, s, v, c.a};
}

OQLinearRGBA OQHSVToRGB(OSHSV c)
{
    CGFloat h = c.h, s = c.s, v = c.v;
    if (h >= 1)
        h = 0; // wraps around; use zero.
    
    CGFloat h6 = h * 6;
    CGFloat h_i = floor(h6);
    CGFloat f = h6 - h_i;
    
    CGFloat p = v * (1 - s);
    CGFloat q = v * (1 - f * s);
    CGFloat t = v * (1 - (1 - f) * s);
    
    switch ((int)h_i) {
        case 0:
            return (OQLinearRGBA){v, t, p, c.a};
        case 1:
            return (OQLinearRGBA){q, v, p, c.a};
        case 2:
            return (OQLinearRGBA){p, v, t, c.a};
        case 3:
            return (OQLinearRGBA){p, q, v, c.a};
        case 4:
            return (OQLinearRGBA){t, p, v, c.a};
        default:
            return (OQLinearRGBA){v, p, q, c.a};
    }
}

static void OQColorInitPlatformColor(OQColor *self);
static OQColor *OSRGBAColorCreate(OQLinearRGBA rgba);
static OQColor *OSHSVAColorCreate(OSHSV hsva);
static OQColor *OSWhiteColorCreate(CGFloat white, CGFloat alpha);

/*
 TODO: What color space are UIColors on the device?  CGColorRef seemingly only has the device CGColorSpaceRef. But, is that supposed to be close to some profile sRGB? linear?
 */

@interface OSRGBAColor : OQColor <OQColor>
{
    OQLinearRGBA _rgba;
}
@end

@implementation OSRGBAColor

static OQColor *OSRGBAColorCreate(OQLinearRGBA rgba)
{
    OSRGBAColor *color = [[OSRGBAColor alloc] init];
    color->_rgba.r = _clampComponent(rgba.r);
    color->_rgba.g = _clampComponent(rgba.g);
    color->_rgba.b = _clampComponent(rgba.b);
    color->_rgba.a = _clampComponent(rgba.a);
    OQColorInitPlatformColor(color);
    return color;
}

- (OQColorSpace)colorSpace;
{
    return OQColorSpaceRGB;
}

- (OQColor *)colorUsingColorSpace:(OQColorSpace)colorSpace;
{
    if (colorSpace == OQColorSpaceRGB)
        return self;
    if (colorSpace == OQColorSpaceHSV) {
        OSHSV hsva = OSRGBToHSV(_rgba);
        return [OSHSVAColorCreate(hsva) autorelease];
    }
    if (colorSpace == OQColorSpaceWhite) {
        CGFloat luma = OQGetRGBAColorLuma(_rgba);
        return [OSWhiteColorCreate(luma, _rgba.a) autorelease];
    }
    OBRequestConcreteImplementation(self, _cmd);
}

static CGFloat interp(CGFloat a, CGFloat b, CGFloat t)
{
    OBPRECONDITION(t >= 0 && t <= 1);
    return t * a + (1-t) * b;
}

// TODO: Experiment to see what NSColor really does for blending when alpha != 1.
static OQLinearRGBA interpRGBA(OQLinearRGBA c0, OQLinearRGBA c1, CGFloat t)
{
    OQLinearRGBA rgba;
    rgba.r = interp(c0.r, c1.r, t);
    rgba.g = interp(c0.g, c1.g, t);
    rgba.b = interp(c0.b, c1.b, t);
    rgba.a = interp(c0.a, c1.a, t);
    return rgba;
}

// NSColor documents this method to to the blending in calibrated RGBA.
- (OQColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(OQColor *)otherColor;
{
    OSRGBAColor *otherRGBA = (OSRGBAColor *)[otherColor colorUsingColorSpace:OQColorSpaceRGB];
    if (!otherRGBA)
        return nil; // This is what NSColor does on failure.
    OBASSERT([otherRGBA isKindOfClass:[OSRGBAColor class]]);
    
    if (fraction <= 0)
        return self;
    if (fraction >= 1)
        return otherColor;
    
    OQLinearRGBA rgba = interpRGBA(otherRGBA->_rgba, _rgba, fraction); // the fraction is "of the other color"
    return [OSRGBAColorCreate(rgba) autorelease];
}

- (OQColor *)colorWithAlphaComponent:(CGFloat)fraction;
{
    OQLinearRGBA rgba = _rgba;
    rgba.a = fraction; // TODO: The naming of this argument makes it sound like this should be '*=', but the docs make it sound like '=' is right.
    return [OSRGBAColorCreate(rgba) autorelease];
}

- (CGFloat)whiteComponent;
{
    return OQGetRGBAColorLuma(_rgba);
}

- (CGFloat)redComponent;
{
    return _rgba.r;
}

- (CGFloat)greenComponent;
{
    return _rgba.g;
}

- (CGFloat)blueComponent;
{
    return _rgba.b;
}

- (OQLinearRGBA)toRGBA;
{
    return _rgba;
}

- (CGFloat)hueComponent;
{
    return OSRGBToHSV(_rgba).h;
}

- (CGFloat)saturationComponent;
{
    return OSRGBToHSV(_rgba).s;
}

- (CGFloat)brightnessComponent;
{
    return OSRGBToHSV(_rgba).v;
}

- (CGFloat)alphaComponent;
{
    return _rgba.a;
}

- (OSHSV)toHSV;
{
    return OSRGBToHSV(_rgba);
}

- (BOOL)isEqualToColorInSameColorSpace:(OQColor *)color;
{
    OBPRECONDITION(color);
    OBPRECONDITION([self colorSpace] == [color colorSpace]);
    OBPRECONDITION([self class] == [color class]); // should be implied from the colorSpace check
    
    OSRGBAColor *otherRGB = (OSRGBAColor *)color;
    return memcmp(&_rgba, &otherRGB->_rgba, sizeof(_rgba)) == 0;
}

- (NSUInteger)hash;
{
    return _hashComponents(&_rgba.r, 4);
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<RGBA: %f %f %f %f>", _rgba.r, _rgba.g, _rgba.b, _rgba.a];
}

#if USE_UIKIT
- (UIColor *)toColor;
{
    return [UIColor colorWithRed:_rgba.r green:_rgba.g blue:_rgba.b alpha:_rgba.a];
}
#else
- (NSColor *)toColor;
{
    return [NSColor colorWithCalibratedRed:_rgba.r green:_rgba.g blue:_rgba.b alpha:_rgba.a];
}
#endif

@end

@interface OSHSVAColor : OQColor <OQColor>
{
    OSHSV _hsva;
}
@end

@implementation OSHSVAColor

static OQColor *OSHSVAColorCreate(OSHSV hsva)
{
    OSHSVAColor *color = [[OSHSVAColor alloc] init];
    color->_hsva.h = _clampComponent(hsva.h);
    color->_hsva.s = _clampComponent(hsva.s);
    color->_hsva.v = _clampComponent(hsva.v);
    color->_hsva.a = _clampComponent(hsva.a);
    OQColorInitPlatformColor(color);
    return color;
}

- (OQColorSpace)colorSpace;
{
    return OQColorSpaceHSV;
}

- (OQColor *)colorUsingColorSpace:(OQColorSpace)colorSpace;
{
    if (colorSpace == OQColorSpaceHSV)
        return self;
    if (colorSpace == OQColorSpaceRGB) {
        OQLinearRGBA rgba = OQHSVToRGB(_hsva);
        return [OSRGBAColorCreate(rgba) autorelease];
    }
    if (colorSpace == OQColorSpaceWhite) {
        OQLinearRGBA rgba = OQHSVToRGB(_hsva);
        CGFloat w = OQGetRGBAColorLuma(rgba);
        return [OSWhiteColorCreate(w, _hsva.a) autorelease];
    }
    
    OBRequestConcreteImplementation(self, _cmd);
}

// NSColor documents this method to to the blending in calibrated RGBA.
- (OQColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(OQColor *)otherColor;
{
    return [[self colorUsingColorSpace:OQColorSpaceRGB] blendedColorWithFraction:fraction ofColor:otherColor];
}

- (OQColor *)colorWithAlphaComponent:(CGFloat)fraction;
{
    OSHSV hsva = _hsva;
    hsva.a = fraction; // TODO: The naming of this argument makes it sound like this should be '*=', but the docs make it sound like '=' is right.
    return [OSHSVAColorCreate(hsva) autorelease];
}

- (CGFloat)whiteComponent;
{
    OQLinearRGBA rgba = OQHSVToRGB(_hsva);
    return OQGetRGBAColorLuma(rgba);
}

- (CGFloat)redComponent;
{
    OQLinearRGBA rgba = OQHSVToRGB(_hsva);
    return rgba.r;
}

- (CGFloat)greenComponent;
{
    OQLinearRGBA rgba = OQHSVToRGB(_hsva);
    return rgba.g;
}

- (CGFloat)blueComponent;
{
    OQLinearRGBA rgba = OQHSVToRGB(_hsva);
    return rgba.b;
}

- (OQLinearRGBA)toRGBA;
{
    OQLinearRGBA rgba = OQHSVToRGB(_hsva);
    return rgba;
}

- (CGFloat)hueComponent;
{
    return _hsva.h;
}

- (CGFloat)saturationComponent;
{
    return _hsva.s;
}

- (CGFloat)brightnessComponent;
{
    return _hsva.v;
}

- (CGFloat)alphaComponent;
{
    return _hsva.a;
}

- (OSHSV)toHSV;
{
    return _hsva;
}

- (BOOL)isEqualToColorInSameColorSpace:(OQColor *)color;
{
    OBPRECONDITION(color);
    OBPRECONDITION([self colorSpace] == [color colorSpace]);
    OBPRECONDITION([self class] == [color class]); // should be implied from the colorSpace check
    
    OSHSVAColor *otherHSV = (OSHSVAColor *)color;
    return memcmp(&_hsva, &otherHSV->_hsva, sizeof(_hsva)) == 0;
}

- (NSUInteger)hash;
{
    return _hashComponents(&_hsva.h, 4);
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<HSVA: %f %f %f %f>", _hsva.h, _hsva.s, _hsva.v, _hsva.a];
}

#if USE_UIKIT
- (UIColor *)toColor;
{
    // There is a HSV initializer on UIColor, but it'll convert to RGBA too. Let's be consistent about how we do that.
    OQLinearRGBA rgba = OQHSVToRGB(_hsva);
    return [UIColor colorWithRed:rgba.r green:rgba.g blue:rgba.b alpha:rgba.a];
}
#else
- (NSColor *)toColor;
{
    OQLinearRGBA rgba = OQHSVToRGB(_hsva);
    return [NSColor colorWithCalibratedRed:rgba.r green:rgba.g blue:rgba.b alpha:rgba.a];
}
#endif

@end

@interface OSWhiteColor : OQColor <OQColor>
{
    CGFloat _white;
    CGFloat _alpha;
}
@end

@implementation OSWhiteColor

static OQColor *OSWhiteColorCreate(CGFloat white, CGFloat alpha)
{
    OSWhiteColor *color = [[OSWhiteColor alloc] init];
    color->_white = _clampComponent(white);
    color->_alpha = _clampComponent(alpha);
    OQColorInitPlatformColor(color);
    return color;
}

- (OQColorSpace)colorSpace;
{
    return OQColorSpaceWhite;
}

- (OQColor *)colorUsingColorSpace:(OQColorSpace)colorSpace;
{
    if (colorSpace == OQColorSpaceWhite)
        return self;
    if (colorSpace == OQColorSpaceRGB) {
        // Cache constants for black and white?
        return [OSRGBAColorCreate((OQLinearRGBA){_white, _white, _white, _alpha}) autorelease]; 
    }
    if (colorSpace == OQColorSpaceHSV) {
        OQLinearRGBA rgba = (OQLinearRGBA){_white, _white, _white, _alpha};
        OSHSV hsv = OSRGBToHSV(rgba);
        return [OSHSVAColorCreate(hsv) autorelease];
    }
    
    OBRequestConcreteImplementation(self, _cmd);
}

- (OQColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(OQColor *)otherColor;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (OQColor *)colorWithAlphaComponent:(CGFloat)fraction;
{
    return [OSWhiteColorCreate(_white, fraction) autorelease];
}

- (CGFloat)whiteComponent;
{
    return _white;
}

- (CGFloat)redComponent;
{
    return _white;
}

- (CGFloat)greenComponent;
{
    return _white;
}

- (CGFloat)blueComponent;
{
    return _white;
}

- (OQLinearRGBA)toRGBA;
{
    return (OQLinearRGBA){_white, _white, _white, _alpha};
}

- (CGFloat)hueComponent;
{
    return 0;
}

- (CGFloat)saturationComponent;
{
    return 0;
}

- (CGFloat)brightnessComponent;
{
    return _white;
}

- (CGFloat)alphaComponent;
{
    return _alpha;
}

- (OSHSV)toHSV;
{
    OSHSV hsv;
    hsv.h = 0;
    hsv.s = 0;
    hsv.v = _white;
    hsv.a = _alpha;
    return hsv;
}

- (BOOL)isEqualToColorInSameColorSpace:(OQColor *)color;
{
    OBPRECONDITION(color);
    OBPRECONDITION([self colorSpace] == [color colorSpace]);
    OBPRECONDITION([self class] == [color class]); // should be implied from the colorSpace check
    
    OSWhiteColor *otherWhite = (OSWhiteColor *)color;
    return _white == otherWhite->_white && _alpha == otherWhite->_alpha;
}

- (NSUInteger)hash;
{
    CGFloat components[2] = {_white, _alpha};
    return _hashComponents(components, 2);
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<WHITE: %f %f>", _white, _alpha];
}

#if USE_UIKIT
- (UIColor *)toColor;
{
    return [UIColor colorWithWhite:_white alpha:_alpha];
}
#else
- (NSColor *)toColor;
{
    return [NSColor colorWithCalibratedWhite:_white alpha:_alpha];
}
#endif

@end


@implementation OQColor

- (void)dealloc;
{
    [_platformColor release];
    [super dealloc];
}

static OQColor *_colorWithCGColorRef(CGColorRef cgColor)
{
    if (!cgColor)
        return nil;
    CGColorSpaceRef colorSpace = CGColorGetColorSpace(cgColor);
    const CGFloat *components = CGColorGetComponents(cgColor);
    
    // There are only two color spaces on the iPhone/iPad, as far as we know. white and rgb.
    switch (CGColorSpaceGetModel(colorSpace)) {
        case kCGColorSpaceModelMonochrome:
            OBASSERT(CGColorSpaceGetNumberOfComponents(colorSpace) == 1);
            OBASSERT(CGColorGetNumberOfComponents(cgColor) == 2);
            return [OQColor colorWithWhite:components[0] alpha:components[1]];
        case kCGColorSpaceModelRGB:
            OBASSERT(CGColorSpaceGetNumberOfComponents(colorSpace) == 3);
            OBASSERT(CGColorGetNumberOfComponents(cgColor) == 4);
            return [OQColor colorWithRed:components[0] green:components[1] blue:components[2] alpha:components[3]];
        default:
            NSLog(@"color = %@", cgColor);
            NSLog(@"colorSpace %@", colorSpace);
            return [OQColor redColor];
    }
}

+ (OQColor *)colorWithCGColor:(CGColorRef)cgColor;
{
    return _colorWithCGColorRef(cgColor);
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

+ (OQColor *)colorWithPlatformColor:(UIColor *)color;
{
    return _colorWithCGColorRef([color CGColor]);
}

#else
+ (OQColor *)colorWithPlatformColor:(NSColor *)color;
{
    if (!color)
        return nil;
    
    NSString *colorSpaceName = [color colorSpaceName];
    NSColor *toConvert;
    
    if (([colorSpaceName isEqualToString:NSCalibratedRGBColorSpace] && (toConvert = color)) ||
        ([colorSpaceName isEqualToString:NSDeviceRGBColorSpace] && (toConvert = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace])) ||
        ([colorSpaceName isEqualToString:NSNamedColorSpace] && (toConvert = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace]))) {
        OQLinearRGBA rgba;
        [toConvert getRed:&rgba.r green:&rgba.g blue:&rgba.b alpha:&rgba.a];
        return [OSRGBAColorCreate(rgba) autorelease]; // TODO: Could reuse the input color here for the platform color.
    }
    
    if (([colorSpaceName isEqualToString:NSCalibratedWhiteColorSpace] && (toConvert = color)) ||
        ([colorSpaceName isEqualToString:NSDeviceWhiteColorSpace] && (toConvert = [color colorUsingColorSpaceName:NSCalibratedWhiteColorSpace]))) {
        CGFloat white, alpha;
        [toConvert getWhite:&white alpha:&alpha];
        return [OSWhiteColorCreate(white, alpha) autorelease];
    }
    
    OBRequestConcreteImplementation(self, _cmd);
}
#endif

// Always returns RGBA. This code is adapted from OmniAppKit so that the preferences are compatible.
static BOOL parseRGBAString(NSString *value, OQLinearRGBA *rgba)
{
    if ([NSString isEmptyString:value])
        return NO;
    
    // This is optional; the others must be initialized by sscanf or we'll bail.
    rgba->a = 1;
    
    int components = sscanf([value UTF8String], "%"SCNfCG "%"SCNfCG "%"SCNfCG "%"SCNfCG, &rgba->r, &rgba->g, &rgba->b, &rgba->a);
    if (components != 3 && components != 4)
        return NO;
    
    return YES;
}

static NSString *rgbaStringFromRGBAColor(OQLinearRGBA rgba)
{
    if (rgba.a == 1.0)
	return [NSString stringWithFormat:@"%g %g %g", rgba.r, rgba.g, rgba.b];
    else
	return [NSString stringWithFormat:@"%g %g %g %g", rgba.r, rgba.g, rgba.b, rgba.a];
}

static void OQColorInitPlatformColor(OQColor *self)
{
    OBPRECONDITION(self->_platformColor == nil);
    self->_platformColor = [self.toColor retain]; // UIColor isn't copyable. -retain is good enough since all colors are immutable anyway.
    OBPOSTCONDITION(self->_platformColor != nil);
}

+ (OQColor *)colorFromRGBAString:(NSString *)rgbaString;
{
    OQLinearRGBA rgba;
    if (!parseRGBAString(rgbaString, &rgba))
        return nil;
    
    return [OSRGBAColorCreate(rgba) autorelease];
}

- (NSString *)rgbaString;
{
    return rgbaStringFromRGBAColor([self toRGBA]);
}

+ (OQColor *)colorForPreferenceKey:(NSString *)preferenceKey;
{
    NSString *colorString = [[OFPreferenceWrapper sharedPreferenceWrapper] stringForKey:preferenceKey];
    return [self colorFromRGBAString:colorString];
}

+ (void)setColor:(OQColor *)color forPreferenceKey:(NSString *)preferenceKey;
{
    NSString *colorString = [color rgbaString];
    if (colorString)
        [[OFPreferenceWrapper sharedPreferenceWrapper] setObject:colorString forKey:preferenceKey];
    else
        [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:preferenceKey];
}

+ (OQColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
{
    OQLinearRGBA rgba;
    rgba.r = red;
    rgba.g = green;
    rgba.b = blue;
    rgba.a = alpha;
    return [OSRGBAColorCreate(rgba) autorelease];
}

+ (OQColor *)colorWithHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness alpha:(CGFloat)alpha;
{
    OSHSV hsva;
    hsva.h = hue;
    hsva.s = saturation;
    hsva.v = brightness;
    hsva.a = alpha;
    return [OSHSVAColorCreate(hsva) autorelease];
}

+ (OQColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
{
    // Use +blackColor or +whiteColor for 0/1?
    return [OSWhiteColorCreate(white, alpha) autorelease];
}

+ (OQColor *)colorWithCalibratedRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
{
    return [self colorWithRed:red green:green blue:blue alpha:alpha];
}

+ (OQColor *)colorWithCalibratedHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness alpha:(CGFloat)alpha;
{
    return [self colorWithHue:hue saturation:saturation brightness:brightness alpha:alpha];
}

+ (OQColor *)colorWithCalibratedWhite:(CGFloat)white alpha:(CGFloat)alpha;
{
    return [self colorWithWhite:white alpha:alpha];
}

+ (OQColor *)clearColor;
{
    static OQColor *c = nil;
    if (!c)
        c = OSWhiteColorCreate(0, 0);
    return c;
}

+ (OQColor *)whiteColor;
{
    static OQColor *c = nil;
    if (!c)
        c = OSWhiteColorCreate(1, 1);
    return c;
}

+ (OQColor *)blackColor;
{
    static OQColor *c = nil;
    if (!c)
        c = OSWhiteColorCreate(0, 1);
    return c;
}

+ (OQColor *)blueColor;
{
    static OQColor *c = nil;
    if (!c)
        c = OSRGBAColorCreate((OQLinearRGBA){0, 0, 1, 1});
    return c;
}

+ (OQColor *)purpleColor;
{
    static OQColor *c = nil;
    if (!c)
        c = OSRGBAColorCreate((OQLinearRGBA){1, 0, 1, 1});
    return c;
}

+ (OQColor *)redColor;
{
    static OQColor *c = nil;
    if (!c)
        c = OSRGBAColorCreate((OQLinearRGBA){1, 0, 0, 1});
    return c;
}

+ (OQColor *)yellowColor;
{
    static OQColor *c = nil;
    if (!c)
        c = OSRGBAColorCreate((OQLinearRGBA){1, 1, 0, 1});
    return c;
}

+ (OQColor *)grayColor;
{
    static OQColor *c = nil;
    if (!c)
        c = OSWhiteColorCreate(0.5f, 1);
    return c;
}

+ (OQColor *)keyboardFocusIndicatorColor;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    OBRequestConcreteImplementation(self, _cmd);
#else
    // TODO: We immediately flatten to a concrete color, while named system colors are dynamic.  Matters?
    return [self colorWithPlatformColor:[NSColor keyboardFocusIndicatorColor]];
#endif
}

+ (OQColor *)selectedTextBackgroundColor;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    static OQColor *c = nil;
    if (!c)
        c = OSRGBAColorCreate((OQLinearRGBA){0.6055, 0.7539, 0.9453, 1});
    return c;
#else
    // TODO: We immediately flatten to a concrete color, while named system colors are dynamic.  Matters?
    return [self colorWithPlatformColor:[NSColor selectedTextBackgroundColor]];
#endif
}

- (void)set;
{
    OBPRECONDITION(_platformColor);
    [_platformColor set];
}

- (BOOL)isEqual:(id)otherObject;
{
    if (![otherObject isKindOfClass:[OQColor class]])
        return NO;
    OQColor *otherColor = otherObject;
    if ([self colorSpace] != [otherColor colorSpace])
        return NO;
    return [self isEqualToColorInSameColorSpace:otherColor];
}

- (NSUInteger)hash;
{
    // Need to implement value-based hashing or not call this.
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark -
#pragma mark Copying

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

@end

