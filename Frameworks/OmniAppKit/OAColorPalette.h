// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSColor;

@interface OAColorPalette : OFObject
{
}

+ (NSColor *)colorForString:(NSString *)colorString gamma:(double)gamma;
+ (NSColor *)colorForString:(NSString *)colorString;
+ (NSString *)stringForColor:(NSColor *)color gamma:(double)gamma;
+ (NSString *)stringForColor:(NSColor *)color;

@end

#import <math.h> // for pow()
#import <AppKit/NSColor.h> // for +colorWithCalibratedRed...

static inline double
OAColorPaletteApplyGammaAndNormalize(unsigned int sample, unsigned int maxValue, double gammaValue)
{
    double normalizedSample = ((double)sample / (double)maxValue);

    if (gammaValue == 1.0)
        return normalizedSample;
    else
        return pow(normalizedSample, gammaValue);
}

static inline NSColor *
OAColorPaletteColorWithRGBMaxAndGamma(unsigned int red, unsigned int green, unsigned int blue, unsigned int maxValue, double gammaValue)
{
    return [NSColor colorWithCalibratedRed:OAColorPaletteApplyGammaAndNormalize(red, maxValue, gammaValue) green:OAColorPaletteApplyGammaAndNormalize(green, maxValue, gammaValue) blue:OAColorPaletteApplyGammaAndNormalize(blue, maxValue, gammaValue) alpha:1.0];
}
