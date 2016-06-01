// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/OFStringDecoder.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

typedef NSString *(^OFStringTestEncodeBlock)(NSData *original);
typedef NSData *(^OFStringTestDecodeBlock)(NSString *encoded, NSError **outError);

@interface OFStringEncodingTests : OFTestCase
{
    OFStringTestEncodeBlock encodeBlock;
    OFStringTestDecodeBlock decodeBlock;

    NSArray *zeroEncodings;
    NSArray *allOnesEncodings;
    NSArray *lsbOnesEncodings;
    NSArray *msbOnesEncodings;
    NSArray *countingNybblesEncodings;
}

@end

@interface OFQuotedPrintableTests : OFTestCase
@end

@implementation OFStringEncodingTests

- (void)testRepeatedBytes:(unsigned char)byte results:(NSArray *)results
{
    NSUInteger maxLength = [results count];
    NSUInteger thisLength;

    for(thisLength = 0; thisLength < maxLength; thisLength ++) {
        NSMutableData *mutable = [[NSMutableData alloc] initWithLength:thisLength];
        if (thisLength > 0)
            memset([mutable mutableBytes], (int)byte, thisLength);
        NSString *encoded = encodeBlock(mutable);
        XCTAssertEqualObjects(encoded, [results objectAtIndex:thisLength], @"%ld-byte-long buffer containing 0x%02x", thisLength, byte);
        
        NSError *error = nil;
        NSData *immutable;
        OBShouldNotError((immutable = decodeBlock(encoded, &error)));

        XCTAssertEqualObjects(mutable, immutable, @"%ld-byte-long buffer containing 0x%02x", thisLength, byte);
    }
}

- (void)testRepeatedbytes
{
    [self testRepeatedBytes:0 results:zeroEncodings];
    [self testRepeatedBytes:~0 results:allOnesEncodings];
    [self testRepeatedBytes:1 results:lsbOnesEncodings];
    [self testRepeatedBytes:0x80 results:msbOnesEncodings];
}

- (void)testCountingNybbles
{
    NSUInteger maxLength = [countingNybblesEncodings count];

    for (NSUInteger thisLength = 0; thisLength < maxLength; thisLength ++) {
        NSMutableData *mutable = [[NSMutableData alloc] initWithLength:thisLength];
        for(NSUInteger thisByte = 0; thisByte < thisLength; thisByte ++) {
            unsigned char ch, *ptr;

            ch =  (( ( 2*thisByte + 1 ) % 16 ) << 4)  |  ( ( 2*thisByte + 2 ) % 16 );
            ptr = [mutable mutableBytes];
            ptr[thisByte] = ch;
        }
        NSString *encoded = encodeBlock(mutable);
        XCTAssertEqualObjects(encoded, [countingNybblesEncodings objectAtIndex:thisLength]);

        NSError *error = nil;
        NSData *immutable;
        OBShouldNotError((immutable = decodeBlock(encoded, &error)));
        
        XCTAssertEqualObjects(mutable, immutable);
    }
}

- (void)testRandomStrings
{
    for (int trial = 0; trial < 1000; trial ++) {
        NSData *randomness = [NSData randomDataOfLength:(OFRandomNext32() % 1050)];
        XCTAssertTrue(randomness != nil);
        
        NSString *encoded = encodeBlock(randomness);
        XCTAssertTrue(encoded != nil);
        
        NSData *decoded = decodeBlock(encoded, NULL);
        XCTAssertEqualObjects(randomness, decoded);
    }
}

- (void)testKnownStrings:(NSDictionary *)cases
{
    BOOL reversible = [[cases objectForKey:@"reversible"] intValue];

    for (NSString *expected in cases) {
        if ([expected isEqual:@"reversible"])
            continue;
            
        NSData *testValue = [cases objectForKey:expected];
        NSString *encoded = nil;
        if (reversible) {
            encoded = encodeBlock(testValue);
            XCTAssertEqualObjects(encoded, expected);
        }
        
        NSData *decoded = decodeBlock(expected, NULL);
        XCTAssertEqualObjects(decoded, testValue);
    }
}

+ (XCTest *)testsForPatternNamed:(NSString *)patternName encode:(OFStringTestEncodeBlock)encodeBlock decode:(OFStringTestDecodeBlock)decodeBlock inf:(NSDictionary *)d
{
    NSArray *inf = [[d objectForKey:@"patternTests"] objectForKey:patternName];
    if ([inf count] != 5) {
        [NSException raise:NSGenericException format:@"+[%@ %@]: patternTests item does not contain the expected number of values", self, NSStringFromSelector(_cmd)];
    }

    encodeBlock = [encodeBlock copy];
    decodeBlock = [decodeBlock copy];
    
    NSArray *invocations = [self testInvocations];
    XCTestSuite *suite = [XCTestSuite testSuiteWithName:patternName];
    for (NSInvocation *invocation in invocations) {
        OFStringEncodingTests *acase = [self testCaseWithInvocation:invocation];
        acase->encodeBlock = encodeBlock;
        acase->decodeBlock = decodeBlock;
        acase->zeroEncodings = [inf objectAtIndex:0];
        acase->allOnesEncodings = [inf objectAtIndex:1];
        acase->lsbOnesEncodings = [inf objectAtIndex:2];
        acase->msbOnesEncodings = [inf objectAtIndex:3];
        acase->countingNybblesEncodings = [inf objectAtIndex:4];
        [suite addTest:acase];
    }

    __unsafe_unretained NSDictionary *vecs = [[d objectForKey:@"knownStrings"] objectForKey:patternName];
    if (vecs) {
        OFStringEncodingTests *acase;
        NSInvocation *call;

        call = [NSInvocation invocationWithMethodSignature:[self instanceMethodSignatureForSelector:@selector(testKnownStrings:)]];
        [call setSelector:@selector(testKnownStrings:)];
        [call setArgument:&vecs atIndex:2];
        [call retainArguments];
        acase = [self testCaseWithInvocation:call];
        acase->encodeBlock = encodeBlock;
        acase->decodeBlock = decodeBlock;
        [suite addTest:acase];
    }

    return suite;
}

+ (XCTestSuite *)defaultTestSuite;
{
    NSDictionary *knownResults;
    XCTestSuite *suite;

    @autoreleasepool {

        knownResults = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle bundleForClass:self] pathForResource:[self description] ofType:@"plist"]];
        suite = [XCTestSuite testSuiteWithName:[self description]];

        // Our wrappers are marked deprecated, but until they are gone, we'll test them.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [suite addTest:[self testsForPatternNamed:@"base64String"
                                           encode:^NSString *(NSData *original){ return [original base64String]; }
                                           decode:^NSData *(NSString *encoded, NSError **outError) {
                                               return [[NSData alloc] initWithBase64String:encoded];
                                           } inf:knownResults]];
#pragma clang diagnostic pop

        [suite addTest:[self testsForPatternNamed:@"ascii85String"
                                           encode:^NSString *(NSData *original){ return [original ascii85String]; }
                                           decode:^NSData *(NSString *encoded, NSError **outError) {
                                               return [[NSData alloc] initWithASCII85String:encoded];
                                           } inf:knownResults]];
        
        [suite addTest:[self testsForPatternNamed:@"unadornedLowercaseHexString"
                                           encode:^NSString *(NSData *original){ return [original unadornedLowercaseHexString]; }
                                           decode:^NSData *(NSString *encoded, NSError **outError) {
                                               return [[NSData alloc] initWithHexString:encoded error:outError];
                                           } inf:knownResults]];
        
        [suite addTest:[self testsForPatternNamed:@"ascii26String"
                                           encode:^NSString *(NSData *original){ return [original ascii26String]; }
                                           decode:^NSData *(NSString *encoded, NSError **outError) {
                                               return [[NSData alloc] initWithASCII26String:encoded];
                                           } inf:knownResults]];
    }
    return suite;
}

@end

@implementation OFQuotedPrintableTests

- (void)testURLDecoding
{
    XCTAssertEqualObjects([NSString decodeURLString:@"foo%20bar"], @"foo bar");
    XCTAssertEqualObjects([NSString decodeURLString:@"foo%%20r"], @"foo% r");
    XCTAssertEqualObjects([NSString decodeURLString:@"foo%%bor"], @"foo%%bor");
    XCTAssertEqualObjects([NSString decodeURLString:@"foo%2Obar"], @"foo%2Obar"); // comes out foo8bar, which is also wrong, maybe foo%2Obar? ryan
    XCTAssertEqualObjects([NSString decodeURLString:@"foo%2%2A"], @"foo%2*");
    XCTAssertEqualObjects([NSString decodeURLString:@"%77"], @"w");
    XCTAssertEqualObjects([NSString decodeURLString:@"%7"], @"%7");
    XCTAssertEqualObjects([NSString decodeURLString:@"%%"], @"%%");
    XCTAssertEqualObjects([NSString decodeURLString:@"%"], @"%");
    XCTAssertEqualObjects([NSString decodeURLString:@""], @"");
}

- (NSArray *)charactersOfString:(NSString *)str
{
    NSMutableArray *a = [[NSMutableArray alloc] initWithCapacity:[str length]];
    unsigned chindex;
    
    for(chindex = 0; chindex < [str length]; chindex ++) {
        [a addObject:[NSNumber numberWithUnsignedInt:[str characterAtIndex:chindex]]];
    }
    
    NSArray *retval = [a copy];
    return retval;
}

- (void)testURLDecodingIURI
{
    NSString *it_s, *lala;
    NSString *decoded;
    
    it_s = [NSString stringWithStrings:
        @"it",
        [NSString stringWithCharacter:0x2019],
        @"s",
        nil];
    NSArray *it_sCharsDesired = [NSArray arrayWithObjects:
        [NSNumber numberWithInt:'i'],
        [NSNumber numberWithInt:'t'],
        [NSNumber numberWithInt:0x2019],    // Non-ASCII character (RIGHT SINGLE QUOTATION MARK)
                                            // Note that you shouldn't use a quotation mark as an apostrophe, but lots of people do.
        [NSNumber numberWithInt:'s'],
        nil];
    
    lala = [NSString stringWithStrings:
        @"la",
        [NSString stringWithCharacter:0x1D15F],  // Non-BMP character (MUSICAL SYMBOL QUARTER NOTE)
        @"la",
        nil];
    /* We put in a non-BMP character, which NSString represents as a surrogate pair because its internal representation is UTF-16. */
    unichar surrogates[2];
    OFCharacterToSurrogatePair(0x1D15F, surrogates);
    NSArray *lalaCharsDesired = [NSArray arrayWithObjects:
        [NSNumber numberWithInt:'l'],
        [NSNumber numberWithInt:'a'],
        [NSNumber numberWithInt:surrogates[0]],
        [NSNumber numberWithInt:surrogates[1]],
        [NSNumber numberWithInt:'l'],
        [NSNumber numberWithInt:'a'],
        nil];
    

    decoded = [NSString decodeURLString:@"it%E2%80%99%73"];
    XCTAssertEqualObjects(decoded, it_s);
    XCTAssertEqualObjects([it_s fullyEncodeAsIURI], @"it%E2%80%99s");
    NSArray *it_sCharsDecoded = [self charactersOfString:decoded];
    XCTAssertEqualObjects(it_sCharsDecoded, it_sCharsDesired);
    XCTAssertEqualObjects([NSString decodeURLString:it_s], it_s);

    decoded = [NSString decodeURLString:@"%6ca%f0%9d%85%9fl%61"];
    XCTAssertEqualObjects(decoded, lala);
    XCTAssertEqualObjects([lala fullyEncodeAsIURI], @"la%F0%9D%85%9Fla");
    XCTAssertEqualObjects([decoded fullyEncodeAsIURI], @"la%F0%9D%85%9Fla");
    NSArray *lalaCharsDecoded = [self charactersOfString:decoded];
    XCTAssertEqualObjects(lalaCharsDecoded, lalaCharsDesired);
    XCTAssertEqualObjects([NSString decodeURLString:lala], lala);
}

static NSString *fooXbar(unsigned xchar)
{
    return [NSString stringWithStrings:@"foo", [NSString stringWithCharacter:xchar], @"bar", nil];
}

- (void)testRFC822Word
{
    XCTAssertEqualObjects([@"hello" asRFC822Word], @"hello");
    XCTAssertEqualObjects([@"hello there" asRFC822Word], @"\"hello there\"");
    XCTAssertEqualObjects([@"*" asRFC822Word], @"*");
    XCTAssertEqualObjects([@"hello.there" asRFC822Word], @"\"hello.there\"");
    XCTAssertEqualObjects([@"hello \\ th\"e\"re" asRFC822Word], @"\"hello \\\\ th\\\"e\\\"re\"");
    XCTAssertEqualObjects([@"[127.0.0.1]" asRFC822Word], @"\"[127.0.0.1]\"");
    XCTAssertEqualObjects([@"127" asRFC822Word], @"127");
    XCTAssertEqualObjects([@"=?127?Q?001?=" asRFC822Word], @"\"=?127?Q?001?=\"");
    XCTAssertEqualObjects([@"?=127?Q?001=?" asRFC822Word], @"?=127?Q?001=?");
    XCTAssertNil([@"foo\nbar" asRFC822Word]);
    XCTAssertNil([fooXbar(161) asRFC822Word]);
}

- (void)testRFC2047EncodedWord
{
    NSString *s;
    
    XCTAssertEqualObjects([@"hello" asRFC2047EncodedWord], @"=?iso-8859-1?Q?hello?=");
    XCTAssertEqualObjects([@"hello there" asRFC2047EncodedWord], @"=?iso-8859-1?Q?hello_there?=");
    XCTAssertEqualObjects([@"*" asRFC2047EncodedWord], @"=?iso-8859-1?Q?*?=");
    XCTAssertEqualObjects([@"hello \\ th\"e\"re" asRFC2047EncodedWord], @"=?iso-8859-1?B?aGVsbG8gXCB0aCJlInJl?=");
    XCTAssertEqualObjects([@"foo\nbar" asRFC2047EncodedWord], @"=?iso-8859-1?Q?foo=0Abar?=");
    XCTAssertEqualObjects([fooXbar(161) asRFC2047EncodedWord], @"=?iso-8859-1?Q?foo=A1bar?=");    // Unicode/Latin-1 0xA1, inverted exclamation point
    XCTAssertEqualObjects([fooXbar(0xFE) asRFC2047EncodedWord], @"=?iso-8859-1?Q?foo=FEbar?=");   // Unicode/Latin-1 0xFE, lowercase thorn
    XCTAssertEqualObjects([fooXbar(1065) asRFC2047EncodedWord], @"=?iso-8859-5?Q?foo=C9bar?=");   // Unicode U0429, Latin-5(Cyrillic) 0xC9, capital shcha
    XCTAssertEqualObjects([fooXbar(0x2026) asRFC2047EncodedWord], @"=?macintosh?Q?foo=C9bar?="); // Unicode U2026, MacRoman 0xC9, horizontal ellipsis
    s = [NSString stringWithStrings:@"Foo... ", [NSString stringWithCharacter:0x444], @" or ",
        [NSString stringWithCharacter:0x3C6], @" which is which?", nil];
    XCTAssertEqualObjects([s asRFC2047EncodedWord], @"=?utf-8?B?Rm9vLi4uINGEIG9yIM+GIHdoaWNoIGlzIHdoaWNoPw==?=");   // Cyrillic small ef (U0444) and Greek small phi (U03C6) in the same string; forces a Unicode format instead of a national charset
    XCTAssertEqualObjects([fooXbar(66368) asRFC2047EncodedWord], @"=?utf-8?B?Zm9v8JCNgGJhcg==?=");  // Unicode U10340, Gothic letter Pairtha (supplementary plane 1); tests UTF8 encoding of non-BMP code points
    XCTAssertEqualObjects([[fooXbar(66368) stringByAppendingString:@" plus some extra text"] asRFC2047EncodedWord],
                  @"=?utf-8?Q?foo=F0=90=8D=80bar_plus_some_extra_text?=");  // same letter, different optimal encoding for the string
    s = [NSString stringWithCharacter:0xFE4C];
    s = [NSString stringWithStrings:s, s, s, s, nil];
#ifdef __LITTLE_ENDIAN__
    XCTAssertEqualObjects([s asRFC2047EncodedWord], @"=?utf-16le?B?TP5M/kz+TP4=?=");
#else
    XCTAssertEqualObjects([s asRFC2047EncodedWord], @"=?utf-16be?B?/kz+TP5M/kw=?=");
#endif
    // Another valid encoding for the above is '=?UTF-16?B?/v/+TP5M/kz+TA==?='.
    // However, rather than have the BOM in the encoding, I think it's better to use the byte-order-specific encoding name; it's slightly shorter, and avoids possible bugs in BOM-ignorant software.
    // So instead we expect '=?UTF-16BE?B?/kz+TP5M/kw=?='  (no BOM).
    // Also note that on little-endian machines we might get '=?UTF-16LE?B?TP5M/kz+TP4=?=' (or the BOMmed equivalent) which is perfectly acceptable.
    XCTAssertEqualObjects([@"Hello, _ Wor=ld!" asRFC2047EncodedWord], @"=?iso-8859-1?Q?Hello=2C_=5F_Wor=3Dld!?=");
}

- (void)testRFC2047Phrase
{
    XCTAssertEqualObjects([@"hello" asRFC2047Phrase], @"hello");
    XCTAssertEqualObjects([@"hello there" asRFC2047Phrase], @"hello there");
    XCTAssertEqualObjects([@"*" asRFC2047Phrase], @"*");
    XCTAssertEqualObjects([@"hello_there" asRFC2047Phrase], @"hello_there");
    XCTAssertEqualObjects([@"hello \\ th\"e\"re" asRFC2047Phrase], @"\"hello \\\\ th\\\"e\\\"re\"");
    XCTAssertEqualObjects([@"[127.0.0.1]" asRFC2047Phrase], @"\"[127.0.0.1]\"");
    XCTAssertEqualObjects([@"127" asRFC2047Phrase], @"127");
    XCTAssertEqualObjects([@"=?127?Q?001?=" asRFC2047Phrase], @"\"=?127?Q?001?=\"");
    XCTAssertEqualObjects([fooXbar(161) asRFC2047Phrase], @"=?iso-8859-1?Q?foo=A1bar?=");
    XCTAssertEqualObjects([@"This or that, one or the other" asRFC2047Phrase], @"\"This or that, one or the other\"");
}

@end
