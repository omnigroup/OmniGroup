// Copyright 2004-2008, 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
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

        should1(roundTrip == enc,
                ([NSString stringWithFormat:@"CFEncoding %lu encodes to \"%@\" decodes to %lu", (unsigned long)enc, savable, (unsigned long)roundTrip]));
    }
    
    should([NSString cfStringEncodingForDefaultValue:@"iana iso-8859-1"] == kCFStringEncodingISOLatin1);
    should([NSString cfStringEncodingForDefaultValue:@"iana utf-8"] == kCFStringEncodingUTF8);
    should([NSString cfStringEncodingForDefaultValue:@"iana UTF-8"] == kCFStringEncodingUTF8);
}



- (void)testAbbreviatedStringForHz;
{
    shouldBeEqual([NSString abbreviatedStringForHertz:0], @"0 Hz");
    shouldBeEqual([NSString abbreviatedStringForHertz:1], @"1 Hz");
    shouldBeEqual([NSString abbreviatedStringForHertz:9], @"9 Hz");
    shouldBeEqual([NSString abbreviatedStringForHertz:10], @"10 Hz");
    shouldBeEqual([NSString abbreviatedStringForHertz:11], @"11 Hz");
    shouldBeEqual([NSString abbreviatedStringForHertz:100], @"100 Hz");
    shouldBeEqual([NSString abbreviatedStringForHertz:990], @"990 Hz");
    shouldBeEqual([NSString abbreviatedStringForHertz:999], @"1.0 KHz");
    shouldBeEqual([NSString abbreviatedStringForHertz:1000], @"1.0 KHz");
    shouldBeEqual([NSString abbreviatedStringForHertz:1099], @"1.1 KHz");
    shouldBeEqual([NSString abbreviatedStringForHertz:1100], @"1.1 KHz");
    shouldBeEqual([NSString abbreviatedStringForHertz:1000000], @"1.0 MHz");
    shouldBeEqual([NSString abbreviatedStringForHertz:10000000], @"10.0 MHz");
    shouldBeEqual([NSString abbreviatedStringForHertz:100000000], @"100.0 MHz");
    shouldBeEqual([NSString abbreviatedStringForHertz:1000000000], @"1.0 GHz");
    shouldBeEqual([NSString abbreviatedStringForHertz:1800000000], @"1.8 GHz");
    shouldBeEqual([NSString abbreviatedStringForHertz:2000000000], @"2.0 GHz");
    shouldBeEqual([NSString abbreviatedStringForHertz:10000000000LL], @"10.0 GHz");
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

    shouldBeEqual([@"" stringByRemovingSurroundingWhitespace], @"");
    shouldBeEqual([@" " stringByRemovingSurroundingWhitespace], @"");
    shouldBeEqual([@"  " stringByRemovingSurroundingWhitespace], @"");
    shouldBeEqual([@"\t\n\r " stringByRemovingSurroundingWhitespace], @"");
    shouldBeEqual([@"foo " stringByRemovingSurroundingWhitespace], @"foo");
    shouldBeEqual([@"foo  " stringByRemovingSurroundingWhitespace], @"foo");
    shouldBeEqual([@"o " stringByRemovingSurroundingWhitespace], @"o");
    shouldBeEqual([@" f " stringByRemovingSurroundingWhitespace], @"f");
    shouldBeEqual([@" foo " stringByRemovingSurroundingWhitespace], @"foo");
    shouldBeEqual([@"  foo " stringByRemovingSurroundingWhitespace], @"foo");
    shouldBeEqual([@"foo" stringByRemovingSurroundingWhitespace], @"foo");
    shouldBeEqual([@"  foo" stringByRemovingSurroundingWhitespace], @"foo");
    
    for(i = 0; i < 3; i ++) {
        NSString *t = [NSString stringWithCharacters:2+s[i] length:sl[i]-4];
        shouldBeEqual([[NSString stringWithCharacters:s[i]   length:sl[i]  ] stringByRemovingSurroundingWhitespace], t);
        shouldBeEqual([[NSString stringWithCharacters:s[i]+2 length:sl[i]-2] stringByRemovingSurroundingWhitespace], t);
        shouldBeEqual([[NSString stringWithCharacters:s[i]   length:sl[i]-2] stringByRemovingSurroundingWhitespace], t);
        shouldBeEqual([[NSString stringWithCharacters:s[i]+2 length:sl[i]-4] stringByRemovingSurroundingWhitespace], t);
    }
    
    NSMutableString *buf = [[NSMutableString alloc] init];

    for(i = 0; i < 3; i ++) {
        NSString *t = [NSString stringWithCharacters:2+s[i] length:sl[i]-4];
        [buf setString:[NSString stringWithCharacters:s[i]   length:sl[i]  ]]; shouldBeEqual([buf stringByRemovingSurroundingWhitespace], t);
        [buf setString:[NSString stringWithCharacters:s[i]+2 length:sl[i]-2]]; shouldBeEqual([buf stringByRemovingSurroundingWhitespace], t);
        [buf setString:[NSString stringWithCharacters:s[i]   length:sl[i]-2]]; shouldBeEqual([buf stringByRemovingSurroundingWhitespace], t);
        [buf setString:[NSString stringWithCharacters:s[i]+2 length:sl[i]-4]]; shouldBeEqual([buf stringByRemovingSurroundingWhitespace], t);
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
    
    shouldBeEqual(t0, decimalized);
    shouldBeEqual(t1, decimalized);
    if (exponential) {
        shouldBeEqual(t2, exponential);
    } else {
        shouldBeEqual(t2, decimalized);
    }
    
    
    if ([decimalized hasPrefix:@"0."]) {
        buf = OFShortASCIIDecimalStringFromDouble(d, OF_FLT_DIGITS_E, NO, NO);
        t1 = CFBridgingRelease(CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, buf, kCFStringEncodingASCII, kCFAllocatorMalloc));
        shouldBeEqual(t1, [decimalized substringFromIndex:1]);
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
    
#define TESTIT(num, expok, force, expect) { char *buf = OFShortASCIIDecimalStringFromDouble(num, OF_FLT_DIGITS_E, expok, force); should1(strcmp(buf, expect) == 0, ([NSString stringWithFormat:@"formatted %g (expok=%d forcelz=%d) got \"%s\" expected \"%s\"", num, expok, force, buf, expect])); free(buf); }
        
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
    float n;
    int i;
    
    for(n = 1.0f, i = 0;
        i < 1000;
        n = nextafterf(n, 100.0f), i++) {
        char *buf = OFShortASCIIDecimalStringFromDouble(n, OF_FLT_DIGITS_E, 0, 1);
        float n2 = -1;
        should1(sscanf(buf, "%f", &n2) == 1 && (n == n2),
                ([NSString stringWithFormat:@"formatted %.10g got \"%s\" scanned %.10g", n, buf, n2]));
        free(buf);
    }
    
    for(n = 1.0f, i = 0;
        i < 1000;
        n = nextafterf(n, -100.0f), i++) {
        char *buf = OFShortASCIIDecimalStringFromDouble(n, OF_FLT_DIGITS_E, 0, 1);
        float n2 = -1;
        should1(sscanf(buf, "%f", &n2) == 1 && (n == n2),
                ([NSString stringWithFormat:@"formatted %.10g got \"%s\" scanned %.10g", n, buf, n2]));
        free(buf);
    }
}

- (void)testComponentsSeparatedByCharactersFromSet
{
    NSCharacterSet *delimiterSet = [NSCharacterSet punctuationCharacterSet];
    NSCharacterSet *emptySet = [NSCharacterSet characterSetWithCharactersInString:@""];
    
    shouldBeEqual([@"Hi.there" componentsSeparatedByCharactersFromSet:delimiterSet], ([NSArray arrayWithObjects:@"Hi", @"there", nil]));
    shouldBeEqual([@"Hi.there" componentsSeparatedByCharactersFromSet:emptySet], ([NSArray arrayWithObject:@"Hi.there"]));
    shouldBeEqual([@".Hi.there!" componentsSeparatedByCharactersFromSet:delimiterSet], ([NSArray arrayWithObjects:@"", @"Hi", @"there", @"", nil]));
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
    should(t == [t stringByPerformingReplacement:simpleXMLEscape onCharacters:s]);
    
    shouldBeEqual([@"This & that" stringByPerformingReplacement:simpleXMLEscape onCharacters:s], @"This &amp; that");
    shouldBeEqual([@"&" stringByPerformingReplacement:simpleXMLEscape onCharacters:s], @"&amp;");
    shouldBeEqual([@"foo &&" stringByPerformingReplacement:simpleXMLEscape onCharacters:s], @"foo &amp;&amp;");
    shouldBeEqual([@"<&>" stringByPerformingReplacement:simpleXMLEscape onCharacters:s], @"&lt;&amp;&gt;");
    shouldBeEqual([@"<&> beelzebub" stringByPerformingReplacement:simpleXMLEscape onCharacters:[NSCharacterSet characterSetWithCharactersInString:@"< "]], @"&lt;&>&#32;beelzebub");
    
    t = @"This is a silly ole test.";
    should(t == [t stringByPerformingReplacement:unpair onCharacters:s]);
    shouldBeEqual([t stringByPerformingReplacement:unpair onCharacters:[s invertedSet]], @"This is a sily ole test.");
    shouldBeEqual([@"mississippi" stringByPerformingReplacement:unpair onCharacters:[s invertedSet]], @"misisipi");
    shouldBeEqual([@"mmississippi" stringByPerformingReplacement:unpair onCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ms"]], @"misisippi");
    shouldBeEqual([@"mmississippii" stringByPerformingReplacement:unpair onCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ip"]], @"mmississipi");
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
            shouldBeEqual(([NSString stringWithStrings:head, [[t substringWithRange:midRange] stringByPerformingReplacement:simpleXMLEscape onCharacters:s], tail, nil]),
                          [t stringByPerformingReplacement:simpleXMLEscape onCharacters:s context:NULL options:0 range:midRange]);
        }
    }
}

- (void)testFourCharCodes
{
    int i, shift, bg;
    FourCharCode fcc, fcc_bg;
    UInt8 backgrounds[5] = { 0, 32, 'x', 128, 255 };
    
    for(shift = 0; shift < 32; shift += 8) {
        for(bg = 0; bg < 5; bg ++) {
            fcc_bg = ( 0x01010101u - ( 0x01u << shift ) );
            fcc_bg *= backgrounds[bg];
            
            for(i = 0; i < 256; i++) {
                fcc = ( ((UInt8)i) << shift ) | fcc_bg;
                NSString *str;
                uint32_t tmp;
                
                id p = OFCreatePlistFor4CC(fcc);
                should1(OFGet4CCFromPlist(p, &tmp) && (tmp == fcc), ([NSString stringWithFormat:@"s=%d i=%d 4cc=%08x", shift, i, (uint32_t)fcc]));
                
                str = CFBridgingRelease(UTCreateStringForOSType(fcc));
                should1(OFGet4CCFromPlist(str, &tmp) && (tmp == fcc), ([NSString stringWithFormat:@"s=%d i=%d 4cc=%08x out=%08x", shift, i, (uint32_t)fcc, tmp]));
                should1(UTGetOSTypeFromString((__bridge CFStringRef)str) == fcc, ([NSString stringWithFormat:@"s=%d i=%d 4cc=%08x", shift, i, (uint32_t)fcc]));
                should1([str fourCharCodeValue] == fcc, ([NSString stringWithFormat:@"s=%d i=%d 4cc=%08x", shift, i, (uint32_t)fcc]));
                
                str = [NSString stringWithFourCharCode:fcc];
                should1(OFGet4CCFromPlist(str, &tmp) && (tmp == fcc), ([NSString stringWithFormat:@"s=%d i=%d 4cc=%08x out=%08x", shift, i, (uint32_t)fcc, tmp]));
                should1(UTGetOSTypeFromString((__bridge CFStringRef)str) == fcc, ([NSString stringWithFormat:@"s=%d i=%d 4cc=%08x", shift, i, (uint32_t)fcc]));
                should1([str fourCharCodeValue] == fcc, ([NSString stringWithFormat:@"s=%d i=%d 4cc=%08x out=%08x", shift, i, (uint32_t)fcc, (uint32_t)[str fourCharCodeValue]]));
            }
        }
    }
}

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
    shouldBeEqual(s, ([Foo substringWithRange:(NSRange){0,1}]));
    
    s = [NSString stringWithCharacter:0x00FE];  // LATIN SMALL LETTER THORN
    shouldBeEqual(s, ([Fuu substringWithRange:(NSRange){0,1}]));
    s = [s stringByAppendingString:[NSString stringWithCharacter:0x00FC]];  // LATIN SMALL LETTER U WITH DIAERESIS
    t = [s mutableCopy];
    [t appendLongCharacter:'u']; // LATIN SMALL LETTER U
    [t appendLongCharacter:0x308]; // COMBINING DIAERESIS
    should([t compare:Fuu options:0] == NSOrderedSame);
    should([t compare:Fuu16 options:0] == NSOrderedSame);
    should([Fuu compare:Fuu16 options:0] == NSOrderedSame);
    shouldBeEqual([t decomposedStringWithCanonicalMapping], [Fuu decomposedStringWithCanonicalMapping]);
    shouldBeEqual([t decomposedStringWithCanonicalMapping], [Fuu16 decomposedStringWithCanonicalMapping]);
    t = [s mutableCopy];
    [t appendLongCharacter:0xFC]; // LATIN SMALL LETTER U WITH DIAERESIS
    shouldBeEqual(t, Fuu);
    
    s = [NSString stringWithCharacter:0x1D072]; // BYZANTINE MUSICAL SYMBOL GORGOSYNTHETON
    shouldBeEqual(s, Gorgo);
    shouldBeEqual(s, Gorgo16);
    shouldBeEqual(Gorgo, Gorgo16);
    
    t = (NSMutableString *)[NSMutableString stringWithCharacter:'z'];
    [t appendLongCharacter:0x1D072]; // BYZANTINE MUSICAL SYMBOL GORGOSYNTHETON
    [t replaceCharactersInRange:(NSRange){0,1} withString:@""];
    shouldBeEqual(t, Gorgo);
    [t appendLongCharacter:'z'];
    should(NSEqualRanges([t rangeOfComposedCharacterSequenceAtIndex:0],(NSRange){0,2}));
    should(NSEqualRanges([t rangeOfComposedCharacterSequenceAtIndex:1],(NSRange){0,2}));
    should(NSEqualRanges([t rangeOfComposedCharacterSequenceAtIndex:2],(NSRange){2,1}));
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
    STAssertTrue(OFStringContainsInvalidSequences(USTR(bad1)), nil);
    STAssertTrue(OFStringContainsInvalidSequences(USTR(bad2)), nil);
    STAssertTrue(OFStringContainsInvalidSequences(USTR(bad3)), nil);
    STAssertTrue(OFStringContainsInvalidSequences(USTR(bad4)), nil);
    STAssertTrue(OFStringContainsInvalidSequences(USTR(bad5)), nil);
    STAssertTrue(OFStringContainsInvalidSequences(USTR(bad6)), nil);
    STAssertTrue(OFStringContainsInvalidSequences(USTR(bad7)), nil);
    STAssertTrue(OFStringContainsInvalidSequences(USTR(bad8)), nil);
    
    STAssertFalse(OFStringContainsInvalidSequences(USTR(good0)), nil);
    STAssertFalse(OFStringContainsInvalidSequences(USTR(good1)), nil);
    STAssertFalse(OFStringContainsInvalidSequences(USTR(good2)), nil);
    STAssertFalse(OFStringContainsInvalidSequences(USTR(good3)), nil);
    STAssertFalse(OFStringContainsInvalidSequences(USTR(good4)), nil);
#undef USTR
}

- (void)testCharacterSets
{
    static const char t0_utf8[] = { 't', 0xEF, 0xBF, 0xBE, 0 }; // Valid UTF8 for 0xFFFE
    static const char t1_utf8[] = { 't', 0xEF, 0xBF, 0xBF, 0 }; // Valid UTF8 for 0xFFFF
    static const char t2_utf8[] = { 't', 0xEF, 0xBB, 0xBF, 0 }; // Valid UTF8 for 0xFEFF

    NSCharacterSet *illegal = [NSString invalidXMLCharacterSet];
    NSCharacterSet *discouraged = [NSString discouragedXMLCharacterSet];
    
    STAssertTrue([[NSString stringWithUTF8String:t0_utf8] containsCharacterInSet:illegal], @"0xFFFE in +invalidXMLCharacterSet");
    STAssertTrue([[NSString stringWithUTF8String:t1_utf8] containsCharacterInSet:illegal], @"0xFFFF in +invalidXMLCharacterSet");
    STAssertFalse([[NSString stringWithUTF8String:t2_utf8] containsCharacterInSet:illegal], @"0xFEFF not in +invalidXMLCharacterSet");
    
    STAssertTrue([@"\x0B" containsCharacterInSet:illegal], @"Page-feed in +invalidXMLCharacterSet");
    STAssertFalse([@"\x0D" containsCharacterInSet:illegal], @"Carriage-return in +invalidXMLCharacterSet");

    STAssertFalse([[NSString stringWithCharacter:0x8A] containsCharacterInSet:illegal], nil);
    STAssertTrue([[NSString stringWithCharacter:0x8A] containsCharacterInSet:discouraged], nil);
    STAssertFalse([[NSString stringWithCharacter:0x85] containsCharacterInSet:discouraged], nil);
    
    /* Check some non-BMP characters. NSString represents those using surrogate pairs internally, and those use UTF-16 values which map to invalid codepoints if you interpret them directly. So make sure we're not breaking all non-BMP strings by forbidding those codepoints. */
    
    static const char t3_utf8[] = { 't', 0xf0, 0x9a, 0xaf, 0x8d, 0 }; // Valid UTF8 for 0x01ABCD
    static const char t4_utf8[] = { 't', 0xf0, 0xaf, 0xbf, 0xbe, 0 }; // Valid UTF8 for 0x02FFFE
    STAssertFalse([[NSString stringWithUTF8String:t3_utf8] containsCharacterInSet:illegal], nil);
    STAssertFalse([[NSString stringWithUTF8String:t4_utf8] containsCharacterInSet:illegal], nil);
    STAssertTrue([[NSString stringWithUTF8String:t4_utf8] containsCharacterInSet:discouraged], nil);
    
    /* Check some invalid UTF-16 sequences. I'm not entirely sure how these occur in practice, but users have managed to get broken surrogate pairs into their documents on multiple occasions. */
    CFStringRef s;
    
#if 0 /* It seems that -containsCharacterInSet: can't detect the reserved codepoints in the surrogate range */
    static const unichar t5_utf16[] = { 't', 0xDFFF, 'k' };          // unpaired low surrogate
    s = CFStringFromUnicharArray(t5_utf16);
    STAssertTrue([(__bridge NSString *)s containsCharacterInSet:illegal], @"t5 - broken surrogate");
    STAssertTrue([(__bridge NSString *)s containsCharacterInSet:[NSCharacterSet illegalCharacterSet]], @"t5 - broken surrogate");
    CFRelease(s);
    
    static const unichar t6_utf16[] = { 't', 0xD801, 'k' };          // unpaired high surrogate
    s = CFStringFromUnicharArray(t6_utf16);
    STAssertTrue([(__bridge NSString *)s containsCharacterInSet:illegal], @"t6 - broken surrogate");
    STAssertTrue([(__bridge NSString *)s containsCharacterInSet:[NSCharacterSet illegalCharacterSet]], @"t6 - broken surrogate");
    CFRelease(s);
#endif
    
    static const unichar t7_utf16[] = { 't', 0xD83D, 0xDCA9, 'k' };  // valid UTF-16 for U+1F4A9 PILE OF POO
    s = CFStringFromUnicharArray(t7_utf16);
    STAssertFalse([(__bridge NSString *)s containsCharacterInSet:illegal], @"t7 - valid surrogate");
    STAssertFalse([(__bridge NSString *)s containsCharacterInSet:[NSCharacterSet illegalCharacterSet]], @"t7 - valid surrogate");
    CFRelease(s);

    static const unichar t8_utf16[] = { 't', 0xD83F, 0xDFFF, 'z' };  // valid surrogate pair encoding an invalid codepoint
    s = CFStringFromUnicharArray(t8_utf16);
    STAssertFalse([(__bridge NSString *)s containsCharacterInSet:illegal], @"t8 - valid surrogate, reserved codepoint");
    STAssertTrue([(__bridge NSString *)s containsCharacterInSet:discouraged], @"t8 - valid surrogate, reserved codepoint");
    STAssertTrue([(__bridge NSString *)s containsCharacterInSet:[NSCharacterSet illegalCharacterSet]], @"t8 - valid surrogate, invalid codepoint");
    CFRelease(s);
}

- (void)testReplaceRegex;
{
    shouldBeEqual([@"    good stuff    " stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"^ +" withString:@"X"], @"Xgood stuff    ");
    shouldBeEqual([@"    good stuff.    " stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"\\.? +$" withString:@"X"], @"    good stuffX");
    shouldBeEqual([@"    good stuff    " stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"\\.? +$" withString:@"X"], @"    good stuffX");
    shouldBeEqual([@"    goodstuff    " stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"^ +| +$" withString:@"X"], @"XgoodstuffX");
    shouldBeEqual([@"    good stuff    " stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"^ +| +$" withString:@"X"], @"Xgood stuffX");
    
    // Make sure we don't re-process characters from the replacement string
    shouldBeEqual([@"aaaa" stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"a" withString:@"aa"], @"aaaaaaaa");
    shouldBeEqual([@"aaaa" stringByReplacingAllOccurrencesOfRegularExpressionPattern:@"aa" withString:@"a"], @"aa");
}

@end

@interface OFStringPathUtilsTest : OFTestCase
@end

@implementation OFStringPathUtilsTest

- (void)testRelativePaths;
{
    shouldBeEqual([NSString commonRootPathOfFilename:@"/this/is/a/path" andFilename:@"/this/is/another/path"], @"/this/is");
    shouldBeEqual([NSString commonRootPathOfFilename:@"/this/is/a/path" andFilename:@"/that/is/another/path"], @"/");
    shouldBeEqual([NSString commonRootPathOfFilename:@"/this/is/a/path" andFilename:@"/this/is"], @"/this/is");
    shouldBeEqual([NSString commonRootPathOfFilename:@"/this" andFilename:@"/this/is/the/way/the/world/ends"], @"/this");
    shouldBeEqual([NSString commonRootPathOfFilename:@"/I/scream/for/ice/cream" andFilename:@"/you/scream/for/ice/cream"], @"/");
    shouldBeEqual([NSString commonRootPathOfFilename:@"/I/scream/for/ice/cream" andFilename:@"I/scream/for/ice/cream"], nil);
    
    shouldBeEqual([@"/biff/boof" relativePathToFilename:@"/biff/boof/zik/zak/zik"], @"zik/zak/zik");
    shouldBeEqual([@"/biff/boof" relativePathToFilename:@"/biff/zik/zak/zik"], @"../zik/zak/zik");
    shouldBeEqual([@"/biff/boof" relativePathToFilename:@"/zik/zak/zik"], @"../../zik/zak/zik");
    shouldBeEqual([@"/biff/boof/zik/zak/zik" relativePathToFilename:@"/biff/boof"], @"../../..");
    shouldBeEqual([@"/biff/boof/zik/zak/zik" relativePathToFilename:@"/biff/boof/"], @"../../..");
    
    shouldBeEqual([@"/biff/boof/" relativePathToFilename:@"/biff/boof/zik/zak/zik"], @"zik/zak/zik");
    shouldBeEqual([@"/biff/boof/" relativePathToFilename:@"/biff/zik/zak/zik"], @"../zik/zak/zik");
    shouldBeEqual([@"/biff/boof/" relativePathToFilename:@"/biff/zik/zak/zik/"], @"../zik/zak/zik");
    shouldBeEqual([@"/biff/boof/" relativePathToFilename:@"/zik/zak/zik"], @"../../zik/zak/zik");
    shouldBeEqual([@"/biff/boof/zik/zak/zik/" relativePathToFilename:@"/biff/boof"], @"../../..");
    shouldBeEqual([@"/biff/boof/zik/zak/zik/" relativePathToFilename:@"/biff/boof/"], @"../../..");
}

- (void)testFancySubpath
{
    NSString *relative;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    relative = nil;
    shouldnt([fm path:@"/foo/bar/baz" isAncestorOfPath:@"/foo/bar" relativePath:&relative]);
    shouldBeEqual(relative, nil);
    should([fm path:@"/foo/bar" isAncestorOfPath:@"/foo/bar/baz" relativePath:&relative]);
    shouldBeEqual(relative, @"baz");
    
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
    shouldBeEqual([scratchMe relativePathToFilename:sc2], @"zik/zak/zik");
    
    NSString *pScratchMe = [@"/private" stringByAppendingString:scratchMe];
    NSString *psc0 = [pScratchMe stringByAppendingPathComponent:@"zik"];
    NSString *psc1 = [psc0 stringByAppendingPathComponent:@"zak"];
    NSString *psc2 = [psc1 stringByAppendingPathComponent:@"zik"];

    //NSLog(@"%@", [[NSArray arrayWithObjects:pScratchMe, psc0, psc1, psc2, nil] description]);

    should([fm fileExistsAtPath:psc2]);

    relative = nil;
    should([fm path:scratchMe isAncestorOfPath:sc2 relativePath:&relative]);
    shouldBeEqual(relative, @"zik/zak/zik");
    
    relative = nil;
    should([fm path:sc0 isAncestorOfPath:sc2 relativePath:&relative]);
    shouldBeEqual(relative, @"zak/zik");
    
    relative = nil;
    should([fm path:psc0 isAncestorOfPath:sc1 relativePath:&relative]);
    shouldBeEqual(relative, @"zak");
    
    relative = nil;
    should([fm path:scratchMe isAncestorOfPath:psc2 relativePath:&relative]);
    shouldBeEqual(relative, @"zik/zak/zik");
    
    relative = nil;
    should([fm path:psc0 isAncestorOfPath:sc2 relativePath:&relative]);
    shouldBeEqual(relative, @"zak/zik");

    system([[NSString stringWithFormat:@"rm -r '%@'", scratchMe] UTF8String]);
}

@end
