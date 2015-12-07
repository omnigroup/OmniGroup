// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniBase/macros.h>
#import <OmniBase/rcsid.h>

#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>

#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFSecurityUtilities.h>

RCS_ID("$Id$");

#define DAT(x) [NSData dataWithBytesNoCopy:(x) length:sizeof(x) freeWhenDone:NO]

@interface OFCryptoTests : OFTestCase
@end

@implementation OFCryptoTests

- (void)testKeyWrap;
{
    uint8_t buffer[512];
    
    /* We're just testing Apple's implementation of RFC3394 KeyWrap here, since Apple probably doesn't */
    
    /* Size computation. RFC3394 only operates on whole numbers of 64-bit halfblocks, and the output is always 64 bits (8 bytes) wider than the input. */
    XCTAssertEqual(CCSymmetricWrappedSize(kCCWRAPAES, 16), (size_t)24);
    XCTAssertEqual(CCSymmetricWrappedSize(kCCWRAPAES, 24), (size_t)32);
    XCTAssertEqual(CCSymmetricUnwrappedSize(kCCWRAPAES, 32), (size_t)24);
    XCTAssertEqual(CCSymmetricUnwrappedSize(kCCWRAPAES, 24), (size_t)16);
    
    /* Some test vectors from RFC3394. Apple's tests include these, so they're kind of redundant here, but whatever */
#define TEST_WRAP(fun, inp, outp) { size_t dummy = sizeof(buffer); memset(buffer, '?', sizeof(buffer)); int rv = fun(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen, kek, sizeof(kek), inp, sizeof(inp), buffer, &dummy); XCTAssertEqual(rv, kCCSuccess); XCTAssert(memcmp(buffer, outp, sizeof(outp)) == 0); }
    
    {
        static const uint8_t kek[] = { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F };
        static const uint8_t cek[] = { 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF };
        static const uint8_t wrapped[] = { 0x1F, 0xA6, 0x8B, 0x0A, 0x81, 0x12, 0xB4, 0x47, 0xAE, 0xF3, 0x4B, 0xD8, 0xFB, 0x5A, 0x7B, 0x82, 0x9D, 0x3E, 0x86, 0x23, 0x71, 0xD2, 0xCF, 0xE5 };
        
        TEST_WRAP(CCSymmetricKeyWrap, cek, wrapped);
        TEST_WRAP(CCSymmetricKeyUnwrap, wrapped, cek);
    }
    
    {
        static const uint8_t kek[] = { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F };
        static const uint8_t cek[] = { 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07 };
        static const uint8_t wrapped[] = { 0xA8, 0xF9, 0xBC, 0x16, 0x12, 0xC6, 0x8B, 0x3F, 0xF6, 0xE6, 0xF4, 0xFB, 0xE3, 0x0E, 0x71, 0xE4, 0x76, 0x9C, 0x8B, 0x80, 0xA3, 0x2C, 0xB8, 0x95, 0x8C, 0xD5, 0xD1, 0x7D, 0x6B, 0x25, 0x4D, 0xA1 };
        
        TEST_WRAP(CCSymmetricKeyWrap, cek, wrapped);
        TEST_WRAP(CCSymmetricKeyUnwrap, wrapped, cek);
    }
    
    {
        static const uint8_t kek[] = { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F };
        static const uint8_t cek[] = { 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F };
        static const uint8_t wrapped[] = { 0x28, 0xC9, 0xF4, 0x04, 0xC4, 0xB8, 0x10, 0xF4, 0xCB, 0xCC, 0xB3, 0x5C, 0xFB, 0x87, 0xF8, 0x26, 0x3F, 0x57, 0x86, 0xE2, 0xD8, 0x0E, 0xD3, 0x26, 0xCB, 0xC7, 0xF0, 0xE7, 0x1A, 0x99, 0xF4, 0x3B, 0xFB, 0x98, 0x8B, 0x9B, 0x7A, 0x02, 0xDD, 0x21 };
        
        TEST_WRAP(CCSymmetricKeyWrap, cek, wrapped);
        TEST_WRAP(CCSymmetricKeyUnwrap, wrapped, cek);
    }

    
    /* Verify that Apple's function is actually checking the integrity field / IV --- this is the important part of these tests, since Apple doesn't unit-test this */
    {
        static const uint8_t kek[] = { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F };
        
        /* A garbled wrapped value */
        static const uint8_t wrapped1[] = { 0x1F, 0xA6, 0x8B, 0x0A, 0x81, 0x12, 0xB4, 0x46, 0xAE, 0xF3, 0x4B, 0xD8, 0xFB, 0x5A, 0x7B, 0x82, 0x9D, 0x3E, 0x86, 0x23, 0x71, 0xD2, 0xCF, 0xE5 };
        
        size_t dummy = sizeof(buffer);
        int rv = CCSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen, kek, sizeof(kek), wrapped1, sizeof(wrapped1), buffer, &dummy);
        XCTAssertNotEqual(rv, kCCSuccess);
        
        /* A wrapped value encrypted with a different IV */
        static const uint8_t wrapped2[] = { 0xEB, 0xBB, 0x15, 0x88, 0x2, 0xE9, 0x75, 0xE2, 0x3F, 0xB6, 0xAE, 0x0, 0x7F, 0x37, 0x83, 0x55, 0xF6, 0x13, 0xF4, 0x5E, 0x8A, 0x1F, 0x25, 0x6A };
        
        dummy = sizeof(buffer);
        rv = CCSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen, kek, sizeof(kek), wrapped2, sizeof(wrapped2), buffer, &dummy);
        XCTAssertNotEqual(rv, kCCSuccess);
    }

    /* Note that CCSymmetricKeyUnwrap() does not check for output buffer overrun in CommonCrypto-60061 -- in the released code, the overrun check is commented out (probably because it is wrong: they swapped <= and >= ). Not even bothering to file a RADAR on that one... they don't even look at ivLen at all, either...*/

}

static void fpstr(NSString *s, FILE *fp)
{
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    fwrite([d bytes], [d length], 1, fp);
}

- (void)testRSAPSS;
{
    NSData *spki = nil;
    SecKeyRef publicKey, privateKey;
    unsigned keySize = 2048;
    NSData *d;
    NSError * __autoreleasing error;
    
    
    FILE *fp = fopen("/tmp/keez", "w");
    
    for (int ki = 0; ki < 16; ki ++) {
    
#if !TARGET_OS_IPHONE
    {
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        OSStatus oserr;
        
        [attributes setObject:[NSNumber numberWithUnsignedInt:keySize] forKey:(__bridge NSString *)kSecAttrKeySizeInBits];
        [attributes setObject:(__bridge id)kSecAttrKeyTypeRSA forKey:(__bridge NSString *)kSecAttrKeyType];
        [attributes setObject:@"OFUnitTests tests key" forKey:(__bridge NSString *)kSecAttrLabel];
        [attributes setObject:(__bridge id)kCFBooleanFalse forKey:(__bridge NSString *)kSecAttrIsPermanent];
        
        publicKey = privateKey = NULL;
        oserr = SecKeyGeneratePair((__bridge CFDictionaryRef)attributes, &publicKey, &privateKey);
        XCTAssertEqual(oserr, noErr);
        if (oserr != noErr)
            continue;
        XCTAssertNotEqual(publicKey, NULL);
        XCTAssertNotEqual(privateKey, NULL);
        
        CFDataRef publicKeyInfo = NULL;
        oserr = SecItemExport(publicKey, kSecFormatOpenSSL /* "OpenSSL" means an X.509 PublicKeyInformation structure */,
                              0 /* flags */,
                              NULL /* parameter block */,
                              &publicKeyInfo);
        XCTAssertEqual(oserr, noErr);
        
        spki = (__bridge_transfer NSData *)publicKeyInfo;
    };
#else
    {
        publicKey = privateKey = NULL;
        spki = nil;
        BOOL ok = OFSecKeyGeneratePairAndInfo(ka_RSA, keySize, YES, nil, &spki, &privateKey, &error);
        XCTAssertTrue(ok);
    }
#endif
    
    fputs("-----BEGIN PUBLIC KEY-----\n", fp);
    d = [spki base64EncodedDataWithOptions:NSDataBase64Encoding64CharacterLineLength];
    fwrite([d bytes], [d length], 1, fp);
    fputs("\n-----END PUBLIC KEY-----\n\n\n", fp);
    
    
    for(int s = 0; s < 128; s ++) {
        
        fprintf(fp, "\nIteration %d:\n", s);
        NSMutableString *log = [NSMutableString string];
        
        NSString *cn = [NSString stringWithFormat:@"Test req #%d", s];
        NSData *derName = OFASN1AppendStructure(nil, "({(dd)})",
                                                OFASN1OIDFromString(@"2.5.4.3"),
                                                OFASN1EnDERString(cn));
        
        NSData *gen = OFGenerateCertificateRequest(derName, spki, privateKey, nil, log, &error);
        XCTAssertNotNil(gen);
        
        fpstr(log, fp);
        
        fputs("\n-----BEGIN CERTIFICATE REQUEST-----\n", fp);
        d = [gen base64EncodedDataWithOptions:NSDataBase64Encoding64CharacterLineLength];
        fwrite([d bytes], [d length], 1, fp);
        fputs("\n-----END CERTIFICATE REQUEST-----\n\n", fp);
    }
    
    /* See RADAR 23003343 / 8820424 for why we have to do this */
#if TARGET_OS_IPHONE
    {
        NSMutableArray *deleteMe = [NSMutableArray array];
        if (publicKey) [deleteMe addObject:(__bridge id)(publicKey)];
        [deleteMe addObject:(__bridge id)(privateKey)];
        SecItemDelete( (__bridge CFDictionaryRef)@{ (__bridge id)kSecMatchItemList: deleteMe });
    }
#else
    if (publicKey) SecKeychainItemDelete((SecKeychainItemRef)publicKey);
    SecKeychainItemDelete((SecKeychainItemRef)privateKey);
#endif
        
    if (publicKey) CFRelease(publicKey);
    CFRelease(privateKey);
    }
    
    fclose(fp);

}

@end


@interface OFASN1Tests : OFTestCase
@end

@implementation OFASN1Tests : OFTestCase

- (void)testSimpleDER;
{
    static uint8_t id_rsaEncryption_der[]  = {             0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01 };  /* RFC 2313 aka PKCS#1 - 1.2.840.113549.1.1.1 */
    static uint8_t oid_rsaEncryption_der[] = { 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01 };  /* RFC 2313 aka PKCS#1 - 1.2.840.113549.1.1.1 */

    XCTAssertEqualObjects(OFASN1DescribeOID(id_rsaEncryption_der, sizeof(id_rsaEncryption_der)), @"1.2.840.113549.1.1.1");
    XCTAssertEqualObjects(DAT(oid_rsaEncryption_der), OFASN1OIDFromString(@"1.2.840.113549.1.1.1"));
    
    static uint8_t s0[] = { 0x13, 0x02, 0x55, 0x53 };  /* PRINTABLESTRING */
    static uint8_t s1[] = { 0x0c, 0x0e, 0x54, 0x68, 0x65, 0x20, 0x4f, 0x6d, 0x6e, 0x69, 0x20, 0x47, 0x72, 0x6f, 0x75, 0x70 }; /* UTF8STRING */
    
    XCTAssertEqualObjects(OFASN1UnDERString(DAT(s0)), @"US");
    XCTAssertEqualObjects(OFASN1UnDERString(DAT(s1)), @"The Omni Group");
    
    static uint8_t vx[] = { 'f', 'o', 'o', 'b', 'a', 'r' };
    NSData *r = OFASN1AppendStructure(nil, "(d*<d>)",
                                      DAT(oid_rsaEncryption_der),
                                      sizeof(s0), s0,
                                      DAT(vx));
    static uint8_t expected[] = {
        0x30, 0x18,
        0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
        0x13, 0x02, 'U', 'S',
        0x03, 0x07, 0x00, 'f', 'o', 'o', 'b', 'a', 'r'
    };
    XCTAssertEqualObjects(r, DAT(expected));
}

- (void)_checkRDN:(NSData *)rdn expecting:(NSArray *)expected;
{
    NSUInteger __block pos = 0;
    XCTAssertTrue(OFASN1EnumerateAVAsInName(rdn, ^(NSData *att, NSData *val, unsigned ix, BOOL *stop) {
        NSArray *ava = [expected objectAtIndex:pos];
        XCTAssertEqualObjects(OFASN1DescribeOID([att bytes], [att length]), [ava objectAtIndex:0]);
        XCTAssertEqualObjects(OFASN1UnDERString(val), [ava objectAtIndex:1]);
        XCTAssertEqual(ix, 0u);
        pos ++;
    }));
    XCTAssertEqual(pos, [expected count]);
}

- (void)testPKIXParse;
{
    NSData *cert = [[NSData alloc] initWithBase64EncodedString:@"MIIEIzCCAwugAwIBAgIBGTANBgkqhkiG9w0BAQUFADBiMQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBwbGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwHhcNMDgwMjE0MTg1NjM1WhcNMTYwMjE0MTg1NjM1WjCBljELMAkGA1UEBhMCVVMxEzARBgNVBAoMCkFwcGxlIEluYy4xLDAqBgNVBAsMI0FwcGxlIFdvcmxkd2lkZSBEZXZlbG9wZXIgUmVsYXRpb25zMUQwQgYDVQQDDDtBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9ucyBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMo4VKbLVqrIJDlI6Yzu7F+4fyaRvDRTes58Y4Bhd2RepQcjtjn+UC0VVlhwLX7EbsFKhT4v8N6EGqFXya97GP9q+hUSSRUIGayq2yoy7ZZjaFIVPYyK7L9rGJXgA6wBfZcFZ84OhZU3au0Jtq5nzVFkn8Zc0bxXbmc1gHY2pIeBbjiP2CsVTnsl2Fq/ToPBjdKT1RpxtWCcnTNOVfkSWAyGuBYNweV3RY1QSLorLeSUheHoxJ3GaKWwo/xnfnC6AllLd0KRObn1zeFM78A7SIym5SFd/Wpqu6cWNWDS5q3zRinJ6MOL6XnAamFnFbLw/eVovGJfbs+Z3e8bY/6SZasCAwEAAaOBrjCBqzAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUiCcXCam2GGCL7Ou69kdZxVJUo7cwHwYDVR0jBBgwFoAUK9BpR5R2Cf70a40uQKb3R01/CF4wNgYDVR0fBC8wLTAroCmgJ4YlaHR0cDovL3d3dy5hcHBsZS5jb20vYXBwbGVjYS9yb290LmNybDAQBgoqhkiG92NkBgIBBAIFADANBgkqhkiG9w0BAQUFAAOCAQEA2jIAlsVUlNM7gjdmfS5o1cPGuMsmjEiQzxMkakaOY9Tw0BMG3djEwTcV8jMTOSYtzi5VQOMLA6/6EsLnDSG41YDPrCgvzi2zTq+GGQTG6VDdTClHECP8bLsbmGtIieFbnd5G2zWFNe8+0OJYSzj07XVaH1xwHVY5EuXhDRHkiSUGvdW0FY5e0FmXkOlLgeLfGK9EdB4ZoDpHzJEdOusjWv6lLZf3e7vWh0ZChetSPSayY6i0scqP9Mzis8hH4L+aWYP62phTKoL1fGUuldkzXfXtZcwxN8VaBOhr4eeIA0p1npsoy0pAiGVDdd3LOiUjxZ5X+C7O0qmSXnMuLyV1FQ=="
                                                       options:0];
    
    NSData * __autoreleasing sn;
    NSData * __autoreleasing issu;
    NSData * __autoreleasing subj;
    NSData * __autoreleasing spki;
    int rv = OFASN1CertificateExtractFields(cert, &sn, &issu, &subj, &spki, ^(NSData *oid, BOOL crit, NSData *v){
        /* nothing yet */
    });
    XCTAssertEqual(rv, 0);
    
    static uint8_t serial25[] = { 0x19 };
    XCTAssertEqualObjects(sn, DAT(serial25));

    [self _checkRDN:subj
          expecting:@[
                      @[ @"2.5.4.6", @"US"],
                      @[ @"2.5.4.10", @"Apple Inc."],
                      @[ @"2.5.4.11", @"Apple Worldwide Developer Relations"],
                      @[ @"2.5.4.3", @"Apple Worldwide Developer Relations Certification Authority"]
                      ]];
    
    [self _checkRDN:issu
          expecting:@[
                      @[ @"2.5.4.6", @"US"],
                      @[ @"2.5.4.10", @"Apple Inc."],
                      @[ @"2.5.4.11", @"Apple Certification Authority"],
                      @[ @"2.5.4.3", @"Apple Root CA"]
                      ]];

    unsigned int keySize = 0;
    XCTAssertEqual(OFASN1KeyInfoGetAlgorithm(spki, &keySize, NULL), ka_RSA);
    XCTAssertEqual(keySize, 2048u);
    
    cert = [[NSData alloc] initWithBase64EncodedString:@"MIIB/TCCAaWgAwIBAgICAP8wCQYHKoZIzj0EATBgMQswCQYDVQQGEwJBVTETMBEGA1UECAwKU29tZS1TdGF0ZTEhMB8GA1UECgwYSW50ZXJuZXQgV2lkZ2l0cyBQdHkgTHRkMRkwFwYDVQQDDBBFbGxpcHNlIG9mIEJsaXNzMB4XDTE1MDExMzAxNTE1NFoXDTE1MDIxMjAxNTE1NFowYDELMAkGA1UEBhMCQVUxEzARBgNVBAgMClNvbWUtU3RhdGUxITAfBgNVBAoMGEludGVybmV0IFdpZGdpdHMgUHR5IEx0ZDEZMBcGA1UEAwwQRWxsaXBzZSBvZiBCbGlzczBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABOyIAG00b6CpUu+G1Kghyunq7nj4VRSoZohJ6hbq8xxTqWdSuOkFS0MaE0NLujhhRpkGY0xuQIpM+9KutGXXs7ejUDBOMB0GA1UdDgQWBBRXEUZVSKKGOSTClw2icZdYkrNAJTAfBgNVHSMEGDAWgBRXEUZVSKKGOSTClw2icZdYkrNAJTAMBgNVHRMEBTADAQH/MAkGByqGSM49BAEDRwAwRAIhALlHlYC3dJS30I2el7mKbOFymAebQc/b/2Okld5jh5abAh8TTbad3Xfzfp6mt8VUAFKoz1mWgE8RU3EcpDfUiPKW" options:0];
    
    rv = OFASN1CertificateExtractFields(cert, &sn, &issu, &subj, &spki, ^(NSData *oid, BOOL crit, NSData *v){
        /* nothing yet */
    });
    XCTAssertEqual(rv, 0);
    
    static uint8_t serial255[] = { 0x00, 0xFF };
    XCTAssertEqualObjects(sn, DAT(serial255));
    
    [self _checkRDN:subj
          expecting:@[
                      @[ @"2.5.4.6", @"AU"],
                      @[ @"2.5.4.8", @"Some-State"],
                      @[ @"2.5.4.10", @"Internet Widgits Pty Ltd"],
                      @[ @"2.5.4.3", @"Ellipse of Bliss"]
                      ]];
    XCTAssertEqualObjects(subj, issu);
    
    keySize = 0;
    XCTAssertEqual(OFASN1KeyInfoGetAlgorithm(spki, &keySize, NULL), ka_EC);
    XCTAssertEqual(keySize, 256u);
}

#if !TARGET_OS_IPHONE

static NSData *OFPKCS7PluckContents(NSData *pkcs7)
{
    CMSDecoderRef decoder = NULL;
    
    CMSDecoderCreate(&decoder);
    [pkcs7 enumerateByteRangesUsingBlock:^(const void *bytes, NSRange brange, BOOL *stop){
        CMSDecoderUpdateMessage(decoder, bytes, brange.length);
    }];
    CMSDecoderFinalizeMessage(decoder);
    
    CFDataRef result = NULL;
    
    CMSDecoderCopyContent(decoder, &result);
    
    CFRelease(decoder);
    
    return (__bridge_transfer NSData *)result;
}

#endif

- (void)_parseRecipt:(NSString *)b64;
{
    NSData *reciept = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    NSData *atts = OFPKCS7PluckContents(reciept);
    NSLog(@"atts = %@", atts);
    
    if (atts) {
        OFASN1EnumerateAppStoreReceiptAttributes(atts, ^(int tp, int v, NSRange p){
            NSLog(@"  Att % 4d: [v%d] = %@", tp, v, [atts subdataWithRange:p]);
        });
    }
}

- (void)testAppRcptParse;
{
    [self _parseRecipt:@"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"];
     
    [self _parseRecipt:@"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"];
    
     [self _parseRecipt:@"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"];
}

@end
