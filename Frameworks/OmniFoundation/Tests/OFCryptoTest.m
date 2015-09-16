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

#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFSecurityUtilities.h>
#import <OmniFoundation/OFCertificateRequest.h>

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
    unsigned keySize = 2049;
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
        [attributes setObject:(__bridge id)kCFBooleanFalse forKey:(__bridge NSString *)kSecAttrIsPermanent];
        
        publicKey = privateKey = NULL;
        oserr = SecKeyGeneratePair((__bridge CFDictionaryRef)attributes, &publicKey, &privateKey);
        XCTAssertEqual(oserr, noErr);
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
        BOOL ok = OFSecKeyGeneratePairAndInfo(ka_RSA, keySize, YES, &spki, &privateKey, &error);
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

@end
