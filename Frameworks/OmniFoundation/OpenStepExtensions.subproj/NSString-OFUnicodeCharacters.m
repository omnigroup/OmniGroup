// Copyright 1997-2008, 2010, 2014 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSString-OFUnicodeCharacters.h>

#import <OmniFoundation/OFUnicodeUtilities.h>

RCS_ID("$Id$");

@implementation NSString (OFUnicodeCharacters)

+ (NSString *)stringWithCharacter:(UnicodeScalarValue)aCharacter;
{
    unichar utf16[2];
    NSString *result;
    
    OBASSERT(sizeof(aCharacter)*8 >= 21);
    /* aCharacter must be at least 21 bits to contain a full Unicode character */
    
    if (aCharacter <= 0xFFFF) {
        utf16[0] = (unichar)aCharacter;
        result = [[self alloc] initWithCharacters:utf16 length:1];
    } else {
        /* Convert Unicode characters in supplementary planes into pairs of UTF-16 surrogates */
        OFCharacterToSurrogatePair(aCharacter, utf16);
        result = [[self alloc] initWithCharacters:utf16 length:2];
    }
    return [result autorelease];
}

+ (NSString *)horizontalEllipsisString;
{
    static NSString *string = nil;
    
    if (!string)
        string = [[self stringWithCharacter:0x2026] retain];
    
    OBPOSTCONDITION(string);
    
    return string;
}

+ (NSString *)leftPointingDoubleAngleQuotationMarkString;
{
    static NSString *string = nil;
    
    if (!string)
        string = [[self stringWithCharacter:0xab] retain];
    
    OBPOSTCONDITION(string);
    
    return string;
}

+ (NSString *)rightPointingDoubleAngleQuotationMarkString;
{
    static NSString *string = nil;
    
    if (!string)
        string = [[self stringWithCharacter:0xbb] retain];
    
    OBPOSTCONDITION(string);
    
    return string;
}

+ (NSString *)emdashString;
{
    static NSString *string = nil;
    
    if (!string)
        string = [[self stringWithCharacter:0x2014] retain];
    
    OBPOSTCONDITION(string);
    
    return string;
}

+ (NSString *)endashString;
{
    static NSString *string = nil;
    
    if (!string)
        string = [[self stringWithCharacter:0x2013] retain];
    
    OBPOSTCONDITION(string);
    
    return string;
}

+ (NSString *)commandKeyIndicatorString;
{
    static NSString *string = nil;
    
    if (!string)
        string = [[self stringWithCharacter:0x2318] retain];
    
    OBPOSTCONDITION(string);
    
    return string;
}

+ (NSString *)controlKeyIndicatorString;
{
    static NSString *string = nil;
    
    if (!string)
        string = [[self stringWithCharacter:0x2303] retain];
    
    OBPOSTCONDITION(string);
    
    return string;
}

+ (NSString *)alternateKeyIndicatorString;
{
    static NSString *string = nil;
    
    // Len and I noticed that this is actually returning the Option key indicator string. The Alternate key indicator string would be character 0x2387. This "works" for us, because everywhere (probably) that uses this actually wants the Option key indicator string. (So ideally we would rename this method accordingly - we probably don't have a need for the Alternate key indicator string.) -andrew
    if (!string)
        string = [[self stringWithCharacter:0x2325] retain];
    
    OBPOSTCONDITION(string);
    
    return string;
}

+ (NSString *)shiftKeyIndicatorString;
{
    static NSString *string = nil;
    
    if (!string)
        string = [[self stringWithCharacter:0x21E7] retain];
    
    OBPOSTCONDITION(string);
    
    return string;
}

static dispatch_once_t makeXMLCharacterSetsOnce;
static NSCharacterSet *invalidXMLCharacterSet;
static NSCharacterSet *discouragedXMLCharacterSet;

static void makeXMLCharacterSets(void *ctxt)
{
    NSMutableCharacterSet *set = [[NSMutableCharacterSet alloc] init];
    
    /* Construct the 'Char' production from REC-xml-20081126 (Extensible Markup Language 1.0 Fifth Edition), section 2.2 */
    [set addCharactersInRange:(NSRange){0x00009, 0x00002}];
    [set addCharactersInRange:(NSRange){0x0000D, 0x00001}];
    [set addCharactersInRange:(NSRange){0x00020, 0x0D7E0}];
    [set addCharactersInRange:(NSRange){0x0E000, 0x01FFE}];
    [set addCharactersInRange:(NSRange){0x10000, 0xF0000}];
    
    [set invert];
    OBPRECONDITION(invalidXMLCharacterSet == nil);
    invalidXMLCharacterSet = [set copy];
    
    /* Additional discouraged characters from section 2.2 */
    [set addCharactersInRange:(NSRange){0x0007F, 0x00006}];
    [set addCharactersInRange:(NSRange){0x00086, 0x0001A}];
    [set addCharactersInRange:(NSRange){0x0FDD0, 0x00020}];
    for (NSInteger plane = 1; plane <= 16; plane ++)
        [set addCharactersInRange:(NSRange){plane * 0x10000 + 0xFFFE, 2}];
    
    discouragedXMLCharacterSet = [set copy];
    
    [set release];
}

+ (NSCharacterSet *)invalidXMLCharacterSet;  // Characters forbidden in an XML document
{
    dispatch_once_f(&makeXMLCharacterSetsOnce, NULL, makeXMLCharacterSets);
    return invalidXMLCharacterSet;
}

+ (NSCharacterSet *)discouragedXMLCharacterSet;  // Characters discouraged in an XML document (a superset of -invalidXMLCharacterSet)
{
    dispatch_once_f(&makeXMLCharacterSetsOnce, NULL, makeXMLCharacterSets);
    return discouragedXMLCharacterSet;
}

@end
