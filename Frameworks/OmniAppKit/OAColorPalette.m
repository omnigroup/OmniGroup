// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAColorPalette.h>

@import Foundation;
@import OmniBase;
@import OmniFoundation;

#if TARGET_OS_IOS
@import UIKit;
#else
@import AppKit;
#endif

RCS_ID("$Id$")

@implementation OAColorPalette

static NSDictionary *namedColorsDictionary(void)
{
    static NSDictionary *_namedColorsDictionary;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _namedColorsDictionary = [[NSDictionary alloc] initWithContentsOfFile:[OMNI_BUNDLE pathForResource:@"namedColors" ofType:@"plist"]];
    });
    return _namedColorsDictionary;
}

#define MAX_HEX_TEXT_LENGTH 40

static inline unsigned int parseHexString(NSString *hexString, unsigned long long int *parsedHexValue)
{
    NSUInteger hexLength = [hexString length];
    if (hexLength > MAX_HEX_TEXT_LENGTH)
        hexLength = MAX_HEX_TEXT_LENGTH;

    unichar hexText[hexLength];
    [hexString getCharacters:hexText range:NSMakeRange(0, hexLength)];

    unsigned int textIndex = 0;
    unsigned long long int hexValue = 0;
    unsigned int hexDigitsFound = 0;

    while (textIndex < hexLength && (isspace(hexText[textIndex]) || hexText[textIndex] == '#')) {
        // Skip leading whitespace and #'s
        textIndex++;
    }

    while (textIndex < hexLength) {
        unichar hexDigit = hexText[textIndex++];

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

static OA_PLATFORM_COLOR_CLASS *_colorForHexString(NSString *colorString)
{
    unsigned long long int rawColor;
    unsigned int bytesInColor = parseHexString(colorString, &rawColor);
    unsigned int bitsPerComponent;
    if (bytesInColor < 6)
        bitsPerComponent = 4;
    else if (bytesInColor < 9)
        bitsPerComponent = 8;
    else
        bitsPerComponent = 12;

    unsigned int maskForSingleComponent = (1 << bitsPerComponent) - 1;

    unsigned int red, green, blue;
    blue = (unsigned int)(rawColor & maskForSingleComponent);
    rawColor >>= bitsPerComponent;
    green = (unsigned int)(rawColor & maskForSingleComponent);
    rawColor >>= bitsPerComponent;
    red = (unsigned int)(rawColor & maskForSingleComponent);

    CGFloat components[4];
    components[0] = (CGFloat)red / (CGFloat)maskForSingleComponent;
    components[1] = (CGFloat)green / (CGFloat)maskForSingleComponent;
    components[2] = (CGFloat)blue / (CGFloat)maskForSingleComponent;
    components[3] = (CGFloat)1.0f; /* Alpha */
    
    return [OA_PLATFORM_COLOR_CLASS colorWithRed:components[0] green:components[1] blue:components[2] alpha:components[3]];
}

static inline OA_PLATFORM_COLOR_CLASS *_colorForNamedColorString(NSString *colorString)
{
    NSString *namedColorString = [namedColorsDictionary() objectForKey:[colorString lowercaseString]];
    if (namedColorString != nil) {
        // Found the named color, look up its hex value and return the color
        return _colorForHexString(namedColorString);
    } else {
        // Named color not found
        return nil;
    }
}

+ (OA_PLATFORM_COLOR_CLASS *)colorForHexString:(NSString *)colorString;
{
    return _colorForHexString(colorString);
}

+ (OA_PLATFORM_COLOR_CLASS *)colorForString:(NSString *)colorString;
{
    if (colorString == nil || [colorString length] == 0)
        return nil;
    if ([colorString hasPrefix:@"#"]) {
        // Should be a hex color string
        OA_PLATFORM_COLOR_CLASS *hexColor = _colorForHexString(colorString);
        if (hexColor != nil) {
            return hexColor;
        } else {
            // Sometimes people set their colors to "#RED"
            return _colorForNamedColorString([colorString substringFromIndex:1]);
        }
    } else {
        // Try named color string first
        OA_PLATFORM_COLOR_CLASS *namedColor = _colorForNamedColorString(colorString);
        if (namedColor != nil) {
            return namedColor;
        } else {
            // Sometimes people write hex colors without a leading "#"
            return _colorForHexString(colorString);
        }
    }
}

static NSString *_stringForColor(OA_PLATFORM_COLOR_CLASS *color)
{
    CGFloat red = 0.0f, green = 0.0f, blue = 0.0f, alpha = 0.0f;

    if (color == nil)
        return nil;

    // Note: alpha is ignored
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    return [NSString stringWithFormat:@"#%02x%02x%02x", ((int)rint(red * 255.0f)),  ((int)rint(green * 255.0f)), ((int)rint(blue * 255.0f))];
}

+ (NSString *)stringForColor:(OA_PLATFORM_COLOR_CLASS *)color;
{
#if !TARGET_OS_IOS
    // Note that colorUsingColorSpaceName: may fail, returning nil
    color = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
#endif

    return _stringForColor(color);
}

@end
