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

#if !TARGET_OS_IPHONE
static enum OFKeyAlgorithm OFSecKeyGetAlgorithm_CSSM(SecKeyRef aKey, SecItemClass *outItemClass, unsigned int *outKeySize, uint32_t *outKeyFlags, NSError **err);
#endif
static enum OFKeyAlgorithm OFSecKeyGetAlgorithm_CopyMatching(SecKeyRef aKey, OFSecItemClass *outItemClass, unsigned int *outKeySize, uint32_t *outKeyFlags, NSError **err);
static BOOL describeSecItem(CFTypeRef item, NSMutableString *buf);

#if TARGET_OS_IPHONE
#define internalSecErrorCode errSecInternalComponent
#else
#define internalSecErrorCode errSecInternalError
#endif

static const struct { SecTrustResultType code; __unsafe_unretained NSString *display; } results[] = {
    { kSecTrustResultInvalid, @"Invalid" },
    { kSecTrustResultProceed, @"Proceed" },
#if defined(MAC_OS_X_VERSION_MIN_REQUIRED) && (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_9) && !TARGET_OS_IPHONE
    { kSecTrustResultConfirm, @"Confirm" }, /* Removed in 10.9 */
#endif
    { kSecTrustResultDeny, @"Deny" },
    { kSecTrustResultUnspecified, @"Unspecified" },
    { kSecTrustResultRecoverableTrustFailure, @"RecoverableTrustFailure" },
    { kSecTrustResultFatalTrustFailure, @"FatalTrustFailure" },
    { kSecTrustResultOtherError, @"OtherError" },
    { 0, nil }
};

static const struct { enum OFKeyAlgorithm algid; NSString *name; } algnames[] = {
    { ka_DH,               @"DH" },       // Diffie-Hellman
//  { CSSM_ALGID_PH,       @"PH" },       // Pohlig-Hellman
    { ka_RSA,              @"RSA" },
    { ka_DSA,              @"DSA" },
//  { CSSM_ALGID_MQV,      @"MQV" },      // Menezes-Qu-Vanstone key agreement
//  { CSSM_ALGID_ElGamal,  @"ElGamal" },
    
    { ka_EC,               @"EC" },
//  { CSSM_ALGID_ECMQV,    @"ECMQV" },
    
    { ka_AES,              @"AES" },
    { ka_DES,              @"DES" },
};

#define arraycount(a) (sizeof(a)/sizeof(a[0]))

/* In order to correctly format DSA and ECDSA signatures, we need to know the key's "size" --- the number of bits it takes to represent a member of the generated group (aka the number of bits in the largest exponent the algorithm will use). On 10.6, 10.7, and some 10.8 betas, this information is returned by SecKeyGetBlockSize(). In 10.8, though, that function's behavior changed to return some other number (unclear what, although the documentation now indicates that it wasn't ever supposed to return the value it was returning in 10.6 and 10.7). Here we use SecKeyGetCSSMKey() or SecKeychainItemCopyAttributesAndData(); if SecItemCopyMatching() starts to work in some future OS release we could switch to that instead.
 
    RADAR references:
      SecItemCopyMatching - 10155924
      SecKeyGetBlockSize  - 11765613   (marked WONTFIX)
      No better API       - 11840882
*/

enum OFKeyAlgorithm OFSecKeyGetAlgorithm(SecKeyRef aKey, OFSecItemClass *outItemClass, unsigned int *outKeySize, uint32_t *outKeyFlags, NSError **err)
{
    enum OFKeyAlgorithm result;
    
#if !TARGET_OS_IPHONE
    /* First, try the method that usually works. Actually as far as I know this always works. */
    NSError *subErr1;
    result = OFSecKeyGetAlgorithm_CSSM(aKey, outItemClass, outKeySize, outKeyFlags, err? &subErr1 : NULL);
    if (result != ka_Failure)
        return result;
    
    /* Next, try SecKeychainItemCopyAttributesAndData(), which works as long as the item came from a keychain. */
    NSError *subErr2;
    result = OFSecKeychainItemGetAlgorithm((SecKeychainItemRef)aKey, outItemClass, outKeySize, outKeyFlags, err? &subErr2 : NULL);
    if (result != ka_Failure)
        return result;
#endif
    
    /* As a last resort, try SecItemCopyMatching(). This function has a history of failing for no apparent reason and sometimes even returning information for a *different key*, so we really don't want to use it. [Wiml: verified broken in 10.7 and 10.9] */
    NSError *subErr3;
    result = OFSecKeyGetAlgorithm_CopyMatching(aKey, outItemClass, outKeySize, outKeyFlags, err? &subErr3 : NULL);
    if (result != ka_Failure)
        return result;
    
    if (err) {
        NSMutableDictionary *infos = [NSMutableDictionary dictionaryWithObject:@"Unable to retrieve key parameters" forKey:NSLocalizedDescriptionKey];
#if !TARGET_OS_IPHONE
        [infos setObject: @[ subErr1, subErr2, subErr3 ] forKey: @"UnderlyingErrors"];
#else
        [infos setObject:subErr3 forKey:NSUnderlyingErrorKey];
#endif
        *err = [NSError errorWithDomain:NSOSStatusErrorDomain code:internalSecErrorCode userInfo:infos];
    }
    
    return ka_Failure;
}

NSString *OFSecKeyAlgorithmDescription(enum OFKeyAlgorithm alg, unsigned int keySizeBits)
{
    NSString *algorithmName = nil;
    
    for(unsigned i = 0; i < arraycount(algnames); i++) {
        if(algnames[i].algid == alg) {
            algorithmName = algnames[i].name;
            break;
        }
    }
    
    if (!algorithmName) {
        algorithmName = NSLocalizedStringWithDefaultValue(@"Unknown(cryptographic algorithm)", @"OmniFoundation", OMNI_BUNDLE, @"Unknown", @"Name used for unknown algorithm (instead of RSA, DSA, ECDH, etc.)");
    }
    
    if (keySizeBits)
        return [NSString stringWithFormat:@"%@-%u", algorithmName, keySizeBits];
    else
        return algorithmName;
}

/* The main reason for OFSecItemDescription() to exist is so that I can tell what the 10.7 crypto APIs are returning to me. Unfortunately, one of the more inscrutably buggy APIs is SecItemCopyMatching(), which is the only way to inspect a key ref in the new world. So using that call to debug itself is kind of counterproductive. */
NSString *OFSecItemDescription(CFTypeRef item)
{
    if (item == NULL)
        return @"(null)";
    
    CFTypeID what = CFGetTypeID(item);
    NSString *classname = CFBridgingRelease(CFCopyTypeIDDescription(what));
    NSMutableString *buf = [NSMutableString stringWithFormat:@"<%@ %p:", classname, item];
    
    if (describeSecItem(item, buf)) {
        [buf appendString:@">"];
        return buf;
    }
    
    return [(__bridge id)item description]; // Fall back on crappy CoreFoundation description
}

static BOOL describeSecItem(CFTypeRef item, NSMutableString *buf)
{
    CFTypeID itemType = CFGetTypeID(item);
    
    if (itemType == SecCertificateGetTypeID()) {
        [buf appendString:@" Certificate"];
        return YES;
    }
    
    if (itemType == SecIdentityGetTypeID()) {
        [buf appendString:@" Identity"];
        return YES;
    }
    
    if (itemType == SecKeyGetTypeID()
#if !TARGET_OS_IPHONE
        || itemType == SecKeychainItemGetTypeID()
#endif
        ) {
        enum OFKeyAlgorithm alg;
        unsigned int keySize;
        uint32_t usage;
        OFSecItemClass returnedClass;
        
        returnedClass = 0;
        keySize = 0;
        usage = 0;
        alg = OFSecKeyGetAlgorithm((SecKeyRef)item, &returnedClass, &keySize, &usage, NULL);
        if (alg != ka_Failure && returnedClass != 0) {
            if (returnedClass == kSecPublicKeyItemClass) {
                [buf appendString:@" Public"];
            } else if (returnedClass == kSecPrivateKeyItemClass) {
                [buf appendString:@" Private"];
            } else if (returnedClass == kSecSymmetricKeyItemClass) {
                [buf appendString:@" Symmetric"];
            }
            [buf appendString:@" "];
            [buf appendString:OFSecKeyAlgorithmDescription(alg, keySize)];
            
            if (usage) {
                [buf appendString:@" ["];
                if (usage & kOFKeyUsageEncrypt)    [buf appendString:@"E"];
                if (usage & kOFKeyUsageDecrypt)    [buf appendString:@"D"];
                if (usage & kOFKeyUsageDerive)     [buf appendString:@"R"];
                if (usage & kOFKeyUsageSign)       [buf appendString:@"S"];
                if (usage & kOFKeyUsageVerify)     [buf appendString:@"V"];
                if (usage & kOFKeyUsageWrap)       [buf appendString:@"W"];
                if (usage & kOFKeyUsageUnwrap)     [buf appendString:@"U"];
                [buf appendString:@"]"];
                
                if (usage & kOFKeyUsagePermanent)
                    [buf appendString:@" perm"];
                if (usage & kOFKeyUsageTemporary)
                    [buf appendString:@" temp"];
            }
            
            return YES;
        }
    }
    
#if !( defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE )
    {
        OFSecItemClass returnedClass;
        
        /* First, discover the item's class. CFGetTypeID() doesn't distinguish between (eg) public, private, and symmetric keys. */
        returnedClass = 0;
        OSStatus oserr = SecKeychainItemCopyAttributesAndData((SecKeychainItemRef)item, NULL, &returnedClass, NULL, NULL, NULL);
        if (oserr == noErr) {
            if (returnedClass == kSecInternetPasswordItemClass || returnedClass == CSSM_DL_DB_RECORD_INTERNET_PASSWORD ||
                returnedClass == kSecGenericPasswordItemClass || returnedClass == CSSM_DL_DB_RECORD_GENERIC_PASSWORD) {
                [buf appendString:@" Password"];
                return YES;
            } else if (returnedClass == kSecPublicKeyItemClass) {
                [buf appendString:@" Public"];
                return YES;
            } else if (returnedClass == kSecPrivateKeyItemClass) {
                [buf appendString:@" Private"];
                return YES;
            } else if (returnedClass == kSecSymmetricKeyItemClass) {
                [buf appendString:@" Symmetric"];
                return YES;
            } else if (returnedClass == kSecCertificateItemClass) {
                [buf appendString:@" Certificate"];
                return YES;
            } else {
                // Unknown class. Not sure we can do any better than -description here.
            }
        }
    }
#endif
    
    return NO;
}

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
#if TARGET_OS_IPHONE
        /* iOS hates usability */
        return [NSString stringWithFormat:@"[SecTrustGetTrustResult failure: code %d]", (int)err];
#else
        return [NSString stringWithFormat:@"[SecTrustGetTrustResult failure: %@]", OFOSStatusDescription(err)];
#endif
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

static Boolean getboolattr(CFDictionaryRef dict, CFTypeRef dictKey)
{
    CFTypeRef value = NULL;
    if (CFDictionaryGetValueIfPresent(dict, dictKey, &value) && value) {
        return CFBooleanGetValue(value);
    } else {
        return false;
    }
}

static enum OFKeyAlgorithm OFSecKeyGetAlgorithm_CopyMatching(SecKeyRef aKey, OFSecItemClass *outItemClass, unsigned int *outKeySize, uint32_t *outKeyFlags, NSError **err)
{
    enum OFKeyAlgorithm keyType;
    
    /* We use kSecUseItemList+kSecMatchItemList because it sometimes works, although the documentation suggests we should use kSecMatchItemList (kSecUseItemList is in "Other Constants", which isn't listed as one of the sets of constants SecItemCopyMatching() looks at). This set of parameters is chosen because it tickles SecItemCopyMatching()'s bugs in a detectable way--- it tends to return information about the wrong key, and we'd rather fail here than return garbage. */
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSArray arrayWithObject:(__bridge id)aKey], (id)kSecUseItemList,
                           //[NSArray arrayWithObject:(__bridge id)aKey], (id)kSecMatchItemList,
                           (id)kCFBooleanTrue, (id)kSecReturnAttributes,
                           (id)kCFBooleanTrue, (id)kSecReturnRef,
                           (id)kSecMatchLimitAll, (id)kSecMatchLimit,
                           (id)kSecClassKey, (id)kSecClass,
                           nil];
    CFTypeRef result = NULL;
    OSStatus rc = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (err != noErr || !result) {
        if (err) {
            *err = [NSError errorWithDomain:NSOSStatusErrorDomain
                                       code:rc
                                   userInfo:@{ NSLocalizedDescriptionKey: @"SecItemCopyMatching failed" }];
        }
        return ka_Failure;
    }
    
    /* Sanity check the result, because SecItemCopyMatching() has a history of being extremely buggy and returning bogus data, or data for other items in the keychain */
    if (CFGetTypeID(result) != CFArrayGetTypeID()) {
    sicm_invalid:
        {
            static BOOL whined;
            if (!whined)
                NSLog(@"Attempting to work around RADAR #10155924");
            whined = YES;
        }
        if (err)
            *err = [NSError errorWithDomain:NSOSStatusErrorDomain
                                       code:internalSecErrorCode
                                   userInfo:@{ NSLocalizedDescriptionKey: @"Invalid result from SecItemCopyMatching (RADAR 10155924)" }];
        CFRelease(result);
        return ka_Failure;
    }
    if (CFArrayGetCount(result) != 1) {
        goto sicm_invalid;
    }
    CFDictionaryRef attrs = CFArrayGetValueAtIndex(result, 0);
    if (!attrs || CFGetTypeID(attrs) != CFDictionaryGetTypeID()) {
        goto sicm_invalid;
    }
    CFTypeRef returnedClass = NULL;
    if (!CFDictionaryGetValueIfPresent(attrs, kSecClass, &returnedClass) || !returnedClass || !CFEqual(returnedClass, kSecClassKey)) {
        /* This could be just a bad caller, not SecItemCopyMatching() badness, so don't whine */
        if (err)
            *err = [NSError errorWithDomain:NSOSStatusErrorDomain
                                       code:internalSecErrorCode
                                   userInfo:@{ NSLocalizedDescriptionKey: @"SecItemCopyMatching returned non-key class" }];
        CFRelease(result);
        return ka_Failure;
    }
    CFTypeRef roundtrip = CFDictionaryGetValue(attrs, kSecValueRef);
    if (!roundtrip || CFGetTypeID(roundtrip) != CFGetTypeID(aKey) ||
        !CFEqual(roundtrip, aKey)) {
        goto sicm_invalid;
    }
    CFTypeRef keyClass = CFDictionaryGetValue(attrs, kSecAttrKeyClass);
    if (!keyClass) {
        goto sicm_invalid;
    }
    CFTypeRef keyAlg = CFDictionaryGetValue(attrs, kSecAttrKeyType);
    if (!keyAlg) {
        goto sicm_invalid;
    }
    
    /* Okay, we've verified that the results from SecItemCopyMatching() are basically plausible. Convert to common format. */
    
    if (CFEqual(keyAlg, kSecAttrKeyTypeRSA)) {
        keyType = ka_RSA;
    } else if (CFEqual(keyAlg, kSecAttrKeyTypeEC)) {
        keyType = ka_EC;
#if !TARGET_OS_IPHONE /* iOS has a really impoverished crypto subsystem */
    } else if (CFEqual(keyAlg, kSecAttrKeyTypeECDSA)) {
        keyType = ka_EC;
    } else if (CFEqual(keyAlg, kSecAttrKeyTypeDSA)) {
        keyType = ka_DSA;
    } else if (CFEqual(keyAlg, kSecAttrKeyTypeDES) || CFEqual(keyAlg, kSecAttrKeyType3DES)) {
        keyType = ka_DES;
    } else if (CFEqual(keyAlg, kSecAttrKeyTypeAES)) {
        keyType = ka_AES;
#endif
    } else {
        keyType = ka_Other;
    }
    
    if (outItemClass) {
        if (CFEqual(keyClass, kSecAttrKeyClassPublic)) {
            *outItemClass = kSecPublicKeyItemClass;
        } else if (CFEqual(keyClass, kSecAttrKeyClassPrivate)) {
            *outItemClass = kSecPrivateKeyItemClass;
        } else if (CFEqual(keyClass, kSecAttrKeyClassSymmetric)) {
            *outItemClass = kSecSymmetricKeyItemClass;
        } else {
            *outItemClass = 0;
        }
    }
    
    if (outKeySize) {
        CFTypeRef keySize;
        SInt32 sIntValue;

        keySize = CFDictionaryGetValue(attrs, kSecAttrEffectiveKeySize);
        if (!keySize)
            keySize = CFDictionaryGetValue(attrs, kSecAttrKeySizeInBits);
        
        if (!keySize)
            *outKeySize = 0;
        else if (CFGetTypeID(keySize) == CFNumberGetTypeID() && CFNumberGetValue(keySize, kCFNumberSInt32Type, &sIntValue) && sIntValue >= 0)
            *outKeySize = sIntValue;
#if TARGET_OS_IPHONE
        /* On iOS, kSecAttrKeySizeInBits is documented to be a CFNumber *or* a CFString. Barf. */
        else if (CFGetTypeID(keySize) == CFStringGetTypeID() && ( sIntValue = CFStringGetIntValue(keySize)) > 0)
            *outKeySize = sIntValue;
#endif
        else
            *outKeySize = 0;
    }
    
    if (outKeyFlags) {
        uint32_t flags = 0;
        
        if (getboolattr(attrs, kSecAttrCanEncrypt))  flags |= kOFKeyUsageEncrypt;
        if (getboolattr(attrs, kSecAttrCanDecrypt))  flags |= kOFKeyUsageDecrypt;
        if (getboolattr(attrs, kSecAttrCanSign))     flags |= kOFKeyUsageSign;
        if (getboolattr(attrs, kSecAttrCanVerify))   flags |= kOFKeyUsageVerify;
        if (getboolattr(attrs, kSecAttrCanWrap))     flags |= kOFKeyUsageWrap;
        if (getboolattr(attrs, kSecAttrCanUnwrap))   flags |= kOFKeyUsageUnwrap;
        if (getboolattr(attrs, kSecAttrCanDerive))   flags |= kOFKeyUsageDerive;
        if (getboolattr(attrs, kSecAttrIsPermanent)) flags |= kOFKeyUsagePermanent;
        
        if (getboolattr(attrs, kSecAttrAccessible))  flags |= kOFKeyUsagePermanent;
        
        /* Computing the "private" flag (which we take to mean "can be used without user interaction") is a little tricky with this API --- we would need to grovel around with kSecAttrAccess on OSX, possibly check kSecAttrAccessible on iOS, evaluate ACLs, etc.
        if (...) {
            flags |= (1u << kSecKeyPrivate);
        }
        */
        
        *outKeyFlags = flags;
    }
    
#if 0
    /* kSecAttrApplicationLabel: This attribute is used to look up a key programmatically; in particular, for keys of class kSecAttrKeyClassPublic and kSecAttrKeyClassPrivate, the value of this attribute is the hash of the public key. This item is a type of CFDataRef. Legacy keys may contain a UUID in this field as a CFStringRef. */
    CFTypeRef ski = CFDictionaryGetValue(attrs, kSecAttrApplicationLabel);
    if (ski != NULL && CFGetTypeID(ski) != CFDataGetTypeID())
        ski = NULL;
        
        if (ski_out) {
            *ski_out = CFRetain(ski);
        }
#endif
    
    CFRelease(result);
    
    return keyType;
}

#if !TARGET_OS_IPHONE
/* iOS has neither the Keychain APIs nor the CDSA APIs, only the SecItem APIs. */

static enum OFKeyAlgorithm cssmAlgToOFAlg(CSSM_ALGORITHMS algorithm, NSError **err)
{
    switch(algorithm) {
        case CSSM_ALGID_RSA:
            return ka_RSA;
        case CSSM_ALGID_DSA:
            return ka_DSA;
        case CSSM_ALGID_ECDSA:
        case CSSM_ALGID_ECDH:
        case CSSM_ALGID_ECC:
            return ka_EC;
        case CSSM_ALGID_DES:
        case CSSM_ALGID_3DES:
            return ka_DES;
        case CSSM_ALGID_AES:
            return ka_AES;
        case CSSM_ALGID_DH:
            return ka_DH;
        case CSSM_ALGID_NONE:
            if (err) {
                *err = [NSError errorWithDomain:NSOSStatusErrorDomain
                                           code:errSecInvalidAlgorithm
                                       userInfo:@{ NSLocalizedDescriptionKey: @"Key Algorithm is NONE"}];
            }
            return ka_Failure;
        default:
            return ka_Other;
    }
}

enum OFKeyAlgorithm OFSecKeychainItemGetAlgorithm(SecKeychainItemRef item, SecItemClass *outItemClass, unsigned int *outKeySize, uint32_t *outKeyFlags, NSError **err)
{
    /* SecKeychainItemCopyAttributesAndData() is not marked as deprecated on 10.7, but that's presumably an oversight on Apple's part, since it uses the CSSM_DB constants. Anyway, it only works for keys that are in a keychain, not for unattached keys. */

    OSStatus oserr;
    SecKeychainAttributeList *returnedAttributes;
    static const UInt32 keyAttributeTags[2]     = { kSecKeyKeyType, kSecKeyKeySizeInBits };
    static const UInt32 keyAttributeFormats[2]  = { CSSM_DB_ATTRIBUTE_FORMAT_UINT32, CSSM_DB_ATTRIBUTE_FORMAT_UINT32 };
    _Static_assert(arraycount(keyAttributeTags) == arraycount(keyAttributeFormats), "array size mismatch");
    
    static const UInt32 moreKeyAttributeTags[9]     = { kSecKeyPermanent, kSecKeyPrivate, kSecKeyEncrypt, kSecKeyDecrypt, kSecKeyDerive, kSecKeySign, kSecKeyVerify, kSecKeyWrap, kSecKeyUnwrap };
    static const UInt32 moreKeyAttributeFormats[9]  = { CSSM_DB_ATTRIBUTE_FORMAT_UINT32, CSSM_DB_ATTRIBUTE_FORMAT_UINT32, CSSM_DB_ATTRIBUTE_FORMAT_UINT32, CSSM_DB_ATTRIBUTE_FORMAT_UINT32, CSSM_DB_ATTRIBUTE_FORMAT_UINT32, CSSM_DB_ATTRIBUTE_FORMAT_UINT32, CSSM_DB_ATTRIBUTE_FORMAT_UINT32, CSSM_DB_ATTRIBUTE_FORMAT_UINT32, CSSM_DB_ATTRIBUTE_FORMAT_UINT32 };
    _Static_assert(arraycount(moreKeyAttributeTags) == arraycount(moreKeyAttributeFormats), "array size mismatch");

    
    SecKeychainAttributeInfo queryAttributes = { .count = arraycount(keyAttributeTags), .tag = (UInt32 *)keyAttributeTags, .format = (UInt32 *)keyAttributeFormats };
    
    returnedAttributes = NULL;
    oserr = SecKeychainItemCopyAttributesAndData(item, &queryAttributes, outItemClass, &returnedAttributes, NULL, NULL);
    if (oserr != noErr) {
        if (err)
            *err = [NSError errorWithDomain:NSOSStatusErrorDomain code:oserr userInfo:@{ NSLocalizedDescriptionKey: @"SecKeychainItemCopyAttributesAndData failed" }];
        return ka_Failure;
    }
    
    UInt32 attrIndex, attrValue;
    enum OFKeyAlgorithm keyAlg = ka_Failure;
    
    for (attrIndex = 0; attrIndex < returnedAttributes->count; attrIndex ++) {
        const SecKeychainAttribute *attr = &( returnedAttributes->attr[attrIndex] );
        if (attr->data == NULL)
            continue;
        
        if (attr->tag == kSecKeyKeyType && attr->length == 4) {
            memcpy(&attrValue, attr->data, 4);
            keyAlg = cssmAlgToOFAlg(attrValue, NULL);
        } else if (attr->tag == kSecKeyKeySizeInBits && attr->length == 4 && outKeySize) {
            memcpy(&attrValue, attr->data, 4);
            *outKeySize = attrValue;
        }
    }
    
    SecKeychainItemFreeAttributesAndData(returnedAttributes, NULL);
    
    if (keyAlg == ka_Failure) {
        if (err)
            *err = [NSError errorWithDomain:NSOSStatusErrorDomain
                                       code:errSecUnsupportedKeyFormat
                                   userInfo:@{ NSLocalizedDescriptionKey: @"Key attributes do not include kSecKeyKeyType" }];
        return ka_Failure;
    }
    
    if (outKeyFlags) {
        queryAttributes = (SecKeychainAttributeInfo){ .count = arraycount(moreKeyAttributeTags), .tag = (UInt32 *)moreKeyAttributeTags, .format = (UInt32 *)moreKeyAttributeFormats };

        returnedAttributes = NULL;
        oserr = SecKeychainItemCopyAttributesAndData(item, &queryAttributes, NULL, &returnedAttributes, NULL, NULL);
        if (oserr == noErr) {
            uint32_t itemFlags = 0;
            
            for (UInt32 ix = 0; ix < returnedAttributes->count; ix ++) {
                if (returnedAttributes->attr[ix].data == NULL ||
                    returnedAttributes->attr[ix].length != 4) {
                    /* Unexpected returned attribute; these should all be UINT32 */
                    continue;
                }
                
                SecKeychainAttrType tag = returnedAttributes->attr[ix].tag;
                UInt32 value;
                memcpy(&value, returnedAttributes->attr[ix].data, 4);
                if (value != 0) {
                    itemFlags |= ( 1u << tag );
                }
            }

            *outKeyFlags = itemFlags;

            SecKeychainItemFreeAttributesAndData(returnedAttributes, NULL);
        }
    }
    
    return keyAlg;
}

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static const struct { CSSM_KEYUSE keyUse; uint32_t keyFlag; } keyUseMap[] = {
    { CSSM_KEYUSE_ENCRYPT,   1u << kSecKeyEncrypt },
    { CSSM_KEYUSE_DECRYPT,   1u << kSecKeyDecrypt },
    { CSSM_KEYUSE_SIGN,      1u << kSecKeySign },
    { CSSM_KEYUSE_VERIFY,    1u << kSecKeyVerify },
    { CSSM_KEYUSE_WRAP,      1u << kSecKeyWrap },
    { CSSM_KEYUSE_UNWRAP,    1u << kSecKeyUnwrap },
    { CSSM_KEYUSE_DERIVE,    1u << kSecKeyDerive },
    //    CSSM_KEYUSE_SIGN_RECOVER =			0x00000010,
    //    CSSM_KEYUSE_VERIFY_RECOVER =		0x00000020,
    
    { CSSM_KEYUSE_ANY,      ((1u << kSecKeyEncrypt) |
                             (1u << kSecKeyDecrypt) |
                             (1u << kSecKeySign) |
                             (1u << kSecKeyVerify) |
                             (1u << kSecKeyWrap) |
                             (1u << kSecKeyUnwrap) |
                             (1u << kSecKeyDerive)) }

};

static enum OFKeyAlgorithm OFSecKeyGetAlgorithm_CSSM(SecKeyRef aKey, SecItemClass *outItemClass, unsigned int *outKeySize, uint32_t *outKeyFlags, NSError **err)
{
    /* This is the simplest, most reliable, most straightforward, best-documented way to get the information we need; needless to day, it's deprecated. See RADAR 11840882 for a request for a working replacement.
     
     Updated note: Some conversations with Apple engineers suggest that this is only kinda-deprecated, in that they'd rather we use other APIs if we can but it's still OK to use this API if necessary. In support of this, as of mid-2014 the OSX 10.10 documentation still has this paragraph despite the API having been marked deprecated in 10.7: "The OS X Keychain Services API provides functions to perform most of the operations needed by applications, [...] However, the underlying CSSM API provides more capabilities [...] For this reason, the Keychain Services API includes a number of functions that return or create CSSM structures so that, if you are familiar with the CSSM API, you can move freely back and forth between Keychain Services and CSSM."
     */
    
    OSStatus rc;
    const CSSM_KEY *keyinfo = NULL;
    rc = SecKeyGetCSSMKey(aKey, &keyinfo);
    if (rc != noErr) {
        if (err)
            *err = [NSError errorWithDomain:NSOSStatusErrorDomain code:rc userInfo:@{ NSLocalizedDescriptionKey: @"SecKeyGetCSSMKey failed" }];
        return ka_Failure;
    }
    
    if (keyinfo == NULL || keyinfo->KeyHeader.HeaderVersion != CSSM_KEYHEADER_VERSION) {
        if (err)
            *err = [NSError errorWithDomain:NSOSStatusErrorDomain
                                       code:errSecKeyHeaderInconsistent
                                   userInfo:@{ NSLocalizedDescriptionKey: @"SecKeyGetCSSMKey() returned an invalid key header" }];
        return ka_Failure;
    }
    
    if (outKeySize != NULL) {
        if (keyinfo->KeyHeader.LogicalKeySizeInBits > 0)
            *outKeySize = keyinfo->KeyHeader.LogicalKeySizeInBits;
        else
            *outKeySize = 0;
    }
    
    if (outItemClass) {
        switch(keyinfo->KeyHeader.KeyClass) {
            case CSSM_KEYCLASS_PUBLIC_KEY:
                *outItemClass = kSecPublicKeyItemClass;
                break;
            case CSSM_KEYCLASS_PRIVATE_KEY:
                *outItemClass = kSecPrivateKeyItemClass;
                break;
            case CSSM_KEYCLASS_SESSION_KEY:
                *outItemClass = kSecSymmetricKeyItemClass;
                break;
            default:
                *outItemClass = 0;
                break;
        }
    }
    
    if (outKeyFlags) {
        uint32_t flags = 0;
        
        for(unsigned ix = 0; ix < arraycount(keyUseMap); ix ++) {
            if (keyUseMap[ix].keyUse & keyinfo->KeyHeader.KeyUsage)
                flags |= keyUseMap[ix].keyFlag;
        }
        
        if (keyinfo->KeyHeader.KeyAttr & CSSM_KEYATTR_PERMANENT)
            flags |= (1u << kSecKeyPermanent);
        if (keyinfo->KeyHeader.KeyAttr & CSSM_KEYATTR_PRIVATE)
            flags |= (1u << kSecKeyPrivate);
        
        // Key attributes we don't map right now: CSSM_KEYATTR_MODIFIABLE, CSSM_KEYATTR_SENSITIVE, CSSM_KEYATTR_EXTRACTABLE
        
        *outKeyFlags = flags;
    }
    
    return cssmAlgToOFAlg(keyinfo->KeyHeader.AlgorithmId, err);
}

#endif

