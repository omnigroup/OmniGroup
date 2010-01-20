// Copyright 1997-2005, 2007-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSString-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <OmniAppKit/OAApplication.h>

RCS_ID("$Id$")

@implementation NSString (OAExtensions)

+ (NSString *)stringForKeyEquivalent:(NSString *)equivalent andModifierMask:(NSUInteger)mask;
{
    NSString *fullString = [NSString commandKeyIndicatorString];

    if (mask & NSControlKeyMask)
        fullString = [[NSString controlKeyIndicatorString] stringByAppendingString:fullString];
    if (mask & NSAlternateKeyMask)
        fullString = [[NSString alternateKeyIndicatorString] stringByAppendingString:fullString];
    if (mask & NSShiftKeyMask)
        fullString = [[NSString shiftKeyIndicatorString] stringByAppendingString:fullString];

    fullString = [fullString stringByAppendingString:[equivalent uppercaseString]];
    return fullString;
}

// Uses deprecated API
#if 0
+ (NSString *)possiblyAbbreviatedStringForBytes:(unsigned long long)bytes inTableView:(NSTableView *)tableView tableColumn:(NSTableColumn *)tableColumn;
{
    NSCell *dataCell;
    NSString *bytesString;

    bytesString = [NSString stringWithFormat:@"%@", [NSNumber numberWithUnsignedLongLong:bytes]];
    dataCell = [tableColumn dataCell];
#warning Deprecated in Mac OS 10.4. This API never returns correct value. Use NSStringDrawing API instead.
    if ([[dataCell font] widthOfString:bytesString] + 5 <= [dataCell titleRectForBounds:NSMakeRect(0, 0, [tableColumn width], [tableView rowHeight])].size.width)
        return [bytesString stringByAppendingString:NSLocalizedStringFromTableInBundle(@" bytes", @"OmniAppKit", [OAApplication bundle], "last word of abbreviated bytes string if no abbreviation is necessary")];
    else
        return [NSString abbreviatedStringForBytes:bytes];
}
#endif

// Uses deprecated API
#if 0
- (NSString *)truncatedStringWithMaxWidth:(SInt16)maxWidth themeFontID:(ThemeFontID)themeFont truncationMode:(TruncCode)truncationCode;
{
#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5  // Uses API deprecated on 10.5
    NSMutableString *mutableSelf = [self mutableCopy];
    Boolean truncated = false;
    OSStatus theErr;
    
    theErr = TruncateThemeText((CFMutableStringRef)mutableSelf, themeFont, kThemeStateActive, maxWidth, truncationCode, &truncated);
    if (theErr != noErr)
        NSLog(@"%s: theErr = %ld", _cmd, theErr);
    
    return [mutableSelf autorelease];
#else
    // OBASSERT_NOT_REACHED("-truncatedStringWithMaxWidth:themeFontID:truncationMode: needs to be updated for 10.5");
    // Rather than failing at runtime, let's at least attempt to do something along the lines of what the caller intended.  (OmniWeb uses this to make sure that its Bookmark and History menu item titles don't get too wide.)
    return [self substringToIndex:MIN([self length], (unsigned)maxWidth / 10)];
#endif
}

- (NSString *)truncatedMenuItemStringWithMaxWidth:(SInt16)maxWidth;
{
    return [self truncatedStringWithMaxWidth:maxWidth themeFontID:kThemeMenuItemFont truncationMode:truncMiddle];
}
#endif

// String drawing

- (void)drawWithFontAttributes:(NSDictionary *)attributes alignment:(int)alignment verticallyCenter:(BOOL)verticallyCenter inRectangle:(NSRect)rectangle;
{
    NSAttributedString *attributedString;
    
    attributedString = [[NSAttributedString alloc] initWithString:self attributes:attributes];
    [attributedString drawInRectangle:rectangle alignment:alignment verticallyCentered:verticallyCenter];
    [attributedString release];
}

- (void)drawWithFont:(NSFont *)font color:(NSColor *)color alignment:(int)alignment verticallyCenter:(BOOL)verticallyCenter inRectangle:(NSRect)rectangle;
{
    NSMutableDictionary *attributes;

    attributes = [[NSMutableDictionary alloc] initWithCapacity:2];
    if (font)
        [attributes setObject:font forKey:NSFontAttributeName];
    if (color)
        [attributes setObject:color forKey:NSForegroundColorAttributeName];

    [self drawWithFontAttributes:attributes alignment:alignment verticallyCenter:verticallyCenter inRectangle:rectangle];
    [attributes release];
}

- (void)drawWithFontAttributes:(NSDictionary *)attributes alignment:(int)alignment rectangle:(NSRect)rectangle;
{
    [self drawWithFontAttributes:attributes alignment:alignment verticallyCenter:NO inRectangle:rectangle];
}

- (void)drawWithFont:(NSFont *)font color:(NSColor *)color alignment:(int)alignment rectangle:(NSRect)rectangle;
{
    [self drawWithFont:font color:color alignment:alignment verticallyCenter:NO inRectangle:rectangle];
}

- (void)drawInRect:(NSRect)rectangle xOffset:(CGFloat)xOffset yOffset:(CGFloat)yOffset attributes:(NSDictionary *)attributes;
{
    rectangle.origin.x += xOffset;
    rectangle.origin.y += yOffset;
    [self drawInRect:rectangle withAttributes:attributes];
}

@end
