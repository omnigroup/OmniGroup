// Copyright 1997-2005,2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSFont-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <ApplicationServices/ApplicationServices.h>

RCS_ID("$Id$")

@implementation NSFont (OAExtensions)

- (BOOL)isScreenFont;
{
    return [self screenFont] == self;
}

- (float)widthOfString:(NSString *)aString;
{
    static NSTextStorage *fontWidthTextStorage = nil;
    static NSLayoutManager *fontWidthLayoutManager = nil;
    static NSTextContainer *fontWidthTextContainer = nil;

    NSAttributedString *attributedString;
    NSRange drawGlyphRange;
    NSRect *rectArray;
    NSUInteger rectCount;
    NSDictionary *attributes;

    if (!fontWidthTextStorage) {
        fontWidthTextStorage = [[NSTextStorage alloc] init];

        fontWidthLayoutManager = [[NSLayoutManager alloc] init];
        [fontWidthTextStorage addLayoutManager:fontWidthLayoutManager];

        fontWidthTextContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(1e7, 1e7)];
        [fontWidthTextContainer setLineFragmentPadding:0];
        [fontWidthLayoutManager addTextContainer:fontWidthTextContainer];
    }

    attributes = [[NSDictionary alloc] initWithObjectsAndKeys: self, NSFontAttributeName, nil];
    attributedString = [[NSAttributedString alloc] initWithString:aString attributes:attributes];
    [fontWidthTextStorage setAttributedString:attributedString];
    [attributedString release];
    [attributes release];

    drawGlyphRange = [fontWidthLayoutManager glyphRangeForTextContainer:fontWidthTextContainer];
    if (drawGlyphRange.length == 0)
        return 0.0;

    rectArray = [fontWidthLayoutManager rectArrayForGlyphRange:drawGlyphRange withinSelectedGlyphRange:NSMakeRange(NSNotFound, 0) inTextContainer:fontWidthTextContainer rectCount:&rectCount];
    if (rectCount < 1)
        return 0.0;
    return rectArray[0].size.width;
}

+ (NSFont *)fontFromPropertyListRepresentation:(NSDictionary *)dict;
{
    return [NSFont fontWithName:[dict objectForKey:@"name"] size:[[dict objectForKey:@"size"] cgFloatValue]];
}

- (NSDictionary *)propertyListRepresentation;
{
    NSMutableDictionary *result;
    
    result = [NSMutableDictionary dictionary];
    [result setObject:[NSNumber numberWithFloat:[self pointSize]] forKey:@"size"];
    [result setObject:[self fontName] forKey:@"name"];
    return result;
}

/*" Returns the PANOSE 1 information from the receiver as a string containing ten space-separated decimal numbers. Returns nil if it can't find a PANOSE 1 description of the font.
 
Some PANOSE specification information can be found at http://www.panose.com/ProductsServices/pan1.aspx "*/
- (NSString *)panose1String;
{
    // On 10.5+, NSFont is toll-free-bridged to CTFont
    CTFontRef ctFont = (CTFontRef)self;
    
    // The OS/2 table contains the PANOSE classification
    CFDataRef os2Table = CTFontCopyTable(ctFont, kCTFontTableOS2, kCTFontTableOptionNoOptions /* TODO: kCTFontTableOptionExcludeSynthetic? */ );
    
    if (!os2Table)
        return nil;
    
    // The PANOSE data is in bytes 32-42 of the table according to the TrueType and OpenType specs.
    if (CFDataGetLength(os2Table) < 42) {
        // Truncated table?
        CFRelease(os2Table);
        return nil;
    }
    
    uint8_t panose[10];
    CFDataGetBytes(os2Table, (CFRange){ 32, 10 }, panose);
    
    CFRelease(os2Table);
    
    // Fonts with no PANOSE info but other OS/2 info will usually set this field to all 0s, which is a wildcard specification.
    int i;
    for(i = 0; i < 10; i++)
        if (panose[i] != 0)
            break;
    if (i == 10)
        return nil;

    // Some sanity checks.
    if(panose[0] > 20) {
        // Only 0 through 5 are actually defined by the PANOSE 1 specification.
        // It lists a few other categories but doesn't assign numbers to them. This check should allow for the unlikely event of future expansion of PANOSE 1, while still eliminating completely bogus data.
        return nil;
    }
    
    return [NSString stringWithFormat:@"%d %d %d %d %d %d %d %d %d %d",
            panose[0], panose[1], panose[2], panose[3], panose[4],
            panose[5], panose[6], panose[7], panose[8], panose[9]];
}


@end
