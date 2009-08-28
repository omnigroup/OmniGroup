// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/OFStringDecoder.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");


@interface OFStringEncodingTests : OFTestCase
{
    SEL encodeSelector;
    SEL decodeSelector;

    NSArray *zeroEncodings;
    NSArray *allOnesEncodings;
    NSArray *lsbOnesEncodings;
    NSArray *msbOnesEncodings;
    NSArray *countingNybblesEncodings;
}

@end

@interface OFQuotedPrintableTests : OFTestCase
{
}

@end

@implementation OFStringEncodingTests

- (void)testRepeatedBytes:(unsigned char)byte results:(NSArray *)results
{
    int maxLength = [results count] - 1;
    int thisLength;

    for(thisLength = 0; thisLength <= maxLength; thisLength ++) {
        NSMutableData *mutable = [[[NSMutableData alloc] initWithLength:thisLength] autorelease];
        if (thisLength > 0)
            memset([mutable mutableBytes], (int)byte, thisLength);
        NSString *encoded = [mutable performSelector:encodeSelector];
        shouldBeEqual1(encoded, [results objectAtIndex:thisLength], ([NSString stringWithFormat:@"%d-byte-long buffer containing 0x%02x", thisLength, byte]));
        
        NSError *error = nil;
        NSData *immutable = [objc_msgSend(objc_msgSend([NSData class], @selector(alloc)), decodeSelector, encoded, &error) autorelease];
        OBShouldNotError(immutable != nil);

        shouldBeEqual1(mutable, immutable, ([NSString stringWithFormat:@"%d-byte-long buffer containing 0x%02x", thisLength, byte]));
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
    int maxLength = [countingNybblesEncodings count] - 1;
    int thisLength, thisByte;

    for(thisLength = 0; thisLength <= maxLength; thisLength ++) {
        NSMutableData *mutable;
        NSData *immutable;
        NSString *encoded;

        mutable = [[NSMutableData alloc] initWithLength:thisLength];
        for(thisByte = 0; thisByte < thisLength; thisByte ++) {
            unsigned char ch, *ptr;

            ch =  (( ( 2*thisByte + 1 ) % 16 ) << 4)  |  ( ( 2*thisByte + 2 ) % 16 );
            ptr = [mutable mutableBytes];
            ptr[thisByte] = ch;
        }
        encoded = [mutable performSelector:encodeSelector];
        shouldBeEqual(encoded, [countingNybblesEncodings objectAtIndex:thisLength]);

        NSError *error = nil;
        immutable = objc_msgSend(objc_msgSend([NSData class], @selector(alloc)), decodeSelector, encoded, &error);
        OBShouldNotError(immutable != nil);
        
        shouldBeEqual(mutable, immutable);
        [mutable release];
        [immutable release];
    }
}

- (void)testRandomStrings
{
    int trial;

    for(trial = 0; trial < 1000; trial ++) {
        NSData *randomness = [NSData randomDataOfLength:(OFRandomNext() % 1050)];
        NSString *encoded;
        NSData *decoded;
        
        should(randomness != nil);
        encoded = [randomness performSelector:encodeSelector];
        should(encoded != nil);
        decoded = [objc_msgSend([NSData class], @selector(alloc)) performSelector:decodeSelector withObject:encoded];
        shouldBeEqual(randomness, decoded);
        [decoded release];
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
            encoded = [testValue performSelector:encodeSelector];
            shouldBeEqual(encoded, expected);
        }
        
        NSData *decoded = [[objc_msgSend([NSData class], @selector(alloc)) performSelector:decodeSelector withObject:expected] autorelease];
        shouldBeEqual(decoded, testValue);
    }
}

+ (SenTest *)testsForEncode:(SEL)encSel decode:(SEL)decSel inf:(NSDictionary *)d
{
    NSArray *invocations;
    SenTestSuite *suite;
    NSArray *inf;
    NSDictionary *vecs;
    unsigned int invIx;

    inf = [[d objectForKey:@"patternTests"] objectForKey:NSStringFromSelector(encSel)];
    if ([inf count] != 5) {
        [NSException raise:NSGenericException format:@"+[%@ %@]: patternTests item does not contain the expected number of values", self, NSStringFromSelector(_cmd)];
    }

    invocations = [self testInvocations];
    suite = [SenTestSuite testSuiteWithName:NSStringFromSelector(encSel)];
    for(invIx = 0; invIx < [invocations count]; invIx ++) {
        OFStringEncodingTests *acase = [self testCaseWithInvocation:[invocations objectAtIndex:invIx]];
        acase->encodeSelector = encSel;
        acase->decodeSelector = decSel;
        acase->zeroEncodings = [[inf objectAtIndex:0] retain];
        acase->allOnesEncodings = [[inf objectAtIndex:1] retain];
        acase->lsbOnesEncodings = [[inf objectAtIndex:2] retain];
        acase->msbOnesEncodings = [[inf objectAtIndex:3] retain];
        acase->countingNybblesEncodings = [[inf objectAtIndex:4] retain];
        [suite addTest:acase];
    }

    vecs = [[d objectForKey:@"knownStrings"] objectForKey:NSStringFromSelector(encSel)];
    if (vecs) {
        OFStringEncodingTests *acase;
        NSInvocation *call;

        call = [NSInvocation invocationWithMethodSignature:[self instanceMethodSignatureForSelector:@selector(testKnownStrings:)]];
        [call setSelector:@selector(testKnownStrings:)];
        [call setArgument:&vecs atIndex:2];
        [call retainArguments];
        acase = [self testCaseWithInvocation:call];
        acase->encodeSelector = encSel;
        acase->decodeSelector = decSel;
        [suite addTest:acase];
    }

    return suite;
}

+ (id) defaultTestSuite
{
    NSDictionary *knownResults;
    SenTestSuite *suite;
    NSAutoreleasePool *pool;

    pool = [[NSAutoreleasePool alloc] init];

    knownResults = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle bundleForClass:self] pathForResource:[self description] ofType:@"plist"]];
    suite = [SenTestSuite testSuiteWithName:[self description]];
    [suite addTest: [self testsForEncode:@selector(base64String) decode:@selector(initWithBase64String:) inf:knownResults]];
    [suite addTest: [self testsForEncode:@selector(ascii85String) decode:@selector(initWithASCII85String:) inf:knownResults]];
    [suite addTest: [self testsForEncode:@selector(unadornedLowercaseHexString) decode:@selector(initWithHexString:error:) inf:knownResults]];
    [suite addTest: [self testsForEncode:@selector(ascii26String) decode:@selector(initWithASCII26String:) inf:knownResults]];

    [suite retain];
    [pool release];
    return [suite autorelease];
}

@end

@implementation OFQuotedPrintableTests

- (void)testURLDecoding
{
    shouldBeEqual([NSString decodeURLString:@"foo%20bar"], @"foo bar");
    shouldBeEqual([NSString decodeURLString:@"foo%%20r"], @"foo% r");
    shouldBeEqual([NSString decodeURLString:@"foo%%bor"], @"foo%%bor");
    shouldBeEqual([NSString decodeURLString:@"foo%2Obar"], @"foo%2Obar"); // comes out foo8bar, which is also wrong, maybe foo%2Obar? ryan
    shouldBeEqual([NSString decodeURLString:@"foo%2%2A"], @"foo%2*");
    shouldBeEqual([NSString decodeURLString:@"%77"], @"w");
    shouldBeEqual([NSString decodeURLString:@"%7"], @"%7");
    shouldBeEqual([NSString decodeURLString:@"%%"], @"%%");
    shouldBeEqual([NSString decodeURLString:@"%"], @"%");
    shouldBeEqual([NSString decodeURLString:@""], @"");
}

- (NSArray *)charactersOfString:(NSString *)str
{
    NSMutableArray *a = [[NSMutableArray alloc] initWithCapacity:[str length]];
    unsigned chindex;
    
    for(chindex = 0; chindex < [str length]; chindex ++) {
        [a addObject:[NSNumber numberWithUnsignedInt:[str characterAtIndex:chindex]]];
    }
    
    NSArray *retval = [a copy];
    [a release];
    [retval autorelease];
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
    shouldBeEqual(decoded, it_s);
    shouldBeEqual([it_s fullyEncodeAsIURI], @"it%E2%80%99s");
    NSArray *it_sCharsDecoded = [self charactersOfString:decoded];
    shouldBeEqual(it_sCharsDecoded, it_sCharsDesired);
    shouldBeEqual([NSString decodeURLString:it_s], it_s);

    decoded = [NSString decodeURLString:@"%6ca%f0%9d%85%9fl%61"];
    shouldBeEqual(decoded, lala);
    shouldBeEqual([lala fullyEncodeAsIURI], @"la%F0%9D%85%9Fla");
    shouldBeEqual([decoded fullyEncodeAsIURI], @"la%F0%9D%85%9Fla");
    NSArray *lalaCharsDecoded = [self charactersOfString:decoded];
    shouldBeEqual(lalaCharsDecoded, lalaCharsDesired);
    shouldBeEqual([NSString decodeURLString:lala], lala);
}

static NSString *fooXbar(unsigned xchar)
{
    return [NSString stringWithStrings:@"foo", [NSString stringWithCharacter:xchar], @"bar", nil];
}

- (void)testRFC822Word
{
    shouldBeEqual([@"hello" asRFC822Word], @"hello");
    shouldBeEqual([@"hello there" asRFC822Word], @"\"hello there\"");
    shouldBeEqual([@"*" asRFC822Word], @"*");
    shouldBeEqual([@"hello.there" asRFC822Word], @"\"hello.there\"");
    shouldBeEqual([@"hello \\ th\"e\"re" asRFC822Word], @"\"hello \\\\ th\\\"e\\\"re\"");
    shouldBeEqual([@"[127.0.0.1]" asRFC822Word], @"\"[127.0.0.1]\"");
    shouldBeEqual([@"127" asRFC822Word], @"127");
    shouldBeEqual([@"=?127?Q?001?=" asRFC822Word], @"\"=?127?Q?001?=\"");
    shouldBeEqual([@"?=127?Q?001=?" asRFC822Word], @"?=127?Q?001=?");
    shouldBeEqual([@"foo\nbar" asRFC822Word], nil);
    shouldBeEqual([fooXbar(161) asRFC822Word], nil);
}

- (void)testRFC2047EncodedWord
{
    NSString *s;
    
    shouldBeEqual([@"hello" asRFC2047EncodedWord], @"=?iso-8859-1?Q?hello?=");
    shouldBeEqual([@"hello there" asRFC2047EncodedWord], @"=?iso-8859-1?Q?hello_there?=");
    shouldBeEqual([@"*" asRFC2047EncodedWord], @"=?iso-8859-1?Q?*?=");
    shouldBeEqual([@"hello \\ th\"e\"re" asRFC2047EncodedWord], @"=?iso-8859-1?B?aGVsbG8gXCB0aCJlInJl?=");
    shouldBeEqual([@"foo\nbar" asRFC2047EncodedWord], @"=?iso-8859-1?Q?foo=0Abar?=");
    shouldBeEqual([fooXbar(161) asRFC2047EncodedWord], @"=?iso-8859-1?Q?foo=A1bar?=");    // Unicode/Latin-1 0xA1, inverted exclamation point
    shouldBeEqual([fooXbar(0xFE) asRFC2047EncodedWord], @"=?iso-8859-1?Q?foo=FEbar?=");   // Unicode/Latin-1 0xFE, lowercase thorn
    shouldBeEqual([fooXbar(1065) asRFC2047EncodedWord], @"=?iso-8859-5?Q?foo=C9bar?=");   // Unicode U0429, Latin-5(Cyrillic) 0xC9, capital shcha
    shouldBeEqual([fooXbar(0x2026) asRFC2047EncodedWord], @"=?macintosh?Q?foo=C9bar?="); // Unicode U2026, MacRoman 0xC9, horizontal ellipsis
    s = [NSString stringWithStrings:@"Foo... ", [NSString stringWithCharacter:0x444], @" or ",
        [NSString stringWithCharacter:0x3C6], @" which is which?", nil];
    shouldBeEqual([s asRFC2047EncodedWord], @"=?utf-8?B?Rm9vLi4uINGEIG9yIM+GIHdoaWNoIGlzIHdoaWNoPw==?=");   // Cyrillic small ef (U0444) and Greek small phi (U03C6) in the same string; forces a Unicode format instead of a national charset
    shouldBeEqual([fooXbar(66368) asRFC2047EncodedWord], @"=?utf-8?B?Zm9v8JCNgGJhcg==?=");  // Unicode U10340, Gothic letter Pairtha (supplementary plane 1); tests UTF8 encoding of non-BMP code points
    shouldBeEqual([[fooXbar(66368) stringByAppendingString:@" plus some extra text"] asRFC2047EncodedWord],
                  @"=?utf-8?Q?foo=F0=90=8D=80bar_plus_some_extra_text?=");  // same letter, different optimal encoding for the string
    s = [NSString stringWithCharacter:0xFE4C];
    s = [NSString stringWithStrings:s, s, s, s, nil];
#ifdef __LITTLE_ENDIAN__
    shouldBeEqual([s asRFC2047EncodedWord], @"=?utf-16le?B?TP5M/kz+TP4=?=");
#else
    shouldBeEqual([s asRFC2047EncodedWord], @"=?utf-16be?B?/kz+TP5M/kw=?=");
#endif
    // Another valid encoding for the above is '=?UTF-16?B?/v/+TP5M/kz+TA==?='.
    // However, rather than have the BOM in the encoding, I think it's better to use the byte-order-specific encoding name; it's slightly shorter, and avoids possible bugs in BOM-ignorant software.
    // So instead we expect '=?UTF-16BE?B?/kz+TP5M/kw=?='  (no BOM).
    // Also note that on little-endian machines we might get '=?UTF-16LE?B?TP5M/kz+TP4=?=' (or the BOMmed equivalent) which is perfectly acceptable.
    shouldBeEqual([@"Hello, _ Wor=ld!" asRFC2047EncodedWord], @"=?iso-8859-1?Q?Hello=2C_=5F_Wor=3Dld!?=");
}

- (void)testRFC2047Phrase
{
    shouldBeEqual([@"hello" asRFC2047Phrase], @"hello");
    shouldBeEqual([@"hello there" asRFC2047Phrase], @"hello there");
    shouldBeEqual([@"*" asRFC2047Phrase], @"*");
    shouldBeEqual([@"hello_there" asRFC2047Phrase], @"hello_there");
    shouldBeEqual([@"hello \\ th\"e\"re" asRFC2047Phrase], @"\"hello \\\\ th\\\"e\\\"re\"");
    shouldBeEqual([@"[127.0.0.1]" asRFC2047Phrase], @"\"[127.0.0.1]\"");
    shouldBeEqual([@"127" asRFC2047Phrase], @"127");
    shouldBeEqual([@"=?127?Q?001?=" asRFC2047Phrase], @"\"=?127?Q?001?=\"");
    shouldBeEqual([fooXbar(161) asRFC2047Phrase], @"=?iso-8859-1?Q?foo=A1bar?=");
    shouldBeEqual([@"This or that, one or the other" asRFC2047Phrase], @"\"This or that, one or the other\"");
}

@end
