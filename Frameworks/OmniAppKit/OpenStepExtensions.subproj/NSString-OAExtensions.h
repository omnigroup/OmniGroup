// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSString.h>

#import <Carbon/Carbon.h> // For ThemeFontID, TruncCode
#import <Foundation/NSGeometry.h> // For NSRect

@class NSColor, NSFont, NSImage, NSTableColumn, NSTableView;
@protocol OAFindPattern;

@interface NSString (OAExtensions)

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

@end

#pragma mark -

@interface NSMutableString (OAExtensions)

- (BOOL)replaceAllOfPattern:(id <OAFindPattern>)pattern;

@end
