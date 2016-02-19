// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSecurityUtilities.h>

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFFeatures.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFASN1-Internal.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Security/Security.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

static OSStatus removeKeyRef(SecKeyRef keyRef);

BOOL OFSecKeyGeneratePairAndInfo(enum OFKeyAlgorithm keyType, int keyBits, BOOL addToKeychain, NSString *label, NSData * __autoreleasing *outSubjectPublicKeyInfo, SecKeyRef *outPrivateKey, NSError * __autoreleasing * outError)
{
    OSStatus oserr;
    CFMutableDictionaryRef params = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    SecKeyRef publicKey, privateKey;
    
    switch (keyType) {
        case ka_RSA:
            CFDictionarySetValue(params, kSecAttrKeyType, kSecAttrKeyTypeRSA);
            break;
        case ka_EC:
            CFDictionarySetValue(params, kSecAttrKeyType, kSecAttrKeyTypeEC);
            break;
        /* There is no kSecAttrKeyTypeDSA on iOS */
        default:
            break;
    }
    
    if (label) {
        CFDictionarySetValue(params, kSecAttrLabel, (__bridge CFStringRef)label);
    }
    
    /* Pass in the number of bits. For EC keys, this actually controls the curve selection. */
    CFNumberRef sz = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &keyBits);
    CFDictionarySetValue(params, kSecAttrKeySizeInBits, sz);
    CFRelease(sz);
    
#if 0 /* RADAR 11840882: If we don't put a key in the keychain, SecItemCopyMatching() can't retrieve information about it. So, we add it and then remove it. */
    {
        const void *kk[1] = { kSecAttrIsPermanent };
        const void *vv[1];
        CFDictionaryRef per;
        
        vv[0] = addToKeychain? kCFBooleanTrue : kCFBooleanFalse;
        per = CFDictionaryCreate(kCFAllocatorDefault, kk, vv, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(params, kSecPrivateKeyAttrs, per);
        CFRelease(per);
        
        vv[0] = kCFBooleanFalse;
        per = CFDictionaryCreate(kCFAllocatorDefault, kk, vv, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(params, kSecPublicKeyAttrs, per);
        CFRelease(per);
    }
#else
    CFDictionarySetValue(params, kSecAttrIsPermanent, kCFBooleanTrue);
#endif
    CFDictionarySetValue(params, kSecAttrAccessible, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly);
    
    /* Actually generate the key pair */
    publicKey = NULL;
    privateKey = NULL;
    oserr = SecKeyGeneratePair(params, &publicKey, &privateKey);
    CFRelease(params);
    
    if (oserr != errSecSuccess) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:oserr userInfo:@{ @"function" : @"SecKeyGeneratePair" }];
        return NO;
    }
    
    /* There's no SecItemExport() on iOS, because Apple is insane, and therefore no kSecFormatOpenSSL constant. Instead, we have to use SecItemCopyMatching() to convert a key ref to a byte blob--- we just have to rely on the undocumented behavior that the resulting byte blob is in a particular format. RADAR #19357674. (Sadly, it seems that filing RADARs for this kind of thing, even just asking for explicit documentation of what the public API does, is pointless. Whoever works on Security.framework doesn't read bug reports.) */
    
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecValueRef, publicKey);
    CFTypeRef hopefullyTheEncodedPublicKey = NULL;
    oserr = SecItemCopyMatching(query, &hopefullyTheEncodedPublicKey);
    CFRelease(query);
    
    /* Now delete the public key from the keychain */
    removeKeyRef(publicKey);
    CFRelease(publicKey);
    
    if (oserr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:oserr userInfo:@{ @"function" : @"SecItemCopyMatching" }];
        removeKeyRef(privateKey);
        CFRelease(privateKey);
        return NO;
    }
    
    /* Double-check SecItemCopyMatching()'s ludicrous badness */
    if (!hopefullyTheEncodedPublicKey || CFGetTypeID(hopefullyTheEncodedPublicKey) != CFDataGetTypeID() || CFDataGetLength(hopefullyTheEncodedPublicKey) < 2) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecInternalComponent userInfo:@{ @"function" : @"SecItemCopyMatching (is really buggy)" }];
        removeKeyRef(privateKey);
        CFRelease(privateKey);
        return NO;
    }
    
    if (!addToKeychain)
        removeKeyRef(privateKey);
    
    /* Now convert the result into a standard format. This involves wrapping the raw key info in a BIT STRING and then putting it in a SEQUENCE with the relevant algorithm identifier. This relies on the blob that SecItemCopyMatching() returns being in the expected format (corresponding to the key-info part of the SubjectPublicKeyInfo structure). */
    
    static uint8_t algid_rsaEncryption_der[] = {
        /* tag = SEQUENCE, length = 13 */
        0x30, 0x0D,
        /* tag = OBJECT IDENTIFIER, length = 9 */
        0x06, 0x09,
        /* iso(1) member-body(2) us(840) rsadsi(113549) pkcs(1) 1 rsaEncryption(1) */
        0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
        /* NULL */
        0x05, 0x00
    };
    
#if 0
    /* This is perhaps more-correct, but OpenSSL doesn't support it. We might want to add a generation option. */
    static uint8_t oid_ecDH_der[] = {
        /* tag = OBJECT IDENTIFIER, length = 5 */
        0x06, 0x05,
        /* RFC 5480 [2.1.2] - 1.3.132.1.12 - ECDH only */
        0x2B, 0x81, 0x04, 0x01, 0x0C
    };
#define EC_OID oid_ecDH_der
#else
    static uint8_t oid_ecPublicKey_der[] = {
        /* tag = OBJECT IDENTIFIER, length = 7 */
        0x06, 0x07,
        /* RFC 5480 [2.1.1] - 1.2.840.10045.2.1 - unrestricted key usage */
        0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01
    };
#define EC_OID oid_ecPublicKey_der
#endif
    
    
    NSData *algIdentifier;
    
    switch (keyType) {
        case ka_RSA:
            algIdentifier = [[NSData alloc] initWithBytesNoCopy:algid_rsaEncryption_der length:sizeof(algid_rsaEncryption_der) freeWhenDone:NO];
            break;
        case ka_EC:
        {
            /* This is completely ridiculous. The iOS crypto APIs completely hide the notion of curve selection--- they try to make EC key generation look like RSA key generation. Of course, the key info we get from SecItemCopyMatching() is unusable without knowledge of the curve being used. So we have to assume a certain curve based on the keyBits we passed in to SecKeyGeneratePair() and the vague references in the documentation. Obviously this is kind of fragile, but we're given no choice if we want to use the iOS keychain... see RADAR #19357823. */
            const struct OFNamedCurveInfo *curve;
            for(curve = _OFEllipticCurveInfoTable; curve->derOid; curve++) {
                if (curve->generatorSize == keyBits)
                    break;
            }
            if (!curve->derOid) {
                /* This shouldn't be reachable normally: SecKeyGeneratePair() should fail if given a key size other one that selects one of the three curves it's documented to support. And our caller should generally be validating the size of EC curves as well. But SecKeyGeneratePair()'s behavior may well change out from under us. */
                if (outError)
                    *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecParam userInfo:@{ NSLocalizedDescriptionKey: @"No expected curve with that size" }];
                CFRelease(privateKey);
                return NO;
            }
            /* SEQUENCE { oid_ecDH, curve oid } */
            algIdentifier = OFASN1AppendStructure(nil, "(**)",
                                                  (size_t)sizeof(EC_OID), EC_OID,
                                                  (size_t)curve->derOidLength, curve->derOid);
            break;
        }
        default:
            return NO;
    }
    
    /* The SubjectPublicKeyInfo structure, which is how a public key is transferred over the wire, is the algorithm identifier plus the key bits (the latter are gratuitously wrapped in a BIT STRING). */
    
    NSData *spki = OFASN1AppendStructure(nil, "(d<d>)", algIdentifier, (__bridge NSData *)hopefullyTheEncodedPublicKey);
    
    CFRelease(hopefullyTheEncodedPublicKey);
    
    *outSubjectPublicKeyInfo = spki;
    *outPrivateKey = privateKey;
    
    return YES;
}

static OSStatus removeKeyRef(SecKeyRef keyRef)
{
    const void *kk[1] = { kSecValueRef };
    const void *vv[1] = { keyRef };
    CFDictionaryRef del = CFDictionaryCreate(kCFAllocatorDefault, kk, vv, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    OSStatus result = SecItemDelete(del);
    CFRelease(del);
    return result;
}

