// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAColorPalette.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation OAColorPalette

static NSDictionary *namedColorsDictionary = nil;

#define NonBuggyCharacterSet NSMutableCharacterSet

+ (void)initialize;
{
    OBINITIALIZE;

    namedColorsDictionary = [[NSDictionary alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[OAColorPalette class]] pathForResource:@"namedColors" ofType:@"plist"]];
}

#define MAX_HEX_TEXT_LENGTH 40

static inline unsigned int parseHexString(NSString *hexString, unsigned long long int *parsedHexValue)
{
    unsigned int hexLength;
    unichar hexText[MAX_HEX_TEXT_LENGTH];
    unichar hexDigit;
    unsigned int textIndex;
    unsigned long long int hexValue;
    unsigned int hexDigitsFound;

    hexLength = [hexString length];
    if (hexLength > MAX_HEX_TEXT_LENGTH)
        hexLength = MAX_HEX_TEXT_LENGTH;
    [hexString getCharacters:hexText range:NSMakeRange(0, hexLength)];

    textIndex = 0;
    hexValue = 0;
    hexDigitsFound = 0;

    while (textIndex < hexLength && (isspace(hexText[textIndex]) || hexText[textIndex] == '#')) {
        // Skip leading whitespace and #'s
        textIndex++;
    }

    while (textIndex < hexLength) {
        hexDigit = hexText[textIndex++];

        if (hexDigit >= '0' && hexDigit <= '9') {
            hexDigit = hexDigit - '0';
        } else if (hexDigit >= 'A' && hexDigit <= 'F') {
            hexDigit = hexDigit - 'A' + 10;
        } else if (hexDigit >= 'a' && hexDigit <= 'f') {
            hexDigit = hexDigit - 'a' + 10;
        } else if (hexDigit == 'o' || hexDigit == 'O') {
            // Some people use 'O' rather than '0'.
            hexDigit = 0;
        } else if (isspace(hexDigit)) {
            continue;
        } else {
            hexDigitsFound = 0;
            break;
        }
        hexDigitsFound++;
        hexValue <<= 4;
        hexValue |= hexDigit;
    }

    *parsedHexValue = hexValue;
    return hexDigitsFound;
}

static inline NSColor *colorForHexString(NSString *colorString, double gammaValue)
{
    unsigned long long int rawColor;
    unsigned int red, green, blue;
    unsigned int maskForSingleComponent;
    unsigned int bitsPerComponent;
    unsigned int bytesInColor;

    bytesInColor = parseHexString(colorString, &rawColor);
    if (bytesInColor < 6)
        bitsPerComponent = 4;
    else if (bytesInColor < 9)
        bitsPerComponent = 8;
    else
        bitsPerComponent = 12;

    maskForSingleComponent = (1 << bitsPerComponent) - 1;

    blue = (unsigned int)(rawColor & maskForSingleComponent);
    rawColor >>= bitsPerComponent;
    green = (unsigned int)(rawColor & maskForSingleComponent);
    rawColor >>= bitsPerComponent;
    red = (unsigned int)(rawColor & maskForSingleComponent);

    return OAColorPaletteColorWithRGBMaxAndGamma(red, green, blue, maskForSingleComponent, gammaValue);
}

static inline NSColor *colorForNamedColorString(NSString *colorString, double gammaValue)
{
    NSString *namedColorString;

    namedColorString = [namedColorsDictionary objectForKey:[colorString lowercaseString]];
    if (namedColorString) {
        // Found the named color, look up its hex value and return the color
        return colorForHexString(namedColorString, gammaValue);
    } else {
        // Named color not found
        return nil;
    }
}

+ (NSColor *)colorForString:(NSString *)colorString gamma:(double)gammaValue;
{
    if (colorString == nil || [colorString length] == 0)
        return nil;
    if ([colorString hasPrefix:@"#"]) {
        NSColor *hexColor;

        // Should be a hex color string
        hexColor = colorForHexString(colorString, gammaValue);
        if (hexColor) {
            return hexColor;
        } else {
            // Sometimes people set their colors to "#RED"
            return colorForNamedColorString([colorString substringFromIndex:1], gammaValue);
        }
    } else {
        NSColor *namedColor;

        // Try named color string first
        namedColor = colorForNamedColorString(colorString, gammaValue);
        if (namedColor) {
            return namedColor;
        } else {
            // Sometimes people write hex colors without a leading "#"
            return colorForHexString(colorString, gammaValue);
        }
    }
}

+ (NSColor *)colorForString:(NSString *)colorString;
{
    return [self colorForString:colorString gamma:1.0];
}

+ (NSString *)stringForColor:(NSColor *)color gamma:(double)gammaValue;
{
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;

    if (color == nil)
        return nil;

    // Note: alpha is ignored
    // Note that colorUsingColorSpaceName: may fail, leaving the values at zero.
    [[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getRed:&red green:&green blue:&blue alpha:&alpha];
    if (gammaValue != 1.0) {
        red = pow(red, 1.0 / gammaValue);
        green = pow(green, 1.0 / gammaValue);
        blue = pow(blue, 1.0 / gammaValue);
    }
    return [NSString stringWithFormat:@"#%02x%02x%02x", ((int)rint(red * 255.0)),  ((int)rint(green * 255.0)), ((int)rint(blue * 255.0))];
}

+ (NSString *)stringForColor:(NSColor *)color;
{
    return [self stringForColor:color gamma:1.0];
}

@end
