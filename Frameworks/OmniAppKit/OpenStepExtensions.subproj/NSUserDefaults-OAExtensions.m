// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSUserDefaults-OAExtensions.h"

#import <Foundation/Foundation.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFontDescriptor.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSColor-OAExtensions.h>

#include <inttypes.h>

RCS_ID("$Id$")

static NSColor *nsColorFromRGBAString(NSString *value)
{
    CGFloat r = 0.0f, g = 0.0f, b = 0.0f, a = 1.0f;
    
    if ([NSString isEmptyString:value])
        return nil;
    
    int components = sscanf([value UTF8String], "%"SCNfCG "%"SCNfCG "%"SCNfCG "%"SCNfCG, &r, &g, &b, &a);
    if (components != 3 && components != 4)
        return nil;

    return OARGBA(r, g, b, a);
}

static NSString *rgbaStringFromNSColor(NSColor *color)
{
    OBASSERT(color != nil); // Caller should be doing fallback
    
    CGFloat r, g, b, a;
    [[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getRed:&r green:&g blue:&b alpha:&a];
    if (a == 1.0)
	return [NSString stringWithFormat:@"%g %g %g", r, g, b];
    else
	return [NSString stringWithFormat:@"%g %g %g %g", r, g, b, a];
}

@implementation NSUserDefaults (OAExtensions)

- (NSColor *)colorForKey:(NSString *)defaultName;
{
    return nsColorFromRGBAString([self stringForKey:defaultName]);
}

- (NSColor *)grayForKey:(NSString *)defaultName;
{
    return [NSColor colorWithCalibratedWhite:[self floatForKey:defaultName] alpha:1.0f];
}

- (void)setColor:(NSColor *)color forKey:(NSString *)defaultName;
{
    if (!color) {
        [self setObject:@"" forKey:defaultName];
    } else {
        [self setObject:rgbaStringFromNSColor(color) forKey:defaultName];
    }
}

- (void)setGray:(NSColor *)gray forKey:(NSString *)defaultName;
{
    CGFloat grayFloat;

    [[gray colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] getWhite:&grayFloat alpha:NULL];
    NSNumber *grayNumber = [[NSNumber alloc] initWithCGFloat:grayFloat];
    [self setObject:grayNumber forKey:defaultName];
}

@end


@implementation OFPreference (OAExtensions)

- (NSColor *)colorValue;
{
    return nsColorFromRGBAString([self stringValue]);
}

- (void)setColorValue:(NSColor *)color;
{
    if (color == nil) {
        [self setObjectValue:nil];
    } else {
        [self setStringValue:rgbaStringFromNSColor(color)];
    }
}

- (NSFontDescriptor *)fontDescriptorValue;
{
    NSDictionary *attributes = [self objectValue];
    return [NSFontDescriptor fontDescriptorWithFontAttributes:attributes];
}

- (void)setFontDescriptorValue:(NSFontDescriptor *)fontDescriptor;
{
    NSDictionary *attributes = [fontDescriptor fontAttributes];
    [self setObjectValue:attributes];
}

@end

@implementation OFPreferenceWrapper (OAExtensions)

- (NSColor *)colorForKey:(NSString *)defaultName;
{
    return nsColorFromRGBAString([self stringForKey:defaultName]);
}

- (NSColor *)grayForKey:(NSString *)defaultName;
{
    return [NSColor colorWithCalibratedWhite:[self floatForKey:defaultName] alpha:1.0f];
}

- (void)setColor:(NSColor *)color forKey:(NSString *)defaultName;
{
    if (!color) {
        [self setObject:@"x" forKey:defaultName];
    } else {
        [self setObject:rgbaStringFromNSColor(color) forKey:defaultName];
    }
}

- (void)setGray:(NSColor *)gray forKey:(NSString *)defaultName;
{
    CGFloat grayFloat;

    [[gray colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] getWhite:&grayFloat alpha:NULL];
    NSNumber *grayNumber = [[NSNumber alloc] initWithCGFloat:grayFloat];
    [self setObject:grayNumber forKey:defaultName];
}

@end

