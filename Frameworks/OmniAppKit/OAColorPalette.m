// Copyright 1997-2005, 2007-2008, 2010-2012 Omni Development, Inc. All rights reserved.
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
    unichar hexText[MAX_HEX_TEXT_LENGTH];
    unichar hexDigit;
    unsigned int textIndex;
    unsigned long long int hexValue;
    unsigned int hexDigitsFound;

    NSUInteger hexLength = [hexString length];
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

static NSColor *colorForHexString(NSString *colorString, NSColorSpace *space)
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

    CGFloat components[4];
    components[0] = (CGFloat)red / (CGFloat)maskForSingleComponent;
    components[1] = (CGFloat)green / (CGFloat)maskForSingleComponent;
    components[2] = (CGFloat)blue / (CGFloat)maskForSingleComponent;
    components[3] = (CGFloat)1; /* Alpha */
    
    return [NSColor colorWithColorSpace:space components:components count:4];
}

static inline NSColor *colorForNamedColorString(NSString *colorString, NSColorSpace *space)
{
    NSString *namedColorString;

    namedColorString = [namedColorsDictionary objectForKey:[colorString lowercaseString]];
    if (namedColorString) {
        // Found the named color, look up its hex value and return the color
        return colorForHexString(namedColorString, space);
    } else {
        // Named color not found
        return nil;
    }
}

+ (NSColor *)colorForString:(NSString *)colorString colorSpace:(NSColorSpace *)space;
{
    if ([space colorSpaceModel] != NSRGBColorSpaceModel) {
        OBRejectInvalidCall(self, _cmd, @"Color space for reading hex strings must be an RGB color space");
    }
        
    if (colorString == nil || [colorString length] == 0)
        return nil;
    if ([colorString hasPrefix:@"#"]) {
        NSColor *hexColor;

        // Should be a hex color string
        hexColor = colorForHexString(colorString, space);
        if (hexColor) {
            return hexColor;
        } else {
            // Sometimes people set their colors to "#RED"
            return colorForNamedColorString([colorString substringFromIndex:1], space);
        }
    } else {
        NSColor *namedColor;

        // Try named color string first
        namedColor = colorForNamedColorString(colorString, space);
        if (namedColor) {
            return namedColor;
        } else {
            // Sometimes people write hex colors without a leading "#"
            return colorForHexString(colorString, space);
        }
    }
}

static NSString *stringForColor(NSColor *color, double gammaValue)
{
    CGFloat red = 0.0f, green = 0.0f, blue = 0.0f, alpha = 0.0f;

    if (color == nil)
        return nil;

    // Note: alpha is ignored
    // Note that colorUsingColorSpaceName: may fail, leaving the values at zero.
    [[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getRed:&red green:&green blue:&blue alpha:&alpha];
    if (gammaValue != 1.0f) {
        red = (CGFloat)pow(red, 1.0 / gammaValue);
        green = (CGFloat)pow(green, 1.0 / gammaValue);
        blue = (CGFloat)pow(blue, 1.0 / gammaValue);
    }
    return [NSString stringWithFormat:@"#%02x%02x%02x", ((int)rint(red * 255.0f)),  ((int)rint(green * 255.0f)), ((int)rint(blue * 255.0f))];
}

+ (NSString *)stringForColor:(NSColor *)color colorSpace:(NSColorSpace *)space;
{
    if ([space colorSpaceModel] != NSRGBColorSpaceModel) {
        OBRejectInvalidCall(self, _cmd, @"Color space for creating hex strings must be an RGB color space");
    }
    
    return stringForColor([color colorUsingColorSpace:space], 1.0f);
}

@end
