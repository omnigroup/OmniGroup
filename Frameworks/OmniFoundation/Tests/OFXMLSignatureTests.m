// Copyright 2009-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import "OFTestCase.h"

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFXMLSignature.h>
#import <OmniFoundation/OFCDSAUtilities.h>
#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFSecurityUtilities.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <Security/Security.h>

RCS_ID("$Id$");

NSString *phaosDocsDir, *merlinDocsDir;
NSString *testKeychainPath;

enum TestKeyType {
    TestKeyType_RSA,
    TestKeyType_DSA,
    TestKeyType_ECDSA
};

static Boolean generateTestKey(SecKeychainRef intoKeychain, SecAccessRef initialAccess, enum TestKeyType keytype, unsigned int keybits, CFErrorRef *outError);
static SecKeyRef copyKeyFromKeychain(SecKeychainRef keychain, xmlNode *signatureMethod, enum OFXMLSignatureOperation op, NSError **outError);

#define FailedForWrongReason(e) XCTFail(@"Failed for wrong reason: %@ / %@", [error description], [[error userInfo] description]);

@interface OFXMLSignatureTests_Abstract : OFTestCase
{
    NSString *docName;
    xmlDoc *loadedDoc;
}

@end

@interface OFXMLSignatureTest : OFXMLSignature
{
    enum testKeySources {
        noKeyAvailable,
        keyFromEmbeddedCertificate,
        keyFromEmbeddedValues,
        keyFromExternalCertificate,
        keyIsOnlyApplicableOneInKeychain,
        keyIsHMACTest,
        keyIsHMACSecret,
        keyIsHMACBogus,
    } keySource;
    
    CFArrayRef externalCerts;
    SecKeychainRef forcedKeychain;
}

- (void)setKeySource:(enum testKeySources)s;
- (void)loadExternalCerts:(NSString *)fromDir;
- (void)setKeychain:(SecKeychainRef)kc;

@end

@implementation OFXMLSignatureTest

- (void)dealloc
{
    if (externalCerts) {
        CFRelease(externalCerts);
    }
    if (forcedKeychain) {
        CFRelease(forcedKeychain);
    }
}

- (void)setKeySource:(enum testKeySources)s;
{
    keySource = s;
}

- (void)setKeychain:(SecKeychainRef)kc;
{
    if (kc)
        CFRetain(kc);
    if (forcedKeychain)
        CFRelease(forcedKeychain);
    forcedKeychain = kc;
}

- (void)loadExternalCerts:(NSString *)fromDir
{
    CFMutableArrayRef certs = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    
    NSFileManager *fm = [NSFileManager defaultManager];
    OFForEachInArray([fm contentsOfDirectoryAtPath:fromDir error:NULL], NSString *, fn, {
        
        // RADAR 7514859, 10057193: You can pass an improperly-formatted item to SecCertificateCreateWithData and it will happily return a non-NULL cert which behaves normally in some ways, fails if you do some things, and segfaults if you do other things. Anyway, we know that these files are not valid certs, so we skip them.
        if ([fn isEqualToString:@"crl.der"] || [fn hasSuffix:@"-key.der"])
            continue;
        
        if ([fn hasSuffix:@".crt"] || [fn hasSuffix:@".der"]) {
            NSError *readError = NULL;
            NSData *derData = [NSData dataWithContentsOfFile:[fromDir stringByAppendingPathComponent:fn] options:0 error:&readError];
            if (!derData) {
                NSLog(@"*** Could not load cert from %@: %@", fn, readError);
                continue;
            }
            SecCertificateRef oneCert = SecCertificateCreateWithData(kCFAllocatorDefault, (__bridge CFDataRef)derData);
            if (oneCert != NULL) {
                CFArrayAppendValue(certs, oneCert);
                CFRelease(oneCert);
            } else {
                // RADAR 10057193: There's no way to know why SecCertificateCreateWithData() failed.
                NSLog(@"*** Could not load cert from %@: SecCertificateCreateFromData returns NULL", fn);
            }
        }
    });

    // NSLog(@"Certs from %@ -> %@", fromDir, [(id) certs description]);
    
    if (externalCerts)
        CFRelease(externalCerts);
    externalCerts = certs;
}

static BOOL ofErrorFromOSError(NSError **outError, OSStatus oserr, NSString *function, NSDictionary *args)
{
    if (outError) {
        NSDictionary *userInfo;
        NSString *keys[2] = { @"function", @"arguments" };
        id values[2];
        values[0] = function;
        values[1] = args;
        if (args)
            userInfo = [NSDictionary dictionaryWithObjects:values forKeys:keys count:2];
        else
            userInfo = [NSDictionary dictionaryWithObjects:values forKeys:keys count:1];
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:oserr userInfo:userInfo];
    }
    return NO;
}

- (SecKeyRef)copySecKeyForMethod:(xmlNode *)signatureMethod keyInfo:(xmlNode *)keyInfo operation:(enum OFXMLSignatureOperation)op error:(NSError **)outError;
{
#if !OFXMLSigGetKeyAsCSSM
    unsigned int count;

    NSMutableDictionary *keyAttributes = [NSMutableDictionary dictionary];
    if (!OFXMLSigGetKeyAttributes(keyAttributes, signatureMethod, op))
        keyAttributes = nil;

    if (keySource == keyFromEmbeddedValues) {
        xmlNode *keyvalue = OFLibXMLChildNamed(keyInfo, "KeyValue", XMLSignatureNamespace, &count);
        if (count == 1 && keyAttributes != nil) {
            NSString *keytype = [keyAttributes objectForKey:(id)kSecAttrKeyType];
            if ([keytype isEqual:(id)kSecAttrKeyTypeDSA])
                return OFXMLSigCopyKeyFromDSAKeyValue(keyvalue, outError);
            if ([keytype isEqual:(id)kSecAttrKeyTypeRSA])
                return OFXMLSigCopyKeyFromRSAKeyValue(keyvalue, outError);
            if ([keytype isEqual:(id)kSecAttrKeyTypeECDSA]) {
                int sigorder = -1;
                SecKeyRef retval = OFXMLSigCopyKeyFromEllipticKeyValue(keyvalue, &sigorder, outError);
                OBASSERT(sigorder > 0);
                return retval;
            }
        }
    }
    
    if (keySource == keyIsHMACTest) {
        return OFXMLSigCopyKeyFromHMACKey([keyAttributes objectForKey:(id)kSecDigestTypeAttribute], (const uint8_t *)"test", 4, outError);
    } else if (keySource == keyIsHMACBogus) {
        return OFXMLSigCopyKeyFromHMACKey([keyAttributes objectForKey:(id)kSecDigestTypeAttribute], (const uint8_t *)"bogus", 5, outError);
    } else if (keySource == keyIsHMACSecret) {
        return OFXMLSigCopyKeyFromHMACKey([keyAttributes objectForKey:(id)kSecDigestTypeAttribute], (const uint8_t *)"secret", 6, outError);
    }

#endif
    
    if (keySource == keyIsOnlyApplicableOneInKeychain) {
        return copyKeyFromKeychain(forcedKeychain, signatureMethod, op, outError);
    }
    
    if (keySource == keyFromEmbeddedCertificate || keySource == keyFromExternalCertificate) {
        CFMutableArrayRef availableCerts;
        
        if (keySource == keyFromExternalCertificate && externalCerts != NULL) {
            availableCerts = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, externalCerts);
        } else {
            availableCerts = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
        }
        
        NSArray *certs = OFXMLSigFindX509Certificates(keyInfo, availableCerts, nil);
        // NSLog(@"avail = %@\ngot = %@", availableCerts, certs);
        CFRelease(availableCerts);
        
        if ([certs count] == 1) {
            SecCertificateRef cert = (__bridge void *)[certs objectAtIndex:0];
            SecKeyRef pubkey = NULL;
            OSStatus oserr = SecCertificateCopyPublicKey(cert, &pubkey);
            if (oserr != noErr) {
                ofErrorFromOSError(outError, oserr, @"SecCertificateCopyPublicKey", nil);
                return NULL;
            }
            return pubkey;
        }
    }
    
    return [super copySecKeyForMethod:signatureMethod keyInfo:keyInfo operation:op error:outError];
    
}

#if OF_ENABLE_CDSA

/* -newVerificationContextForMethod:keyInfo:operation:error: will call this if the CDSA APIs are available */
- (OFCSSMKey *)getCSSMKeyForMethod:(xmlNode *)signatureMethod keyInfo:(xmlNode *)keyInfo operation:(enum OFXMLSignatureOperation)op error:(NSError **)outError;
{
#if OFXMLSigGetKeyAsCSSM
    CSSM_ALGORITHMS keytype = OFXMLCSSMKeyTypeForAlgorithm(signatureMethod);
    if (keySource == keyFromEmbeddedValues) {
        unsigned int count;
        xmlNode *keyvalue = OFLibXMLChildNamed(keyInfo, "KeyValue", XMLSignatureNamespace, &count);
        if (count == 1) {
            if (keytype == CSSM_ALGID_DSA)
                return OFXMLSigGetKeyFromDSAKeyValue(keyvalue, outError);
            if (keytype == CSSM_ALGID_RSA)
                return OFXMLSigGetKeyFromRSAKeyValue(keyvalue, outError);
            if (keytype == CSSM_ALGID_ECDSA) {
                int sigorder = -1;
                return OFXMLSigGetKeyFromEllipticKeyValue(keyvalue, &sigorder, outError);
            }
        }
    }
#endif
    
    NSData *keyData;  /* HMAC key bytes */
    if (keySource == keyIsHMACTest) {
        keyData = [NSData dataWithBytesNoCopy:"test" length:4 freeWhenDone:NO];
    } else if (keySource == keyIsHMACBogus) {
        keyData = [NSData dataWithBytesNoCopy:"bogus" length:5 freeWhenDone:NO];
    } else if (keySource == keyIsHMACSecret) {
        keyData = [NSData dataWithBytesNoCopy:"secret" length:6 freeWhenDone:NO];
    } else {
        return [super getCSSMKeyForMethod:signatureMethod keyInfo:keyInfo operation:op error:outError];
    }
    
    OFCSSMKey *key = [[OFCSSMKey alloc] initWithCSP:[OFCDSAModule appleCSP]];
    [key autorelease];
    
    CSSM_KEYHEADER keyHeader = { 0 };
    
    keyHeader.HeaderVersion = CSSM_KEYHEADER_VERSION;
    keyHeader.CspId = gGuidAppleCSP;
    keyHeader.BlobType = CSSM_KEYBLOB_RAW;
    keyHeader.Format = CSSM_KEYBLOB_RAW_FORMAT_OCTET_STRING;
    keyHeader.AlgorithmId = keytype;
    keyHeader.KeyClass = CSSM_KEYCLASS_SESSION_KEY;
    keyHeader.KeyAttr = CSSM_KEYATTR_SENSITIVE;
    keyHeader.KeyUsage = CSSM_KEYUSE_VERIFY | CSSM_KEYUSE_SIGN;
    keyHeader.LogicalKeySizeInBits = 8 * (uint32)[keyData length];
    
    [key setKeyHeader:&keyHeader data:keyData];
    
    return key;
}

#endif

- (BOOL)writeReference:(NSString *)externalReference type:(NSString *)referenceType to:(xmlOutputBuffer *)stream error:(NSError **)outError;
{
    if (![OFTestCase shouldRunSlowUnitTests])
        return [super writeReference:externalReference type:referenceType to:stream error:outError];
        
    NSURL *refURL;
    
    if ([NSString isEmptyString:externalReference] || !(refURL = [NSURL URLWithString:externalReference])) {
        if (outError)
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationFailure userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Invalid URI \"%@\"", externalReference] forKey:NSLocalizedDescriptionKey]];
        return NO;
    }
    
    NSLog(@"   Retrieving external reference <%@>", [refURL absoluteString]);
    
    NSData *remoteData = [NSData dataWithContentsOfURL:refURL options:0 error:outError];
    if (!remoteData)  // -dataWithContentsOfURL: will have filled *outError for us
        return NO;
    
#ifdef DEBUG_XMLSIG_TESTS
    NSLog(@"Retrieved %u bytes from %@", (unsigned int)[remoteData length], refURL);
#endif
    
    OBASSERT([remoteData length] < INT_MAX);
    int xmlOk = xmlOutputBufferWrite(stream, (int)[remoteData length], [remoteData bytes]);
    
    if (xmlOk < 0) {
        if (outError)
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationFailure userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Failed to process retrieved data"] forKey:NSLocalizedDescriptionKey]];
        return NO;
    }
    
    return YES;
}


@end

@implementation OFXMLSignatureTests_Abstract

+ (NSString *)unpackedArchive:(NSString *)rsrcName nickname:(NSString *)nick;
{
    NSString *srcBundle = [[NSBundle bundleForClass:self] pathForResource:rsrcName ofType:nil];
    if (!srcBundle) {
        [NSException raise:NSGenericException format:@"Can't find resource \"%@\"", rsrcName];
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSString *tmpl = [NSTemporaryDirectory() stringByAppendingPathComponent:[nick stringByAppendingString:@"#"]];
    NSString *destDir = [fm tempFilenameFromTemplate:tmpl andRange:(NSRange){.location = [tmpl length]-1, .length = 1}];

    NSError *err = nil;
    if (![fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:&err]) {
        [NSException raise:NSGenericException format:@"Unable to create temp dir %@: %@", destDir, [err description]];
    }
    
    NSLog(@"Unpacking %@ into temporary directory...", rsrcName);
    NSString *cmd;
    if ([[srcBundle pathExtension] isEqual:@"zip"]) {
        cmd = [NSString stringWithFormat:@"unzip -bq '%@' -d '%@'", srcBundle, destDir];
    } else if ([srcBundle hasSuffix:@".tar.gz"]) {
        cmd = [NSString stringWithFormat:@"tar x -C '%@' -f '%@'", destDir, srcBundle];
    } else {
        OBRejectInvalidCall(self, _cmd, @"Unknown file extension?");
    }
    
    int e = system([cmd cStringUsingEncoding:NSUTF8StringEncoding]);
    if (e) {
        [NSException raise:NSGenericException format:@"system('%@') returned %d", cmd, e];
    }

    return destDir;
}

- (NSString *)baseDir;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSArray *)getSigs:(NSString *)tcName;
{
    if (loadedDoc != NULL && [tcName isEqualToString:docName]) {
        return [OFXMLSignatureTest signaturesInTree:loadedDoc]; 
    }
    
    NSString *path = [[self baseDir] stringByAppendingPathComponent:tcName];
    if (![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
        [NSException raise:NSGenericException format:@"No testcase input found at '%@' !", path];
    }
    
    if (loadedDoc != NULL) {
        xmlFreeDoc(loadedDoc);
        loadedDoc = NULL;
    }
    
    const char *pathString = [path fileSystemRepresentation];
    loadedDoc = xmlReadFile(pathString, "UTF-8",  XML_PARSE_NONET);
    if (!loadedDoc) {
        [NSException raise:NSGenericException format:@"xmlReadFile() failed to read '%@' !", path];
    }
    
    docName = [tcName copy];

    return [OFXMLSignatureTest signaturesInTree:loadedDoc]; 
}

- (void)checkReferences:(OFXMLSignature *)sig
{
    NSUInteger num = [sig countOfReferenceNodes];
    for(NSUInteger n = 0; n < num; n ++) {
        if (![sig isLocalReferenceAtIndex:n] && ![[self class] shouldRunSlowUnitTests]) {
            NSLog(@"SKIPPING test of ref %lu (count=%lu) of %@: is an external reference. (setenv RunSlowUnitTests to enable)",
                  n, num, docName);
            continue;
        }
        
        NSError *failWhy = nil;
        BOOL didVerify = [sig verifyReferenceAtIndex:n toBuffer:NULL error:&failWhy];
        XCTAssertTrue(didVerify, @"Verification of reference digest");
        if (didVerify) {
            NSLog(@"-> Ref %lu of %@ passed", n, docName);
        } else {
            NSLog(@" -verifyReferenceAtIndex:%lu returned error: %@ : %@", n, [failWhy description], [[failWhy userInfo] description]);
        }
    }
}

- (void)tearDown
{
    if (loadedDoc != NULL) {
        xmlFreeDoc(loadedDoc);
        loadedDoc = NULL;
    }
    
    [super tearDown];
}

@end

/* When checking a signature that is incorrect but syntactically valid, we want to make sure we fail for the right reason. (Otherwise we'll falsely pass tests which fail due to bugs in OSX's crypto API.) */
static BOOL isExpectedBadSignatureError(NSError *error)
{
    if ([[error domain] isEqual:OFXMLSignatureErrorDomain] &&
        [error code] == OFXMLSignatureValidationFailure &&
        [[error userInfo] objectForKey:NSUnderlyingErrorKey] != nil)
        error = [[error userInfo] objectForKey:NSUnderlyingErrorKey];
    
    NSString *domain = [error domain];
    NSInteger code = [error code];
#if OF_ENABLE_CDSA
    if ([domain isEqual:NSOSStatusErrorDomain] || [domain isEqual:OFCDSAErrorDomain]) {
        if (code == CSSMERR_CSP_VERIFY_FAILED) /* CSSM_VerifyDataFinal returns this */
            return YES;
    }
#endif
    /* OFCCDigestContext doesn't have a specific error code */
    /* SecVerifyTransform doesn't have a specific error code */
    if ([domain isEqual:OFXMLSignatureErrorDomain] &&
        code == OFXMLSignatureValidationFailure &&
        [[error userInfo] objectForKey:NSUnderlyingErrorKey] == nil) {
        return YES;
    }
    
    /* Some other kind of error */
    return NO;
}


@interface OFXMLSignatureTests_Merlin : OFXMLSignatureTests_Abstract
@end
@implementation OFXMLSignatureTests_Merlin

+ (void)setUp;
{
    if (!merlinDocsDir)
        merlinDocsDir = [[self unpackedArchive:@"01-merlin-xmldsig-twenty-three.tar.gz" nickname:@"merlin"] copy];
}

+ (void)tearDown;
{
    if (merlinDocsDir) {
        NSLog(@"Removing scratch directory %@", merlinDocsDir);
        [[NSFileManager defaultManager] removeItemAtPath:merlinDocsDir error:NULL];
        merlinDocsDir = nil;
    }
}

- (NSString *)baseDir;
{
    return [merlinDocsDir stringByAppendingPathComponent:@"merlin-xmldsig-twenty-three"];
}

- (void)testDSAEnveloped;
{
    NSArray *sigs = [self getSigs:@"signature-enveloped-dsa.xml"];
    NSError *error;
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
}

- (void)testEnvelopingVarious;
{
    NSArray *sigs;
    NSError *error;
    
    sigs = [self getSigs:@"signature-enveloping-dsa.xml"];
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    sigs = [self getSigs:@"signature-enveloping-rsa.xml"];
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    sigs = [self getSigs:@"signature-enveloping-hmac-sha1.xml"];
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACSecret]);
#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7
    NSLog(@"SKIPPING HMAC tests on Lion (RADAR 10424173 et al.)");
#else    
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
#endif
    
    sigs = [self getSigs:@"signature-enveloping-b64-dsa.xml"];
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
}

- (void)testExternalVarious;
{
    NSArray *sigs;
    NSError *error;
    
    sigs = [self getSigs:@"signature-external-b64-dsa.xml"];
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    sigs = [self getSigs:@"signature-external-dsa.xml"];
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);    
}

- (void)testCertReferences;
{
    NSArray *sigs;
    NSError *error;
    
    sigs = [self getSigs:@"signature-x509-ski.xml"];
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromExternalCertificate]);
    [[sigs objectAtIndex:0] loadExternalCerts:[[self baseDir] stringByAppendingPathComponent:@"certs"]];
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    
}

- (void)testCertEmbedded;
{
    NSArray *sigs;
    NSError *error;
    
    sigs = [self getSigs:@"signature-x509-crt.xml"];
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    
    sigs = [self getSigs:@"signature-x509-crt-crl.xml"];
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
}

/*
 The following cases from this test suite aren't checked:
 
 signature-enveloping-hmac-sha1-40.xml
    - Apple CDSA implementation doesn't trivially support truncated HMACs, and I have no need for this so I didn't implement it myself.
 
 signature-keyname.xml
 signature-retrievalmethod-rawx509crt.xml
    - I've had no need for these key retrieval methods.
 
 signature.xml
 signature-x509-is.xml
 signature-x509-sn.xml
    - We don't parse and match DNs from <X509SubjectName> or <X509IssuerSerial>. (Unfortunately in the case of signature.xml this means we also don't get coverage of a few other cases that file would exercise.)
 */ 

@end


@interface OFXMLSignatureTests_Phaos : OFXMLSignatureTests_Abstract
@end
@implementation OFXMLSignatureTests_Phaos

+ (void)setUp;
{
    if (!phaosDocsDir)
        phaosDocsDir = [[self unpackedArchive:@"phaos-xmldsig-three.zip" nickname:@"phaos"] copy];
}

+ (void)tearDown;
{
    if (phaosDocsDir) {
        NSLog(@"Removing scratch directory %@", phaosDocsDir);
        [[NSFileManager defaultManager] removeItemAtPath:phaosDocsDir error:NULL];
        phaosDocsDir = nil;
    }
}

- (NSString *)baseDir;
{
    return [phaosDocsDir stringByAppendingPathComponent:@"phaos-xmldsig-three"];
}

/*
 signature-dsa-enveloped.xml
 ---------------------------	
 Contains a DSA enveloped signature.
*/ 
- (void)testDSAEnveloped;
{
    NSArray *sigs = [self getSigs:@"signature-dsa-enveloped.xml"];
    NSError *error;
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
}

/*
 signature-rsa-enveloped.xml
 ---------------------------	
 Contains an RSA enveloped signature.
*/
- (void)testRSAEnveloped;
{
    NSArray *sigs = [self getSigs:@"signature-rsa-enveloped.xml"];
    NSError *error;
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
}

/*
 signature-rsa-enveloping.xml
 ----------------------------
 Contains an RSA enveloping signature.
*/
- (void)testRSAEnveloping;
{
    NSArray *sigs = [self getSigs:@"signature-rsa-enveloping.xml"];
    NSError *error;
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
}

- (void)testRSADetached;
{
    /*
     signature-rsa-detached.xml
     --------------------------
     Contains an RSA detached signature.
     */
    NSArray *sigs = [self getSigs:@"signature-rsa-detached.xml"];
    NSError *error;
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);

    /*
     signature-rsa-manifest.xml
     ----------------------------------
     Contains a detached RSA signature with a manifest.
     */
    sigs = [self getSigs:@"signature-rsa-manifest.xml"];
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
}

/*
 signature-dsa-enveloping.xml
 ----------------------------
 Contains a DSA enveloping signature.
*/
- (void)testDSAEnveloping;
{
    NSArray *sigs = [self getSigs:@"signature-dsa-enveloping.xml"];
    NSError *error;
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
}

/*
signature-rsa-enveloped-bad-digest-val.xml
------------------------------------------
Contains an enveloped RSA signature that contains a reference with an INCORRECT
digest value.  Verification should FAIL.
*/
- (void)testRSAEnvelopedBadDigest;
{
    NSArray *sigs = [self getSigs:@"signature-rsa-enveloped-bad-sig.xml"];
    NSError *error;
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    
    BOOL verified = [[sigs objectAtIndex:0] processSignatureElement:&error];
    XCTAssertFalse(verified, @"This verification should fail!");
    if (!verified && !isExpectedBadSignatureError(error)) {
        FailedForWrongReason(error);
    }
}

/*
signature-rsa-enveloped-bad-sig.xml
-----------------------------------
Contains an enveloped RSA signature that contains a reference that was added 
after the signature value was computed.  Verification should FAIL.
*/ 
- (void)testRSAEnvelopedBadSignature;
{
    NSArray *sigs = [self getSigs:@"signature-rsa-enveloped-bad-sig.xml"];
    NSError *error;
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    
    BOOL verified = [[sigs objectAtIndex:0] processSignatureElement:&error];
    XCTAssertFalse(verified, @"This verification should fail!");
    if (!verified && !isExpectedBadSignatureError(error)) {
        FailedForWrongReason(error);
    }
}


- (void)testDSADetached;
{
    /*
     signature-dsa-detached.xml
     --------------------------
     Contains a DSA detached signature.
     */
    NSArray *sigs = [self getSigs:@"signature-dsa-detached.xml"];
    NSError *error;
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    /*
     signature-dsa-detached-manifest.xml
     -----------------------------------
     Contains a detached DSA signature with a manifest.
     */
    sigs = [self getSigs:@"signature-dsa-manifest.xml"];
    XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
}

- (void)testHMACVarious;
{
#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7
    NSLog(@"SKIPPING HMAC tests on Lion (RADAR 10424173 et al.)");
#else
    NSArray *sigs;
    NSError *error;
    BOOL verifiedOK;
    
    /*
     signature-hmac-md5-c14n-enveloping.xml
     --------------------------------------
     Contains an enveloping MD5 HMAC signature and uses XML Canonicalization 
     as the canonicalization method.  The HMAC secret is the ASCII encoding of
     the word "test".
     */
    @autoreleasepool {
        sigs = [self getSigs:@"signature-hmac-md5-c14n-enveloping.xml"];
        XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
        OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACTest]);
        OFForEachInArray(sigs, OFXMLSignature *, sig,
                         OBShouldNotError([sig processSignatureElement:&error]);
                         [self checkReferences:sig];);
    }

    @autoreleasepool {
        sigs = [self getSigs:@"signature-hmac-md5-c14n-enveloping.xml"];
        XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
        OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACBogus]);
        verifiedOK = [[sigs objectAtIndex:0] processSignatureElement:&error];
        XCTAssertFalse(verifiedOK, @"This verification should fail!");
        if (!verifiedOK && !isExpectedBadSignatureError(error)) {
            FailedForWrongReason(error);
        }
    }
    
    /*
     signature-hmac-sha1-exclusive-c14n-enveloped.xml
     ------------------------------------------------
     Contains an enveloped SHA-1 HMAC signature and uses the Exclusive XML
     Canonicalization canonicalization method.  The HMAC secret is the ASCII 
     encoding of the word "test".
     */
    @autoreleasepool {
        sigs = [self getSigs:@"signature-hmac-sha1-exclusive-c14n-enveloped.xml"];
        XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
        OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACTest]);
        OFForEachInArray(sigs, OFXMLSignature *, sig,
                         OBShouldNotError([sig processSignatureElement:&error]);
                         [self checkReferences:sig];);
        
        sigs = [self getSigs:@"signature-hmac-sha1-exclusive-c14n-enveloped.xml"];
        XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
        OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACSecret]);
        verifiedOK = [[sigs objectAtIndex:0] processSignatureElement:&error];
        XCTAssertFalse(verifiedOK, @"This verification should fail!");
        if (!verifiedOK && !isExpectedBadSignatureError(error)) {
            FailedForWrongReason(error);
        }
    }

    /*
     signature-hmac-sha1-exclusive-c14n-comments-detached.xml
     --------------------------------------------------------
     Contains a detached SHA-1 HMAC signature and uses the Exclusive XML
     Canonicalization With Comments canonicalization method.  The HMAC secret 
     is the ASCII encoding of the word "test".
     */
    @autoreleasepool {
        sigs = [self getSigs:@"signature-hmac-sha1-exclusive-c14n-comments-detached.xml"];
        XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
        OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACTest]);
        OFForEachInArray(sigs, OFXMLSignature *, sig,
                         OBShouldNotError([sig processSignatureElement:&error]);
                         [self checkReferences:sig];);
    }
#endif
}

- (void)testX509Various
{
    NSArray *sigs;
    NSError *error;
    
    /*
     signature-rsa-detached-x509-data-ski.xml
     ------------------------------------
     Contains a detached RSA signature with an X509SKI that 
     references the Subject Key Identifier of the certificate stored in
     certs/rsa-client-cert.der.
     */
    @autoreleasepool {
        sigs = [self getSigs:@"signature-rsa-manifest-x509-data-ski.xml"];
        XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
        OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromExternalCertificate]);
        [[sigs objectAtIndex:0] loadExternalCerts:[[self baseDir] stringByAppendingPathComponent:@"certs"]];
        OFForEachInArray(sigs, OFXMLSignature *, sig,
                         OBShouldNotError([sig processSignatureElement:&error]);
                         [self checkReferences:sig];);
        

        /*
        signature-rsa-detached-x509-data-client-cert.xml
        ------------------------------------
        Contains a detached RSA signature with an X509Certificate that 
        represents the certificate stored in certs/rsa-client-cert.der.
        */
        sigs = [self getSigs:@"signature-rsa-manifest-x509-data-cert.xml"];
        XCTAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
        /* Slipping in another test case here: we have some external certs, but none of them are the desired cert; the cert is actually embedded */
        OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromExternalCertificate]);
        [[sigs objectAtIndex:0] loadExternalCerts:[[self baseDir] stringByAppendingPathComponent:@"certs"]];
        OFForEachInArray(sigs, OFXMLSignature *, sig,
                         OBShouldNotError([sig processSignatureElement:&error]);
                         [self checkReferences:sig];);
    
    }
}

/*
 These test cases are not checked because this implementation doesn't include some feature they require:
 

 ** truncated HMACs **
 
 signature-hmac-sha1-40-c14n-comments-detached.xml
 -------------------------------------------------
 Contains a detached 40-byte SHA-1 HMAC signature and uses the XML
 Canonicalization With Comments canonicalization method.  The HMAC secret is 
 the ASCII encoding of the word "test".
 
 
 signature-hmac-sha1-40-exclusive-c14n-comments-detached.xml
 -----------------------------------------------------------
 Contains a detached 40 byte SHA-1 HMAC signature and uses the Exclusive
 XML Canonicalization With Comments canonicalization method.  The HMAC secret 
 is the ASCII encoding of the word "test".
 

 signature-rsa-detached-xslt-transform-retrieval-method.xml
 ------------------------------------
 Contains a detached RSA signature with an XSLT transform and a KeyInfo 
 element that refers to an external X.509 certificate.  The certificate 
 is located in certs/rsa-client-cert.der.
 
 
 ** Manifest verification (these cases pass, but don't really test much since we don't check the manifest) **
 
 signature-rsa-detached-b64-transform.xml
 ----------------------------------------
 Contains a detached RSA signature with a Base64 decode transform.
 
 
 ** General XPath and XSLT transforms - especially the here() function **
 
 signature-rsa-detached-xpath-transform.xml
 ------------------------------------------
 Contains a detached RSA signature with an XPath transform.
 
 
 signature-rsa-xpath-transform-enveloped.xml
 ------------------------------------------
 Contains an RSA signature with an XPath transform that produces the
 same result as the enveloped signature algorithm.
 
 
 signature-rsa-detached-xslt-transform.xml
 ------------------------------------------
 Contains a detached RSA signature with an XSLT transformation.
 
 
 signature-rsa-detached-xslt-transform-bad-retrieval-method.xml
 ---------------------------------------------------------------
 Contains a detached RSA signature with an XSLT transform and a KeyInfo 
 element that refers to an INCORRECT external X.509 certificate. (The correct
 X.509 certificate is located in certs/rsa-client-cert.der.)  Verification 
 should FAIL.
 
 ** Some aspect of the X.509 key reference **
 
 signature-rsa-detached-x509-data.xml
 ------------------------------------
 Contains a detached RSA signature with several X509Data subelements.
 
 
 signature-rsa-detached-x509-data-subject-name.xml
 ------------------------------------
 Contains a detached RSA signature with an X509SubjectName that 
 references the subject name of the certificate stored in
 certs/rsa-client-cert.der.
 
 
 signature-rsa-detached-x509-data-issuer-serial.xml
 ------------------------------------
 Contains a detached RSA signature with an X509IssuerSerial that 
 references the issuer and serial number of the certificate stored in
 certs/rsa-client-cert.der.
 
 signature-rsa-detached-x509-data-cert-chain.xml
 ------------------------------------
 Contains a detached RSA signature with two X509Certificate 
 elements that represent the certificates stored in  
 certs/rsa-client-cert.der and certs/rsa-ca-cert.der.

 signature-big.xml
 -----------------
 Contains a larger detached RSA signature that contains a manifest and many 
 references that test various transformation algorithms, URI reference syntax 
 formats, etc. The KeyInfo contains a KeyName whose value is the subject
 name of the certificate stored in certs/rsa-client-cert.der.
 
 
 */
 
@end

@interface OFXMLSignatureKeychainTests : OFXMLSignatureTests_Abstract
{
    SecKeychainRef kc;
}

@end

@implementation OFXMLSignatureKeychainTests

+ (void)setUp;
{
    if (!testKeychainPath) {
        NSFileManager *fm = [NSFileManager defaultManager];
        
        NSString *tmpl = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OFUnitTests#.keychain"];
        NSString *filename = [fm tempFilenameFromTemplate:tmpl andRange:[tmpl rangeOfString:@"#" options:NSBackwardsSearch]];
        
        NSLog(@"Creating temporary keychain %@ ...", filename);
        
        SecKeychainRef newKeychain = NULL;
        OSStatus oserr = SecKeychainCreate([filename fileSystemRepresentation], 0, "", FALSE, NULL, &newKeychain);
        if (oserr != noErr) {
            [NSException raise:NSGenericException format:@"Unable to create temp keychain: %@", OFOSStatusDescription(oserr)];
        }
        
        testKeychainPath = [filename copy];

#if OF_ENABLE_CDSA
        CSSM_CSP_HANDLE keychainCSP = CSSM_INVALID_HANDLE;
        oserr = SecKeychainGetCSPHandle(newKeychain, &keychainCSP);
        if (oserr != noErr) {
            [NSException raise:NSGenericException format:@"Unable to get keychain CSP: %@", OFStringFromCSSMReturn(oserr)];
        }
#endif
        
        SecAccessRef acl = NULL;
        oserr = SecAccessCreate(CFSTR("OFXMLSignatureTest test keys"), NULL, &acl);
        if (oserr != noErr) {
            [NSException raise:NSGenericException format:@"Unable to create temporary SecAccess: %@", OFOSStatusDescription(oserr)];
        }
        
        CFErrorRef keygenError = NULL;
        if (!(generateTestKey(newKeychain, acl, TestKeyType_RSA, 768, &keygenError) &&
              generateTestKey(newKeychain, acl, TestKeyType_DSA, 512, &keygenError) &&
              /* Apple CSP docs specify valid ECDSA key sizes: 192, 256, 384, 521 bits. Presumably they use this to choose the generator prime or polynomial. */
              generateTestKey(newKeychain, acl, TestKeyType_ECDSA, 384, &keygenError))) {
            NSString *desc = [(__bridge NSError *)keygenError description];
            CFRelease(keygenError);
            [NSException raise:NSGenericException format:@"Unable to create temporary keys: %@", desc];
        }
        
        CFRelease(acl);
        
        CFRelease(newKeychain);
    }
}

- (void)setUp;
{
    if (!kc) {
        OSStatus oserr = SecKeychainOpen([testKeychainPath fileSystemRepresentation], &kc);
        if (oserr != noErr || kc == NULL) {
            [NSException raise:NSGenericException format:@"Unable to open temp keychain: %@", OFOSStatusDescription(oserr)];
        }
    }
}

- (void)tearDown;
{
    if (kc != NULL) {
        CFRelease(kc);
        kc = NULL;
    }
    
    [super tearDown];
}

+ (void)tearDown;
{
    if (testKeychainPath) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSLog(@"Removing temporary keychain");
        SecKeychainRef oldKeychain;
        OSStatus oserr = SecKeychainOpen([testKeychainPath fileSystemRepresentation], &oldKeychain);
        if (oserr != noErr) {
            NSLog(@"(Can't open it; just deleting its file)");
            [fm removeItemAtPath:testKeychainPath error:NULL];
        } else {
            SecKeychainDelete(oldKeychain);
            CFRelease(oldKeychain);
        }
        testKeychainPath = nil;
    }
}

- (xmlDocPtr)_readDoc:(NSString *)rsrcName
{
    if (loadedDoc) {
        xmlFreeDoc(loadedDoc);
        loadedDoc = NULL;
    }
    
    NSString *xmlFile = [[NSBundle bundleForClass:[self class]] pathForResource:rsrcName ofType:nil];
    if (!xmlFile) {
        [NSException raise:NSGenericException format:@"Can't find resource \"%@\"", rsrcName];
    }
    
    const char *pathString = [xmlFile fileSystemRepresentation];
    loadedDoc = xmlReadFile(pathString, "UTF-8",  XML_PARSE_NONET);
    if (!loadedDoc) {
        [NSException raise:NSGenericException format:@"xmlReadFile() failed to read '%@' !", xmlFile];
    }
    
    return loadedDoc;
}

static xmlNode *applySigBlob(xmlDoc *tree, const xmlChar *sigAlg, const xmlChar *canonAlg)
{
    xmlNode *sigNode = xmlNewNode(NULL, (const xmlChar *)"Signature");
    xmlAddChild(xmlDocGetRootElement(tree), sigNode);
    xmlNs *dsig = xmlNewNs(sigNode, XMLSignatureNamespace, NULL);
    sigNode->ns = dsig;
    
    xmlNode *signedInfo = xmlNewChild(sigNode, dsig, (const xmlChar *)"SignedInfo", NULL);
    
    xmlNode *method = xmlNewChild(signedInfo, dsig, (const xmlChar *)"CanonicalizationMethod", NULL);
    xmlSetNsProp(method, dsig, (const xmlChar *)"Algorithm", canonAlg);
    
    method = xmlNewChild(signedInfo, dsig, (const xmlChar *)"SignatureMethod", NULL);
    xmlSetNsProp(method, dsig, (const xmlChar *)"Algorithm", sigAlg);
    
    xmlNewChild(sigNode, dsig, (const xmlChar *)"SignatureValue", NULL);
    
    return sigNode;
}

static xmlNode *addRefNode(xmlNode *sigNode, const xmlChar *uri, const xmlChar *digestAlg, const xmlChar *xformAlg)
{
    xmlNode *signedInfo = OFLibXMLChildNamed(sigNode, "SignedInfo", XMLSignatureNamespace, NULL);
    xmlNs *dsig = signedInfo->ns;
    
    xmlNode *refNode = xmlNewChild(signedInfo, dsig, (const xmlChar *)"Reference", NULL);
    xmlSetNsProp(refNode, dsig, (const xmlChar *)"URI", uri);
    
    if (xformAlg) {
        xmlNode *xforms = xmlNewChild(refNode, dsig, (const xmlChar *)"Transforms", NULL);
        xmlNode *xform = xmlNewChild(xforms, dsig, (const xmlChar *)"Transform", NULL);
        xmlSetNsProp(xform, dsig, (const xmlChar *)"Algorithm", xformAlg);
    }
    
    xmlNode *method = xmlNewChild(refNode, dsig, (const xmlChar *)"DigestMethod", NULL);
    xmlSetNsProp(method, dsig, (const xmlChar *)"Algorithm", digestAlg);
    
    xmlNewChild(refNode, dsig, (const xmlChar *)"DigestValue", NULL);
    
    return refNode;
}

static void alterSignature(xmlNode *sigNode, int delta)
{
    xmlNode *sigelt = OFLibXMLChildNamed(sigNode, "SignatureValue", XMLSignatureNamespace, NULL);
    
    xmlChar *contentbuf = xmlNodeGetContent(sigelt);
    NSMutableData *dec = [[[NSData alloc] initWithBase64EncodedString:[NSString stringWithCString:(void *)contentbuf encoding:NSUTF8StringEncoding] options:NSDataBase64DecodingIgnoreUnknownCharacters] mutableCopy];
    unsigned int b0 = ((unsigned char *)[dec bytes])[6];
    b0 = ( b0 + delta ) & 0xFF;
    ((unsigned char *)[dec mutableBytes])[6] = b0;
    NSData *enc = [[dec base64EncodedStringWithOptions:0] dataUsingEncoding:NSUTF8StringEncoding];
    
    // NSLog(@"Alter<%d>  %s -> %.*s\n", delta, contentbuf, (int)[enc length], (char *)[enc bytes]);
    
    xmlNode *newText = xmlNewTextLen([enc bytes], (int)[enc length]);

    while (sigelt->children) {
        xmlNode *popped = sigelt->children;
        xmlUnlinkNode(popped);
        xmlFreeNode(popped);
    }
    
    xmlAddChild(sigelt, newText);
    
    xmlFree(contentbuf);
}

static int retrieveKeyAndCheckSize(SecKeychainRef keychain, const xmlChar *sigAlg, enum OFXMLSignatureOperation op, enum OFKeyAlgorithm tp)
{
    int result;
    xmlDoc *d = xmlNewDoc((xmlChar *)"1.0");
    xmlNode *sigNode = applySigBlob(d, sigAlg, ((const xmlChar *)"http://www.w3.org/2001/10/xml-exc-c14n#"));
    xmlNode *signedInfo = OFLibXMLChildNamed(sigNode, "SignedInfo", XMLSignatureNamespace, NULL);
    xmlNode *signatureMethod = OFLibXMLChildNamed(signedInfo, "SignatureMethod", XMLSignatureNamespace, NULL);
    SecKeyRef k = copyKeyFromKeychain(keychain, signatureMethod, op, NULL);
    if (!k) {
        NSLog(@"%s: Unable to retrieve key for alg = %s", __PRETTY_FUNCTION__, (const char *)sigAlg);
        result = -1;
    } else {
        SecItemClass kclass = 0;
        unsigned ksize = 0;
        enum OFKeyAlgorithm alg = OFSecKeyGetAlgorithm(k, &kclass, &ksize, NULL, NULL);
        if (alg != tp) {
            NSLog(@"%s: failed to retrieve alg from key ref (got %d, expected %d)", __PRETTY_FUNCTION__, (int)alg, (int)tp);
            result = -1;
        } else {
            result = ksize;
        }
        
        switch(op) {
            case OFXMLSignature_Sign:
                if (kclass != kSecPrivateKeyItemClass) {
                    NSLog(@"%s: expected private key, got SecItemClass %d", __PRETTY_FUNCTION__, kclass);
                    result = -1;
                }
                break;
            case OFXMLSignature_Verify:
                if (kclass != kSecPublicKeyItemClass) {
                    NSLog(@"%s: expected public key, got SecItemClass %d", __PRETTY_FUNCTION__, kclass);
                    result = -1;
                }
                break;
        }
        
        CFRelease(k);
    }
    
    xmlFreeDoc(d);
    return result;
}

- (void)testSizes;
{
    /* Make sure that OFSecKeyGetAlgorithm() returns the expected values for the three keys we generated in +setUp. */
    XCTAssertEqual(retrieveKeyAndCheckSize(kc, XMLPKSignatureRSA_SHA256, OFXMLSignature_Sign, ka_RSA), 768, @"RSA private key size");
    XCTAssertEqual(retrieveKeyAndCheckSize(kc, XMLPKSignatureRSA_SHA256, OFXMLSignature_Verify, ka_RSA), 768, @"RSA public key size");
    
    XCTAssertEqual(retrieveKeyAndCheckSize(kc, XMLPKSignatureDSS, OFXMLSignature_Sign, ka_DSA), 512, @"DSA private key size");
    XCTAssertEqual(retrieveKeyAndCheckSize(kc, XMLPKSignatureDSS, OFXMLSignature_Verify, ka_DSA), 512, @"DSA public key size");

    XCTAssertEqual(retrieveKeyAndCheckSize(kc, XMLPKSignatureECDSA_SHA512, OFXMLSignature_Sign, ka_EC), 384, @"ECDSA private key size");
    XCTAssertEqual(retrieveKeyAndCheckSize(kc, XMLPKSignatureECDSA_SHA512, OFXMLSignature_Verify, ka_EC), 384, @"ECDSA public key size");
}

- (void)testSign;
{
    xmlDoc *info = [self _readDoc:@"0001-Namespaces.svg"];
    xmlNode *sigNode = applySigBlob(info, XMLPKSignaturePKCS1_v1_5, ((const xmlChar *)"http://www.w3.org/2001/10/xml-exc-c14n#"));
    /* xmlNode *refNode = */ addRefNode(sigNode, (const xmlChar *)"", XMLDigestSHA224, NULL);
    
    OFXMLSignature *sig = [[OFXMLSignature alloc] initWithElement:sigNode inDocument:info];
    NSError *error;
    OBShouldNotError([sig computeReferenceDigests:&error]);

    BOOL signSuccess = [sig processSignatureElement:OFXMLSignature_Sign error:&error];
    XCTAssertFalse(signSuccess, @"Should fail to sign since no key is available");
    if (!signSuccess && !( [[error domain] isEqual:OFXMLSignatureErrorDomain] && [error code] == OFKeyNotAvailable )) {
        XCTFail(@"Failed for wrong reason (expecting domain=%@ code=%d): %@", OFXMLSignatureErrorDomain, (int)OFKeyNotAvailable, [error description]);
    }
    
    
    NSArray *sigs = [OFXMLSignatureTest signaturesInTree:info];
    XCTAssertEqual((unsigned)[sigs count], 1u, @"Should be exactly one signature node in this tree");
    OFXMLSignatureTest *sigt = [sigs objectAtIndex:0];
    [sigt setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sigt setKeychain:kc];
    OBShouldNotError([sigt processSignatureElement:OFXMLSignature_Sign error:&error]);
    
    // xmlDocDump(stdout, info);
    
    sigs = [OFXMLSignatureTest signaturesInTree:info];
    XCTAssertEqual((unsigned)[sigs count], 1u, @"Should be exactly one signature node in this tree");
    sigt = [sigs objectAtIndex:0];
    [sigt setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sigt setKeychain:kc];
    OBShouldNotError([sigt processSignatureElement:OFXMLSignature_Verify error:&error]);    
    
    /* xmlFreeDoc(info) Freed automatically in -tearDown */
}

- (void)testSignAndBreak;
{
    xmlDoc *info = [self _readDoc:@"0003-attrs.xml"];
    xmlNode *sigNode = applySigBlob(info, XMLPKSignatureDSS, ((const xmlChar *)"http://www.w3.org/2001/10/xml-exc-c14n#"));
    /* xmlNode *refNode = */ addRefNode(sigNode, (const xmlChar *)"", XMLDigestMD5, XMLTransformEnveloped);
    
    NSError *error;
    OFXMLSignatureTest *sig;
    
    sig = [[OFXMLSignatureTest alloc] initWithElement:sigNode inDocument:info];
    OBShouldNotError([sig computeReferenceDigests:&error]);
    [sig setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sig setKeychain:kc];
    OBShouldNotError([sig processSignatureElement:OFXMLSignature_Sign error:&error]);
    
    sig = [[OFXMLSignatureTest alloc] initWithElement:sigNode inDocument:info];
    [sig setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sig setKeychain:kc];
    OBShouldNotError([sig processSignatureElement:OFXMLSignature_Verify error:&error]);
    OBShouldNotError([sig verifyReferenceAtIndex:0 toBuffer:NULL error:&error]);
    
    // xmlDocDump(stdout, info);
    
    xmlNode *insert = xmlNewNode(NULL, (const xmlChar *)"breaky");
    xmlAddPrevSibling(xmlDocGetRootElement(info)->children, insert);
    
    NSArray *sigs = [OFXMLSignatureTest signaturesInTree:info];
    XCTAssertEqual((unsigned)[sigs count], 1u, @"Should be exactly one signature node in this tree");
    sig = [sigs objectAtIndex:0];
    [sig setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sig setKeychain:kc];
    // This should succeed, since the <SignedInfo> section is consistent ...
    OBShouldNotError([sig processSignatureElement:OFXMLSignature_Verify error:&error]);    
    // ... but this should fail, since the reference no longer matches.
    BOOL verifiedOK = [sig verifyReferenceAtIndex:0 toBuffer:NULL error:&error];
    XCTAssertFalse(verifiedOK, @"Modified document should not pass verification");
    if (!verifiedOK && !isExpectedBadSignatureError(error)) {
        FailedForWrongReason(error);
    }
    
    xmlUnlinkNode(insert);
    xmlFreeNode(insert);
    
    /* We've returned to the earlier state, so verify should succeed again */
    OBShouldNotError([sig verifyReferenceAtIndex:0 toBuffer:NULL error:&error]);    
    
    /* Alter the DSS signature (as opposed to the digests), make sure that verify fails */
    alterSignature(sigNode, 42);
    
    sigs = [OFXMLSignatureTest signaturesInTree:info];
    XCTAssertEqual((unsigned)[sigs count], 1u, @"Should be exactly one signature node in this tree");
    sig = [sigs objectAtIndex:0];
    [sig setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sig setKeychain:kc];
    // This should fail, since the <SignedInfo> section is no longer consistent
    verifiedOK = [sig processSignatureElement:OFXMLSignature_Verify error:&error];
    XCTAssertFalse(verifiedOK, @"Modified document should not pass verification");
    if (!verifiedOK && !isExpectedBadSignatureError(error)) {
        FailedForWrongReason(error);
    }
    
    /* Make sure that it succeeds again after we put it back */
    alterSignature(sigNode, 256 - 42);
    
    sigs = [OFXMLSignatureTest signaturesInTree:info];
    XCTAssertEqual((unsigned)[sigs count], 1u, @"Should be exactly one signature node in this tree");
    sig = [sigs objectAtIndex:0];
    [sig setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sig setKeychain:kc];
    OBShouldNotError([sig processSignatureElement:OFXMLSignature_Verify error:&error]);
    OBShouldNotError([sig verifyReferenceAtIndex:0 toBuffer:NULL error:&error]);
    
    /* xmlFreeDoc(info) Freed automatically in -tearDown */
}

- (void)testECDSA;
{
    xmlDoc *info = [self _readDoc:@"0001-Namespaces.svg"];
    xmlNode *sigNode = applySigBlob(info, XMLPKSignatureECDSA_SHA512, ((const xmlChar *)"http://www.w3.org/2001/10/xml-exc-c14n#"));
    /* xmlNode *refNode = */ addRefNode(sigNode, (const xmlChar *)"", XMLDigestSHA256, NULL);
    
    OFXMLSignature *sig = [[OFXMLSignature alloc] initWithElement:sigNode inDocument:info];
    NSError *error;
    OBShouldNotError([sig computeReferenceDigests:&error]);
    
    BOOL signSuccess = [sig processSignatureElement:OFXMLSignature_Sign error:&error];
    XCTAssertFalse(signSuccess, @"Should fail to sign since no key is available");
    
    
    NSArray *sigs = [OFXMLSignatureTest signaturesInTree:info];
    XCTAssertEqual((unsigned)[sigs count], 1u, @"Should be exactly one signature node in this tree");
    OFXMLSignatureTest *sigt = [sigs objectAtIndex:0];
    [sigt setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sigt setKeychain:kc];
    OBShouldNotError([sigt processSignatureElement:OFXMLSignature_Sign error:&error]);
    
    // xmlDocDump(stdout, info);
    
    sigs = [OFXMLSignatureTest signaturesInTree:info];
    XCTAssertEqual((unsigned)[sigs count], 1u, @"Should be exactly one signature node in this tree");
    sigt = [sigs objectAtIndex:0];
    [sigt setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sigt setKeychain:kc];
    OBShouldNotError([sigt processSignatureElement:OFXMLSignature_Verify error:&error]);    
    
    /* Alter the signature, make sure that verify fails */
    alterSignature(sigNode, 101);
    
    sigs = [OFXMLSignatureTest signaturesInTree:info];
    XCTAssertEqual((unsigned)[sigs count], 1u, @"Should be exactly one signature node in this tree");
    sigt = [sigs objectAtIndex:0];
    [sigt setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sigt setKeychain:kc];
    BOOL verifiedOK = [sigt processSignatureElement:OFXMLSignature_Verify error:&error];
    XCTAssertFalse(verifiedOK, @"Modified document should not pass verification");
    if (!verifiedOK && !isExpectedBadSignatureError(error)) {
        FailedForWrongReason(error);
    }
    
    /* xmlFreeDoc(info) Freed automatically in -tearDown */
}
@end

@interface OFXMLSignatureTests_EllipticInterop : OFXMLSignatureTests_Abstract
@end
@implementation OFXMLSignatureTests_EllipticInterop

+ (XCTestSuite *)defaultTestSuite;
{
    XCTestSuite *suite;
    @autoreleasepool {
        suite = [super defaultTestSuite];
        __unsafe_unretained NSString *files[] = { @"w3c_microsoft_ecc_p256_sha256_c14n.xml", @"w3c_microsoft_ecc_p521_sha256_c14n.xml", @"w3c_microsoft_ecc_p521_sha512_c14n.xml", @"w3c_oracle_signature-enveloping-p256_sha1.xml", @"w3c_oracle_signature-enveloping-p521_sha256.xml", nil };
        
        for (int testfile = 0; files[testfile]; testfile ++) {
            NSInvocation *call = [NSInvocation invocationWithMethodSignature:[self instanceMethodSignatureForSelector:@selector(testSignatureOnFile:)]];
            [call setSelector:@selector(testSignatureOnFile:)];
            [call setArgument:&(files[testfile]) atIndex:2];
            [call retainArguments];
            
            [suite addTest:[self testCaseWithInvocation:call]];
        }
    }
    
    return suite;
}

- (NSString *)baseDir;
{
    return [[NSBundle bundleForClass:[self class]] resourcePath];
}

- (void)testSignatureOnFile:(NSString *)filename
{
    NSArray *signatures = [self getSigs:filename];
    NSError *error;
    
    XCTAssertEqual([signatures count], (NSUInteger)1, @"Should be exactly one signature node in this tree");

    OFXMLSignatureTest *sig = [signatures objectAtIndex:0];
    
    [sig setKeySource:keyFromEmbeddedValues];
    OBShouldNotError([sig processSignatureElement:OFXMLSignature_Verify error:&error]);
}

@end

#pragma mark Key generation

/* Key generation is split out into two functions --- the pre-10.7 version and the post-10.7 function. These are written in pure C (no ObjC syntax) to make it marginally easier to crank out test cases for RADAR submission. (Not sure that Apple reads those RADARs but it's worth a try.) */

#if 1  // Unconditionally choose the SecKeyCreatePair() version because of bugs in SecKeyGeneratePair().

#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#else
// Annoyingly, Apple's GCC doesn't understand "GCC diagnostic push". This code is at the end of the file to minimize the amount of other code unintentionally covered by the pragma here.
//#pragma GCC diagnostic push
#pragma GCC diagnostic warning "-Wdeprecated-declarations"
#endif

static
Boolean generateTestKey(SecKeychainRef intoKeychain, SecAccessRef initialAccess, enum TestKeyType keytype, unsigned int keybits, CFErrorRef *outError)
{
    SecKeyRef pubKey, privKey;
    OSStatus oserr;
    CSSM_ALGORITHMS algid = -1;;
    const char *algname = NULL;
    
    switch (keytype) {
        case TestKeyType_RSA:   algid = CSSM_ALGID_RSA;   algname = "RSA";   break;
        case TestKeyType_DSA:   algid = CSSM_ALGID_DSA;   algname = "DSA";   break;
        case TestKeyType_ECDSA: algid = CSSM_ALGID_ECDSA; algname = "ECDSA"; break;
    }
    
    pubKey = privKey = NULL;
    oserr = SecKeyCreatePair(intoKeychain, algid, (uint32)keybits, CSSM_INVALID_HANDLE, CSSM_KEYUSE_VERIFY, CSSM_KEYATTR_EXTRACTABLE | CSSM_KEYATTR_PERMANENT, CSSM_KEYUSE_SIGN,  CSSM_KEYATTR_SENSITIVE | CSSM_KEYATTR_PERMANENT, initialAccess, &pubKey, &privKey);
    if (oserr != noErr) {
        if (outError)
            *outError = CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainOSStatus, oserr, NULL);
        return 0;
    }
    fprintf(stderr, "    Created temp %s-%u keys %p %p\n", algname, keybits, pubKey, privKey);
    CFRelease(pubKey);
    CFRelease(privKey);
    
    return 1;
}


#ifdef __clang__
#pragma clang diagnostic pop
#else
//#pragma GCC diagnostic pop
#endif

#else

static
Boolean generateTestKey(SecKeychainRef intoKeychain, SecAccessRef initialAccess, enum TestKeyType keytype, unsigned int keybits, CFErrorRef *outError)
{
#warning These APIs do not appear to work reliably.
    
    CFDictionaryRef params;
    const void *keys[10], *values[10];
    CFIndex n;
    CFStringRef errLocation;
    OSStatus oserr;
    
    if (0) {
    fail:
        if (outError) {
            keys[0] = kCFErrorDescriptionKey;
            values[0] = errLocation;
            CFDictionaryRef uinfo = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFErrorRef carbonError = CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainOSStatus, oserr, uinfo);
            CFRelease(uinfo);
            *outError = carbonError;
        }
        CFRelease(errLocation);
        return 0;
    }
    
    CFStringRef keytypeObject = NULL, keyLabelObject;
    const char *algname = NULL;
    CFNumberRef keySizeObject = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &keybits);
    switch (keytype) {
        case TestKeyType_RSA:   keytypeObject = kSecAttrKeyTypeRSA;   algname = "RSA";   break;
        case TestKeyType_DSA:   keytypeObject = kSecAttrKeyTypeDSA;   algname = "DSA";   break;
        case TestKeyType_ECDSA: keytypeObject = kSecAttrKeyTypeECDSA; algname = "ECDSA"; break;
    }
    keyLabelObject = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("Temporary %s-%u key for unit tests"), algname, keybits);
    
    
    n = 0;
    keys[n] = kSecAttrIsPermanent;          values[n] = kCFBooleanFalse; n++;
    if (initialAccess) { keys[n] = kSecAttrAccess;               values[n] = initialAccess; n++; }
    keys[n] = kSecAttrKeyType;              values[n] = keytypeObject; n++;
    keys[n] = kSecAttrKeySizeInBits;        values[n] = keySizeObject; n++;
    keys[n] = kSecAttrLabel;                values[n] = keyLabelObject; n++;
    
    params = CFDictionaryCreate(kCFAllocatorDefault, keys, values, n, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    CFRelease(keytypeObject);
    CFRelease(keyLabelObject);
    CFRelease(keySizeObject);
    
    SecKeyRef createdKeys[2];
    createdKeys[0] = createdKeys[1] = NULL;
    oserr = SecKeyGeneratePair(params, &(createdKeys[0]), &(createdKeys[1]));
    CFRelease(params);
    if (oserr != noErr) {
        errLocation = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("Unable to create temporary %s-%u key (SecKeyGeneratePair failure)"), algname, keybits);
        goto fail;
    }
    fprintf(stderr, "    Created temp %s-%u keys %p %p\n", algname, keybits, createdKeys[0], createdKeys[1]);
    
    CFArrayRef addThese = CFArrayCreate(kCFAllocatorDefault, (const void **)createdKeys, 2, &kCFTypeArrayCallBacks);
    CFRelease(createdKeys[0]);
    CFRelease(createdKeys[1]);
    
    n = 0;
    keys[n] = kSecUseItemList;  values[n] = addThese; n++;
    keys[n] = kSecUseKeychain;  values[n] = intoKeychain; n++;
    keys[n] = kSecClass; values[n] = kSecClassKey; n++;
    
    params = CFDictionaryCreate(kCFAllocatorDefault, keys, values, n, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    CFRelease(addThese);
    
    oserr = SecItemAdd(params, NULL);
    CFRelease(params);
    if (oserr != noErr) {
        errLocation = CFSTR("Unable to add keys to temporary keychain");
        goto fail;
    }
    
    return 1;
}

#endif

#pragma mark Retrieving a key from a keychain

/* Ridiculously, we have three versions of copyKeyFromKeychain() here.
 
 The pre-10.7 one uses the SecKeychainSearch API and is reasonably straightforward.
 
 The post-10.7 one creates a dictionary of key attributes and calls SecItemCopyMatching(). It's also reasonably straightforward, except that SecItemCopyMatching() is really buggy.
 
 There's another post-10.7 one which creates a dictionary of key attributes as for SecItemCopyMatching(), then converts it to an attribute array and uses SecKeychainSearch. That one works a bit better, and can exercise some of the code which will eventually be used if SecItemCopyMatching() is fixed in the future.
*/

#if !defined(MAC_OS_X_VERSION_10_7) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7

/* Simple, straightforward SecKeychainSearch implementation */
static SecKeyRef copyKeyFromKeychain(SecKeychainRef keychain, xmlNode *signatureMethod, enum OFXMLSignatureOperation op, NSError **outError)
{
    CSSM_ALGORITHMS keytype = OFXMLCSSMKeyTypeForAlgorithm(signatureMethod);
    SecItemClass keyclass = ( op == OFXMLSignature_Sign )?  kSecPrivateKeyItemClass : kSecPublicKeyItemClass;
    
    SecKeychainAttribute attrs[1];
    attrs[0] = (SecKeychainAttribute){ .tag = kSecKeyKeyType, .length = sizeof(keytype), .data = &keytype };
    SecKeychainAttributeList want = { .count = 1, .attr = attrs };
    SecKeychainSearchRef looker = NULL;
    OSStatus oserr = SecKeychainSearchCreateFromAttributes(keychain, keyclass, &want, &looker);
    if (oserr != noErr) {
        OFErrorFromCSSMReturn(outError, oserr, @"SecKeychainSearchCreateFromAttributes");
        return nil;
    }
    SecKeychainItemRef found = NULL;
    oserr = SecKeychainSearchCopyNext(looker, &found);
    CFRelease(looker);
    if (oserr != noErr) {
        OFErrorFromCSSMReturn(outError, oserr, @"SecKeychainSearchCopyNext");
        return nil;
    }
    
    OBASSERT(CFGetTypeID(found) == SecKeyGetTypeID());
    return (SecKeyRef)found;
}

#elif defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7

static SecKeyRef copyMatchingKeyFromKeychain(SecKeychainRef keychain, NSDictionary *attributes, NSError **outError);

static SecKeyRef copyKeyFromKeychain(SecKeychainRef keychain, xmlNode *signatureMethod, enum OFXMLSignatureOperation op, NSError **outError)
{
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    
    OFXMLSigGetKeyAttributes(attributes, signatureMethod, op);
    
    return copyMatchingKeyFromKeychain(keychain, attributes, outError);
}


#if 0 // SecItemCopyMatching() doesn't work yet in 10.7.2.

/* There are many keys used to specify what items SecItemCopyMatching() should look at.
 kSecUseItemList - "If provided, this array is treated as the set of all possible items to search [...] When this attribute is provided, no keychains are searched" (not sure how it interacts with kSecMatchSearchList)
 kSecMatchItemList - "If provided, returned items will be limited to the subset which are contained in this list"
 kSecMatchSearchList - "If provided, the search will be limited to the keychains contained in this list"
 
 For more authoritative "documentation" of the values of the dictionary, see _CreateSecKeychainKeyAttributeListFromDictionary() in SecItem.cpp in libsecurity_keychain. Bring some meatballs and parmesan cheese.
 */
static SecKeyRef copyMatchingKeyFromKeychain(SecKeychainRef keychain, NSDictionary *attributes, NSError **outError)
{
    NSMutableDictionary *query = [NSMutableDictionary dictionaryWithDictionary:attributes];
    [query setObject:(id)kSecClassKey forKey:(id)kSecClass];
    /* Quoth docs: "By default, this function searches for items in the keychain. [By which they mean the user's default keychain list, I think.] To instead provide your own set of items to be filtered by this search query, specify the search key kSecMatchItemList with a value that consists of an object of type CFArrayRef referencing an array that contains items of type either SecKeychainItemRef, SecKeyRef, SecCertificateRef, or SecIdentityRef. The objects in the provided array must all be of the same type" */
    // [query setObject:[NSArray arrayWithObject:(id)keychain] forKey:(id)kSecMatchItemList];
    // kSecMatchSearchList's docs suggest it is more appropriate, but it doesn't work.
    [query setObject:[NSArray arrayWithObject:(id)keychain] forKey:(id)kSecMatchSearchList];
    // [query setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];
    [query setObject:(id)kSecMatchLimitAll forKey:(id)kSecMatchLimit]; // attempt workaround of #10155924
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnRef];
//#ifdef DEBUG_XMLSIG_TESTS
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];
//#endif
    CFTypeRef result = NULL;
    OSStatus err = SecItemCopyMatching((CFDictionaryRef)query, &result);
    if (err != noErr) {
        ofErrorFromOSError(outError, err, @"SecItemCopyMatching", query);
        return NULL;
    }
    
#if 0 // This workaround doesn't work because the returned attributes aren't a superset of the request attributes (even the strict-equality match ones).
    // Also it doesn't work because the returned items don't always include the requested item, so we can't fix by just post-filtering.
    // Note that SecItemCopyMatching() can return many completely unrelated non-matching keys (RADAR 10155924)
    if (CFGetTypeID(result) == CFArrayGetTypeID()) {
        // We passed kSecMatchLimitAll, so we should have gotten an array.
        CFIndex resultCount = CFArrayGetCount(result);
        CFMutableArrayRef filtered = CFArrayCreateMutable(kCFAllocatorDefault, resultCount, &kCFTypeArrayCallBacks);
        for(CFIndex ix = 0; ix < resultCount; ix ++) {
            CFDictionaryRef res = CFArrayGetValueAtIndex(result, ix);
            BOOL mismatch = NO;
            for(NSString *attrKey in attributes) {
                CFTypeRef resultAttrValue;
                if (!CFDictionaryGetValueIfPresent(res, (CFTypeRef)attrKey, &resultAttrValue)) {
                    mismatch = YES;
                    NSLog(@" ** Result %d does not have requested %@ attribute", (int)ix, attrKey);
                    break;
                }
                if (!CFEqual(resultAttrValue, (CFTypeRef)[attributes objectForKey:attrKey])) {
                    NSLog(@" ** Result %d doesn't match %@ attribute (has %@, want %@)", (int)ix, attrKey, (id)resultAttrValue, [attribute objectForKey:attrKey]);
                    mismatch = YES;
                    break;
                }
                if (!mismatch)
                    CFArrayAppendValue(filtered, res);
            }
        }
        CFRelease(result);
        result = filtered;
    }
#endif
    
#ifdef DEBUG_XMLSIG_TESTS
    // Note that SecItemCopyMatching() can return a completely unrelated non-matching key (RADAR 10155924)
    NSLog(@"SecItemCopyMatching(%@) -> %@", [query description], result);
#endif
    SecKeyRef keyrefResult;
    if (CFGetTypeID(result) == CFArrayGetTypeID()) {
        // We passed kSecMatchLimitAll, so we should have gotten an array.
        CFIndex resultCount = CFArrayGetCount(result);
        if (resultCount < 1) {
            CFRelease(result);
            return NULL;
        }
#ifdef DEBUG_XMLSIG_TESTS
        for(CFIndex ix = 0; ix < resultCount; ix ++) {
            NSLog(@"  Result[%d] = %@", (int)ix, OFSecItemDescription(CFDictionaryGetValue(CFArrayGetValueAtIndex(result, ix), kSecValueRef)));
        }
#endif
        CFTypeRef firstResult = CFArrayGetValueAtIndex(result, 0);
        CFRetain(firstResult);
        CFRelease(result);
        result = firstResult;
    } 
    if (CFGetTypeID(result) == CFDictionaryGetTypeID()) {
        // If debugging was turned on, we asked for a dictionary of attributes so we could log them. But we only want to return the key ref.
        keyrefResult = (SecKeyRef)CFDictionaryGetValue(result, kSecValueRef);
    } else {
        keyrefResult = result;
    }
    CFRetain(keyrefResult);
    CFRelease(result);
    OBASSERT(CFGetTypeID(keyrefResult) == SecKeyGetTypeID());
    return keyrefResult;
}

#else

#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#else
// Annoyingly, Apple's GCC doesn't understand "GCC diagnostic push". This code is at the end of the file to minimize the amount of other code unintentionally covered by the pragma here.
//#pragma GCC diagnostic push
#pragma GCC diagnostic warning "-Wdeprecated-declarations"
#endif

/* Here's a kind of cheesy implementation of SecItemCopyMatching() in terms of SecKeychainSearches. It only handles the cases we'll run into with OFXMLSignature, though. */ 
static SecKeyRef copyMatchingKeyFromKeychain(SecKeychainRef keychain, NSDictionary *attributes, NSError **outError)
{
    SecKeychainAttribute searchAttributes[4];
    SecKeychainAttributeList query = { .count = 0, .attr = searchAttributes };
    
#define ADDATTR(n, v) buf_ ## n = v; query.attr[query.count++] = (SecKeychainAttribute){ .tag = n, .length = sizeof(buf_ ## n), .data = &(buf_ ## n) };
    UInt32 buf_kSecKeyKeyType;
    UInt32 buf_kSecKeySign, buf_kSecKeyVerify, buf_kSecKeyDecrypt;
    CFTypeRef cfBuf;
    BOOL probablyPrivate;
    
    SecItemClass keyclass = CSSM_DL_DB_RECORD_ANY;
    probablyPrivate = NO;
    
    id secKeytype = [attributes objectForKey:(id)kSecAttrKeyType];
    if (!secKeytype) { /* */ 
    } else if ([secKeytype isEqual:(id)kSecAttrKeyTypeRSA]) {
        ADDATTR(kSecKeyKeyType, CSSM_ALGID_RSA);
    } else if ([secKeytype isEqual:(id)kSecAttrKeyTypeDSA]) {
        ADDATTR(kSecKeyKeyType, CSSM_ALGID_DSA);
    } else if ([secKeytype isEqual:(id)kSecAttrKeyTypeECDSA]) {
        ADDATTR(kSecKeyKeyType, CSSM_ALGID_ECDSA);
    }
    
#define WANTS(x) CFDictionaryGetValueIfPresent((CFDictionaryRef)attributes, x, &cfBuf)? CFBooleanGetValue(cfBuf) : 0
    if (WANTS(kSecAttrCanSign)) {
        ADDATTR(kSecKeySign, 1);
        probablyPrivate = YES;
    }
    if (WANTS(kSecAttrCanVerify)) {
        ADDATTR(kSecKeyVerify, 1);
    }
    if (WANTS(kSecAttrCanDecrypt)) {
        ADDATTR(kSecKeyDecrypt, 1);
        probablyPrivate = YES;
    }
    
    id secPubPriv = [attributes objectForKey:(id)kSecAttrKeyClass];
    if (!secPubPriv) {
        if (probablyPrivate)
            keyclass = kSecPrivateKeyItemClass;
    } else if ([secKeytype isEqual:(id)kSecAttrKeyClassPrivate]) {
        keyclass = kSecPrivateKeyItemClass;
    } else if ([secKeytype isEqual:(id)kSecAttrKeyClassPrivate]) {
        keyclass = kSecPublicKeyItemClass;
    }
    
    SecKeychainSearchRef looker = NULL;
    OSStatus oserr = SecKeychainSearchCreateFromAttributes(keychain, keyclass, &query, &looker);
    if (oserr != noErr) {
        ofErrorFromOSError(outError, oserr, @"SecKeychainSearchCreateFromAttributes", attributes);
        return NULL;
    }
    SecKeychainItemRef found = NULL;
    oserr = SecKeychainSearchCopyNext(looker, &found);
    CFRelease(looker);
    if (oserr != noErr) {
        ofErrorFromOSError(outError, oserr, @"SecKeychainSearchCopyNext", attributes);
        return NULL;
    }
    
    OBASSERT(CFGetTypeID(found) == SecKeyGetTypeID());
    return (SecKeyRef)found;
}

#ifdef __clang__
#pragma clang diagnostic pop
#else
//#pragma GCC diagnostic pop
#endif

#endif /* Lion Lossage */
#endif /* MAX_ALLOWED >= 10.7 */
