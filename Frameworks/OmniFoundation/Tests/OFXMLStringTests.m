// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/OFUnicodeUtilities.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFXMLStringTests : OFTestCase
@end

#define QUOTE_NEWLINE(src, dest, flags, nl) do { \
    NSString *q = OFXMLCreateStringWithEntityReferencesInCFEncoding(src, flags, nl, kCFStringEncodingUTF8); \
    XCTAssertEqualObjects(q, dest, @""); \
} while (0)
#define QUOTE(src, dest, flags) QUOTE_NEWLINE((src), (dest), (flags), nil)

@implementation OFXMLStringTests

- (void)testDefaultQuoting;
{
    QUOTE(@"&", @"&amp;", OFXMLBasicEntityMask);
    QUOTE(@"<", @"&lt;", OFXMLBasicEntityMask);
    QUOTE(@">", @"&gt;", OFXMLBasicEntityMask);
    QUOTE(@"'", @"&apos;", OFXMLBasicEntityMask);
    QUOTE(@"\"", @"&quot;", OFXMLBasicEntityMask);
    QUOTE(@"\n", @"\n", OFXMLBasicEntityMask);
}

- (void)testHTMLQuoting;
{
    QUOTE(@"&", @"&amp;", OFXMLHTMLEntityMask);
    QUOTE(@"<", @"&lt;", OFXMLHTMLEntityMask);
    QUOTE(@">", @"&gt;", OFXMLHTMLEntityMask);
    QUOTE(@"'", @"&#39;", OFXMLHTMLEntityMask);
    QUOTE(@"\"", @"&quot;", OFXMLHTMLEntityMask);
    QUOTE(@"\n", @"\n", OFXMLHTMLEntityMask);
}

- (void)testCharacterQuoting;
{
    QUOTE(@"'", @"&#39;", (OFXMLCharacterFlagWriteCharacterEntity << OFXMLAposCharacterOptionsShift));
    QUOTE(@"\"", @"&#34;", (OFXMLCharacterFlagWriteCharacterEntity << OFXMLQuotCharacterOptionsShift));
}

- (void)testNoQuoting;
{
    QUOTE(@"'", @"'", (OFXMLCharacterFlagWriteUnquotedCharacter << OFXMLAposCharacterOptionsShift));
    QUOTE(@"\"", @"\"", (OFXMLCharacterFlagWriteUnquotedCharacter << OFXMLQuotCharacterOptionsShift));
}

- (void)testNewlineReplacement;
{
    QUOTE_NEWLINE(@"\n", @"!", OFXMLBasicWithNewlinesEntityMask, @"!");
    QUOTE_NEWLINE(@"\na\nb\n", @"!a!b!", OFXMLBasicWithNewlinesEntityMask, @"!");

    QUOTE_NEWLINE(@"\n", @"!", OFXMLHTMLWithNewlinesEntityMask, @"!");
    QUOTE_NEWLINE(@"\na\nb\n", @"!a!b!", OFXMLHTMLWithNewlinesEntityMask, @"!");
}

static unichar HighSurrogateHalf = 0xD83D;
static unichar LowSurrogateHalf = 0xDFFF;

//
// This group of tests checks what happens if a corrupt string object makes its way to OFXMLBufferAppendString()
//

- (void)testAppendOnlyHighSurrogateHalf;
{
    OBASSERT(OFCharacterIsSurrogate(HighSurrogateHalf) == OFIsSurrogate_HighSurrogate);
    NSString *source = [[NSString alloc] initWithCharacters:&HighSurrogateHalf length:1];

    OFXMLBuffer buffer = OFXMLBufferCreate();

    OFXMLBufferAppendString(buffer, (__bridge CFStringRef)source);

    NSString *output = (__bridge NSString *)OFXMLBufferCopyString(buffer);
    XCTAssertEqualObjects(output, @""); // Should drop the invalid half surrogate
}

- (void)testAppendOnlyHighSurrogateHalfInMiddle;
{
    unichar characters[3] = {'a', HighSurrogateHalf, 'b'};
    NSString *source = [[NSString alloc] initWithCharacters:characters length:3];

    OFXMLBuffer buffer = OFXMLBufferCreate();

    OFXMLBufferAppendString(buffer, (__bridge CFStringRef)source);

    NSString *output = (__bridge NSString *)OFXMLBufferCopyString(buffer);
    XCTAssertEqualObjects(output, @"ab"); // Should drop the invalid half surrogate
}

- (void)testAppendOnlyLowSurrogateHalf;
{
    OBASSERT(OFCharacterIsSurrogate(LowSurrogateHalf) == OFIsSurrogate_LowSurrogate);
    NSString *source = [[NSString alloc] initWithCharacters:&LowSurrogateHalf length:1];

    OFXMLBuffer buffer = OFXMLBufferCreate();

    OFXMLBufferAppendString(buffer, (__bridge CFStringRef)source);

    NSString *output = (__bridge NSString *)OFXMLBufferCopyString(buffer);
    XCTAssertEqualObjects(output, @""); // Should drop the invalid half surrogate
}

- (void)testAppendOnlyLowSurrogateHalfInMiddle;
{
    OBASSERT(OFCharacterIsSurrogate(LowSurrogateHalf) == OFIsSurrogate_LowSurrogate);
    unichar characters[3] = {'a', LowSurrogateHalf, 'b'};
    NSString *source = [[NSString alloc] initWithCharacters:characters length:3];

    OFXMLBuffer buffer = OFXMLBufferCreate();

    OFXMLBufferAppendString(buffer, (__bridge CFStringRef)source);

    NSString *output = (__bridge NSString *)OFXMLBufferCopyString(buffer);
    XCTAssertEqualObjects(output, @"ab"); // Should drop the invalid half surrogate
}

//
// This group of tests checks what happens if a corrupt string object is entity encoded
//


- (void)testEncodeOnlyHighSurrogateHalf;
{
    OBASSERT(OFCharacterIsSurrogate(HighSurrogateHalf) == OFIsSurrogate_HighSurrogate);
    NSString *source = [[NSString alloc] initWithCharacters:&HighSurrogateHalf length:1];

    NSString *output = OFXMLCreateStringWithEntityReferencesInCFEncoding(source, OFXMLBasicEntityMask, nil, kCFStringEncodingUTF8);
    XCTAssertEqualObjects(output, @""); // Should drop the invalid half surrogate
}

- (void)testEncodeOnlyHighSurrogateHalfInMiddle;
{
    unichar characters[3] = {'a', HighSurrogateHalf, 'b'};
    NSString *source = [[NSString alloc] initWithCharacters:characters length:3];

    NSString *output = OFXMLCreateStringWithEntityReferencesInCFEncoding(source, OFXMLBasicEntityMask, nil, kCFStringEncodingUTF8);
    XCTAssertEqualObjects(output, @"ab"); // Should drop the invalid half surrogate
}

- (void)testEncodeOnlyLowSurrogateHalf;
{
    OBASSERT(OFCharacterIsSurrogate(LowSurrogateHalf) == OFIsSurrogate_LowSurrogate);
    NSString *source = [[NSString alloc] initWithCharacters:&LowSurrogateHalf length:1];

    NSString *output = OFXMLCreateStringWithEntityReferencesInCFEncoding(source, OFXMLBasicEntityMask, nil, kCFStringEncodingUTF8);
    XCTAssertEqualObjects(output, @""); // Should drop the invalid half surrogate
}

- (void)testEncodeOnlyLowSurrogateHalfInMiddle;
{
    OBASSERT(OFCharacterIsSurrogate(LowSurrogateHalf) == OFIsSurrogate_LowSurrogate);
    unichar characters[3] = {'a', LowSurrogateHalf, 'b'};
    NSString *source = [[NSString alloc] initWithCharacters:characters length:3];

    NSString *output = OFXMLCreateStringWithEntityReferencesInCFEncoding(source, OFXMLBasicEntityMask, nil, kCFStringEncodingUTF8);
    XCTAssertEqualObjects(output, @"ab"); // Should drop the invalid half surrogate
}

//
// Make sure a valid character works
//

- (void)testEncodeSurrogatePair;
{
    unichar surrogates[2];
    OFCharacterToSurrogatePair(0x1D15F, surrogates);
    NSString *source = [[NSString alloc] initWithCharacters:surrogates length:2];

    NSString *ascii = OFXMLCreateStringWithEntityReferencesInCFEncoding(source, OFXMLBasicEntityMask, nil, kCFStringEncodingASCII);
    XCTAssertEqualObjects(ascii, @"&#119135;"); // Here the character must be quoted, and should come out as a single entity (not as a surrogate pair).

    NSString *utf8 = OFXMLCreateStringWithEntityReferencesInCFEncoding(source, OFXMLBasicEntityMask, nil, kCFStringEncodingUTF8);
    XCTAssertEqualObjects(utf8, source); // Here the character is representable and shouldn't get quoted
}

//
// Test specifically invalid characters
//

static unichar InvalidCharacter = 0xFFFF;

// These two tests do not pass since CFStringGetBytes will happily encode a specifically invalid character (though not mismatched surrogate pairs). We could update OFXMLBufferAppendString() to do an extra character set check, but the intention is that we should go through the encoding path which will strip these. Tests left here in case we find cases where users are getting invalid characters in documents.
#if 0
- (void)testAppendInvalid;
{
    NSString *source = [[NSString alloc] initWithCharacters:&InvalidCharacter length:1];

    OFXMLBuffer buffer = OFXMLBufferCreate();

    OFXMLBufferAppendString(buffer, (__bridge CFStringRef)source);

    NSString *output = (__bridge NSString *)OFXMLBufferCopyString(buffer);
    XCTAssertEqualObjects(output, @""); // Should drop the invalid character
}

- (void)testAppendInvalidInMiddle;
{
    unichar characters[3] = {'a', InvalidCharacter, 'b'};
    NSString *source = [[NSString alloc] initWithCharacters:characters length:3];

    OFXMLBuffer buffer = OFXMLBufferCreate();

    OFXMLBufferAppendString(buffer, (__bridge CFStringRef)source);

    NSString *output = (__bridge NSString *)OFXMLBufferCopyString(buffer);
    XCTAssertEqualObjects(output, @"ab"); // Should drop the invalid character
}
#endif

- (void)testEncodeInvalid;
{
    NSString *source = [[NSString alloc] initWithCharacters:&InvalidCharacter length:1];

    NSString *output = OFXMLCreateStringWithEntityReferencesInCFEncoding(source, OFXMLBasicEntityMask, nil, kCFStringEncodingUTF8);
    XCTAssertEqualObjects(output, @""); // Should drop the invalid character
}

- (void)testEncodeInvalidInMiddle;
{
    unichar characters[3] = {'a', InvalidCharacter, 'b'};
    NSString *source = [[NSString alloc] initWithCharacters:characters length:3];

    NSString *output = OFXMLCreateStringWithEntityReferencesInCFEncoding(source, OFXMLBasicEntityMask, nil, kCFStringEncodingUTF8);
    XCTAssertEqualObjects(output, @"ab"); // Should drop the invalid character
}

@end
