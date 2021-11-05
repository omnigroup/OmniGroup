// Copyright 2003-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAColor.h>

#import <OmniBase/OmniBase.h>
#import <tgmath.h>

#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFPreference.h>

#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>

#if OMNI_BUILDING_FOR_IOS
#import <UIKit/UIColor.h>
#import <UIKit/UIImage.h>
#endif

#if OMNI_BUILDING_FOR_MAC
#import <AppKit/NSColor.h>
#import <OmniAppKit/NSColor-OAExtensions.h>
#import <OmniAppKit/NSUserDefaults-OAExtensions.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/*
 Conceptually, we want to draw the opaque outline background color and then layer on colors based on other styles until we have filled the cell.  But, we need to provide a single color for the layer background color and we start from the deepest nesting. So, instead we want to compute start from the top color and work our way back until we hit an opaque color (hopefully quickly). As we work, we need to either composite a top translucent color and a bottom color that may be opaque or translucent.
 */


#if OMNI_BUILDING_FOR_MAC
OALinearRGBA OAGetColorComponents(NSColor *c)
{
    OALinearRGBA l;
    if (c)
        [[c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] getRed:&l.r green:&l.g blue:&l.b alpha:&l.a];
    else
        memset(&l, 0, sizeof(l)); // Treat nil as clear.
    return l;
}
#endif

#if OMNI_BUILDING_FOR_IOS
OALinearRGBA OAGetColorComponents(OAColor *c)
{
    if (c)
        return [c toRGBA];

    OALinearRGBA l;
    memset(&l, 0, sizeof(l)); // Treat nil as clear.
    return l;
}
#endif

BOOL OAColorComponentsEqual(OALinearRGBA x, OALinearRGBA y)
{
    return
    x.r == y.r &&
    x.g == y.g &&
    x.b == y.b &&
    x.a == y.a;
}

#if OMNI_BUILDING_FOR_MAC || OMNI_BUILDING_FOR_IOS
OALinearRGBA OAGetColorRefComponents(CGColorRef c)
{
    OBPRECONDITION(!c || CFGetTypeID(c) == CGColorGetTypeID());
    
    OALinearRGBA l;
    if (c != NULL) {
        CGColorSpaceRef colorSpace = CGColorGetColorSpace(c);
        const CGFloat *components = CGColorGetComponents(c);
        
        // This is theoretically wrong on OSX where there are lots of possible RGB spaces that can differ from each other, but it's better to be close than pedantic and super wrong.
        switch (CGColorSpaceGetModel(colorSpace)) {
            case kCGColorSpaceModelMonochrome: {
                OBASSERT(CGColorSpaceGetNumberOfComponents(colorSpace) == 1);
                OBASSERT(CGColorGetNumberOfComponents(c) == 2);
                CGFloat gray = components[0], alpha = components[1];
                return (OALinearRGBA){gray, gray, gray, alpha}; // This is what our white color's toRGBA does
            }
            case kCGColorSpaceModelRGB:
                OBASSERT(CGColorSpaceGetNumberOfComponents(colorSpace) == 3);
                OBASSERT(CGColorGetNumberOfComponents(c) == 4);
                return (OALinearRGBA){components[0], components[1], components[2], components[3]};
            default:
                OBFinishPortingLater("<bug:///147856> (Frameworks-iOS Engineering: Handle unknown color space model in OAGetColorRefComponents)");
                return (OALinearRGBA){1, 0, 0, 1};
        }
    } else
        memset(&l, 0, sizeof(l)); // Treat nil as clear.
    return l;
}
#endif

CGFloat OAGetRGBAColorLuma(OALinearRGBA c)
{
    return (CGFloat)(0.3*c.r + 0.59*c.g + 0.11*c.b);
}

#if OMNI_BUILDING_FOR_MAC
CGFloat OAGetColorLuma(NSColor *c, CGFloat *outAlpha)
{
    OALinearRGBA components = OAGetColorComponents(c);
    if (outAlpha)
        *outAlpha = components.a;
    return OAGetRGBAColorLuma(components);
}
#endif

OALinearRGBA OACompositeLinearRGBA(OALinearRGBA T, OALinearRGBA B)
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
    
    OALinearRGBA R;
    
    R.a = T.a + B.a - T.a * B.a;
    
    CGFloat f_T = T.a / R.a;
    CGFloat f_B = (1-T.a) * B.a / R.a;
    
    R.r = f_T * T.r + f_B * B.r;
    R.g = f_T * T.g + f_B * B.g;
    R.b = f_T * T.b + f_B * B.b;
    
    return R;
}

// Composites *ioTop on bottom and puts it back in *ioTop, using the sRGB color space. Return YES if the output is opaque.  A nil input is interpreted as clear.
#if OMNI_BUILDING_FOR_MAC
NSColor * _Nullable OACompositeColors(NSColor * _Nullable topColor, NSColor * _Nullable bottomColor, BOOL * _Nullable isOpaque)
#elif OMNI_BUILDING_FOR_IOS
OAColor * _Nullable OACompositeColors(OAColor * _Nullable topColor, OAColor * _Nullable bottomColor, BOOL * _Nullable isOpaque)
#endif
#if OMNI_BUILDING_FOR_MAC || OMNI_BUILDING_FOR_IOS
{
    OALinearRGBA T = OAGetColorComponents(topColor);
    if (T.a >= 1.0) {
        // Top is opaque; just use it.
        if (isOpaque)
            *isOpaque = YES;
        return topColor;
    }
    OALinearRGBA B = OAGetColorComponents(bottomColor);
    if (T.a <= 0.0) {
        // Top is totally transparent, so return the bottom color (which may itself be opaque or not).
        if (isOpaque)
            *isOpaque = B.a >= 1.0;
        return bottomColor;
    }
    if (B.a <= 0.0) {
        // Bottom is clear, return the top color.  We know the top isn't opaque here since we checked above, so we just return NO.
        if (isOpaque)
            *isOpaque = NO;
        return topColor;
    }
    
    OALinearRGBA R = OACompositeLinearRGBA(T, B);
    
    if (isOpaque)
        *isOpaque = R.a >= 1.0; // Might be fully opaque now if T was translucent and B was opaque.

#if OMNI_BUILDING_FOR_MAC
    return [NSColor colorWithRed:R.r green:R.g blue:R.b alpha:R.a];
#elif OMNI_BUILDING_FOR_IOS
    return [OAColor colorWithRed:R.r green:R.g blue:R.b alpha:R.a];
#endif
}
#endif

#if OMNI_BUILDING_FOR_MAC || OMNI_BUILDING_FOR_IOS
CGColorRef OACreateCompositeColorRef(CGColorRef topColor, CGColorRef bottomColor, BOOL * _Nullable isOpaque)
{
    OALinearRGBA T = OAGetColorRefComponents(topColor);
    if (T.a >= 1.0) {
        // Top is opaque; just use it.
        if (isOpaque)
            *isOpaque = YES;
        CGColorRetain(topColor);
        return topColor;
    }
    
    OALinearRGBA B = OAGetColorRefComponents(bottomColor);
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
    
    OALinearRGBA R = OACompositeLinearRGBA(T, B);
    
    if (isOpaque)
        *isOpaque = R.a >= 1.0; // Might be fully opaque now if T was translucent and B was opaque.
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorRef result = CGColorCreate(colorSpace, &R.r);
    CFRelease(colorSpace);
    return result;
}

CGColorRef OACreateCompositeColorFromColors(CGColorSpaceRef destinationColorSpace, NSArray *colors)
{
    OBPRECONDITION(CGColorGetAlpha((CGColorRef)[colors objectAtIndex:0]) == 1.0f);

    // A common case is that the 'top' (last) color is opaque.
    CGColorRef lastColor = (__bridge CGColorRef)colors.lastObject;
    if (CGColorGetAlpha(lastColor) >= 1.0)  {
        if (CGColorGetColorSpace(lastColor) == destinationColorSpace) {
            CGColorRetain(lastColor);
            return lastColor;
        } else {
            // Wrong colorspace -- need to convert it.
        }
    }

    // We calculate the composite color by rendering into a 1x1px 8888RGBA bitmap.
    unsigned char bitmapData[4] = {0, 0, 0, 0};
    CGContextRef ctx = CGBitmapContextCreate(bitmapData, 1, 1, 8, 4, destinationColorSpace, kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    
    CGRect pixelRect = CGRectMake(0, 0, 1, 1);
    
    for (id obj in colors) {
        CGColorRef color = (__bridge CGColorRef)obj;
        CGContextSetFillColorWithColor(ctx, color);
        CGContextFillRect(ctx, pixelRect);
    };
    
    OBASSERT(bitmapData[3] == 255);
    
    CGFloat floatComponents[4];
    NSUInteger componentIndex;
    for (componentIndex = 0; componentIndex < 4; componentIndex++)
        floatComponents[componentIndex] = bitmapData[componentIndex] / (CGFloat)255;
    
    OBASSERT(floatComponents[3] == 1.0f);
    
    CGColorRef color = CGColorCreate(destinationColorSpace, floatComponents);

    CGContextRelease(ctx);
    return color;
}
#endif

#if OMNI_BUILDING_FOR_MAC
CGColorRef __nullable OACreateColorRefFromColor(CGColorSpaceRef destinationColorSpace, NSColor *c)
{
    // <bug:///98617> (Exception nil colorspace argument in initWithColorSpace:components:count)
    // Convert nil to nil to avoid an exception in NSColor. The call site might not be prepared to handle nil; if it turns out that all callsites are, maybe we should make nil -> nil part of the contract for this function.
    OBASSERT_NOTNULL(destinationColorSpace, "OACreateColorRefFromColor returning nil for nil colorspace -- didn't used to allow that, now we are.");
    OBASSERT_NOTNULL(c, "OACreateColorRefFromColor returning nil for nil color -- didn't used to allow that, now we are.");
    if (!destinationColorSpace || !c)
        return NULL;
    
    return [c newCGColorWithCGColorSpace:destinationColorSpace];
}

NSColor * __nullable OAColorFromColorRef(CGColorRef c)
{
    // <bug:///98617> (Exception nil colorspace argument in initWithColorSpace:components:count)
    // Convert nil to nil to avoid an exception in NSColor. The call site might not be prepared to handle nil; if it turns out that all callsites are, maybe we should make nil -> nil part of the contract for this function.
    OBASSERT_NOTNULL(c, "OAColorFromColorRef returning nil for nil color -- didn't used to allow that, now we are.");
    if (!c)
        return nil;
    
    return [NSColor colorFromCGColor:c];
}

CGColorRef __nullable OACreateGrayColorRefFromColor(NSColor *c)
{
    // <bug:///98617> (Exception nil colorspace argument in initWithColorSpace:components:count)
    // Convert nil to nil to avoid an exception in NSColor. The call site might not be prepared to handle nil; if it turns out that all callsites are, maybe we should make nil -> nil part of the contract for this function.
    OBASSERT_NOTNULL(c, "OACreateGrayColorRefFromColor returning nil for nil color -- didn't used to allow that, now we are.");
    if (!c)
        return NULL;
    
    CGFloat alpha;
    CGFloat luma = OAGetColorLuma(c, &alpha);
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

OAHSV OARGBToHSV(OALinearRGBA c)
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
    
    return (OAHSV){h, s, v, c.a};
}

OALinearRGBA OAHSVToRGB(OAHSV c)
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
            return (OALinearRGBA){v, t, p, c.a};
        case 1:
            return (OALinearRGBA){q, v, p, c.a};
        case 2:
            return (OALinearRGBA){p, v, t, c.a};
        case 3:
            return (OALinearRGBA){p, q, v, c.a};
        case 4:
            return (OALinearRGBA){t, p, v, c.a};
        default:
            return (OALinearRGBA){v, p, q, c.a};
    }
}

#if OMNI_BUILDING_FOR_MAC
static void _addComponent(NSAppleEventDescriptor *record, FourCharCode code, CGFloat component)
{
    // Cast up to double always for now.
    double d = component;
    NSAppleEventDescriptor *desc = [[NSAppleEventDescriptor alloc] initWithDescriptorType:typeIEEE64BitFloatingPoint bytes:&d length:(sizeof(d))];
    [record setDescriptor:desc forKeyword:code];
}
#endif

static void OAColorInitPlatformColor(OAColor *self);
static OAColor *OARGBAColorCreate(OALinearRGBA rgba);
static OAColor *OAHSVAColorCreate(OAHSV hsva);
static OAColor *OAWhiteColorCreate(CGFloat white, CGFloat alpha);

/*
 TODO: What color space are UIColors on the device?  CGColorRef seemingly only has the device CGColorSpaceRef. But, is that supposed to be close to some profile sRGB? linear?
 */

@interface OARGBAColor : OAColor <OAColor>
{
    OALinearRGBA _rgba;
}
@end

@implementation OARGBAColor

static OAColor *OARGBAColorCreate(OALinearRGBA rgba)
{
    OARGBAColor *color = [[OARGBAColor alloc] init];
    color->_rgba.r = _clampComponent(rgba.r);
    color->_rgba.g = _clampComponent(rgba.g);
    color->_rgba.b = _clampComponent(rgba.b);
    color->_rgba.a = _clampComponent(rgba.a);
    OAColorInitPlatformColor(color);
    return color;
}

- (OAColorSpace)colorSpace;
{
    return OAColorSpaceRGB;
}

- (OAColor *)colorUsingColorSpace:(OAColorSpace)colorSpace;
{
    if (colorSpace == OAColorSpaceRGB)
        return self;
    if (colorSpace == OAColorSpaceHSV) {
        OAHSV hsva = OARGBToHSV(_rgba);
        return OAHSVAColorCreate(hsva);
    }
    if (colorSpace == OAColorSpaceWhite) {
        CGFloat luma = OAGetRGBAColorLuma(_rgba);
        return OAWhiteColorCreate(luma, _rgba.a);
    }
    OBRequestConcreteImplementation(self, _cmd);
}

static CGFloat interp(CGFloat a, CGFloat b, CGFloat t)
{
    OBPRECONDITION(t >= 0 && t <= 1);
    return t * a + (1-t) * b;
}

// TODO: Experiment to see what NSColor really does for blending when alpha != 1.
static OALinearRGBA interpRGBA(OALinearRGBA c0, OALinearRGBA c1, CGFloat t)
{
    OALinearRGBA rgba;
    rgba.r = interp(c0.r, c1.r, t);
    rgba.g = interp(c0.g, c1.g, t);
    rgba.b = interp(c0.b, c1.b, t);
    rgba.a = interp(c0.a, c1.a, t);
    return rgba;
}

// NSColor documents this method to to the blending in calibrated RGBA.
- (nullable OAColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(OAColor *)otherColor;
{
    OARGBAColor *otherRGBA = (OARGBAColor *)[otherColor colorUsingColorSpace:OAColorSpaceRGB];
    if (!otherRGBA)
        return nil; // This is what NSColor does on failure.
    OBASSERT([otherRGBA isKindOfClass:[OARGBAColor class]]);
    
    if (fraction <= 0)
        return self;
    if (fraction >= 1)
        return otherColor;
    
    OALinearRGBA rgba = interpRGBA(otherRGBA->_rgba, _rgba, fraction); // the fraction is "of the other color"
    return OARGBAColorCreate(rgba);
}

- (OAColor *)colorWithAlphaComponent:(CGFloat)fraction;
{
    OALinearRGBA rgba = _rgba;
    rgba.a = fraction; // TODO: The naming of this argument makes it sound like this should be '*=', but the docs make it sound like '=' is right.
    return OARGBAColorCreate(rgba);
}

- (CGFloat)whiteComponent;
{
    return OAGetRGBAColorLuma(_rgba);
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

- (OALinearRGBA)toRGBA;
{
    return _rgba;
}

- (CGFloat)hueComponent;
{
    return OARGBToHSV(_rgba).h;
}

- (CGFloat)saturationComponent;
{
    return OARGBToHSV(_rgba).s;
}

- (CGFloat)brightnessComponent;
{
    return OARGBToHSV(_rgba).v;
}

- (CGFloat)alphaComponent;
{
    return _rgba.a;
}

- (OAHSV)toHSV;
{
    return OARGBToHSV(_rgba);
}

- (BOOL)isEqualToColorInSameColorSpace:(OAColor *)color;
{
    OBPRECONDITION(color);
    OBPRECONDITION([self colorSpace] == [color colorSpace]);
    OBPRECONDITION([self class] == [color class]); // should be implied from the colorSpace check
    
    OARGBAColor *otherRGB = (OARGBAColor *)color;
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

#if OMNI_BUILDING_FOR_IOS
- (UIColor *)makePlatformColor;
{
    return [UIColor colorWithRed:_rgba.r green:_rgba.g blue:_rgba.b alpha:_rgba.a];
}
#endif

#if OMNI_BUILDING_FOR_MAC
- (NSColor *)makePlatformColor;
{
    return [NSColor colorWithRed:_rgba.r green:_rgba.g blue:_rgba.b alpha:_rgba.a];
}
#endif

#if OMNI_BUILDING_FOR_MAC
- (NSAppleEventDescriptor *)scriptingColorDescriptor;
{
    NSAppleEventDescriptor *result = [[NSAppleEventDescriptor alloc] initRecordDescriptor];
    
    // The order is significant when the result is coerced to a list.
    _addComponent(result, 'OSrv', _rgba.r);
    _addComponent(result, 'OSgv', _rgba.g);
    _addComponent(result, 'OSbv', _rgba.b);
    _addComponent(result, 'OSav', _rgba.a);
    
    return result;
}
#endif

@end

@interface OAHSVAColor : OAColor <OAColor>
{
    OAHSV _hsva;
}
@end

@implementation OAHSVAColor

static OAColor *OAHSVAColorCreate(OAHSV hsva)
{
    OAHSVAColor *color = [[OAHSVAColor alloc] init];
    color->_hsva.h = _clampComponent(hsva.h);
    color->_hsva.s = _clampComponent(hsva.s);
    color->_hsva.v = _clampComponent(hsva.v);
    color->_hsva.a = _clampComponent(hsva.a);
    OAColorInitPlatformColor(color);
    return color;
}

- (OAColorSpace)colorSpace;
{
    return OAColorSpaceHSV;
}

- (OAColor *)colorUsingColorSpace:(OAColorSpace)colorSpace;
{
    if (colorSpace == OAColorSpaceHSV)
        return self;
    if (colorSpace == OAColorSpaceRGB) {
        OALinearRGBA rgba = OAHSVToRGB(_hsva);
        return OARGBAColorCreate(rgba);
    }
    if (colorSpace == OAColorSpaceWhite) {
        OALinearRGBA rgba = OAHSVToRGB(_hsva);
        CGFloat w = OAGetRGBAColorLuma(rgba);
        return OAWhiteColorCreate(w, _hsva.a);
    }
    
    OBRequestConcreteImplementation(self, _cmd);
}

// NSColor documents this method to to the blending in calibrated RGBA.
- (nullable OAColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(OAColor *)otherColor;
{
    return [[self colorUsingColorSpace:OAColorSpaceRGB] blendedColorWithFraction:fraction ofColor:otherColor];
}

- (OAColor *)colorWithAlphaComponent:(CGFloat)fraction;
{
    OAHSV hsva = _hsva;
    hsva.a = fraction; // TODO: The naming of this argument makes it sound like this should be '*=', but the docs make it sound like '=' is right.
    return OAHSVAColorCreate(hsva);
}

- (CGFloat)whiteComponent;
{
    OALinearRGBA rgba = OAHSVToRGB(_hsva);
    return OAGetRGBAColorLuma(rgba);
}

- (CGFloat)redComponent;
{
    OALinearRGBA rgba = OAHSVToRGB(_hsva);
    return rgba.r;
}

- (CGFloat)greenComponent;
{
    OALinearRGBA rgba = OAHSVToRGB(_hsva);
    return rgba.g;
}

- (CGFloat)blueComponent;
{
    OALinearRGBA rgba = OAHSVToRGB(_hsva);
    return rgba.b;
}

- (OALinearRGBA)toRGBA;
{
    OALinearRGBA rgba = OAHSVToRGB(_hsva);
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

- (OAHSV)toHSV;
{
    return _hsva;
}

- (BOOL)isEqualToColorInSameColorSpace:(OAColor *)color;
{
    OBPRECONDITION(color);
    OBPRECONDITION([self colorSpace] == [color colorSpace]);
    OBPRECONDITION([self class] == [color class]); // should be implied from the colorSpace check
    
    OAHSVAColor *otherHSV = (OAHSVAColor *)color;
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

#if OMNI_BUILDING_FOR_IOS
- (UIColor *)makePlatformColor;
{
    // There is a HSV initializer on UIColor, but it'll convert to RGBA too. Let's be consistent about how we do that.
    OALinearRGBA rgba = OAHSVToRGB(_hsva);
    return [UIColor colorWithRed:rgba.r green:rgba.g blue:rgba.b alpha:rgba.a];
}
#endif

#if OMNI_BUILDING_FOR_MAC
- (NSColor *)makePlatformColor;
{
    OALinearRGBA rgba = OAHSVToRGB(_hsva);
    return [NSColor colorWithRed:rgba.r green:rgba.g blue:rgba.b alpha:rgba.a];
}
- (NSAppleEventDescriptor *)scriptingColorDescriptor;
{
    NSAppleEventDescriptor *result = [[NSAppleEventDescriptor alloc] initRecordDescriptor];
    
    // The order is significant when the result is coerced to a list.
    _addComponent(result, 'OShv', _hsva.h);
    _addComponent(result, 'OSsv', _hsva.s);
    _addComponent(result, 'OSvv', _hsva.v);
    _addComponent(result, 'OSav', _hsva.a);
    
    return result;
}
#endif

@end

@interface OAWhiteColor : OAColor <OAColor>
{
    CGFloat _white;
    CGFloat _alpha;
}
@end

@implementation OAWhiteColor

static OAColor *OAWhiteColorCreate(CGFloat white, CGFloat alpha)
{
    OAWhiteColor *color = [[OAWhiteColor alloc] init];
    color->_white = _clampComponent(white);
    color->_alpha = _clampComponent(alpha);
    OAColorInitPlatformColor(color);
    return color;
}

- (OAColorSpace)colorSpace;
{
    return OAColorSpaceWhite;
}

- (OAColor *)colorUsingColorSpace:(OAColorSpace)colorSpace;
{
    if (colorSpace == OAColorSpaceWhite)
        return self;
    if (colorSpace == OAColorSpaceRGB) {
        // Cache constants for black and white?
        return OARGBAColorCreate((OALinearRGBA){_white, _white, _white, _alpha});
    }
    if (colorSpace == OAColorSpaceHSV) {
        OALinearRGBA rgba = (OALinearRGBA){_white, _white, _white, _alpha};
        OAHSV hsv = OARGBToHSV(rgba);
        return OAHSVAColorCreate(hsv);
    }
    
    OBRequestConcreteImplementation(self, _cmd);
}

- (nullable OAColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(OAColor *)otherColor;
{
    return [[self colorUsingColorSpace:OAColorSpaceRGB] blendedColorWithFraction:fraction ofColor:otherColor];
}

- (OAColor *)colorWithAlphaComponent:(CGFloat)fraction;
{
    return OAWhiteColorCreate(_white, fraction);
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

- (OALinearRGBA)toRGBA;
{
    return (OALinearRGBA){_white, _white, _white, _alpha};
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

- (OAHSV)toHSV;
{
    OAHSV hsv;
    hsv.h = 0;
    hsv.s = 0;
    hsv.v = _white;
    hsv.a = _alpha;
    return hsv;
}

- (BOOL)isEqualToColorInSameColorSpace:(OAColor *)color;
{
    OBPRECONDITION(color);
    OBPRECONDITION([self colorSpace] == [color colorSpace]);
    OBPRECONDITION([self class] == [color class]); // should be implied from the colorSpace check
    
    OAWhiteColor *otherWhite = (OAWhiteColor *)color;
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

#if OMNI_BUILDING_FOR_IOS
- (UIColor *)makePlatformColor;
{
    return [UIColor colorWithWhite:_white alpha:_alpha];
}
#endif

#if OMNI_BUILDING_FOR_MAC
- (NSColor *)makePlatformColor;
{
    return [NSColor colorWithWhite:_white alpha:_alpha];
}

- (NSAppleEventDescriptor *)scriptingColorDescriptor;
{
    NSAppleEventDescriptor *result = [[NSAppleEventDescriptor alloc] initRecordDescriptor];
    
    // The order is significant when the result is coerced to a list.
    _addComponent(result, 'OSwv', _white);
    _addComponent(result, 'OSav', _alpha);
    
    return result;
}

#endif

@end

@interface OAUnknownXMLColor : OAWhiteColor
@property (nonatomic, strong) OFXMLElement *element;
@end

@implementation OAUnknownXMLColor

static OAColor *OAUnknownXMLColorCreate(OFXMLElement *element)
{
    OAUnknownXMLColor *color = [[OAUnknownXMLColor alloc] init];
    color->_white = 1.0;
    color->_alpha = 1.0;
    color.element = element;
    OAColorInitPlatformColor(color);
    return color;
}

- (void)appendXML:(OFXMLDocument *)doc;
{
    [doc.topElement appendChild:self.element];
}

@end

#if OA_SUPPORT_PATTERN_COLOR
@interface OAPatternColor : OAColor <OAColor>
{
    NSData *_imageData;
}

@end

@implementation OAPatternColor

static OAColor *OAPatternColorCreate(NSData *imageData)
{
    OAPatternColor *color = [[OAPatternColor alloc] init];
    color->_imageData = [imageData copy];
    OAColorInitPlatformColor(color);
    return color;
}

- (OAColorSpace)colorSpace;
{
    return OAColorSpacePattern;
}

- (CGFloat)whiteComponent;
{
    OBRejectInvalidCall(self, _cmd, @"Pattern colors don't have components.");
}

- (CGFloat)redComponent;
{
    OBRejectInvalidCall(self, _cmd, @"Pattern colors don't have components.");
}

- (CGFloat)greenComponent;
{
    OBRejectInvalidCall(self, _cmd, @"Pattern colors don't have components.");
}

- (CGFloat)blueComponent;
{
    OBRejectInvalidCall(self, _cmd, @"Pattern colors don't have components.");
}

- (OALinearRGBA)toRGBA;
{
    OBRejectInvalidCall(self, _cmd, @"Pattern colors don't have components.");
}

- (CGFloat)hueComponent;
{
    OBRejectInvalidCall(self, _cmd, @"Pattern colors don't have components.");
}

- (CGFloat)saturationComponent;
{
    OBRejectInvalidCall(self, _cmd, @"Pattern colors don't have components.");
}

- (CGFloat)brightnessComponent;
{
    OBRejectInvalidCall(self, _cmd, @"Pattern colors don't have components.");
}

- (CGFloat)alphaComponent;
{
    OBRejectInvalidCall(self, _cmd, @"Pattern colors don't have components.");
}

#if USE_UIKIT
- (UIColor *)makePlatformColor;
{
    UIImage *image = [[UIImage alloc] initWithData:_imageData];
    CGSize imageSize = image.size;
    if (image == nil || CGSizeEqualToSize(imageSize, CGSizeZero)) {
        NSLog(@"Warning, could not rebuild pattern color from image %@, data %@", image, _imageData);
        return [UIColor blackColor];
    } else {
        return [UIColor colorWithPatternImage:image];
    }
}
#else
- (NSColor *)makePlatformColor;
{
    NSBitmapImageRep *bitmapImageRep = (id)[NSBitmapImageRep imageRepWithData:_imageData];
    CGSize imageSize = [bitmapImageRep size];
    if (bitmapImageRep == nil || CGSizeEqualToSize(imageSize, CGSizeZero)) {
        NSLog(@"Warning, could not rebuild pattern color from image rep %@, data %@", bitmapImageRep, _imageData);
        return [NSColor blackColor];
    } else {
        NSImage *patternImage = [[NSImage alloc] initWithSize:imageSize];
        [patternImage addRepresentation:bitmapImageRep];
        return [NSColor colorWithPatternImage:patternImage];
    }
}
#endif

@end
#endif


@implementation OAColor
{
#ifdef OA_PLATFORM_COLOR_CLASS
    OA_PLATFORM_COLOR_CLASS *_platformColor;
#endif
}

#if OMNI_BUILDING_FOR_MAC || OMNI_BUILDING_FOR_IOS
static OAColor *_colorWithCGColorRef(CGColorRef cgColor)
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
            return [OAColor colorWithWhite:components[0] alpha:components[1]];
        case kCGColorSpaceModelRGB:
            OBASSERT(CGColorSpaceGetNumberOfComponents(colorSpace) == 3);
            OBASSERT(CGColorGetNumberOfComponents(cgColor) == 4);
            return [OAColor colorWithRed:components[0] green:components[1] blue:components[2] alpha:components[3]];
        case kCGColorSpaceModelPattern:
            OBASSERT_NOT_REACHED("Graffle uses color patterns that are generated in MacOS documents");
            return [OAColor purpleColor];
        default:
            OBASSERT_NOT_REACHED("Graffle uses color patterns that are generated in MacOS documents");
            NSLog(@"color = %@", cgColor);
            NSLog(@"colorSpace %@", colorSpace);
            return [OAColor redColor];
    }
}

+ (OAColor *)colorWithCGColor:(CGColorRef)cgColor;
{
    return _colorWithCGColorRef(cgColor);
}
#endif

#if OMNI_BUILDING_FOR_IOS

+ (OAColor *)colorWithPlatformColor:(UIColor *)color;
{
    return _colorWithCGColorRef([color CGColor]);
}

#endif

#if OMNI_BUILDING_FOR_MAC

static NSColorSpace *_grayscaleColorSpace(void)
{
    static NSColorSpace *colorSpace = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        colorSpace = [[NSColor colorWithWhite:0.5f alpha:1.0f] colorSpace];
    });
    return colorSpace;
}

+ (OAColor *)colorWithPlatformColor:(NSColor *)color;
{
    // Some colors (e.g. named and pattern colors) will raise an exception when asked for their color space, so the NSColor header suggests this code to get the colorSpace of an arbitrary color whose type you don't know.
    NSColorSpace *colorSpace = [color colorUsingType:NSColorTypeComponentBased].colorSpace;
    NSColorSpaceModel colorSpaceModel = colorSpace.colorSpaceModel;

    if (colorSpaceModel == NSColorSpaceModelRGB) {
        NSColor *toConvert = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];

        OALinearRGBA rgba;
        [toConvert getRed:&rgba.r green:&rgba.g blue:&rgba.b alpha:&rgba.a];
        return OARGBAColorCreate(rgba); // TODO: Could reuse the input color here for the platform color.
    }

    if (colorSpaceModel == NSColorSpaceModelGray) {
        NSColor *toConvert = [color colorUsingColorSpace:_grayscaleColorSpace()];

        CGFloat white, alpha;
        [toConvert getWhite:&white alpha:&alpha];
        return OAWhiteColorCreate(white, alpha);
    }

    OBASSERT_NOT_REACHED("Unknown color space %@, model %ld", colorSpace, colorSpaceModel);
    NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return rgbColor ? [self colorWithPlatformColor:rgbColor] : [OAColor blackColor];
}
#endif

#if OA_SUPPORT_PATTERN_COLOR
+ (OAColor *)colorWithPatternImageData:(NSData *)imageData
{
    return OAPatternColorCreate(imageData);
}
#endif

// Always returns RGBA. This code is adapted from OmniAppKit so that the preferences are compatible.
static BOOL parseRGBAString(NSString *value, OALinearRGBA *rgba)
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

static NSString *rgbaStringFromRGBAColor(OALinearRGBA rgba)
{
    if (rgba.a == 1.0)
	return [NSString stringWithFormat:@"%g %g %g", rgba.r, rgba.g, rgba.b];
    else
	return [NSString stringWithFormat:@"%g %g %g %g", rgba.r, rgba.g, rgba.b, rgba.a];
}

static void OAColorInitPlatformColor(OAColor *self)
{
#ifdef OA_PLATFORM_COLOR_CLASS
    OBPRECONDITION(self->_platformColor == nil);
    self->_platformColor = [self makePlatformColor]; // UIColor isn't copyable. -retain is good enough since all colors are immutable anyway.
    OBPOSTCONDITION(self->_platformColor != nil);
#endif
}

+ (nullable OAColor *)colorFromRGBAString:(NSString *)rgbaString;
{
    OALinearRGBA rgba;
    if (!parseRGBAString(rgbaString, &rgba))
        return nil;
    
    return OARGBAColorCreate(rgba);
}

- (NSString *)rgbaString;
{
    return rgbaStringFromRGBAColor([self toRGBA]);
}

+ (nullable OAColor *)colorForPreferenceKey:(NSString *)preferenceKey;
{
    NSString *colorString = [[OFPreferenceWrapper sharedPreferenceWrapper] stringForKey:preferenceKey];
    return [self colorFromRGBAString:colorString];
}

+ (void)setColor:(OAColor *)color forPreferenceKey:(NSString *)preferenceKey;
{
    NSString *colorString = [color rgbaString];
    if (colorString)
        [[OFPreferenceWrapper sharedPreferenceWrapper] setObject:colorString forKey:preferenceKey];
    else
        [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:preferenceKey];
}

+ (OAColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
{
    OALinearRGBA rgba;
    rgba.r = red;
    rgba.g = green;
    rgba.b = blue;
    rgba.a = alpha;
    return OARGBAColorCreate(rgba);
}

+ (OAColor *)colorWithHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness alpha:(CGFloat)alpha;
{
    OAHSV hsva;
    hsva.h = hue;
    hsva.s = saturation;
    hsva.v = brightness;
    hsva.a = alpha;
    return OAHSVAColorCreate(hsva);
}

+ (OAColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
{
    // Use +blackColor or +whiteColor for 0/1?
    return OAWhiteColorCreate(white, alpha);
}

+ (OAColor *)colorWithUnknownXML:(OFXMLElement *)element;
{
    return OAUnknownXMLColorCreate(element);
}

+ (OAColor *)blackColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OAWhiteColorCreate(0, 1);
    return c;
}

+ (OAColor *)darkGrayColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OAWhiteColorCreate(0.333, 1);
    return c;
}

+ (OAColor *)lightGrayColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OAWhiteColorCreate(0.667, 1);
    return c;
}

+ (OAColor *)whiteColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OAWhiteColorCreate(1, 1);
    return c;
}

+ (OAColor *)grayColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OAWhiteColorCreate(0.5f, 1);
    return c;
}

+ (OAColor *)redColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OARGBAColorCreate((OALinearRGBA){1, 0, 0, 1});
    return c;
}

+ (OAColor *)greenColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OARGBAColorCreate((OALinearRGBA){0, 1, 0, 1});
    return c;
}

+ (OAColor *)blueColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OARGBAColorCreate((OALinearRGBA){0, 0, 1, 1});
    return c;
}

+ (OAColor *)cyanColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OARGBAColorCreate((OALinearRGBA){0, 1, 1, 1});
    return c;
}

+ (OAColor *)yellowColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OARGBAColorCreate((OALinearRGBA){1, 1, 0, 1});
    return c;
}

+ (OAColor *)magentaColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OARGBAColorCreate((OALinearRGBA){1, 0, 1, 1});
    return c;
}

+ (OAColor *)orangeColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OARGBAColorCreate((OALinearRGBA){1, 0.5, 0, 1});
    return c;
}

+ (OAColor *)purpleColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OARGBAColorCreate((OALinearRGBA){1, 0, 1, 1});
    return c;
}

+ (OAColor *)brownColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OARGBAColorCreate((OALinearRGBA){0.6, 0.4, 0.2, 1});
    return c;
}

+ (OAColor *)clearColor;
{
    static OAColor *c = nil;
    if (!c)
        c = OAWhiteColorCreate(0, 0);
    return c;
}


+ (OAColor *)keyboardFocusIndicatorColor;
{
#if OMNI_BUILDING_FOR_MAC
    // TODO: We immediately flatten to a concrete color, while named system colors are dynamic.  Matters?
    return [self colorWithPlatformColor:[NSColor keyboardFocusIndicatorColor]];
#else
    OBRequestConcreteImplementation(self, _cmd);
#endif
}

+ (OAColor *)selectedTextBackgroundColor;
{
#if OMNI_BUILDING_FOR_MAC
    // TODO: We immediately flatten to a concrete color, while named system colors are dynamic.  Matters?
    return [self colorWithPlatformColor:[NSColor selectedTextBackgroundColor]];
#else
    static OAColor *c = nil;
    if (!c)
        c = OARGBAColorCreate((OALinearRGBA){0.6055, 0.7539, 0.9453, 1});
    return c;
#endif
}

#ifdef OA_PLATFORM_COLOR_CLASS
- (OA_PLATFORM_COLOR_CLASS *)toColor;
{
    OBPRECONDITION(_platformColor);
    return _platformColor;
}

- (void)set;
{
    OBPRECONDITION(_platformColor);
    [_platformColor set];
}
#endif

- (BOOL)isEqual:(nullable id)otherObject;
{
    if (![otherObject isKindOfClass:[OAColor class]])
        return NO;
    OAColor *otherColor = otherObject;
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

- (id)copyWithZone:(nullable NSZone *)zone;
{
    return self;
}

@end

#if OMNI_BUILDING_FOR_MAC

void OAFillRGBAColorPair(OARGBAColorPair *pair, NSColor *color1, NSColor *color2)
{
    [color1 getRed:&pair->color1.r green:&pair->color1.g blue:&pair->color1.b alpha:&pair->color1.a];
    [color2 getRed:&pair->color2.r green:&pair->color2.g blue:&pair->color2.b alpha:&pair->color2.a];
}

static void _OALinearColorBlendFunction(void *info, const CGFloat *in, CGFloat *out)
{
    OARGBAColorPair *colorPair = info;
    
    CGFloat A = (1.0f - *in), B = *in;
    out[0] = A * colorPair->color1.r + B * colorPair->color2.r;
    out[1] = A * colorPair->color1.g + B * colorPair->color2.g;
    out[2] = A * colorPair->color1.b + B * colorPair->color2.b;
    out[3] = A * colorPair->color1.a + B * colorPair->color2.a;
}

static void _OALinearColorReleaseInfoFunction(void *info)
{
    free(info);
}

const CGFunctionCallbacks OALinearFunctionCallbacks = {0, &_OALinearColorBlendFunction, &_OALinearColorReleaseInfoFunction};

#endif

NS_ASSUME_NONNULL_END

