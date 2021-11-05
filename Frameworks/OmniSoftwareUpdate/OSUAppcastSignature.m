// Copyright 2009-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUAppcastSignature.h"

#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/OFXMLSignature.h>
#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFSecurityUtilities.h>
#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");


@interface OSUAppcastSignature : OFXMLSignature

// API
@property (nonatomic, retain) NSArray *trustedKeys;

@end

@implementation OSUAppcastSignature
{
    NSArray *trustedKeys;
}

@synthesize trustedKeys;

static void stashError(NSMutableDictionary *errorInfo, OSStatus code, NSString *where)
{
    NSDictionary *userInfo;
    
    if (where)
        userInfo = [NSDictionary dictionaryWithObject:where forKey:@"function"];
    else
        userInfo = nil;
    
    [errorInfo setObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:code userInfo:userInfo] forKey:NSUnderlyingErrorKey];
}

// API
- (SecKeyRef)copySecKeyForMethod:(xmlNode *)signatureMethod keyInfo:(xmlNode *)keyInfo operation:(enum OFXMLSignatureOperation)op error:(NSError **)outError;
{
    if (![trustedKeys count] || op != OFXMLSignature_Verify)
        return [super copySecKeyForMethod:signatureMethod keyInfo:keyInfo operation:op error:outError];
    
    CFMutableArrayRef auxCertificates = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, (CFArrayRef)trustedKeys);
    NSMutableDictionary *errorInfo = [NSMutableDictionary dictionary];
    NSArray *testCertificates = OFXMLSigFindX509Certificates(keyInfo, auxCertificates, errorInfo);
    
    CFArrayRef emptyArray = CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
    SecPolicyRef trustPolicy = NULL;
    
    if (0) {
    fail_out:
        if (trustPolicy)
            CFRelease(trustPolicy);
        CFRelease(auxCertificates);
        CFRelease(emptyArray);
        return nil;
    }
    
    if (![testCertificates count]) {
        if (outError) {
            [errorInfo setObject:@"Could not find public key certificate" forKey:NSLocalizedDescriptionKey];
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationFailure userInfo:errorInfo];
        }
        goto fail_out;
    }
        
    // OK, we have:
    //   - A set of certificates (probably only 1) for keys we could use
    //   - A set of certificates we trust (e.g., CAs or hardcoded leaves)
    //   - A set of auxiliary certificates (e.g. intermediate trust chain)
    
    // We need to find the first cert in testCertificates which we can trust (and which has the right key type...), and return its key.
    // We use the SecTrust functions, which are just wrappers around the CSSM TP functions.

    // First off, we have to get the trust policy we use. 
    trustPolicy = SecPolicyCreateBasicX509(); /* Starting with 10.6 we have this convenience function */
    
    // Now we have some certificates and a trust policy, we can check whether we trust any of the certificates.
    
    SecKeyRef resultKey = NULL;
    
    CFIndex auxCertCount = CFArrayGetCount(auxCertificates);
    OFForEachObject([testCertificates objectEnumerator], id, certReference) {
        SecCertificateRef testCert = (__bridge SecCertificateRef)certReference;
        
        // Create a trust evaluation context for this cert, including the auxiliary certificates in the group
        CFMutableArrayRef certGroup = CFArrayCreateMutable(kCFAllocatorDefault, 1 + auxCertCount, &kCFTypeArrayCallBacks);
        CFArrayAppendValue(certGroup, testCert); // Cert to test is at index 0
        CFArrayAppendArray(certGroup, auxCertificates, (CFRange){ .location = 0, .length = auxCertCount });
        SecTrustRef evaluationContext;
        OSStatus err = SecTrustCreateWithCertificates(certGroup, trustPolicy, &evaluationContext);
        CFRelease(certGroup);
        
        if (err != noErr) {
            NSLog(@"SecTrustCreateWithCertificates returns %@", OFOSStatusDescription(err));
            continue;
        }
        
        // Replace the default set of anchors with our own. We don't want to trust the system set.
        // (Might want to allow that as an option someday, though.)
        err = SecTrustSetAnchorCertificates(evaluationContext, (__bridge CFArrayRef)trustedKeys);
        if (err != noErr) {
            NSLog(@"SecTrustSet[AnchorCertificates|Keychains] returns %@", OFOSStatusDescription(err));
            CFRelease(evaluationContext);
            continue;
        }

        CFErrorRef error;
        BOOL sucess = SecTrustEvaluateWithError(evaluationContext, &error);

        if (!sucess) {
            NSLog(@"SecTrustEvaluate returns %@", CFAutorelease(CFErrorCopyDescription(error)));
            [errorInfo setObject:OFSummarizeTrustResult(evaluationContext) forKey:@"trustResult"];
            CFRelease(evaluationContext);
            CFRelease(error);
            continue;
        } else {
            SecKeyRef trustedSigningKey = SecCertificateCopyKey(testCert);
            if (trustedSigningKey == NULL) {
                // See SecItem-OFExtensions.swift for a note on this.
                stashError(errorInfo, errSecUnsupportedKeyFormat, @"SecCertificateCopyKey");
                // Keep going, in case another key works
            } else {
                errorInfo = nil; // Suppress overwrite of *outError
                resultKey = trustedSigningKey;
            }
        }
        
        CFRelease(evaluationContext);
        
        if (resultKey)
            break;
    }
    
    if (!resultKey) {
        if (outError && errorInfo) {
            [errorInfo setObject:@"Unable to trust the signing key" forKey:NSLocalizedDescriptionKey];
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationFailure userInfo:errorInfo];
        }
        goto fail_out;
    }

    CFRelease(trustPolicy);
    CFRelease(auxCertificates);
    CFRelease(emptyArray);

    return resultKey;
}

@end

#import <libxml/parser.h>

NSArray *OSUGetSignedPortionsOfAppcast(NSData *xmlData, NSString *pemFile, NSError **outError)
{
    NSArray *trusts = OFReadCertificatesFromFile(pemFile, kSecFormatPEMSequence, outError);
    if (!trusts)
        return nil;
    
    NSUInteger xmlDataLength = [xmlData length];
    if (xmlDataLength >= INT_MAX) {
        if (outError)
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadTooLargeError userInfo:nil];
        return nil;
    }
    
    xmlDoc *untrustedDoc = xmlParseMemory([xmlData bytes], (int)xmlDataLength);
    if (!untrustedDoc) {
        if (outError)
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationError userInfo:nil];
        return nil;
    }
    
    NSMutableArray *results = [NSMutableArray array];
    NSError *resultError = nil;

    // We don't want objects which reference the doc to live longer than the doc does
    @autoreleasepool {
        NSError *firstSignatureFailure = nil;
        NSError *firstChecksumFailure = nil;
        
        NSArray *signatures = [OSUAppcastSignature signaturesInTree:untrustedDoc];
        OFForEachObject([signatures objectEnumerator], OSUAppcastSignature *, signature) {
            [signature setTrustedKeys:trusts];
            
            __autoreleasing NSError *thisError = nil;
            
            BOOL ok = [signature processSignatureElement:&thisError];
            if (ok) {
                NSUInteger signedStuffCount = [signature countOfReferenceNodes];
                for(NSUInteger signedStuffIndex = 0; signedStuffIndex < signedStuffCount; signedStuffIndex ++) {
                    if ([signature isLocalReferenceAtIndex:signedStuffIndex]) {
                        NSData *verified = [signature verifiedReferenceAtIndex:signedStuffIndex error:&thisError];
                        if (verified)
                            [results addObject:verified];
                        else {
                            NSLog(@"OmniSoftwareUpdate: (ref %u) %@", (unsigned)signedStuffIndex, [thisError description]);
                            if (firstChecksumFailure == nil)
                                firstChecksumFailure = thisError;
                        }
                    }
                }
            } else {
                NSLog(@"OmniSoftwareUpdate: %@", [thisError description]);
                if (firstSignatureFailure == nil)
                    firstSignatureFailure = thisError;
            }
        }
        
        if ([results count] == 0) {
            if (firstChecksumFailure)
                resultError = firstChecksumFailure;
            else if (firstSignatureFailure)
                resultError = firstSignatureFailure;
        }
    }
    
    xmlFreeDoc(untrustedDoc);
    
    if (resultError) {
        if (outError)
            *outError = resultError;
        return nil;
    } else 
        return results;
}

