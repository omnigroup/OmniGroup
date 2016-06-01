// Copyright 2004-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <XCTest/XCTest.h>
#import <OmniNetworking/ONHost.h>

RCS_ID("$Id$");

@interface IDNEncodingTests : XCTestCase
{
    CFStringEncoding oldNSCFStringEncodingForLogging;
    NSStringEncoding oldNSCStringEncoding, oldNSDefaultStringEncoding;
}


@end

@implementation IDNEncodingTests

// Test cases

// Test vectors from RFC 3492 [7.1]

const unichar rfc3492_7_A[] = { 0x0644, 0x064A, 0x0647, 0x0645, 0x0627, 0x0628, 0x062A, 0x0643, 0x0644, 0x0645, 0x0648, 0x0634, 0x0639, 0x0631, 0x0628, 0x064A, 0x061F }; // Arabic
const char *rfc3492_7_A_pc = "egbpdaj6bu4bxfgehfvwxn";

const unichar rfc3492_7_B[] = { 0x4ED6, 0x4EEC, 0x4E3A, 0x4EC0, 0x4E48, 0x4E0D, 0x8BF4, 0x4E2D, 0x6587}; // Chinese (simplified)
const char *rfc3492_7_B_pc = "ihqwcrb4cv8a8dqg056pqjye";

const unichar rfc3492_7_C[] = { 0x4ED6, 0x5011, 0x7232, 0x4EC0, 0x9EBD, 0x4E0D, 0x8AAA, 0x4E2D, 0x6587 }; // Chinese (traditional)
const char *rfc3492_7_C_pc = "ihqwctvzc91f659drss3x8bo0yb";

const unichar rfc3492_7_D[] = { 0x0050, 0x0072, 0x006F, 0x010D, 0x0070, 0x0072, 0x006F, 0x0073, 0x0074, 0x011B, 0x006E, 0x0065, 0x006D, 0x006C, 0x0075, 0x0076, 0x00ED, 0x010D, 0x0065, 0x0073, 0x006B, 0x0079 }; // Czech
const char *rfc3492_7_D_pc = "Proprostnemluvesky-uyb24dma41a";

const unichar rfc3492_7_E[] = { 0x05DC, 0x05DE, 0x05D4, 0x05D4, 0x05DD, 0x05E4, 0x05E9, 0x05D5, 0x05D8, 0x05DC, 0x05D0, 0x05DE, 0x05D3, 0x05D1, 0x05E8, 0x05D9, 0x05DD, 0x05E2, 0x05D1, 0x05E8, 0x05D9, 0x05EA }; // Hebrew
const char *rfc3492_7_E_pc = "4dbcagdahymbxekheh6e0a7fei0b";

const unichar rfc3492_7_F[] = { 0x092F, 0x0939, 0x0932, 0x094B, 0x0917, 0x0939, 0x093F, 0x0928, 0x094D, 0x0926, 0x0940, 0x0915, 0x094D, 0x092F, 0x094B, 0x0902, 0x0928, 0x0939, 0x0940, 0x0902, 0x092C, 0x094B, 0x0932, 0x0938, 0x0915, 0x0924, 0x0947, 0x0939, 0x0948, 0x0902 }; // Hindi (Devanagari)
const char *rfc3492_7_F_pc = "i1baa7eci9glrd9b2ae1bj0hfcgg6iyaf8o0a1dig0cd";

const unichar rfc3492_7_G[] = { 0x306A, 0x305C, 0x307F, 0x3093, 0x306A, 0x65E5, 0x672C, 0x8A9E, 0x3092
   , 0x8A71, 0x3057, 0x3066, 0x304F, 0x308C, 0x306A, 0x3044, 0x306E, 0x304B }; // Japanese (kanji and hiragana)
const char *rfc3492_7_G_pc = "n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa";

const unichar rfc3492_7_H[] = { 0xC138, 0xACC4, 0xC758, 0xBAA8, 0xB4E0, 0xC0AC, 0xB78C, 0xB4E4, 0xC774, 0xD55C, 0xAD6D, 0xC5B4, 0xB97C, 0xC774, 0xD574, 0xD55C, 0xB2E4, 0xBA74, 0xC5BC, 0xB9C8, 0xB098, 0xC88B, 0xC744, 0xAE4C }; // Korean (Hangul syllables)
const char *rfc3492_7_H_pc = "989aomsvi5e83db1d2a355cv1e0vak1dwrv93d5xbh15a0dt30a5jpsd879ccm6fea98c";

const unichar rfc3492_7_I[] = { 0x043F, 0x043E, 0x0447, 0x0435, 0x043C, 0x0443, 0x0436, 0x0435, 0x043E, 0x043D, 0x0438, 0x043D, 0x0435, 0x0433, 0x043E, 0x0432, 0x043E, 0x0440, 0x044F, 0x0442, 0x043F, 0x043E, 0x0440, 0x0443, 0x0441, 0x0441, 0x043A, 0x0438 }; // Russian (Cyrillic)
const char *rfc3492_7_I_pc = "b1abfaaepdrnnbgefbaDotcwatmq2g4l";

const unichar rfc3492_7_J[] = { 0x0050, 0x006F, 0x0072, 0x0071, 0x0075, 0x00E9, 0x006E, 0x006F, 0x0070, 0x0075, 0x0065, 0x0064, 0x0065, 0x006E, 0x0073, 0x0069, 0x006D, 0x0070, 0x006C, 0x0065, 0x006D, 0x0065, 0x006E, 0x0074, 0x0065, 0x0068, 0x0061, 0x0062, 0x006C, 0x0061, 0x0072, 0x0065, 0x006E, 0x0045, 0x0073, 0x0070, 0x0061, 0x00F1, 0x006F, 0x006C }; // Spanish
const char *rfc3492_7_J_pc = "PorqunopuedensimplementehablarenEspaol-fmd56a";

const unichar rfc3492_7_K[] = { 0x0054, 0x1EA1, 0x0069, 0x0073, 0x0061, 0x006F, 0x0068, 0x1ECD, 0x006B, 0x0068, 0x00F4, 0x006E, 0x0067, 0x0074, 0x0068, 0x1EC3, 0x0063, 0x0068, 0x1EC9, 0x006E, 0x00F3, 0x0069, 0x0074, 0x0069, 0x1EBF, 0x006E, 0x0067, 0x0056, 0x0069, 0x1EC7, 0x0074 }; // Vietnamese
const char *rfc3492_7_K_pc = "TisaohkhngthchnitingVit-kjcr8268qyxafd2f1b9g";

const unichar rfc3492_7_L[] = { 0x0033, 0x5E74, 0x0042, 0x7D44, 0x91D1, 0x516B, 0x5148, 0x751F }; // 3<nen>B<gumi><kinpachi><sensei>
const char *rfc3492_7_L_pc = "3B-ww4c5e180e575a65lsy2b";

const unichar rfc3492_7_M[] = { 0x5B89, 0x5BA4, 0x5948, 0x7F8E, 0x6075, 0x002D, 0x0077, 0x0069, 0x0074, 0x0068, 0x002D, 0x0053, 0x0055, 0x0050, 0x0045, 0x0052, 0x002D, 0x004D, 0x004F, 0x004E, 0x004B, 0x0045, 0x0059, 0x0053 }; // <amuro><namie>-with-SUPER-MONKEYS
const char *rfc3492_7_M_pc = "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n";

const unichar rfc3492_7_N[] = { 0x0048, 0x0065, 0x006C, 0x006C, 0x006F, 0x002D, 0x0041, 0x006E, 0x006F, 0x0074, 0x0068, 0x0065, 0x0072, 0x002D, 0x0057, 0x0061, 0x0079, 0x002D, 0x305D, 0x308C, 0x305E, 0x308C, 0x306E, 0x5834, 0x6240 }; //  Hello-Another-Way-<sorezore><no><basho>
const char *rfc3492_7_N_pc = "Hello-Another-Way--fc4qua05auwb3674vfr0b";

const unichar rfc3492_7_O[] = { 0x3072, 0x3068, 0x3064, 0x5C4B, 0x6839, 0x306E, 0x4E0B, 0x0032 }; // <hitotsu><yane><no><shita>2
const char *rfc3492_7_O_pc = "2-u9tlzr9756bt3uc0v";

const unichar rfc3492_7_P[] = { 0x004D, 0x0061, 0x006A, 0x0069, 0x3067, 0x004B, 0x006F, 0x0069, 0x3059, 0x308B, 0x0035, 0x79D2, 0x524D }; // Maji<de>Koi<suru>5<byou><mae>
const char *rfc3492_7_P_pc = "MajiKoi5-783gue6qz075azm5e";

const unichar rfc3492_7_Q[] = { 0x30D1, 0x30D5, 0x30A3, 0x30FC, 0x0064, 0x0065, 0x30EB, 0x30F3, 0x30D0 }; // <pafii>de<runba>
const char *rfc3492_7_Q_pc = "de-jg4avhby1noc0d";

const unichar rfc3492_7_R[] = { 0x305D, 0x306E, 0x30B9, 0x30D4, 0x30FC, 0x30C9, 0x3067 }; // <sono><supiido><de>
const char *rfc3492_7_R_pc = "d9juau41awczczp";


extern NSStringEncoding _NSCStringEncoding, _NSDefaultStringEncoding;

- (void)setUp
{
    [super setUp];
    
    oldNSCStringEncoding = _NSCStringEncoding;
    oldNSDefaultStringEncoding = _NSDefaultStringEncoding;

    _NSCStringEncoding = NSUTF8StringEncoding;
    _NSDefaultStringEncoding = NSUTF8StringEncoding;
}

- (void)tearDown
{
    _NSCStringEncoding = oldNSCStringEncoding;
    _NSDefaultStringEncoding = oldNSDefaultStringEncoding;
    
    [super tearDown];
}

- (void)testProvincial
{
    const unichar *cases[11] = { rfc3492_7_A, rfc3492_7_B, rfc3492_7_C, rfc3492_7_D, rfc3492_7_E, rfc3492_7_F, rfc3492_7_G, rfc3492_7_H, rfc3492_7_I, rfc3492_7_J, rfc3492_7_K };
    const int caselengths[11] = { sizeof(rfc3492_7_A)/sizeof(unichar), sizeof(rfc3492_7_B)/sizeof(unichar), sizeof(rfc3492_7_C)/sizeof(unichar), sizeof(rfc3492_7_D)/sizeof(unichar), sizeof(rfc3492_7_E)/sizeof(unichar), sizeof(rfc3492_7_F)/sizeof(unichar), sizeof(rfc3492_7_G)/sizeof(unichar), sizeof(rfc3492_7_H)/sizeof(unichar), sizeof(rfc3492_7_I)/sizeof(unichar), sizeof(rfc3492_7_J)/sizeof(unichar), sizeof(rfc3492_7_K)/sizeof(unichar) };
    const char *results[11] = { rfc3492_7_A_pc, rfc3492_7_B_pc, rfc3492_7_C_pc, rfc3492_7_D_pc, rfc3492_7_E_pc, rfc3492_7_F_pc, rfc3492_7_G_pc, rfc3492_7_H_pc, rfc3492_7_I_pc, rfc3492_7_J_pc, rfc3492_7_K_pc };

    int i;
    for(i = 0; i < 11; i++) {
        NSString *intl = [[[NSString alloc] initWithCharacters:cases[i] length:caselengths[i]] autorelease];
        NSString *puny = [NSString stringWithFormat:@"xn--%s", results[i]];
        NSString *puny_out = [ONHost IDNEncodedHostname:intl];
        NSString *intl_out = [ONHost IDNDecodedHostname:puny];
        
        XCTAssertEqualObjects([puny lowercaseString], [puny_out lowercaseString]);
        XCTAssertEqualObjects(intl, intl_out);
        // NSLog(@"%@ <-- %@", puny, intl);
    }
    
    
    NSString *czech = [[NSString alloc] initWithCharacters:rfc3492_7_D length:(sizeof(rfc3492_7_D)/sizeof(unichar))];
    XCTAssertEqualObjects(czech, [ONHost IDNDecodedHostname:@"xn--Proprostnemluvesky-UYB24DMA41A"]);
    // Make the string uppercase, except for the characters which would be IDN-encoded
    NSMutableString *caseSmashed = [[czech uppercaseString] mutableCopy];
    [caseSmashed replaceCharactersInRange:(NSRange){3,1} withString:[czech substringWithRange:(NSRange){3,1}]];
    [caseSmashed replaceCharactersInRange:(NSRange){9,1} withString:[czech substringWithRange:(NSRange){9,1}]];
    [caseSmashed replaceCharactersInRange:(NSRange){16,2} withString:[czech substringWithRange:(NSRange){16,2}]];
    XCTAssertEqualObjects(caseSmashed, [ONHost IDNDecodedHostname:@"XN--PROPROSTNEMLUVESKY-UYB24DMA41A"]);
    [czech release];
    [caseSmashed release];

}

- (void)testJapanesePop
{
    const unichar *cases[7] = { rfc3492_7_L, rfc3492_7_M, rfc3492_7_N, rfc3492_7_O, rfc3492_7_P, rfc3492_7_Q, rfc3492_7_R };
    const int caselengths[7] = { sizeof(rfc3492_7_L)/sizeof(unichar), sizeof(rfc3492_7_M)/sizeof(unichar), sizeof(rfc3492_7_N)/sizeof(unichar), sizeof(rfc3492_7_O)/sizeof(unichar), sizeof(rfc3492_7_P)/sizeof(unichar), sizeof(rfc3492_7_Q)/sizeof(unichar), sizeof(rfc3492_7_R)/sizeof(unichar) };
    const char *results[7] = { rfc3492_7_L_pc, rfc3492_7_M_pc, rfc3492_7_N_pc, rfc3492_7_O_pc, rfc3492_7_P_pc, rfc3492_7_Q_pc, rfc3492_7_R_pc };
    
    int i;
    for(i = 0; i < 7; i++) {
        NSString *intl = [[[NSString alloc] initWithCharacters:cases[i] length:caselengths[i]] autorelease];
        NSString *puny = [NSString stringWithFormat:@"xn--%s", results[i]];
        NSString *puny_out = [ONHost IDNEncodedHostname:intl];
        NSString *intl_out = [ONHost IDNDecodedHostname:puny];
        
        XCTAssertEqualObjects(puny, puny_out);
        XCTAssertEqualObjects(intl, intl_out);
    }
}

- (void)testNormalization
{
    const unichar combiningAccent[] = { 0x0075, 0x0308, 0x0062, 0x0061, 0x0300, 0x0072 };
    const unichar combinedAccent[] = { 0x00FC, 0x0062, 0x00E0, 0x0072 };
    NSString *expectedEncoding = @"xn--br-jia4i";
    NSString *denormalizedEncoding = @"xn--ubar-svc9b";
    
    NSString *uncombined = [[[NSString alloc] initWithCharacters:combiningAccent length:6] autorelease];
    NSString *combined = [[[NSString alloc] initWithCharacters:combinedAccent length:4] autorelease];
    
    XCTAssertTrue([uncombined compare:combined] == NSOrderedSame);
    XCTAssertFalse([uncombined compare:combined options:NSLiteralSearch] == NSOrderedSame);
    
    NSString *encoded = [ONHost IDNEncodedHostname:uncombined];
    XCTAssertEqualObjects(encoded, [ONHost IDNEncodedHostname:combined]);
    XCTAssertEqualObjects(encoded, expectedEncoding);
    XCTAssertFalse([encoded isEqual:denormalizedEncoding]);
    
    NSString *decoded = [ONHost IDNDecodedHostname:encoded];
    XCTAssertEqualObjects(decoded, combined);
    XCTAssertTrue([decoded compare:uncombined options:0] == NSOrderedSame);
    XCTAssertFalse([decoded compare:uncombined options:NSLiteralSearch] == NSOrderedSame);
    
    // verify that we don't accept incorrectly normalized labels
    XCTAssertEqualObjects(denormalizedEncoding, [ONHost IDNDecodedHostname:denormalizedEncoding]);
}

@end


