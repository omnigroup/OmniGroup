// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSString.h>

#if OMNI_BUILDING_FOR_MAC
#import <Carbon/Carbon.h> // For ThemeFontID, TruncCode
#import <Foundation/NSGeometry.h> // For NSRect
#endif

@class NSColor, NSFont, NSImage, NSTableColumn, NSTableView;
@protocol OAFindPattern;

@interface NSString (OAExtensions)

#if OMNI_BUILDING_FOR_MAC
+ (NSString *)stringForKeyEquivalent:(NSString *)equivalent andModifierMask:(NSUInteger)mask;

// String drawing
- (void)drawWithFontAttributes:(NSDictionary *)attributes alignment:(NSTextAlignment)alignment verticallyCenter:(BOOL)verticallyCenter inRectangle:(NSRect)rectangle;
- (void)drawWithFont:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment verticallyCenter:(BOOL)verticallyCenter inRectangle:(NSRect)rectangle;
- (void)drawWithFontAttributes:(NSDictionary *)attributes alignment:(NSTextAlignment)alignment rectangle:(NSRect)rectangle;
- (void)drawWithFont:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment rectangle:(NSRect)rectangle;

// Replacement

- (BOOL)findPattern:(id <OAFindPattern>)pattern foundRange:(NSRangePointer)foundRangePointer;
- (BOOL)findPattern:(id <OAFindPattern>)pattern inRange:(NSRange)range foundRange:(NSRangePointer)foundRangePointer;

- (NSString *)stringByReplacingAllOfPattern:(id <OAFindPattern>)pattern;
#endif

/// We're currently assuming you'll use & as the delimeter for query arguments. As http://tools.ietf.org/html/rfc3986#section-2.2 shows, there are other sub-delimiters that could be used.
/// This utility is provided as a convenience for use with & as the delimiter because it's prevalent throughout OmniFocus
- (NSString *)stringByAddingPercentEncodingWithURLQueryAllowedCharactersForQueryArgumentAssumingAmpersandDelimiter;

/// Useful for undoing the work of stringByAddingPercentEncodingWithURLQueryAllowedCharactersForQueryArgumentAssumingAmpersandDelimiter and retrieving & from a percent encoded string
- (NSString *)stringByRemovingPercentEncodingFromURLQueryAssumingAmpersandDelimiter;

@end

#pragma mark -

#if !OMNI_BUILDING_FOR_SERVER
@interface NSMutableString (OAExtensions)

- (BOOL)replaceAllOfPattern:(id <OAFindPattern>)pattern;

@end
#endif
