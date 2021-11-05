// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSString-OAExtensions.h>
#import <Foundation/Foundation.h>

#if OMNI_BUILDING_FOR_MAC
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <OmniAppKit/OAApplication.h>
#endif

#if !OMNI_BUILDING_FOR_SERVER
#import <OmniAppKit/OAFindPattern.h>
#endif

//RCS_ID("$Id$")

@implementation NSString (OAExtensions)

#if OMNI_BUILDING_FOR_MAC

+ (NSString *)stringForKeyEquivalent:(NSString *)equivalent andModifierMask:(NSUInteger)mask;
{
    NSString *fullString = [NSString commandKeyIndicatorString];

    if (mask & NSEventModifierFlagControl)
        fullString = [[NSString controlKeyIndicatorString] stringByAppendingString:fullString];
    if (mask & NSEventModifierFlagOption)
        fullString = [[NSString alternateKeyIndicatorString] stringByAppendingString:fullString];
    if (mask & NSEventModifierFlagShift)
        fullString = [[NSString shiftKeyIndicatorString] stringByAppendingString:fullString];

    fullString = [fullString stringByAppendingString:[equivalent uppercaseString]];
    return fullString;
}

// String drawing

- (void)drawWithFontAttributes:(NSDictionary *)attributes alignment:(NSTextAlignment)alignment verticallyCenter:(BOOL)verticallyCenter inRectangle:(NSRect)rectangle;
{
    NSAttributedString *attributedString;
    
    attributedString = [[NSAttributedString alloc] initWithString:self attributes:attributes];
    [attributedString drawInRectangle:rectangle alignment:alignment verticallyCentered:verticallyCenter];
}

- (void)drawWithFont:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment verticallyCenter:(BOOL)verticallyCenter inRectangle:(NSRect)rectangle;
{
    NSMutableDictionary *attributes;

    attributes = [[NSMutableDictionary alloc] initWithCapacity:2];
    if (font)
        [attributes setObject:font forKey:NSFontAttributeName];
    if (color)
        [attributes setObject:color forKey:NSForegroundColorAttributeName];

    [self drawWithFontAttributes:attributes alignment:alignment verticallyCenter:verticallyCenter inRectangle:rectangle];
}

- (void)drawWithFontAttributes:(NSDictionary *)attributes alignment:(NSTextAlignment)alignment rectangle:(NSRect)rectangle;
{
    [self drawWithFontAttributes:attributes alignment:alignment verticallyCenter:NO inRectangle:rectangle];
}

- (void)drawWithFont:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment rectangle:(NSRect)rectangle;
{
    [self drawWithFont:font color:color alignment:alignment verticallyCenter:NO inRectangle:rectangle];
}

- (void)drawInRect:(NSRect)rectangle xOffset:(CGFloat)xOffset yOffset:(CGFloat)yOffset attributes:(NSDictionary *)attributes;
{
    rectangle.origin.x += xOffset;
    rectangle.origin.y += yOffset;
    [self drawInRect:rectangle withAttributes:attributes];
}

// Replacement

- (BOOL)findPattern:(id <OAFindPattern>)pattern foundRange:(NSRangePointer)foundRangePointer;
{
    return [pattern findInString:self foundRange:foundRangePointer];
}

- (BOOL)findPattern:(id <OAFindPattern>)pattern inRange:(NSRange)range foundRange:(NSRangePointer)foundRangePointer;
{
    return [pattern findInRange:range ofString:self foundRange:foundRangePointer];
}

- (NSString *)stringByReplacingAllOfPattern:(id <OAFindPattern>)pattern;
{
    NSRange foundRange = NSMakeRange(0, 0);
    if ([self findPattern:pattern foundRange:&foundRange]) {
        NSMutableString *mutableCopy = [self mutableCopy];
        [mutableCopy replaceAllOfPattern:pattern];
        return mutableCopy;
    }
    
    return self;
}

#endif // OMNI_BUILDING_FOR_MAC

- (nullable NSString *)stringByAddingPercentEncodingWithURLQueryAllowedCharactersForQueryArgumentAssumingAmpersandDelimiter;
{
    NSCharacterSet *queryCharacterSet = [NSCharacterSet URLQueryAllowedCharacterSet];
    
    // & handled directly per http://stackoverflow.com/questions/8088473/how-do-i-url-encode-a-string/22388417#22388417
    // & is allowed in the URLQueryAllowedCharacterSet
    NSString *result = [self stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
    return [result stringByAddingPercentEncodingWithAllowedCharacters:queryCharacterSet];
}

- (NSString *)stringByRemovingPercentEncodingFromURLQueryAssumingAmpersandDelimiter;
{
    NSString *result = [self stringByReplacingOccurrencesOfString:@"%26" withString:@"&"];
    return [result stringByRemovingPercentEncoding];
}

@end

#pragma mark -

#if !OMNI_BUILDING_FOR_SERVER
@implementation NSMutableString (OAExtensions)

- (BOOL)replaceAllOfPattern:(id <OAFindPattern>)pattern;
{
    NSUInteger location = 0;
    NSUInteger length = self.length;
    BOOL madeReplacements = NO;
    
    while (location < length) {
        NSRange range = NSMakeRange(0, 0);
        if (![pattern findInRange:NSMakeRange(location, length - location) ofString:self foundRange:&range]) {
            break;
        }
        
        NSString *replacement = [pattern replacementStringForLastFind];
        [self replaceCharactersInRange:range withString:replacement];

        madeReplacements = YES;
        length = self.length;
        location = range.location + replacement.length;
    }

    return madeReplacements;
}

@end
#endif // !OMNI_BUILDING_FOR_SERVER
