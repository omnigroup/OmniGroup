// Copyright 2004-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniBase/system.h>
#import <OmniBase/OBUtilities.h>

// This, my friends, is a hack.
#undef OB_DEPRECATED_ATTRIBUTE
#define OB_DEPRECATED_ATTRIBUTE  /* empty */

#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/NSMutableString-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniFoundation/CFString-OFExtensions.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFStringExtensionTest : OFTestCase
@end

@implementation OFStringExtensionTest

- (void)testStringEncodingNames;
{
    const CFStringEncoding *allEncodings = CFStringGetListOfAvailableEncodings();
    CFIndex encodingIndex;
    
    for(encodingIndex = 0; allEncodings[encodingIndex] != kCFStringEncodingInvalidId; encodingIndex ++) {
        CFStringEncoding enc = allEncodings[encodingIndex];
	
        NSString *savable = [NSString defaultValueForCFStringEncoding:enc];
        CFStringEncoding roundTrip = [NSString cfStringEncodingForDefaultValue:savable];

        //  kCFStringEncodingShiftJIS_X0213_00 comes through the roundtrip as kCFStringEncodingShiftJIS which produces a spurious(?) failure
        if (enc == kCFStringEncodingShiftJIS_X0213_00 && roundTrip == kCFStringEncodingShiftJIS) {
            NSLog(@"Allowing ShiftJIS_X0213_00 to map to ShiftJIS (via \"%@\") w/o unit test failure.", savable);
            continue;
        }

        XCTAssertTrue(roundTrip == enc,
                      @"CFEncoding %lu encodes to \"%@\" decodes to %lu", (unsigned long)enc, savable, (unsigned long)roundTrip);
    }
    
    XCTAssertTrue([NSString cfStringEncodingForDefaultValue:@"iana iso-8859-1"] == kCFStringEncodingISOLatin1);
    XCTAssertTrue([NSString cfStringEncodingForDefaultValue:@"iana utf-8"] == kCFStringEncodingUTF8);
    XCTAssertTrue([NSString cfStringEncodingForDefaultValue:@"iana UTF-8"] == kCFStringEncodingUTF8);
}



- (void)testAbbreviatedStringForHz;
{
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:0], @"0 Hz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:1], @"1 Hz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:9], @"9 Hz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:10], @"10 Hz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:11], @"11 Hz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:100], @"100 Hz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:990], @"990 Hz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:999], @"1.0 KHz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:1000], @"1.0 KHz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:1099], @"1.1 KHz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:1100], @"1.1 KHz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:1000000], @"1.0 MHz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:10000000], @"10.0 MHz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:100000000], @"100.0 MHz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:1000000000], @"1.0 GHz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:1800000000], @"1.8 GHz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:2000000000], @"2.0 GHz");
    XCTAssertEqualObjects([NSString abbreviatedStringForHertz:10000000000LL], @"10.0 GHz");
}

- (void)testTrimming
{
    // Multi-codepoint characters.
    unichar cmark1[] = { 0x20, 0x20, 'e', 0x301, 0x20, 0x20 };
    unichar cmark2[] = { 0x20, 0x20, 'a', 0x300, 'e', 0x300, 0x20, 0x20 };
    unichar surr[] = { 0x20, 0x20, 0xD834, 0xDD5F, 0x20, 0x20 };
    unichar *s[3] = { cmark1, cmark2, surr };
    int sl[3] = { 6, 8, 6 };
    int i;

    XCTAssertEqualObjects([@"" stringByRemovingSurroundingWhitespace], @"");
    XCTAssertEqualObjects([@" " stringByRemovingSurroundingWhitespace], @"");
    XCTAssertEqualObjects([@"  " stringByRemovingSurroundingWhitespace], @"");
    XCTAssertEqualObjects([@"\t\n\r " stringByRemovingSurroundingWhitespace], @"");
    XCTAssertEqualObjects([@"foo " stringByRemovingSurroundingWhitespace], @"foo");
    XCTAssertEqualObjects([@"foo  " stringByRemovingSurroundingWhitespace], @"foo");
    XCTAssertEqualObjects([@"o " stringByRemovingSurroundingWhitespace], @"o");
    XCTAssertEqualObjects([@" f " stringByRemovingSurroundingWhitespace], @"f");
    XCTAssertEqualObjects([@" foo " stringByRemovingSurroundingWhitespace], @"foo");
    XCTAssertEqualObjects([@"  foo " stringByRemovingSurroundingWhitespace], @"foo");
    XCTAssertEqualObjects([@"foo" stringByRemovingSurroundingWhitespace], @"foo");
    XCTAssertEqualObjects([@"  foo" stringByRemovingSurroundingWhitespace], @"foo");
    
    for(i = 0; i < 3; i ++) {
        NSString *t = [NSString stringWithCharacters:2+s[i] length:sl[i]-4];
        XCTAssertEqualObjects([[NSString stringWithCharacters:s[i]   length:sl[i]  ] stringByRemovingSurroundingWhitespace], t);
        XCTAssertEqualObjects([[NSString stringWithCharacters:s[i]+2 length:sl[i]-2] stringByRemovingSurroundingWhitespace], t);
        XCTAssertEqualObjects([[NSString stringWithCharacters:s[i]   length:sl[i]-2] stringByRemovingSurroundingWhitespace], t);
        XCTAssertEqualObjects([[NSString stringWithCharacters:s[i]+2 length:sl[i]-4] stringByRemovingSurroundingWhitespace], t);
    }
    
    NSMutableString *buf = [[NSMutableString alloc] init];

    for(i = 0; i < 3; i ++) {
        NSString *t = [NSString stringWithCharacters:2+s[i] length:sl[i]-4];
        [buf setString:[NSString stringWithCharacters:s[i]   length:sl[i]  ]]; XCTAssertEqualObjects([buf stringByRemovingSurroundingWhitespace], t);
        [buf setString:[NSString stringWithCharacters:s[i]+2 length:sl[i]-2]]; XCTAssertEqualObjects([buf stringByRemovingSurroundingWhitespace], t);
        [buf setString:[NSString stringWithCharacters:s[i]   length:sl[i]-2]]; XCTAssertEqualObjects([buf stringByRemovingSurroundingWhitespace], t);
        [buf setString:[NSString stringWithCharacters:s[i]+2 length:sl[i]-4]]; XCTAssertEqualObjects([buf stringByRemovingSurroundingWhitespace], t);
    }
}

- (void)testDecimal:(double)d expecting:(NSString *)decimalized :(NSString *)exponential
{
    NSString *t0 = OFCreateDecimalStringFromDouble(d);
    NSString *t1, *t2;
    char *buf;
    
    buf = OFShortASCIIDecimalStringFromDouble(d, OF_FLT_DIGITS_E, NO, YES);
    t1 = CFBridgingRelease(CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, buf, kCFStringEncodingASCII, kCFAllocatorMalloc));
    
    buf = OFShortASCIIDecimalStringFromDouble(d, OF_FLT_DIGITS_E, YES, YES);
    t2 = CFBridgingRelease(CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, buf, kCFStringEncodingASCII, kCFAllocatorMalloc));
    
    XCTAssertEqualObjects(t0, decimalized);
    XCTAssertEqualObjects(t1, decimalized);
    if (exponential) {
        XCTAssertEqualObjects(t2, exponential);
    } else {
        XCTAssertEqualObjects(t2, decimalized);
    }
    
    
    if ([decimalized hasPrefix:@"0."]) {
        buf = OFShortASCIIDecimalStringFromDouble(d, OF_FLT_DIGITS_E, NO, NO);
        t1 = CFBridgingRelease(CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, buf, kCFStringEncodingASCII, kCFAllocatorMalloc));
        XCTAssertEqualObjects(t1, [decimalized substringFromIndex:1]);
    }
}

- (void)testDecimalFormatting
{
    /* There are a crazy number of different cases in formatting a decimal number. This covers them all, I think. */
    
    [self testDecimal:0 expecting:@"0" :nil];
    [self testDecimal:1 expecting:@"1" :nil];
    [self testDecimal:-1 expecting:@"-1" :nil];
    [self testDecimal:10 expecting:@"10" :nil];
    [self testDecimal:-10 expecting:@"-10" :nil];
    [self testDecimal:.1 expecting:@"0.1" :nil];
    [self testDecimal:-.1 expecting:@"-0.1" :nil];
    [self testDecimal:-.01 expecting:@"-0.01" :nil];
    
    [self testDecimal:1e30 expecting:@"1000000000000000000000000000000" :@"1e30"];
    [self testDecimal:1e40 expecting:@"10000000000000000000000000000000000000000" :@"1e40"];
    [self testDecimal:1e50 expecting:@"100000000000000000000000000000000000000000000000000" :@"1e50"];
    [self testDecimal:1e60 expecting:@"1000000000000000000000000000000000000000000000000000000000000" :@"1e60"];
    [self testDecimal:-1e30 expecting:@"-1000000000000000000000000000000" :@"-1e30"];
    [self testDecimal:-1e40 expecting:@"-10000000000000000000000000000000000000000" :@"-1e40"];
    [self testDecimal:-1e50 expecting:@"-100000000000000000000000000000000000000000000000000" :@"-1e50"];
    [self testDecimal:-1e60 expecting:@"-1000000000000000000000000000000000000000000000000000000000000" :@"-1e60"];
    
    [self testDecimal:7e-3 expecting:@"0.007" :@"7e-3"];
    [self testDecimal:-7e-3 expecting:@"-0.007" :@"-7e-3"];
    [self testDecimal:17e-3 expecting:@"0.017" :@"0.017"];
    [self testDecimal:-17e-3 expecting:@"-0.017" :@"-0.017"];
    [self testDecimal:1e-10 expecting:@"0.0000000001" :@"1e-10"];
    [self testDecimal:-1e-10 expecting:@"-0.0000000001" :@"-1e-10"];
    [self testDecimal:1e-20 expecting:@"0.00000000000000000001" :@"1e-20"];
    [self testDecimal:1e-30 expecting:@"0.000000000000000000000000000001" :@"1e-30"];
    [self testDecimal:1e-40 expecting:@"0.0000000000000000000000000000000000000001" :@"1e-40"];
    [self testDecimal:1e-50 expecting:@"0.00000000000000000000000000000000000000000000000001" :@"1e-50"];
    [self testDecimal:1e-60 expecting:@"0.000000000000000000000000000000000000000000000000000000000001" :@"1e-60"];
    [self testDecimal:-1e-60 expecting:@"-0.000000000000000000000000000000000000000000000000000000000001" :@"-1e-60"];
    
    [self testDecimal:1.000001 expecting:@"1.000001" :nil];
    [self testDecimal:-2.000002 expecting:@"-2.000002" :nil];
    
    [self testDecimal:1.000001e20 expecting:@"100000100000000000000" :@"1000001e14"];
    [self testDecimal:-2.000002e20 expecting:@"-200000200000000000000" :@"-2000002e14"];
    [self testDecimal:1.000001e-20 expecting:@"0.00000000000000000001000001" :@"1000001e-26"];
    [self testDecimal:-2.000002e-20 expecting:@"-0.00000000000000000002000002" :@"-2000002e-26"];
    
#define TESTIT(num, expok, force, expect) { char *buf = OFShortASCIIDecimalStringFromDouble(num, OF_FLT_DIGITS_E, expok, force); XCTAssertTrue(strcmp(buf, expect) == 0, "formatted %g (expok=%d forcelz=%d) got \"%s\" expected \"%s\"", num, expok, force, buf, expect); free(buf); }
        
    TESTIT(0.017,   1, 0, ".017");
    TESTIT(0.017,   1, 1, "0.017");
    TESTIT(0.0017,  1, 1, "17e-4");
    TESTIT(0.0017,  1, 0, ".0017");
    TESTIT(0.0017,  0, 1, "0.0017");
    TESTIT(0.00017, 1, 0, "17e-5");
    TESTIT(0.00017, 0, 0, ".00017");
    TESTIT(0.00017, 0, 1, "0.00017");
    
#undef TESTIT
}

- (void)testDecimalFormattingULP
{
    double binaryRoundtripDigitsBaseE = log(exp2(FLT_MANT_DIG)); // This tests whether OFShortASCIIDecimalStringFromDouble() will correctly roundtrip any binary representation of a float value to a decimal string and back. We used to use OF_FLT_DIGITS_E for this, but it has a different use case: our goal there is to roundtrip decimal strings to binary floats and back.
    float n;
    int i;
    
    for(n = 1.0f, i = 0;
        i < 1000;
        n = nextafterf(n, 100.0f), i++) {
        char *buf = OFShortASCIIDecimalStringFromDouble(n, binaryRoundtripDigitsBaseE, 0, 1);
        float n2 = -1;
        XCTAssertTrue(sscanf(buf, "%f", &n2) == 1 && (n == n2),
                      @"formatted %.10g got \"%s\" scanned %.10g", n, buf, n2);
        free(buf);
    }
    
    for(n = 1.0f, i = 0;
        i < 1000;
        n = nextafterf(n, -100.0f), i++) {
        char *buf = OFShortASCIIDecimalStringFromDouble(n, binaryRoundtripDigitsBaseE, 0, 1);
        float n2 = -1;
        XCTAssertTrue(sscanf(buf, "%f", &n2) == 1 && (n == n2),
                      @"formatted %.10g got \"%s\" scanned %.10g", n, buf, n2);
        free(buf);
    }
}

- (void)testComponentsSeparatedByCharactersFromSet
{
    NSCharacterSet *delimiterSet = [NSCharacterSet punctuationCharacterSet];
    NSCharacterSet *emptySet = [NSCharacterSet characterSetWithCharactersInString:@""];
    
    XCTAssertEqualObjects([@"Hi.there" componentsSeparatedByCharactersFromSet:delimiterSet], ([NSArray arrayWithObjects:@"Hi", @"there", nil]));
    XCTAssertEqualObjects([@"Hi.there" componentsSeparatedByCharactersFromSet:emptySet], ([NSArray arrayWithObject:@"Hi.there"]));
    XCTAssertEqualObjects([@".Hi.there!" componentsSeparatedByCharactersFromSet:delimiterSet], ([NSArray arrayWithObjects:@"", @"Hi", @"there", @"", nil]));
}

static NSString *simpleXMLEscape(NSString *str, NSRange *where, void *dummy)
{
    OBASSERT(where->length == 1);
    unichar ch = [str characterAtIndex:where->location];
    
    switch(ch) {
        case '&':
            return @"&amp;";
        case '<':
            return @"&lt;";
        case '>':
            return @"&gt;";
        case '"':
            return @"&quot;";
        default:
            return [NSString stringWithFormat:@"&#%u;", (unsigned int)ch];
    }
}

static NSString *unpair(NSString *str, NSRange *where, void *dummy)
{
    NSRange another;
    
    another.location = NSMaxRange(*where);
    another.length = where->length;
    
    if (NSMaxRange(another) <= [str length]) {
        NSString *p1 = [str substringWithRange:*where];
        NSString *p2 = [str substringWithRange:another];
        if ([p1 isEqualToString:p2]) {
            where->length = NSMaxRange(another) - where->location;
            return p1;
        }
    }
    
    return nil;
}

- (void)testGenericReplace
{
    NSString *t;
    NSCharacterSet *s = [NSCharacterSet characterSetWithCharactersInString:@"<&>"];
    
    t = @"This is a silly ole test.";
    XCTAssertTrue(t == [t stringByPerformingReplacement:simpleXMLEscape onCharacters:s]);
    
    XCTAssertEqualObjects([@"This & that" stringByPerformingReplacement:simpleXMLEscape onCharacters:s], @"This &amp; that");
    XCTAssertEqualObjects([@"&" stringByPerformingReplacement:simpleXMLEscape onCharacters:s], @"&amp;");
    XCTAssertEqualObjects([@"foo &&" stringByPerformingReplacement:simpleXMLEscape onCharacters:s], @"foo &amp;&amp;");
    XCTAssertEqualObjects([@"<&>" stringByPerformingReplacement:simpleXMLEscape onCharacters:s], @"&lt;&amp;&gt;");
    XCTAssertEqualObjects([@"<&> beelzebub" stringByPerformingReplacement:simpleXMLEscape onCharacters:[NSCharacterSet characterSetWithCharactersInString:@"< "]], @"&lt;&>&#32;beelzebub");
    
    t = @"This is a silly ole test.";
    XCTAssertTrue(t == [t stringByPerformingReplacement:unpair onCharacters:s]);
    XCTAssertEqualObjects([t stringByPerformingReplacement:unpair onCharacters:[s invertedSet]], @"This is a sily ole test.");
    XCTAssertEqualObjects([@"mississippi" stringByPerformingReplacement:unpair onCharacters:[s invertedSet]], @"misisipi");
    XCTAssertEqualObjects([@"mmississippi" stringByPerformingReplacement:unpair onCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ms"]], @"misisippi");
    XCTAssertEqualObjects([@"mmississippii" stringByPerformingReplacement:unpair onCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ip"]], @"mmississipi");
}

- (void)testGenericReplaceRange
{
    NSCharacterSet *s = [NSCharacterSet characterSetWithCharactersInString:@"<&>"];
    NSString *t = @"We&are<the Lo'lli\"p&>o&''<>p Guild\"";
    
    unsigned int l, r;
    for(r = 0; r < [t length]; r++) {
        NSString *tail = [t substringFromIndex:r];
        for(l = 0; l < r; l++) {
            NSString *head = [t substringToIndex:l];
            NSRange midRange;
            midRange.location = l;
            midRange.length = r - l;
            XCTAssertEqualObjects(([NSString stringWithStrings:head, [[t substringWithRange:midRange] stringByPerformingReplacement:simpleXMLEscape onCharacters:s], tail, nil]),
                          [t stringByPerformingReplacement:simpleXMLEscape onCharacters:s context:NULL options:0 range:midRange]);
        }
    }
}

#if !OMNI_BUILDING_FOR_IOS
- (void)testFourCharCodes
{
    FourCharCode fcc, fcc_bg;
    UInt8 backgrounds[5] = { 0, 32, 'x', 128, 255 };
    
    for (UInt32 shift = 0; shift < 32; shift += 8) {
        for (UInt32 bg = 0; bg < 5; bg ++) {
            fcc_bg = ( 0x01010101u - ( 0x01u << shift ) );
            fcc_bg *= backgrounds[bg];
            
            for (UInt32 i = 0; i < 256; i++) {
                fcc = ( i << shift ) | fcc_bg;
                NSString *str;
                uint32_t tmp;
                
                id p = OFCreatePlistFor4CC(fcc);
                XCTAssertTrue(OFGet4CCFromPlist(p, &tmp) && (tmp == fcc), @"s=%d i=%d 4cc=%08x", shift, i, (uint32_t)fcc);
                
                str = CFBridgingRelease(UTCreateStringForOSType(fcc));
                XCTAssertTrue(OFGet4CCFromPlist(str, &tmp) && (tmp == fcc), @"s=%d i=%d 4cc=%08x out=%08x", shift, i, (uint32_t)fcc, tmp);
                XCTAssertTrue(UTGetOSTypeFromString((__bridge CFStringRef)str) == fcc, @"s=%d i=%d 4cc=%08x", shift, i, (uint32_t)fcc);
                XCTAssertTrue([str fourCharCodeValue] == fcc, @"s=%d i=%d 4cc=%08x", shift, i, (uint32_t)fcc);
                
                str = [NSString stringWithFourCharCode:fcc];
                XCTAssertTrue(OFGet4CCFromPlist(str, &tmp) && (tmp == fcc), @"s=%d i=%d 4cc=%08x out=%08x", shift, i, (uint32_t)fcc, tmp);
                XCTAssertTrue(UTGetOSTypeFromString((__bridge CFStringRef)str) == fcc, @"s=%d i=%d 4cc=%08x", shift, i, (uint32_t)fcc);
                XCTAssertTrue([str fourCharCodeValue] == fcc, @"s=%d i=%d 4cc=%08x out=%08x", shift, i, (uint32_t)fcc, (uint32_t)[str fourCharCodeValue]);
            }
        }
    }
}
#endif

static NSString *fromutf8(const unsigned char *u, unsigned int length)
{
    NSString *s = [[NSString alloc] initWithBytes:u length:length encoding:NSUTF8StringEncoding];
    return s;
}

// From c.h in the 10.4u SDK
#define sizeofA(array)	(sizeof(array)/sizeof(array[0]))

- (void)testWithCharacter
{
    const unsigned char foo[3] = { 'f', 'o', 'o' };
    const unsigned char fuu[6] = { 0xC3, 0xBE, 0xC3, 0xBC, 0xC3, 0xBC };
    const unsigned char gorgo[4] = { 0xF0, 0x9D, 0x81, 0xB2 };
    const unichar fuu16[4] = { 0x00FE, 0x0075, 0x0308, 0x00FC };
    const unichar gorgo16[2] = { 0xD834, 0xDC72 };
    
    NSString *Foo = fromutf8(foo, sizeofA(foo));
    NSString *Fuu = fromutf8(fuu, sizeofA(fuu));
    NSString *Gorgo = fromutf8(gorgo, sizeofA(gorgo));
    
    NSString *Fuu16 = [[NSString alloc] initWithCharacters:fuu16 length:sizeofA(fuu16)];
    NSString *Gorgo16 = [[NSString alloc] initWithCharacters:gorgo16 length:sizeofA(gorgo16)];
    
    NSString *s;
    NSMutableString *t;
    
    s = [NSString stringWithCharacter:'f'];
    XCTAssertEqualObjects(s, ([Foo substringWithRange:(NSRange){0,1}]));
    
    s = [NSString stringWithCharacter:0x00FE];  // LATIN SMALL LETTER THORN
    XCTAssertEqualObjects(s, ([Fuu substringWithRange:(NSRange){0,1}]));
    s = [s stringByAppendingString:[NSString stringWithCharacter:0x00FC]];  // LATIN SMALL LETTER U WITH DIAERESIS
    t = [s mutableCopy];
    [t appendLongCharacter:'u']; // LATIN SMALL LETTER U
    [t appendLongCharacter:0x308]; // COMBINING DIAERESIS
    XCTAssertTrue([t compare:Fuu options:0] == NSOrderedSame);
    XCTAssertTrue([t compare:Fuu16 options:0] == NSOrderedSame);
    XCTAssertTrue([Fuu compare:Fuu16 options:0] == NSOrderedSame);
    XCTAssertEqualObjects([t decomposedStringWithCanonicalMapping], [Fuu decomposedStringWithCanonicalMapping]);
    XCTAssertEqualObjects([t decomposedStringWithCanonicalMapping], [Fuu16 decomposedStringWithCanonicalMapping]);
    t = [s mutableCopy];
    [t appendLongCharacter:0xFC]; // LATIN SMALL LETTER U WITH DIAERESIS
    XCTAssertEqualObjects(t, Fuu);
    
    s = [NSString stringWithCharacter:0x1D072]; // BYZANTINE MUSICAL SYMBOL GORGOSYNTHETON
    XCTAssertEqualObjects(s, Gorgo);
    XCTAssertEqualObjects(s, Gorgo16);
    XCTAssertEqualObjects(Gorgo, Gorgo16);
    
    t = (NSMutableString *)[NSMutableString stringWithCharacter:'z'];
    [t appendLongCharacter:0x1D072]; // BYZANTINE MUSICAL SYMBOL GORGOSYNTHETON
    [t replaceCharactersInRange:(NSRange){0,1} withString:@""];
    XCTAssertEqualObjects(t, Gorgo);
    [t appendLongCharacter:'z'];
    XCTAssertTrue(NSEqualRanges([t rangeOfComposedCharacterSequenceAtIndex:0],(NSRange){0,2}));
    XCTAssertTrue(NSEqualRanges([t rangeOfComposedCharacterSequenceAtIndex:1],(NSRange){0,2}));
    XCTAssertTrue(NSEqualRanges([t rangeOfComposedCharacterSequenceAtIndex:2],(NSRange){2,1}));
}

#define CFStringFromUnicharArray(x) CFStringCreateWithCharactersNoCopy(kCFAllocatorDefault, x, sizeof(x)/sizeof(x[0]), kCFAllocatorNull)

- (void)testInvalidSequence
{
    static const unichar good0[0] = { };                               // zero-length string is valid
    static const unichar good1[1] = { 'y' };
    static const unichar good2[4] = { 'y', 'x', 0, 'Z' };              // NULs are valid, even if they don't correspond to a character
    static const unichar good3[4] = { 'p', 'q', 0xD900, 0xDD00 };      // a normal surrogate pair
    static const unichar good4[5] = { 0xD900, 0xDD00, 0xD900, 0xDD00, 'k' };  // more surrogate pair stuff
    
    static const unichar bad1[1] = { 0xD900 };                 // broken pair
    static const unichar bad2[2] = { 0xD900, 'A' };            // broken pair
    static const unichar bad3[2] = { 0xDD00, 0xD900 };         // reversed pair
    static const unichar bad4[3] = { 0xDD00, 0xD900, 0xDD00 }; // reversed pair
    static const unichar bad5[4] = { 'y', 'x', 0, 0xFFFE };    // reversed BOM
    static const unichar bad6[3] = { 0xD87F, 0xDFFF, 'z' };    // valid surrogate pair encoding an invalid codepoint
    static const unichar bad7[4] = { 0xFFFE, 'H', 'i', '!' };  // reversed BOM
    static const unichar bad8[4] = { 'H', 'i', '0', 0xDFEE };  // broken pair

#define USTR(x) (__bridge CFStringRef)CFBridgingRelease(CFStringFromUnicharArray(x))
    XCTAssertTrue(OFStringContainsInvalidSequences(USTR(bad1)));
    XCTAssertTrue(OFStringContainsInvalidSequences(USTR(bad2)));
    XCTAssertTrue(OFStringContainsInvalidSequences(USTR(bad3)));
    XCTAssertTrue(OFStringContainsInvalidSequences(USTR(bad4)));
    XCTAssertTrue(OFStringContainsInvalidSequences(USTR(bad5)));
    XCTAssertTrue(OFStringContainsInvalidSequences(USTR(bad6)));
    XCTAssertTrue(OFStringContainsInvalidSequences(USTR(bad7)));
    XCTAssertTrue(OFStringContainsInvalidSequences(USTR(bad8)));
    
    XCTAssertFalse(OFStringContainsInvalidSequences(USTR(good0)));
    XCTAssertFalse(OFStringContainsInvalidSequences(USTR(good1)));
    XCTAssertFalse(OFStringContainsInvalidSequences(USTR(good2)));
    XCTAssertFalse(OFStringContainsInvalidSequences(USTR(good3)));
    XCTAssertFalse(OFStringContainsInvalidSequences(USTR(good4)));
#undef USTR
}

- (void)testCharacterSets
{
    static const char t0_utf8[] = { 't', 0xEF, 0xBF, 0xBE, 0 }; // Valid UTF8 for 0xFFFE
    static const char t1_utf8[] = { 't', 0xEF, 0xBF, 0xBF, 0 }; // Valid UTF8 for 0xFFFF
    static const char t2_utf8[] = { 't', 0xEF, 0xBB, 0xBF, 0 }; // Valid UTF8 for 0xFEFF

    NSCharacterSet *illegal = [NSString invalidXMLCharacterSet];
    NSCharacterSet *discouraged = [NSString discouragedXMLCharacterSet];
    
    XCTAssertTrue([[NSString stringWithUTF8String:t0_utf8] containsCharacterInSet:illegal], @"0xFFFE in +invalidXMLCharacterSet");
    XCTAssertTrue([[NSString stringWithUTF8String:t1_utf8] containsCharacterInSet:illegal], @"0xFFFF in +invalidXMLCharacterSet");
    XCTAssertFalse([[NSString stringWithUTF8String:t2_utf8] containsCharacterInSet:illegal], @"0xFEFF not in +invalidXMLCharacterSet");
    
    XCTAssertTrue([@"\x0B" containsCharacterInSet:illegal], @"Page-feed in +invalidXMLCharacterSet");
    XCTAssertFalse([@"\x0D" containsCharacterInSet:illegal], @"Carriage-return in +invalidXMLCharacterSet");

    XCTAssertFalse([[NSString stringWithCharacter:0x8A] containsCharacterInSet:illegal]);
    XCTAssertTrue([[NSString stringWithCharacter:0x8A] containsCharacterInSet:discouraged]);
    XCTAssertFalse([[NSString stringWithCharacter:0x85] containsCharacterInSet:discouraged]);
    
    /* Check some non-BMP characters. NSString represents those using surrogate pairs internally, and those use UTF-16 values which map to invalid codepoints if you interpret them directly. So make sure we're not breaking all non-BMP strings by forbidding those codepoints. */
    
    static const char t3_utf8[] = { 't', 0xf0, 0x9a, 0xaf, 0x8d, 0 }; // Valid UTF8 for 0x01ABCD
    static const char t4_utf8[] = { 't', 0xf0, 0xaf, 0xbf, 0xbe, 0 }; // Valid UTF8 for 0x02FFFE
    XCTAssertFalse([[NSString stringWithUTF8String:t3_utf8] containsCharacterInSet:illegal]);
    XCTAssertFalse([[NSString stringWithUTF8String:t4_utf8] containsCharacterInSet:illegal]);
    XCTAssertTrue([[NSString stringWithUTF8String:t4_utf8] containsCharacterInSet:discouraged]);
    
    /* Check some invalid UTF-16 sequences. I'm not entirely sure how these occur in practice, but users have managed to get broken surrogate pairs into their documents on multiple occasions. */
    CFStringRef s;
    
#if 0 /* It seems that -containsCharacterInSet: can't detect the reserved codepoints in the surrogate range */
    static const unichar t5_utf16[] = { 't', 0xDFFF, 'k' };          // unpaired low surrogate
    s = CFStringFromUnicharArray(t5_utf16);
    XCTAssertTrue([(__bridge NSString *)s containsCharacterInSet:illegal], @"t5 - broken surrogate");
    XCTAssertTrue([(__bridge NSString *)s containsCharacterInSet:[NSCharacterSet illegalCharacterSet]], @"t5 - broken surrogate");
    CFRelease(s);
    
    static const unichar t6_utf16[] = { 't', 0xD801, 'k' };          // unpaired high surrogate
    s = CFStringFromUnicharArray(t6_utf16);
    XCTAssertTrue([(__bridge NSString *)s containsCharacterInSet:illegal], @"t6 - broken surrogate");
    XCTAssertTrue([(__bridge NSString *)s containsCharacterInSet:[NSCharacterSet illegalCharacterSet]], @"t6 - broken surrogate");
    CFRelease(s);
#endif
    
    static const unichar t7_utf16[] = { 't', 0xD83D, 0xDCA9, 'k' };  // valid UTF-16 for U+1F4A9 PILE OF POO
    s = CFStringFromUnicharArray(t7_utf16);
    XCTAssertFalse([(__bridge NSString *)s containsCharacterInSet:illegal], @"t7 - valid surrogate");
    XCTAssertFalse([(__bridge NSString *)s containsCharacterInSet:[NSCharacterSet illegalCharacterSet]], @"t7 - valid surrogate");
    CFRelease(s);

    static const unichar t8_utf16[] = { 't', 0xD83F, 0xDFFF, 'z' };  // valid surrogate pair encoding an invalid codepoint
    s = CFStringFromUnicharArray(t8_utf16);
    XCTAssertFalse([(__bridge NSString *)s containsCharacterInSet:illegal], @"t8 - valid surrogate, reserved codepoint");
    XCTAssertTrue([(__bridge NSString *)s containsCharacterInSet:discouraged], @"t8 - valid surrogate, reserved codepoint");
    XCTAssertTrue([(__bridge NSString *)s containsCharacterInSet:[NSCharacterSet illegalCharacterSet]], @"t8 - valid surrogate, invalid codepoint");
    CFRelease(s);
}

- (void)testReplaceRegex;
{
    XCTAssertEqualObjects([@"    good stuff    " stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"^ +" withString:@"X"], @"Xgood stuff    ");
    XCTAssertEqualObjects([@"    good stuff.    " stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"\\.? +$" withString:@"X"], @"    good stuffX");
    XCTAssertEqualObjects([@"    good stuff    " stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"\\.? +$" withString:@"X"], @"    good stuffX");
    XCTAssertEqualObjects([@"    goodstuff    " stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"^ +| +$" withString:@"X"], @"XgoodstuffX");
    XCTAssertEqualObjects([@"    good stuff    " stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"^ +| +$" withString:@"X"], @"Xgood stuffX");
    
    // Make sure we don't re-process characters from the replacement string
    XCTAssertEqualObjects([@"aaaa" stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"a" withString:@"aa"], @"aaaaaaaa");
    XCTAssertEqualObjects([@"aaaa" stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"aa" withString:@"a"], @"aa");
}

@end

@interface OFStringPathUtilsTest : OFTestCase
@end

@implementation OFStringPathUtilsTest

- (void)testRelativePaths;
{
    XCTAssertEqualObjects([NSString commonRootPathOfFilename:@"/this/is/a/path" andFilename:@"/this/is/another/path"], @"/this/is");
    XCTAssertEqualObjects([NSString commonRootPathOfFilename:@"/this/is/a/path" andFilename:@"/that/is/another/path"], @"/");
    XCTAssertEqualObjects([NSString commonRootPathOfFilename:@"/this/is/a/path" andFilename:@"/this/is"], @"/this/is");
    XCTAssertEqualObjects([NSString commonRootPathOfFilename:@"/this" andFilename:@"/this/is/the/way/the/world/ends"], @"/this");
    XCTAssertEqualObjects([NSString commonRootPathOfFilename:@"/I/scream/for/ice/cream" andFilename:@"/you/scream/for/ice/cream"], @"/");
    XCTAssertNil([NSString commonRootPathOfFilename:@"/I/scream/for/ice/cream" andFilename:@"I/scream/for/ice/cream"]);
    
    XCTAssertEqualObjects([@"/biff/boof" relativePathToFilename:@"/biff/boof/zik/zak/zik"], @"zik/zak/zik");
    XCTAssertEqualObjects([@"/biff/boof" relativePathToFilename:@"/biff/zik/zak/zik"], @"../zik/zak/zik");
    XCTAssertEqualObjects([@"/biff/boof" relativePathToFilename:@"/zik/zak/zik"], @"../../zik/zak/zik");
    XCTAssertEqualObjects([@"/biff/boof/zik/zak/zik" relativePathToFilename:@"/biff/boof"], @"../../..");
    XCTAssertEqualObjects([@"/biff/boof/zik/zak/zik" relativePathToFilename:@"/biff/boof/"], @"../../..");
    
    XCTAssertEqualObjects([@"/biff/boof/" relativePathToFilename:@"/biff/boof/zik/zak/zik"], @"zik/zak/zik");
    XCTAssertEqualObjects([@"/biff/boof/" relativePathToFilename:@"/biff/zik/zak/zik"], @"../zik/zak/zik");
    XCTAssertEqualObjects([@"/biff/boof/" relativePathToFilename:@"/biff/zik/zak/zik/"], @"../zik/zak/zik");
    XCTAssertEqualObjects([@"/biff/boof/" relativePathToFilename:@"/zik/zak/zik"], @"../../zik/zak/zik");
    XCTAssertEqualObjects([@"/biff/boof/zik/zak/zik/" relativePathToFilename:@"/biff/boof"], @"../../..");
    XCTAssertEqualObjects([@"/biff/boof/zik/zak/zik/" relativePathToFilename:@"/biff/boof/"], @"../../..");
}

#if !OMNI_BUILDING_FOR_IOS
- (void)testFancySubpath
{
    NSString *relative;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    relative = nil;
    XCTAssertFalse([fm path:@"/foo/bar/baz" isAncestorOfPath:@"/foo/bar" relativePath:&relative]);
    XCTAssertNil(relative);
    XCTAssertTrue([fm path:@"/foo/bar" isAncestorOfPath:@"/foo/bar/baz" relativePath:&relative]);
    XCTAssertEqualObjects(relative, @"baz");
    
    NSError *error = nil;
    
    NSString *scratchMe = [@"/tmp" stringByAppendingPathComponent:[NSString stringWithFormat:@"test-%@-%u-%ld", NSUserName(), getpid(), time(NULL)]];
    OBShouldNotError([fm createDirectoryAtPath:scratchMe withIntermediateDirectories:NO attributes:nil error:&error]);
    NSString *sc0 = [scratchMe stringByAppendingPathComponent:@"zik"];
    OBShouldNotError([fm createDirectoryAtPath:sc0 withIntermediateDirectories:NO attributes:nil error:&error]);
    NSString *sc1 = [sc0 stringByAppendingPathComponent:@"zak"];
    OBShouldNotError([fm createDirectoryAtPath:sc1 withIntermediateDirectories:NO attributes:nil error:&error]);
    NSString *sc2 = [sc1 stringByAppendingPathComponent:@"zik"];
    OBShouldNotError([fm createDirectoryAtPath:sc2 withIntermediateDirectories:NO attributes:nil error:&error]);
    
    //NSLog(@"%@", [[NSArray arrayWithObjects:scratchMe, sc0, sc1, sc2, nil] description]);
    XCTAssertEqualObjects([scratchMe relativePathToFilename:sc2], @"zik/zak/zik");
    
    NSString *pScratchMe = [@"/private" stringByAppendingString:scratchMe];
    NSString *psc0 = [pScratchMe stringByAppendingPathComponent:@"zik"];
    NSString *psc1 = [psc0 stringByAppendingPathComponent:@"zak"];
    NSString *psc2 = [psc1 stringByAppendingPathComponent:@"zik"];

    //NSLog(@"%@", [[NSArray arrayWithObjects:pScratchMe, psc0, psc1, psc2, nil] description]);

    XCTAssertTrue([fm fileExistsAtPath:psc2]);

    relative = nil;
    XCTAssertTrue([fm path:scratchMe isAncestorOfPath:sc2 relativePath:&relative]);
    XCTAssertEqualObjects(relative, @"zik/zak/zik");
    
    relative = nil;
    XCTAssertTrue([fm path:sc0 isAncestorOfPath:sc2 relativePath:&relative]);
    XCTAssertEqualObjects(relative, @"zak/zik");
    
    relative = nil;
    XCTAssertTrue([fm path:psc0 isAncestorOfPath:sc1 relativePath:&relative]);
    XCTAssertEqualObjects(relative, @"zak");
    
    relative = nil;
    XCTAssertTrue([fm path:scratchMe isAncestorOfPath:psc2 relativePath:&relative]);
    XCTAssertEqualObjects(relative, @"zik/zak/zik");
    
    relative = nil;
    XCTAssertTrue([fm path:psc0 isAncestorOfPath:sc2 relativePath:&relative]);
    XCTAssertEqualObjects(relative, @"zak/zik");

    system([[NSString stringWithFormat:@"rm -r '%@'", scratchMe] UTF8String]);
}
#endif

@end
