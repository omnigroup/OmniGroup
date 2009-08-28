// Copyright 2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// http://www.omnigroup.com/DeveloperResources/OmniSourceLicense.html.


#import "OFTestCase.h"

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFXMLSignature.h>
#import <OmniFoundation/OFCDSAUtilities.h>
#import <Security/Security.h>

RCS_ID("$Id$");

NSString *phaosDocsDir, *merlinDocsDir;
NSString *testKeychainPath;

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
    [super dealloc];
}

- (void)setKeySource:(enum testKeySources)s;
{
    keySource = s;
}

- (void)setKeychain:(SecKeychainRef)kc;
{
    if (forcedKeychain)
        CFRelease(forcedKeychain);
    if (kc)
        CFRetain(kc);
    forcedKeychain = kc;
}

- (void)loadExternalCerts:(NSString *)fromDir
{
    CFMutableArrayRef certs = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    
    NSFileManager *fm = [NSFileManager defaultManager];
    OFForEachInArray([fm contentsOfDirectoryAtPath:fromDir error:NULL], NSString *, fn, {
        if ([fn hasSuffix:@".crt"] || [fn hasSuffix:@".der"]) {
            NSError *readError = NULL;
            NSData *derData = [NSData dataWithContentsOfFile:[fromDir stringByAppendingPathComponent:fn] options:NSMappedRead error:&readError];
            if (!derData) {
                NSLog(@"*** Could not load cert from %@: %@", fn, readError);
                continue;
            }
            CSSM_DATA buf;
            buf.Data = (void *)[derData bytes];
            buf.Length = [derData length];
            // NSLog(@"Parsing cert %@ (len=%u)", fn, buf.Length);
            SecCertificateRef oneCert = NULL;
            OSStatus oserr = SecCertificateCreateFromData(&buf, CSSM_CERT_X_509v3, CSSM_CERT_ENCODING_BER, &oneCert);
            if (oserr == noErr) {
                CFArrayAppendValue(certs, oneCert);
                CFRelease(oneCert);
            } else {
                NSLog(@"*** Could not load cert from %@: SecCertificateCreateFromData returns %ld", fn, oserr);
            }
        }
    });

    if (externalCerts)
        CFRelease(externalCerts);
    externalCerts = certs;
}

static SecKeyRef copyKey(SecKeychainRef keychain, CSSM_ALGORITHMS keytype, SecItemClass keyclass, NSError **outError)
{
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

- (OFCSSMKey *)getPublicKey:(xmlNode *)keyInfo algorithm:(CSSM_ALGORITHMS)keytype error:(NSError **)outError;
{
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
            SecCertificateRef cert = (void *)[certs objectAtIndex:0];
            SecKeyRef pubkey = NULL;
            SecCertificateCopyPublicKey(cert, &pubkey);
            OFCSSMKey *result = [OFCSSMKey keyFromKeyRef:pubkey error:outError];
            CFRelease(pubkey);
            return result;
        }
    }
    
    if (keySource == keyFromEmbeddedValues) {
        unsigned int count;
        xmlNode *keyvalue = OFLibXMLChildNamed(keyInfo, "KeyValue", XMLSignatureNamespace, &count);
        if (count == 1) {
            if (keytype == CSSM_ALGID_DSA)
                return OFXMLSigGetKeyFromDSAKeyValue(keyvalue, outError);
            if (keytype == CSSM_ALGID_RSA)
                return OFXMLSigGetKeyFromRSAKeyValue(keyvalue, outError);
        }
    }
    
    if (keySource == keyIsOnlyApplicableOneInKeychain) {
        SecKeyRef foundKey = copyKey(forcedKeychain, keytype, kSecPublicKeyItemClass, outError);
        if (!foundKey)
            return nil;
        
        OFCSSMKey *retval = [OFCSSMKey keyFromKeyRef:foundKey error:outError];
        
        CFRelease(foundKey);
        return retval;
    }    
    
    return [super getPublicKey:keyInfo algorithm:keytype error:outError];
}

- (OFCSSMKey *)getHMACKey:(xmlNode *)keyInfo algorithm:(CSSM_ALGORITHMS)keytype error:(NSError **)outError;
{
    NSData *keyData;
    
    if (keySource == keyIsHMACTest) {
        keyData = [NSData dataWithBytesNoCopy:"test" length:4 freeWhenDone:NO];
    } else if (keySource == keyIsHMACBogus) {
        keyData = [NSData dataWithBytesNoCopy:"bogus" length:5 freeWhenDone:NO];
    } else if (keySource == keyIsHMACSecret) {
        keyData = [NSData dataWithBytesNoCopy:"secret" length:6 freeWhenDone:NO];
    } else {
        return [super getHMACKey:keyInfo algorithm:keytype error:outError];
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
    keyHeader.LogicalKeySizeInBits = 8 * [keyData length];
    
    [key setKeyHeader:&keyHeader data:keyData];
    
    return key;
}

- (OFCSSMKey *)getPrivateKey:(xmlNode *)keyInfo algorithm:(CSSM_ALGORITHMS)keytype error:(NSError **)outError;
{
    if (keySource == keyIsOnlyApplicableOneInKeychain) {
        SecKeyRef foundKey = copyKey(forcedKeychain, keytype, kSecPrivateKeyItemClass, outError);
        if (!foundKey)
            return nil;
        
        OFCSSMKey *retval = [OFCSSMKey keyFromKeyRef:foundKey error:outError];
        
        const CSSM_ACCESS_CREDENTIALS *creds;
        OSStatus oserr = SecKeyGetCredentials(foundKey, CSSM_ACL_AUTHORIZATION_SIGN, kSecCredentialTypeNoUI, &creds);
        if (oserr != noErr) {
            CFRelease(foundKey);
            OFErrorFromCSSMReturn(outError, oserr, @"SecKeyGetCredentials");
            return nil;
        }
        [retval setCredentials:creds];
        
        CFRelease(foundKey);
        return retval;
    }
    
    return [super getPrivateKey:keyInfo algorithm:keytype error:outError];
}

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
    
    NSData *remoteData = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:refURL cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:45] returningResponse:NULL error:outError];
    if (!remoteData)  // NSURLConnection will have filled *outError for us
        return NO;
    
//     NSLog(@"Retrieved %u bytes from %@", (unsigned int)[remoteData length], refURL);
    
    int xmlOk = xmlOutputBufferWrite(stream, [remoteData length], [remoteData bytes]);
    
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
        abort();
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
    
    [docName autorelease];
    docName = [tcName copy];

    return [OFXMLSignatureTest signaturesInTree:loadedDoc]; 
}

- (void)checkReferences:(OFXMLSignature *)sig
{
    NSUInteger num = [sig countOfReferenceNodes];
    for(NSUInteger n = 0; n < num; n ++) {
        if (![sig isLocalReferenceAtIndex:n] && ![[self class] shouldRunSlowUnitTests]) {
            NSLog(@"SKIPPING test of ref %u (count=%u) of %@: is an external reference.",
                  n, num, docName);
            continue;
        }
        
        NSError *failWhy = nil;
        BOOL didVerify = [sig verifyReferenceAtIndex:n toBuffer:NULL error:&failWhy];
        STAssertTrue(didVerify, @"Verification of reference digest");
        if (didVerify) {
            NSLog(@"-> Ref %u of %@ passed", n, docName);
        } else {
            NSLog(@" -verifyReferenceAtIndex:%u returned error: %@ : %@", n, [failWhy description], [[failWhy userInfo] description]);
        }
    }
}

- (void)tearDown
{
    if (loadedDoc != NULL) {
        xmlFreeDoc(loadedDoc);
        loadedDoc = NULL;
    }
}

@end

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
        [merlinDocsDir release];
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    sigs = [self getSigs:@"signature-enveloping-rsa.xml"];
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    sigs = [self getSigs:@"signature-enveloping-hmac-sha1.xml"];
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACSecret]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    sigs = [self getSigs:@"signature-enveloping-b64-dsa.xml"];
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    sigs = [self getSigs:@"signature-external-dsa.xml"];
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    
    sigs = [self getSigs:@"signature-x509-crt-crl.xml"];
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
        [phaosDocsDir release];
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    
    BOOL verified = [[sigs objectAtIndex:0] processSignatureElement:&error];
    STAssertFalse(verified, @"This verification should fail!");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedCertificate]);
    
    BOOL verified = [[sigs objectAtIndex:0] processSignatureElement:&error];
    STAssertFalse(verified, @"This verification should fail!");
    STAssertEquals((int)[error code], (int)CSSMERR_CSP_VERIFY_FAILED, @"Failure reason should be failure of CSSM_VerifyDataFinal()");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromEmbeddedValues]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
}

- (void)testHMACVarious;
{
    NSAutoreleasePool *p;
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
    p = [[NSAutoreleasePool alloc] init];
    sigs = [self getSigs:@"signature-hmac-md5-c14n-enveloping.xml"];
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACTest]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    [p release];
    
    p = [[NSAutoreleasePool alloc] init];
    sigs = [self getSigs:@"signature-hmac-md5-c14n-enveloping.xml"];
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACBogus]);
    verifiedOK = [[sigs objectAtIndex:0] processSignatureElement:&error];
    STAssertFalse(verifiedOK, @"This verification should fail!");
    STAssertEquals((int)[error code], (int)CSSMERR_CSP_VERIFY_FAILED, @"Failure reason should be failure of CSSM_VerifyDataFinal()");
    [p release];
        
    /*
     signature-hmac-sha1-exclusive-c14n-enveloped.xml
     ------------------------------------------------
     Contains an enveloped SHA-1 HMAC signature and uses the Exclusive XML
     Canonicalization canonicalization method.  The HMAC secret is the ASCII 
     encoding of the word "test".
     */
    p = [[NSAutoreleasePool alloc] init];
    sigs = [self getSigs:@"signature-hmac-sha1-exclusive-c14n-enveloped.xml"];
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACTest]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    sigs = [self getSigs:@"signature-hmac-sha1-exclusive-c14n-enveloped.xml"];
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACSecret]);
    verifiedOK = [[sigs objectAtIndex:0] processSignatureElement:&error];
    STAssertFalse(verifiedOK, @"This verification should fail!");
    STAssertEquals((int)[error code], (int)CSSMERR_CSP_VERIFY_FAILED, @"Failure reason should be failure of CSSM_VerifyDataFinal()");
    [p release];

    /*
     signature-hmac-sha1-exclusive-c14n-comments-detached.xml
     --------------------------------------------------------
     Contains a detached SHA-1 HMAC signature and uses the Exclusive XML
     Canonicalization With Comments canonicalization method.  The HMAC secret 
     is the ASCII encoding of the word "test".
     */
    p = [[NSAutoreleasePool alloc] init];
    sigs = [self getSigs:@"signature-hmac-sha1-exclusive-c14n-comments-detached.xml"];
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyIsHMACTest]);
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    [p release];
}

- (void)testX509Various
{
    NSAutoreleasePool *p;
    NSArray *sigs;
    NSError *error;
    
    /*
     signature-rsa-detached-x509-data-ski.xml
     ------------------------------------
     Contains a detached RSA signature with an X509SKI that 
     references the Subject Key Identifier of the certificate stored in
     certs/rsa-client-cert.der.
     */
    p = [[NSAutoreleasePool alloc] init];
    sigs = [self getSigs:@"signature-rsa-manifest-x509-data-ski.xml"];
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
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
    STAssertTrue([sigs count] == 1, @"Should have found one signature in this file");
    /* Slipping in another test case here: we have some external certs, but none of them are the desired cert; the cert is actually embedded */
    OFForEachInArray(sigs, OFXMLSignatureTest *, sig, [sig setKeySource:keyFromExternalCertificate]);
    [[sigs objectAtIndex:0] loadExternalCerts:[[self baseDir] stringByAppendingPathComponent:@"certs"]];
    OFForEachInArray(sigs, OFXMLSignature *, sig,
                     OBShouldNotError([sig processSignatureElement:&error]);
                     [self checkReferences:sig];);
    
    [p release];
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
            [NSException raise:NSGenericException format:@"Unable to create temp keychain: %@", OFStringFromCSSMReturn(oserr)];
        }
        
        testKeychainPath = [filename copy];
        
        CSSM_CSP_HANDLE keychainCSP = CSSM_INVALID_HANDLE;
        oserr = SecKeychainGetCSPHandle(newKeychain, &keychainCSP);
        if (oserr != noErr) {
            [NSException raise:NSGenericException format:@"Unable to get keychain CSP: %@", OFStringFromCSSMReturn(oserr)];
        }
                
        SecKeyRef pubKey, privKey;
        
        pubKey = privKey = NULL;
        oserr = SecKeyCreatePair(newKeychain, CSSM_ALGID_RSA, 768, CSSM_INVALID_HANDLE, CSSM_KEYUSE_VERIFY, CSSM_KEYATTR_EXTRACTABLE | CSSM_KEYATTR_PERMANENT, CSSM_KEYUSE_SIGN,  CSSM_KEYATTR_SENSITIVE | CSSM_KEYATTR_PERMANENT, NULL, &pubKey, &privKey);
        if (oserr != noErr) {
            [NSException raise:NSGenericException format:@"Unable to create temporary RSA-768 key: %@", OFStringFromCSSMReturn(oserr)];
        }
        CFRelease(pubKey);
        CFRelease(privKey);
        
        pubKey = privKey = NULL;
        oserr = SecKeyCreatePair(newKeychain, CSSM_ALGID_DSA, 512, CSSM_INVALID_HANDLE, CSSM_KEYUSE_VERIFY, CSSM_KEYATTR_EXTRACTABLE | CSSM_KEYATTR_PERMANENT, CSSM_KEYUSE_SIGN, CSSM_KEYATTR_SENSITIVE | CSSM_KEYATTR_PERMANENT, NULL, &pubKey, &privKey);
        if (oserr != noErr) {
            [NSException raise:NSGenericException format:@"Unable to create temporary DSA-512 key: %@", OFStringFromCSSMReturn(oserr)];
        }
        CFRelease(pubKey);
        CFRelease(privKey);
        
        CFRelease(newKeychain);
    }
}

- (void)setUp;
{
    if (!kc) {
        OSStatus oserr = SecKeychainOpen([testKeychainPath fileSystemRepresentation], &kc);
        if (oserr != noErr || kc == NULL) {
            [NSException raise:NSGenericException format:@"Unable to open temp keychain: %@", OFStringFromCSSMReturn(oserr)];
        }
    }
}

- (void)tearDown;
{
    if (kc != NULL) {
        CFRelease(kc);
        kc = NULL;
    }
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
        [testKeychainPath release];
        testKeychainPath = nil;
    }
}

- (xmlDocPtr)_readDoc:(NSString *)rsrcName
{
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

xmlNode *applySigBlob(xmlDoc *tree, const xmlChar *sigAlg, const xmlChar *canonAlg)
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

xmlNode *addRefNode(xmlNode *sigNode, const xmlChar *uri, const xmlChar *digestAlg, const xmlChar *xformAlg)
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

- (void)testSign;
{
    xmlDoc *info = [self _readDoc:@"0001-Namespaces.svg"];
    xmlNode *sigNode = applySigBlob(info, XMLPKSignaturePKCS1_v1_5, ((const xmlChar *)"http://www.w3.org/2001/10/xml-exc-c14n#"));
    /* xmlNode *refNode = */ addRefNode(sigNode, (const xmlChar *)"", XMLDigestSHA224, NULL);
    
    OFXMLSignature *sig = [[OFXMLSignature alloc] initWithElement:sigNode inDocument:info];
    NSError *error;
    OBShouldNotError([sig computeReferenceDigests:&error]);

    BOOL signSuccess = [sig processSignatureElement:OFXMLSignature_Sign error:&error];
    STAssertFalse(signSuccess, @"Should fail to sign since no key is available");
    
    [sig release];
    
    NSArray *sigs = [OFXMLSignatureTest signaturesInTree:info];
    STAssertEquals((unsigned)[sigs count], 1u, @"Should be exactly one signature node in this tree");
    OFXMLSignatureTest *sigt = [sigs objectAtIndex:0];
    [sigt setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sigt setKeychain:kc];
    OBShouldNotError([sigt processSignatureElement:OFXMLSignature_Sign error:&error]);
    
    // xmlDocDump(stdout, info);
    
    sigs = [OFXMLSignatureTest signaturesInTree:info];
    STAssertEquals((unsigned)[sigs count], 1u, @"Should be exactly one signature node in this tree");
    sigt = [sigs objectAtIndex:0];
    [sigt setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sigt setKeychain:kc];
    OBShouldNotError([sigt processSignatureElement:OFXMLSignature_Verify error:&error]);    
    
    xmlFreeDoc(info);
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
    [sig release];
    
    sig = [[OFXMLSignatureTest alloc] initWithElement:sigNode inDocument:info];
    [sig setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sig setKeychain:kc];
    OBShouldNotError([sig processSignatureElement:OFXMLSignature_Verify error:&error]);
    OBShouldNotError([sig verifyReferenceAtIndex:0 toBuffer:NULL error:&error]);
    [sig release];
    
    // xmlDocDump(stdout, info);
    
    xmlNode *insert = xmlNewNode(NULL, (const xmlChar *)"breaky");
    xmlAddPrevSibling(xmlDocGetRootElement(info)->children, insert);
    
    NSArray *sigs = [OFXMLSignatureTest signaturesInTree:info];
    STAssertEquals((unsigned)[sigs count], 1u, @"Should be exactly one signature node in this tree");
    sig = [sigs objectAtIndex:0];
    [sig setKeySource:keyIsOnlyApplicableOneInKeychain];
    [sig setKeychain:kc];
    // This should succeed ...
    OBShouldNotError([sig processSignatureElement:OFXMLSignature_Verify error:&error]);    
    // ... but this should fail.
    BOOL verifiedOK = [sig verifyReferenceAtIndex:0 toBuffer:NULL error:&error];
    STAssertFalse(verifiedOK, @"Modified document should not pass verification");
    
    xmlUnlinkNode(insert);
    xmlFreeNode(insert);
    
    OBShouldNotError([sig verifyReferenceAtIndex:0 toBuffer:NULL error:&error]);    
    
    xmlFreeDoc(info);
}

@end

