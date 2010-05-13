// Copyright 2009-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUAppcastSignature.h"

#import <OmniFoundation/OFCDSAUtilities.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/OFXMLSignature.h>
#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");


@interface OSUAppcastSignature : OFXMLSignature
{
    NSArray *trustedKeys;
}

// API
@property (readwrite, retain) NSArray *trustedKeys;

@end

@implementation OSUAppcastSignature

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
- (OFCSSMKey *)getPublicKey:(xmlNode *)keyInfo algorithm:(CSSM_ALGORITHMS)keytype error:(NSError **)outError;
{
    if (![trustedKeys count])
        return [super getPublicKey:keyInfo algorithm:keytype error:outError];
    
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
    
    OFCSSMKey *resultKey = nil;
    
    CFIndex auxCertCount = CFArrayGetCount(auxCertificates);
    OFForEachObject([testCertificates objectEnumerator], id, certReference) {
        SecCertificateRef testCert = (SecCertificateRef)certReference;
        
        // Create a trust evaluation context for this cert, including the auxiliary certificates in the group
        CFMutableArrayRef certGroup = CFArrayCreateMutable(kCFAllocatorDefault, 1 + auxCertCount, &kCFTypeArrayCallBacks);
        CFArrayAppendValue(certGroup, testCert); // Cert to test is at index 0
        CFArrayAppendArray(certGroup, auxCertificates, (CFRange){ .location = 0, .length = auxCertCount });
        SecTrustRef evaluationContext;
        OSStatus err = SecTrustCreateWithCertificates(certGroup, trustPolicy, &evaluationContext);
        CFRelease(certGroup);
        
        if (err != noErr) {
            NSLog(@"SecTrustCreateWithCertificates returns %ld", (long)err);
            continue;
        }
        
        // Replace the default set of anchors with our own. We don't want to trust the system set.
        // (Might want to allow that as an option someday, though.)
        err = SecTrustSetAnchorCertificates(evaluationContext, (CFArrayRef)trustedKeys);
//        if (err == noErr)
//            err = SecTrustSetKeychains(evaluationContext, emptyArray);
        if (err != noErr) {
            NSLog(@"SecTrustSet[AnchorCertificates|Keychains] returns %ld", (long)err);
            CFRelease(evaluationContext);
            continue;
        }

        // If needed: SecTrustSetParameters(evaluationContext, ..., ...)
        
        SecTrustResultType trustResult;
        err = SecTrustEvaluate(evaluationContext, &trustResult);
        if (err != noErr) {
            NSLog(@"SecTrustEvaluate returns %ld", (long)err);
            CFRelease(evaluationContext);
            continue;
        }
        
        NSLog(@"SecTrustEvaluate -> %@", OFSummarizeTrustResult(evaluationContext));
        
        /*
         
         I find the "Unspecified" result a little confusing. Apparently it means the mechanical verification is completely successful, but the user hasn't said anything in particular about the trust of this cert, other than having it in the anchors list (or in our case, we've put it in our own anchors list and never set any specific trust settings, so this is always what we'll get). That's good enough for us, since we're actually updating ourselves.
         
         This info is from a post to the apple-cdsa mailing list by PerryTheCynic <perry@apple.com> on 1 May 2007:
         
         "Unspecified means that the user never expressed any persistent opinion about this certificate (or any of its signers). Either this is the first time this certificate has been encountered (in these circumstances), or the user has previously dealt with it on a one-off basis without recording a persistent decision. In practice, this is what most (cryptographically successful) evaluations return. [....] The application gets to choose what it wants to do in the Unspecified case. In effect, it will map this return to either Proceed or Ask, depending on the level of paranoia it wishes to apply. Most existing clients map to Proceed and thus treat Unspecified as a success case. [...]"
         
         */
        
        if (trustResult == kSecTrustResultProceed || trustResult == kSecTrustResultUnspecified) {
            SecKeyRef trustedSigningKey = NULL;
            err = SecCertificateCopyPublicKey(testCert, &trustedSigningKey);
            if (err != noErr) {
                stashError(errorInfo, err, @"SecCertificateCopyPublicKey");
                // Keep going, in case another key works
            } else {
                errorInfo = nil; // Suppress overwrite of *outError
                resultKey = [OFCSSMKey keyFromKeyRef:trustedSigningKey error:outError];
            }
        } else {
            [errorInfo setObject:OFSummarizeTrustResult(evaluationContext) forKey:@"trustResult"];
        }
        
        CFRelease(evaluationContext);
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
    
    // We don't want objects which reference the doc to live longer than the doc does
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSError *firstSignatureFailure = nil;
    NSError *firstChecksumFailure = nil;
    
    NSArray *signatures = [OSUAppcastSignature signaturesInTree:untrustedDoc];
    OFForEachObject([signatures objectEnumerator], OSUAppcastSignature *, signature) {
        [signature setTrustedKeys:trusts];
        
        NSError *thisError = nil;
        
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
    
    NSError *resultError = nil;
    if ([results count] == 0) {
        if (firstChecksumFailure)
            resultError = [firstChecksumFailure retain];
        else if (firstSignatureFailure)
            resultError = [firstSignatureFailure retain];
    }
    
    [pool release];
    
    xmlFreeDoc(untrustedDoc);
    
    if (resultError) {
        [resultError autorelease];
        if (outError)
            *outError = resultError;
        return nil;
    } else 
        return results;
}

