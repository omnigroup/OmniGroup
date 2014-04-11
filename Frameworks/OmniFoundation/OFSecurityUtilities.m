// Copyright 2009-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSecurityUtilities.h>

#import <OmniFoundation/OFFeatures.h>
#import <Security/Security.h>
#import <Security/SecTrust.h>

RCS_ID("$Id$");

static const struct { SecTrustResultType code; NSString *display; } results[] = {
    { kSecTrustResultInvalid, @"Invalid" },
    { kSecTrustResultProceed, @"Proceed" },
#if defined(MAC_OS_X_VERSION_MIN_REQUIRED) && (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_9)
    { kSecTrustResultConfirm, @"Confirm" }, /* Removed in 10.9 */
#endif
    { kSecTrustResultDeny, @"Deny" },
    { kSecTrustResultUnspecified, @"Unspecified" },
    { kSecTrustResultRecoverableTrustFailure, @"RecoverableTrustFailure" },
    { kSecTrustResultFatalTrustFailure, @"FatalTrustFailure" },
    { kSecTrustResultOtherError, @"OtherError" },
    { 0, nil }
};

#if OF_ENABLE_CDSA

#pragma clang diagnostic ignored "-Wdeprecated-declarations" // TODO: Avoid using deprecated CSSM API

static const struct { CSSM_TP_APPLE_CERT_STATUS bit; NSString *display; } statusBits[] = {
    { CSSM_CERT_STATUS_EXPIRED, @"EXPIRED" },
    { CSSM_CERT_STATUS_NOT_VALID_YET, @"NOT_VALID_YET" },
    { CSSM_CERT_STATUS_IS_IN_INPUT_CERTS, @"IS_IN_INPUT_CERTS" },
    { CSSM_CERT_STATUS_IS_IN_ANCHORS, @"IS_IN_ANCHORS" },
    { CSSM_CERT_STATUS_IS_ROOT, @"IS_ROOT" },
    { CSSM_CERT_STATUS_IS_FROM_NET, @"IS_FROM_NET" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_FOUND_USER, @"SETTINGS_FOUND_USER" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_FOUND_ADMIN, @"SETTINGS_FOUND_ADMIN" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_FOUND_SYSTEM, @"SETTINGS_FOUND_SYSTEM" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_TRUST, @"SETTINGS_TRUST" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_DENY, @"SETTINGS_DENY" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_IGNORED_ERROR, @"SETTINGS_IGNORED_ERROR" },
    { 0, nil }
};

NSString *OFSummarizeTrustResult(SecTrustRef evaluationContext)
{
    SecTrustResultType trustResult;
    CFArrayRef chain = NULL;
    CSSM_TP_APPLE_EVIDENCE_INFO *stats = NULL;
    if (SecTrustGetResult(evaluationContext, &trustResult, &chain, &stats) != noErr) {
        return @"[SecTrustGetResult failure]";
    }
    
    NSMutableString *buf = [NSMutableString stringWithFormat:@"Trust result = %d", (int)trustResult];
    for(int i = 0; results[i].display; i++) {
        if(results[i].code == trustResult) {
            [buf appendFormat:@" (%@)", results[i].display];
        }
    }
    
    for(CFIndex i = 0; i < CFArrayGetCount(chain); i++) {
        SecCertificateRef c = (SecCertificateRef)CFArrayGetValueAtIndex(chain, i);
        CFStringRef cert = CFCopyDescription(c);
        [buf appendFormat:@"\n   %@: status=%08x ", cert, stats[i].StatusBits];
        CFRelease(cert);
        NSMutableArray *codez = [NSMutableArray array];
        
        for(int b = 0; statusBits[b].display; b ++) {
            if ((statusBits[b].bit & stats[i].StatusBits) == statusBits[b].bit)
                [codez addObject:statusBits[b].display];
        }
        if ([codez count]) {
            [buf appendFormat:@"(%@) ", [codez componentsJoinedByComma]];
            [codez removeAllObjects];
        }
        
        for(unsigned int ret = 0; ret < stats[i].NumStatusCodes; ret++)
            [codez addObject:OFStringFromCSSMReturn(stats[i].StatusCodes[ret])];
    }
    
    CFRelease(chain);
    
    return buf;
}

#else

NSString *OFSummarizeTrustResult(SecTrustRef evaluationContext)
{
    OSStatus err;
    SecTrustResultType trustResult;
    
    err = SecTrustGetTrustResult(evaluationContext, &trustResult);
    if (err != noErr) {
        return [NSString stringWithFormat:@"[SecTrustGetTrustResult failure: %@]", OFOSStatusDescription(err)];
    }
    
    NSMutableString *buf = [NSMutableString stringWithFormat:@"Trust result = %d", (int)trustResult];
    for(int i = 0; results[i].display; i++) {
        if(results[i].code == trustResult) {
            [buf appendFormat:@" (%@)", results[i].display];
        }
    }
    
    CFArrayRef certProperties = SecTrustCopyProperties(evaluationContext);
    for(CFIndex i = 0; i < CFArrayGetCount(certProperties); i++) {
        NSDictionary *c = (NSDictionary *)CFArrayGetValueAtIndex(certProperties, i);
        [buf appendFormat:@"\n  "];
        for (NSString *k in c) {
            [buf appendFormat:@" %@=%@", k, [[c objectForKey:k] description]];
        }
    }
    CFRelease(certProperties);
    
    return buf;
}

#endif
