// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSecurityUtilities.h>

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFASN1-Internal.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFCMS.h>
#import <OmniFoundation/OFSymmetricKeywrap.h>
#import "OFCMS-Internal.h"
#import "GeneratedOIDs.h"
#import "OFRFC3211Wrap.h"
#import <Foundation/NSData.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonRandom.h>
#import <Security/Security.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

#if HAVE_APPLE_ECDH_SUPPORT
#if (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && (__IPHONE_OS_VERSION_MIN_REQUIRED < 100000)) || (defined(MAC_OS_X_VERSION_MIN_REQUIRED) && (MAC_OS_X_VERSION_MIN_REQUIRED < 101200))
// This symbol was added as of MacOSX 10.12+ and iOS 10.10+, but the later SDKs don't properly declare it weak when building with a lower minimum target (see RADAR 29541215).
extern const CFStringRef kSecAttrKeyTypeECSECPrimeRandom __attribute__((weak_import));
#define CAN_USE_APPLE_ECDH_SUPPORT (&kSecAttrKeyTypeECSECPrimeRandom != NULL && &SecKeyCopyKeyExchangeResult != NULL)
#endif
#endif

static unsigned kekLengthOfWrapAlgorithm(enum OFASN1Algorithm wrapAlg, NSData *buf, NSRange parameterRange) __attribute__((unused));
static NSData *rsaTransportKey(NSData *payload, SecKeyRef publicKey, NSError **outError);
static NSData *rsaReceiveKey(NSData *encrypted, SecKeyRef secretKey, NSError **outError);
static NSError *unsupportedCMSFeature(NSString *fmt, ...) __attribute__((cold));
static NSError *cmsFormatError(NSString *detail);
#if HAVE_APPLE_ECDH_SUPPORT
static NSData *cmsECCSharedInfo(NSData *wrapAlg, NSData *ukm, uint32_t kekSizeBytes);
#endif

/* Algorithm identifiers. */

/* From RFC3565: id-aes128-wrap and id-aes256-wrap, in a SEQUENCE for use as an AlgorithmIdentifier, but missing the final byte */
static const unsigned char alg_aesXXX_wrap_prefix[] = { 0x30, 0x0b, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x01 /* plus one byte indicating key size */ };

/* From RFC3370 [4.2.1]: rsaEncryption = { iso(1) member-body(2) us(840) rsadsi(113549) pkcs(1) pkcs-1(1) 1 } This indicates PKCS #1 v1.5 encryption.
   This includes the optional NULL due to the historical accidents of PKCS: see the text of RFC3370 [4.2.1] and [2.1] for more information.
*/
static uint8_t alg_rsaEncryption_pkcs1_5[] = {
    /* tag = SEQUENCE, length = 13 */
    0x30, 0x0D,
    /* tag = OBJECT IDENTIFIER, length = 9 */
    0x06, 0x09,
    /* iso(1) member-body(2) us(840) rsadsi(113549) pkcs(1) 1 rsaEncryption(1) */
    0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
    /* NULL */
    0x05, 0x00
};


#pragma mark Password-Based recipients

NSData *OFGeneratePBKDF2AlgorithmInfo(NSUInteger keyLength, unsigned int iterations)
{
    /* saltLength is fairly arbitrary, but 12 bytes is the standard length */
    size_t saltLength = 12; /* Must be size_t for OFASN1AppendStructure() */
    
    /* Iterations can be tuned to adjust the speed/bruteforceability tradeoff */
    if (iterations < 100)
        iterations = OF_REASONABLE_PBKDF2_ITERATIONS;
    
    unsigned char salt[saltLength];
    CCRNGStatus rngOk = CCRandomGenerateBytes(salt, saltLength);
    if (rngOk != kCCSuccess) {
        // There's really no reason for CCRandomGenerateBytes() to fail unless the system is kinda hosed.
        [NSException raise:NSGenericException format:@"RNG failure: CCRandomGenerateBytes() returned %d", rngOk];
        return nil;
    }
    
    const uint8_t *prfOid;
    
    /* Choose a PRF appropriate to the key length */
    if (keyLength <= CC_SHA256_DIGEST_LENGTH) {
        prfOid = der_prf_hmacWithSHA256;
    } else {
        prfOid = der_prf_hmacWithSHA512;
    }
    
    /* From RFC3370 [4.4.1]: id-PBKDF2 = { iso(1) member-body(2) us(840) rsadsi(113549) pkcs(1) pkcs-5(5) 12} */
    
    /* The embedded PRF algorithms are encoded with the optional NULL omitted, per RFC5754 [2]. */
    
    /* The algorithm info is a SEQUENCE, but it's used in the password recipient info structure, which gives it an IMPLICIT TAG of 0. So we apply that here. */
    
    NSMutableData *encodedResult = OFASN1AppendStructure(nil, "!(+([*]uu(+)))",
                                                         0 /* IMPLICIT TAG */ | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC,
                                                         der_PBKDF2,
                                                         saltLength, salt, (unsigned)iterations, (unsigned)keyLength, prfOid);
    
    
    return encodedResult;
}

NSData *OFDeriveKEKForCMSPWRI(NSData *password, NSData *encodedAlgInfo, NSError **outError)
{
    enum OFASN1Algorithm derivationAlgorithm, prf;
    NSRange derivationParameters;
    int iterations, keyLength;
    NSData * __autoreleasing salt;
    CCPseudoRandomAlgorithm ccPRF;
    int asn1err;
    
    asn1err = OFASN1ParseAlgorithmIdentifier(encodedAlgInfo, NO, &derivationAlgorithm, &derivationParameters);
    if (asn1err) {
        if (outError) {
            *outError = OFNSErrorFromASN1Error(asn1err, @"derivation algorithm");
        }
        return nil;
    }

    if (derivationAlgorithm != OFASN1Algorithm_PBKDF2) {
        // The only derivation algorithm we currently support is PBKDF2. We may want to support something like Argon2 in the future, but we'll have to wait for it to be assigned an OID in the CMS context.
        if (outError) {
            *outError = unsupportedCMSFeature(@"Key derivation algorithm");
        }
        return nil;
    }
    
    asn1err = OFASN1ParsePBKDF2Parameters(encodedAlgInfo, derivationParameters, &salt, &iterations, &keyLength, &prf);
    if (asn1err) {
        if (outError) {
            *outError = OFNSErrorFromASN1Error(asn1err, @"PBKDF2 parameters");
        }
        return nil;
    }
    
    // NB: It's legal for keyLength to be omitted from the parameters, in which case OFASN1ParsePBKDF2Parameters() will set it to 0. In that case we would need to look at the algorithmIdentifier of the wrapped key itself to discover the key length. We currently don't support that.
    if (keyLength == 0) {
        if (outError)
            *outError = unsupportedCMSFeature(@"Implicit wrap key length");
        return nil;
    }
    
    if ([salt length] < 2 || iterations < 1 || keyLength < kCCKeySizeAES128 || keyLength > kCCKeySizeAES256) {
        if (outError) {
            *outError = unsupportedCMSFeature(@"Key derivation parameters");
        }
        return nil;
    }
    
    switch (prf) {
        case OFASN1Algorithm_prf_hmacWithSHA1: // Legacy, but we'll still read files with this PRF
            ccPRF = kCCPRFHmacAlgSHA1;
            break;
        case OFASN1Algorithm_prf_hmacWithSHA256:
            ccPRF = kCCPRFHmacAlgSHA256;
            break;
        case OFASN1Algorithm_prf_hmacWithSHA512:
            ccPRF = kCCPRFHmacAlgSHA512;
            break;
        default:
            if (outError) {
                *outError = unsupportedCMSFeature(@"Key derivation algorithm");
            }
            return nil;
    }
    
    NSMutableData *derived = [[NSMutableData alloc] initWithLength:keyLength];
    
    int deriveOk = CCKeyDerivationPBKDF(kCCPBKDF2, [password bytes], [password length],
                                        [salt bytes], [salt length],
                                        ccPRF, iterations,
                                        [derived mutableBytes], keyLength);
    if (deriveOk != kCCSuccess) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:deriveOk userInfo: @{ @"function": @"CCKeyDerivationPBKDF" }];
        }
        return nil;
    }
    
    return derived;
}

/* This wraps the CEK using AESWRAP and appends to the buffer the key-wrapping algorithm ID and the wrapped key. */
static BOOL wrapAndAppendWithAlgId(NSMutableData *buffer, NSData *KEK, NSData *CEK)
{
    NSUInteger kekLength = [KEK length];
    NSUInteger cekLength = [CEK length];
    
    uint8_t finalByte;
    switch (kekLength) {
        case kCCKeySizeAES128: finalByte = 5;   break;
        case kCCKeySizeAES192: finalByte = 25;  break;
        case kCCKeySizeAES256: finalByte = 45;  break;
        default:
            return NO;
    }
    [buffer appendBytes:alg_aesXXX_wrap_prefix length:sizeof(alg_aesXXX_wrap_prefix)];
    [buffer appendBytes:&finalByte length:1];
    
    /* CCSymmetricKeyWrap() does RFC3394 key-wrap, not RFC5649 key-wrap, which means we can only wrap things which are multiples of half the block size. Apple's implementation doesn't check for an invalid length, so do it here. */
    if (cekLength % (kCCBlockSizeAES128/2) != 0)
        return NO;
    
    size_t wrappedKeyLength = CCSymmetricWrappedSize(kCCWRAPAES, cekLength);
    
    OFASN1AppendTagLength(buffer, BER_TAG_OCTET_STRING, wrappedKeyLength);
    NSUInteger prevOffset = [buffer length];
    [buffer setLength:prevOffset + wrappedKeyLength];
    size_t wrappedLenTmp = wrappedKeyLength; /* RADAR 18206798 aka 15949620 */
    int wrapOK = CCSymmetricKeyWrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen, [KEK bytes], kekLength, [CEK bytes], cekLength, [buffer mutableBytes] + prevOffset, &wrappedLenTmp);
    if (wrapOK != kCCSuccess)
        return NO;
    
    return YES;
}

#ifdef WITH_RFC3211_KEY_WRAP

/* This wraps the CEK using PWRI-KEK/AES */

static BOOL wrapAndAppendWithAlgId_RFC3211KeyWrap(NSMutableData *buffer, NSData *KEK, NSData *CEK)
{
    const uint8_t *inner_alg_oid;
    switch ([KEK length]) {
        case kCCKeySizeAES128: inner_alg_oid = der_alg_aes128_cbc; break;
        case kCCKeySizeAES192: inner_alg_oid = der_alg_aes192_cbc; break;
        case kCCKeySizeAES256: inner_alg_oid = der_alg_aes256_cbc; break;
        default:
            return NO;
    }
    
    NSData *iv = [NSData cryptographicRandomDataOfLength:kCCBlockSizeAES128];
    NSData *wrapped = OFRFC3211Wrap(CEK, KEK, iv, kCCAlgorithmAES, kCCBlockSizeAES128);
    if (!wrapped)
        return NO;
    
    OFASN1AppendStructure(buffer, "(+(+[d]))[d]", der_PWRI_KEK, inner_alg_oid, iv, wrapped);
    
    return YES;
}

static NSData *unwrapWithAlgId_PWRI(NSData *kekParameters, NSData *wrappedKey, NSData *KEK, NSError **outError)
{
    enum OFASN1Algorithm alg = OFASN1Algorithm_Unknown;
    NSRange algParams;
    
    enum OFASN1ErrorCodes rc = OFASN1ParseAlgorithmIdentifier(kekParameters, NO, &alg, &algParams);
    if (rc) {
        if (outError)
            *outError = OFNSErrorFromASN1Error(rc, @"Key wrap algorithm");
        return nil;
    }
    
    CCAlgorithm innerAlgorithm;
    NSUInteger blockSize;
    NSUInteger expectedKeyLength;
    switch (alg) {
        case OFASN1Algorithm_aes128_cbc:
            expectedKeyLength = kCCKeySizeAES128;
            innerAlgorithm = kCCAlgorithmAES;
            blockSize = kCCBlockSizeAES128;
            break;
        case OFASN1Algorithm_aes192_cbc:
            expectedKeyLength = kCCKeySizeAES192;
            innerAlgorithm = kCCAlgorithmAES;
            blockSize = kCCBlockSizeAES128;
            break;
        case OFASN1Algorithm_aes256_cbc:
            expectedKeyLength = kCCKeySizeAES256;
            innerAlgorithm = kCCAlgorithmAES;
            blockSize = kCCBlockSizeAES128;
            break;
        case OFASN1Algorithm_des_ede_cbc:
            expectedKeyLength = kCCKeySize3DES;
            innerAlgorithm = kCCAlgorithm3DES;
            blockSize = kCCBlockSize3DES;
            break;
        default:
            if (outError)
                *outError = unsupportedCMSFeature(@"Key wrap algorithm");
            return nil;
    }
    
    if ([KEK length] != expectedKeyLength) {
        if (outError)
            *outError = cmsFormatError(@"Key-encryption-key length mismatch");
        return nil;
    }
    
    NSData * __autoreleasing iv = nil;
    rc = OFASN1ParseSymmetricEncryptionParameters(kekParameters, alg, algParams, &iv, NULL);
    if (rc) {
        if (outError)
            *outError = OFNSErrorFromASN1Error(rc, @"Key wrap algorithm");
        return nil;
    }
    
    NSData *CEK = OFRFC3211Unwrap(wrappedKey, KEK, iv, innerAlgorithm, blockSize);
    if (!CEK) {
        if (outError)
            *outError = [NSError errorWithDomain:OFErrorDomain code:OFKeyNotApplicable userInfo:@{ @"function" : @"RFC3211Unwrap" }];
        return nil;
    } else {
        return CEK;
    }
}

#endif

/* This takes the concatenated wrapping algorithm identifier and wrapped key as generated by wrapAndAppendWithAlgId() and unwraps the key. */
static NSData *unwrapWithAlgId(NSData *encrypted, NSData *KEK, NSError **outError)
{
    enum OFASN1Algorithm alg = OFASN1Algorithm_Unknown;
    NSRange algParams;
    
    enum OFASN1ErrorCodes rc = OFASN1ParseAlgorithmIdentifier(encrypted, YES, &alg, &algParams);
    if (rc) {
        if (outError)
            *outError = OFNSErrorFromASN1Error(rc, @"Key wrap algorithm");
        return nil;
    }
    
    NSData *wrappedKey = OFASN1UnwrapOctetString(encrypted, (NSRange){ NSMaxRange(algParams), [encrypted length] - NSMaxRange(algParams) });
    if (!wrappedKey) {
        if (outError) {
            *outError = OFNSErrorFromASN1Error(OFASN1UnexpectedType, nil);
        }
        return nil;
    }
    
    NSUInteger expectedKeyLength;
    switch (alg) {
        case OFASN1Algorithm_aes128_wrap:
            expectedKeyLength = kCCKeySizeAES128;
            break;
        case OFASN1Algorithm_aes192_wrap:
            expectedKeyLength = kCCKeySizeAES192;
            break;
        case OFASN1Algorithm_aes256_wrap:
            expectedKeyLength = kCCKeySizeAES256;
            break;
#ifdef WITH_RFC3211_KEY_WRAP
        case OFASN1Algorithm_PWRI_KEK:
            return unwrapWithAlgId_PWRI([encrypted subdataWithRange:algParams], wrappedKey, KEK, outError);
#endif
        default:
            if (outError)
                *outError = unsupportedCMSFeature(@"Key wrap algorithm");
            return nil;
    }
    
    if ([KEK length] != expectedKeyLength) {
        if (outError)
            *outError = cmsFormatError(@"Key-encryption-key length mismatch");
        return nil;
    }
    
    NSData *result = OFSymmetricKeyUnwrapDataRFC3394(KEK, wrappedKey, outError);
    if (!result && outError) {
        NSError *underlying = *outError;
        if (underlying.code == kCCDecodeError) {
            *outError = [NSError errorWithDomain:OFErrorDomain code:OFKeyNotApplicable userInfo:@{ NSUnderlyingErrorKey: underlying }];
        }
    }
    return result;
}

/* This takes an algorithm identifier for a key-wrapping algorithm and returns the length (in bytes) of the KEK required by that algorithm. For algorithms with parameters, they are read from "parameterRange" of "buf". Returns zero on failure (parse failure or unknown algorithm). */
static unsigned kekLengthOfWrapAlgorithm(enum OFASN1Algorithm wrapAlg, NSData *buf, NSRange parameterRange)
{
    switch (wrapAlg) {
        case OFASN1Algorithm_aes128_wrap: return kCCKeySizeAES128;
        case OFASN1Algorithm_aes192_wrap: return kCCKeySizeAES192;
        case OFASN1Algorithm_aes256_wrap: return kCCKeySizeAES256;
        case OFASN1Algorithm_PWRI_KEK:
        {
            enum OFASN1Algorithm innerAlgorithm = OFASN1Algorithm_Unknown;
            NSRange innerAlgorithmParams;
            
            enum OFASN1ErrorCodes rc = OFASN1ParseAlgorithmIdentifier([buf subdataWithRange:parameterRange], NO, &innerAlgorithm, &innerAlgorithmParams);
            if (rc)
                return 0;

            switch (innerAlgorithm) {
                case OFASN1Algorithm_aes128_cbc:  return kCCKeySizeAES128;
                case OFASN1Algorithm_aes192_cbc:  return kCCKeySizeAES192;
                case OFASN1Algorithm_aes256_cbc:  return kCCKeySizeAES256;
                case OFASN1Algorithm_des_ede_cbc: return kCCKeySize3DES;
                default:
                    return 0;
            }
        }
        default:
            return 0;
    }
}

NSData *OFProduceRIForCMSPWRI(NSData *KEK, NSData *CEK, NSData *algInfo, OFCMSOptions options)
{
    /* We're producing the following structure, in an IMPLICIT TAGS context (see RFC3852 [6.2] etc):
     
     [3] SEQUENCE {
         version CMSVersion,   -- Always set to 0
         keyDerivationAlgorithm [0] KeyDerivationAlgorithmIdentifier OPTIONAL,
         keyEncryptionAlgorithm KeyEncryptionAlgorithmIdentifier,
         encryptedKey EncryptedKey
     }
     
     KeyDerivationAlgorithmIdentifier := SEQUENCE { ... passed in as algInfo ... }
     
     KeyEncryptionAlgorithmIdentifier := SEQUENCE { OBJECT IDENTIFIER }
     
     EncryptedKey := OCTET STRING
     
     */
    
    NSMutableData *buffer = [NSMutableData data];
    OFASN1AppendInteger(buffer, 0); // Version number: always 0
    [buffer appendData:algInfo];
    
#ifdef WITH_RFC3211_KEY_WRAP
    if (options & OFCMSOptionPreferRFC3211) {
        if (!wrapAndAppendWithAlgId_RFC3211KeyWrap(buffer, KEK, CEK))
            return nil;
    } else
#endif
    {
        if (!wrapAndAppendWithAlgId(buffer, KEK, CEK))
            return nil;
    }
    
    /* Finally, wrap that in a SEQUENCE with an implicit tag 3. */
    NSMutableData *result = [NSMutableData data];
    OFASN1AppendTagLength(result, 3 | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, [buffer length]);
    [result appendData:buffer];
    
    return result;
}

static NSError *parsePasswordDerivationRecipient(NSData *rid, const struct parsedTag *recip, NSData **outKDFAlgorithmIdentifier, NSData **outWrapped)
{
        /*
        PasswordRecipientInfo ::= SEQUENCE {
            version CMSVersion,   -- always set to 0
            keyDerivationAlgorithm [0] KeyDerivationAlgorithmIdentifier OPTIONAL,
            keyEncryptionAlgorithm KeyEncryptionAlgorithmIdentifier,
            encryptedKey EncryptedKey
        }
        */

    static const struct scanItem pwriDataItems[4] = {
        { FLAG_PRIMITIVE, BER_TAG_INTEGER }, /* version */
        { FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC | FLAG_OPTIONAL, 0 }, /* KeyDerivationAlgorithmIdentifier */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* wrapping algorithm */
        { FLAG_PRIMITIVE, BER_TAG_OCTET_STRING } /* wrapped key */
    };
    struct parsedItem pwriDataValues[4];
    
    enum OFASN1ErrorCodes rc = OFASN1ParseItemsInObject(rid, *recip, YES, pwriDataItems, pwriDataValues);
    if (rc)
        return OFNSErrorFromASN1Error(rc, @"PasswordRecipient");
    
    int syntaxVersion = -1;
    rc = OFASN1UnDERSmallInteger(rid, &pwriDataValues[0].i, &syntaxVersion);
    if (rc != OFASN1Success || syntaxVersion < 0 || syntaxVersion > 0) {
        // Don't try to parse something whose version field is out of the range we know about.
        return unsupportedCMSFeature(@"PasswordRecipientInfo.version (%d)", syntaxVersion);
    }
    
    if (pwriDataValues[1].i.classAndConstructed != (FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC)) {
        /* The keyDerivationAlgorithm is OPTIONAL, but we don't support not having it. */
        return unsupportedCMSFeature(@"Missing keyDerivationAlgorithm");
    }
    
    *outKDFAlgorithmIdentifier = [rid subdataWithRange:(NSRange){ pwriDataValues[1].startPosition, NSMaxRange(pwriDataValues[1].i.content) - pwriDataValues[1].startPosition }];
    *outWrapped = [rid subdataWithRange:(NSRange){ pwriDataValues[2].startPosition, NSMaxRange(pwriDataValues[3].i.content) - pwriDataValues[2].startPosition } ];
    return nil;
}

NSData *OFUnwrapRIForCMSPWRI(NSData *encrypted, NSData *KEK, NSError **outError)
{
    return unwrapWithAlgId(encrypted, KEK, outError);
}

#pragma mark External key transport recipients

NSData *OFProduceRIForCMSKEK(NSData *KEK, NSData *CEK, NSData *keyIdentifier, OFCMSOptions options)
{
    /* We're producing the following structure, in an IMPLICIT TAGS context (see RFC3852 [6.2.3] etc):
     
     [2] SEQUENCE {
         version CMSVersion,   -- Always set to 4
         kekid KEKIdentifier ::= SEQUENCE {
             keyIdentifier OCTET STRING,
             date GeneralizedTime OPTIONAL,
             other OtherKeyAttribute OPTIONAL
         }
         keyEncryptionAlgorithm KeyEncryptionAlgorithmIdentifier,
         encryptedKey OCTET STRING
     }
     
     */
    
    NSMutableData *buffer = [NSMutableData data];
    OFASN1AppendInteger(buffer, 4); // Version number: always 4, see RFC3852 [6.2.4]
    OFASN1AppendStructure(buffer, "([d])", keyIdentifier);
    
#ifdef WITH_RFC3211_KEY_WRAP
    if (options & OFCMSOptionPreferRFC3211) {
        if (!wrapAndAppendWithAlgId_RFC3211KeyWrap(buffer, KEK, CEK))
            return nil;
    } else
#endif
    {
        if (!wrapAndAppendWithAlgId(buffer, KEK, CEK))
            return nil;
    }
    
    /* Finally, wrap that in a SEQUENCE with an implicit tag 2. */
    NSMutableData *result = [NSMutableData data];
    OFASN1AppendTagLength(result, 2 | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, [buffer length]);
    [result appendData:buffer];
    
    return result;
}

static NSError *parsePreSharedKeyRecipient(NSData *rid, const struct parsedTag *recip, NSData **outKeyIdentifier, NSData **outWrapped)
{
    /* see RFC3852 [6.2.3] etc:
     
     [2] SEQUENCE {
         version CMSVersion,   -- Always set to 4
         kekid KEKIdentifier ::= SEQUENCE {
             keyIdentifier OCTET STRING,
             date GeneralizedTime OPTIONAL,
             other OtherKeyAttribute OPTIONAL
         },
         keyEncryptionAlgorithm KeyEncryptionAlgorithmIdentifier,
         encryptedKey OCTET STRING
     }

     */
    
    static const struct scanItem kekDataItems[4] = {
        { FLAG_PRIMITIVE, BER_TAG_INTEGER }, /* version */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* KEKIdentifier sequence */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* wrapping algorithm */
        { FLAG_PRIMITIVE, BER_TAG_OCTET_STRING } /* wrapped key */
    };
    struct parsedItem kekDataValues[4];
    
    enum OFASN1ErrorCodes rc = OFASN1ParseItemsInObject(rid, *recip, YES, kekDataItems, kekDataValues);
    if (rc)
        return OFNSErrorFromASN1Error(rc, @"KEKRecipient");
    
    int syntaxVersion = -1;
    rc = OFASN1UnDERSmallInteger(rid, &kekDataValues[0].i, &syntaxVersion);
    if (rc != OFASN1Success || syntaxVersion > 4 /* section [6.2.3], version is always 4 */) {
        return unsupportedCMSFeature(@"Unexpected RecipientInfo version (%d)", syntaxVersion);
    }
    
    /* The only part of the KEK identifier we use is the actual keyIdentifier. For now, just extract that and discard the optional other selectors which might follow it. */
    struct parsedTag kiTag;
    rc = OFASN1ParseTagAndLength(rid, kekDataValues[1].i.content.location, NSMaxRange(kekDataValues[1].i.content), YES, &kiTag);
    if (rc == OFASN1Success && !(kiTag.classAndConstructed == (CLASS_UNIVERSAL|FLAG_PRIMITIVE) && kiTag.tag == BER_TAG_OCTET_STRING))
        rc = OFASN1UnexpectedType;
    if (rc)
        return OFNSErrorFromASN1Error(rc, @"KEKRecipient");
    
    *outKeyIdentifier = [rid subdataWithRange:kiTag.content];
    *outWrapped = [rid subdataWithRange:(NSRange){ kekDataValues[2].startPosition, NSMaxRange(kekDataValues[3].i.content) - kekDataValues[2].startPosition } ];
    return nil;
}

#pragma mark Asymmetric-crypto recipients

NSData *OFProduceRIForCMSRSAKeyTransport(SecKeyRef publicKey, NSData *recipientIdentifier, NSData *CEK, NSError **outError)
{
    /* We're producing the following structure:
    
     KeyTransRecipientInfo ::= SEQUENCE {
         version CMSVersion,  -- always set to 0 or 2
         rid RecipientIdentifier,
         keyEncryptionAlgorithm KeyEncryptionAlgorithmIdentifier,
         encryptedKey OCTET STRING }
    */
    
    /* The version field is 0 if the recipient identifier is issuerAndSerialNumber, or 2 if it is subjectKeyIdentifier. The recipient identifier is an implicitly-tagged CHOICE, so we look at its tag. */
    unsigned version;
    uint8_t ridTag[1];
    [recipientIdentifier getBytes:ridTag range:(NSRange){0, 1}];
    if (ridTag[0] == (BER_TAG_SEQUENCE|FLAG_CONSTRUCTED)) {
        version = 0;
    } else /* if ridTag == (0 | FLAG_PRIMITIVE | CLASS_CONTEXT_SPECIFIC) */ {
        version = 2;
    }

    NSData *encryptedForTransport = rsaTransportKey(CEK, publicKey, outError);
    if (!encryptedForTransport)
        return nil;
    
    // You'd think that we'd want to deal with any leading 0s in the integer returned from the RSA computation, but PKCS#1/RFC3447 specifies PKCS #1 v1.5 padding as resulting in an octet string (via I2OSP), not a bit string.
    
    return OFASN1AppendStructure(nil, "(ud+[d])",
                                 version,
                                 recipientIdentifier,
                                 alg_rsaEncryption_pkcs1_5,
                                 encryptedForTransport);
}

static NSError *parseKeyTransportRecipient(NSData *rid, const struct parsedTag *recip, NSData **outRecipientIdentifier, NSData **outWrapped)
{
    /*
     KeyTransRecipientInfo ::= SEQUENCE {
         version CMSVersion,  -- always set to 0 or 2
         rid RecipientIdentifier,
         keyEncryptionAlgorithm KeyEncryptionAlgorithmIdentifier,
         encryptedKey EncryptedKey
     }
     */
    
    static const struct scanItem ktriDataItems[4] = {
        { FLAG_PRIMITIVE, BER_TAG_INTEGER }, /* version */
        { FLAG_ANY_OBJECT, 0 }, /* RecipientIdentifier */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* wrapping algorithm */
        { FLAG_PRIMITIVE, BER_TAG_OCTET_STRING } /* wrapped key */
    };
    struct parsedItem ktriDataValues[4];
    
    enum OFASN1ErrorCodes rc = OFASN1ParseItemsInObject(rid, *recip, YES, ktriDataItems, ktriDataValues);
    if (rc)
        return OFNSErrorFromASN1Error(rc, @"KeyTransportRecipient");
    
    int syntaxVersion = -1;
    rc = OFASN1UnDERSmallInteger(rid, &ktriDataValues[0].i, &syntaxVersion);
    if (rc != OFASN1Success || syntaxVersion < 0 || syntaxVersion > 2) {
        // Don't try to parse something whose version field is out of the range we know about.
        return unsupportedCMSFeature(@"KeyTransRecipientInfo.version=%d", syntaxVersion);
    }
    
    /* The recipient identifier is: CHOICE {
          issuerAndSerialNumber SEQUENCE { ... },
          subjectKeyIdentifier [0] OCTET STRING
       }
     For future expansion, we'll accept any context-tagged object here. Our caller will deal with the fallout.
     */
    if (!(( ktriDataValues[1].i.classAndConstructed == (FLAG_CONSTRUCTED|CLASS_UNIVERSAL) && ktriDataValues[1].i.tag == BER_TAG_SEQUENCE ) ||
          ( (ktriDataValues[1].i.classAndConstructed & CLASS_MASK) == CLASS_CONTEXT_SPECIFIC )))
        return OFNSErrorFromASN1Error(OFASN1UnexpectedType, @"KeyTransportRecipient");
    
    *outRecipientIdentifier = [rid subdataWithRange:(NSRange){ ktriDataValues[1].startPosition, NSMaxRange(ktriDataValues[1].i.content) - ktriDataValues[1].startPosition }];
    *outWrapped = [rid subdataWithRange:(NSRange){ ktriDataValues[2].startPosition, NSMaxRange(ktriDataValues[3].i.content) - ktriDataValues[2].startPosition } ];
    return nil;
}

static NSError *parseKeyAgreementRecipient(NSData *rid, const struct parsedTag *recip, NSData **outRecipientIdKeyPairs, NSData **outOriginatorFragment)
{
    /*
     KeyAgreeRecipientInfo ::= SEQUENCE {
         version CMSVersion,  -- always set to 3
         originator [0] EXPLICIT OriginatorIdentifierOrKey,
         ukm [1] EXPLICIT UserKeyingMaterial OPTIONAL,
         keyEncryptionAlgorithm KeyEncryptionAlgorithmIdentifier,
         recipientEncryptedKeys RecipientEncryptedKeys ::= SEQUENCE {
             SEQUENCE {
                 rid KeyAgreeRecipientIdentifier,
                 encryptedKey EncryptedKey
             }
         }
     }
     */
    
    static const struct scanItem kariDataItems[5] = {
        { FLAG_PRIMITIVE, BER_TAG_INTEGER }, /* version */
        { FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC, 0 }, /* OriginatorIdentifierOrKey */
        { FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC|FLAG_OPTIONAL, 1 }, /* UserKeyingMaterial */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* wrapping algorithm */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE } /* wrapped keys (multiple) */
    };
    struct parsedItem kariDataValues[5];
    
    enum OFASN1ErrorCodes rc = OFASN1ParseItemsInObject(rid, *recip, YES, kariDataItems, kariDataValues);
    if (rc)
        return OFNSErrorFromASN1Error(rc, @"KeyAgreementRecipient");
    
    int syntaxVersion = -1;
    rc = OFASN1UnDERSmallInteger(rid, &kariDataValues[0].i, &syntaxVersion);
    if (rc != OFASN1Success || syntaxVersion < 0 || syntaxVersion > 3) {
        // Don't try to parse something whose version field is out of the range we know about.
        // (Technically we should only accept syntax version 3 and later, since this structure didn't exist earlier.)
        return unsupportedCMSFeature(@"KeyAgreementRecipient.version=%d", syntaxVersion);
    }
    
    /* The only kind of key agreement originator we support is the OriginatorKey option. (This also seems to be the only one that most PKIX standards use.)
     OriginatorIdentifierOrKey = CHOICE {
         originatorKey [1] IMPLICIT OriginatorPublicKey = SEQUENCE {
           algorithm AlgorithmIdentifier,
           publicKey BIT STRING
       }
     } */
    struct parsedTag oiokTag;
    NSUInteger oiokEnd = NSMaxRange(kariDataValues[1].i.content);
    rc = OFASN1ParseTagAndLength(rid, kariDataValues[1].i.content.location, oiokEnd, YES, &oiokTag);
    if (!rc) {
        if (NSMaxRange(oiokTag.content) != oiokEnd)
            rc = OFASN1TrailingData;
        else if (oiokTag.classAndConstructed != (CLASS_CONTEXT_SPECIFIC | FLAG_CONSTRUCTED) || oiokTag.tag != 1)
            rc = OFASN1UnexpectedType;
    }
    if (rc)
        return OFNSErrorFromASN1Error(rc, @"KeyAgreementRecipient.originator");
    
    // We can't really split the data in the same way that the other recipient information parsers do, since we represent several recipients with some shared information. The caller will have to further rearrange the data we return by calling _OFASN1UnzipKeyAgreementRecipients().
    // We put the common information in *outRecipientIdentifier: algId + bitstring of the ephemeral key, the optional UKM, and the common wrapping algorithm.
    // (The following subrange-ing only works because the various tags and sequences containing the algId + bitstring don't append any bytes to the end of the content they wrap; we can snip off the headers and get just the content, contiguous with the next few fields.)
    *outOriginatorFragment = [rid subdataWithRange:(NSRange){ oiokTag.content.location, NSMaxRange(kariDataValues[3].i.content) - oiokTag.content.location }];
    
    // And all the actual recipient identifiers and wrapped keys go into *outWrapped
    *outRecipientIdKeyPairs = [rid subdataWithRange:kariDataValues[4].i.content];
    
    return nil;
}

// A KeyAgreementRecipientInfo contains one common set of key-agreement parameters (ephemeral key, algorithm identifiers, etc) followed by possibly several RID+wrappedKey pairs. This function rearranges them into a structure as if we had multiple KARI structures each with only one RID (and possibly duplicated parameters).
// If we were going to decrypt multiple recipients, this would be inefficient, but we don't generally do that. So the overhead of re-parsing the originator fragment for each recipient should be minimal.
NSArray *_OFASN1UnzipKeyAgreementRecipients(NSData *originatorFragment, NSData *seq, NSError **outError) {
    NSMutableArray *rids = [NSMutableArray array];
    NSMutableArray *wrappedKeys = [NSMutableArray array];
    enum OFASN1ErrorCodes rc0;
    rc0 = OFASN1EnumerateMembersAsBERRanges(seq,
                                            (struct parsedTag){
                                                .tag = BER_TAG_SEQUENCE,
                                                .classAndConstructed = CLASS_UNIVERSAL | FLAG_CONSTRUCTED,
                                                .indefinite = NO,
                                                .content = (NSRange){ 0, seq.length }
                                            },
                                            ^enum OFASN1ErrorCodes(NSData *samebuf, struct parsedTag item, NSRange berRange)
    {
        if (item.tag != BER_TAG_SEQUENCE || item.classAndConstructed != (CLASS_UNIVERSAL|FLAG_CONSTRUCTED) || item.indefinite != NO)
            return OFASN1UnexpectedType;
        
        struct parsedTag ridTag;
        NSRange ridDERRange, wrappedKeyRange;
        enum OFASN1ErrorCodes rc = OFASN1ParseTagAndLength(samebuf, item.content.location, NSMaxRange(item.content), YES, &ridTag);
        if (rc)
            return rc;
        ridDERRange = (NSRange){ .location = item.content.location, .length = NSMaxRange(ridTag.content) - item.content.location };
        wrappedKeyRange = (NSRange){ .location = NSMaxRange(ridDERRange), .length = NSMaxRange(item.content) - NSMaxRange(ridDERRange) };
        
        [rids addObject:[samebuf subdataWithRange:ridDERRange]];
        [wrappedKeys addObject:[originatorFragment dataByAppendingData:[samebuf subdataWithRange:wrappedKeyRange]]];
        
        return OFASN1Success;
    });
    
    if (rc0) {
        if (outError)
            *outError = OFNSErrorFromASN1Error(rc0, @"KeyAgreementRecipient.RecipientEncryptedKeys");
        return nil;
    }
    
    return @[ rids, wrappedKeys ];
}

NSData *OFUnwrapRIForCMSKeyTransport(SecKeyRef secretKey, NSData *encrypted, NSError **outError)
{
    enum OFASN1Algorithm alg = OFASN1Algorithm_Unknown;
    NSRange algParams;
    
    enum OFASN1ErrorCodes rc = OFASN1ParseAlgorithmIdentifier(encrypted, YES, &alg, &algParams);
    if (rc) {
        if (outError)
            *outError = OFNSErrorFromASN1Error(rc, @"ktri algorithm identifier");
        return nil;
    }
    
    switch (alg) {
        case OFASN1Algorithm_rsaEncryption_pkcs1_5:
        {
            NSData *encryptedForTransport = OFASN1UnwrapOctetString(encrypted, (NSRange){NSMaxRange(algParams), [encrypted length] - NSMaxRange(algParams)});
            return rsaReceiveKey(encryptedForTransport, secretKey, outError);
        }
        default:
            if (outError) {
                *outError = [NSError errorWithDomain:OFErrorDomain
                                                code:OFUnsupportedCMSFeature
                                            userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringFromTableInBundle(@"Unknown public key algorithm", @"OmniFoundation", OMNI_BUNDLE, @"Error message when a CMS KeyTransport algorithm is not recognized")}];
            }
            return nil;
    }
}

#if HAVE_APPLE_ECDH_SUPPORT

NSData *OFUnwrapRIForCMSKeyAgreement(SecKeyRef secretKey, NSData *originatorFragmentAndEncryptedKey, NSError **outError)
{
#ifdef CAN_USE_APPLE_ECDH_SUPPORT
    if (!CAN_USE_APPLE_ECDH_SUPPORT) {
        if (outError)
            *outError = [NSError errorWithDomain:OFErrorDomain code:OFUnsupportedCMSFeature userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringFromTableInBundle(@"EC public keys are not usable on this OS version", @"OmniFoundation", OMNI_BUNDLE, @"Error message when trying to use an elliptic-curve key on a MacOS or iOS version that does not support them")}];
        return nil;
    }
#endif

    /* originatorFragment is put together by parseKeyAgreementRecipient(); it contains the part of the KeyAgreeRecipientInfo that is common to all the recipients of this KARI. It is then prepended to each wrappedKey by _OFASN1UnzipKeyAgreementRecipients() to produce this structure:

     algorithm AlgorithmIdentifier,
     publicKey BIT STRING
     ukm [1] EXPLICIT UserKeyingMaterial OPTIONAL,
     keyEncryptionAlgorithm KeyEncryptionAlgorithmIdentifier,
     encryptedKey OCTET STRING
     
     */
    
    static const struct scanItem originatorFragmentDataItems[5] = {
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* OriginatorKey algorithm identifier */
        { FLAG_PRIMITIVE, BER_TAG_BIT_STRING }, /* OriginatorKey public key */
        { FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC|FLAG_OPTIONAL, 1 }, /* UserKeyingMaterial */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* wrapping algorithm */
        { FLAG_PRIMITIVE, BER_TAG_OCTET_STRING }, /* wrapped key */
    };
    struct parsedItem originatorFragmentDataValues[5];
    
    enum OFASN1ErrorCodes rc = OFASN1ParseBERSequence(originatorFragmentAndEncryptedKey, 0, originatorFragmentAndEncryptedKey.length, YES, originatorFragmentDataItems, originatorFragmentDataValues, 5);
    if (rc) {
        if (outError)
            *outError = OFNSErrorFromASN1Error(rc, @"KeyAgreementRecipient");
        return nil;
    }
    
    /* Parse the originator key information */
    enum OFASN1Algorithm keyType = OFASN1Algorithm_Unknown;
    NSRange kaParameterRange = { 0, 0 };
    rc = OFASN1ParseAlgorithmIdentifier([originatorFragmentAndEncryptedKey subdataWithRange:(NSRange){ 0, NSMaxRange(originatorFragmentDataValues[0].i.content) }], NO, &keyType, &kaParameterRange);
    if (rc) {
        if (outError)
            *outError = OFNSErrorFromASN1Error(rc, @"KeyAgreementRecipient.originatorKey.algorithm");
        return nil;
    }
    if (keyType != OFASN1Algorithm_ecPublicKey) {
        /* RFC5753 [3.1.1]: "The originatorKey algorithm field MUST contain the id-ecPublicKey object identifier" */
        /* If it doesn't, the originator is trying to do something other than elliptic-curve-key-agreement. */
        if (outError)
            *outError = unsupportedCMSFeature(@"Unknown key type in key agreement recipient");
        return nil;
    }
    /* We're required to accept absent/NULL parameters. TODO: If the sender included parameters, verify that they specify the NamedCurve we expect them to (see RFC5753 [7.1.2]. */
    
    /* Next parse the key-agreement algorithm and convert it to Apple's algorithm identifier */
    NSData *keyAgreementAlgorithm = [originatorFragmentAndEncryptedKey subdataWithRange:(NSRange){ originatorFragmentDataValues[3].startPosition, NSMaxRange(originatorFragmentDataValues[3].i.content) - originatorFragmentDataValues[3].startPosition }];
    enum OFASN1Algorithm keyAgreementAlg = OFASN1Algorithm_Unknown;
    CFStringRef keyAgreementAlgApple;
    kaParameterRange = (NSRange){ 0, 0 };
    rc = OFASN1ParseAlgorithmIdentifier(keyAgreementAlgorithm, NO, &keyAgreementAlg, &kaParameterRange);
    if (rc) {
        if (outError)
            *outError = OFNSErrorFromASN1Error(rc, @"KeyAgreementRecipient.keyEncryptionAlgorithm");
        return nil;
    }
    switch (keyAgreementAlg) {
        // We never generate objects with the SHA1-based KDF, but Apple's encoder does, so we might as well support them.
        case OFASN1Algorithm_ECDH_standard_sha1kdf:
            keyAgreementAlgApple = kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA1;
            break;
        case OFASN1Algorithm_ECDH_standard_sha256kdf:
            keyAgreementAlgApple = kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256;
            break;
        case OFASN1Algorithm_ECDH_standard_sha512kdf:
            keyAgreementAlgApple = kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA512;
            break;
        case OFASN1Algorithm_ECDH_cofactor_sha1kdf:
            keyAgreementAlgApple = kSecKeyAlgorithmECDHKeyExchangeCofactorX963SHA1;
            break;
        case OFASN1Algorithm_ECDH_cofactor_sha256kdf:
            keyAgreementAlgApple = kSecKeyAlgorithmECDHKeyExchangeCofactorX963SHA256;
            break;
        case OFASN1Algorithm_ECDH_cofactor_sha512kdf:
            keyAgreementAlgApple = kSecKeyAlgorithmECDHKeyExchangeCofactorX963SHA512;
            break;
        default:
            if (outError)
                *outError = unsupportedCMSFeature(@"Unknown key agreement algorithm");
            return nil;
    }
    
    /* Next parse the key-wrapping algorithm, which is stored as the algorithm parameter of the key-agreement algorithm. This will be something like AESWRAP, taking the result of the ECDH KDF as a key-encryption-key to unwrap the key in encryptedKey and produce the CEK. */
    enum OFASN1Algorithm keyWrappingAlg = OFASN1Algorithm_Unknown;
    NSData *keyWrappingAlgIdentifier = [keyAgreementAlgorithm subdataWithRange:kaParameterRange];
    NSRange keyWrappingAlgParameterRange = { 0, 0 };
    rc = OFASN1ParseAlgorithmIdentifier(keyWrappingAlgIdentifier, NO, &keyWrappingAlg, &keyWrappingAlgParameterRange);
    if (rc) {
        if (outError)
            *outError = OFNSErrorFromASN1Error(rc, @"KeyAgreementRecipient.keyEncryptionAlgorithm");
        return nil;
    }
    
    /* Look at the wrapping algorithm and *its* parameter (if any) to see how many bytes of output we need to ask the KDF for. */
    unsigned kekLength = kekLengthOfWrapAlgorithm(keyWrappingAlg, keyWrappingAlgIdentifier, keyWrappingAlgParameterRange);
    if (!kekLength) {
        if (outError)
            *outError = unsupportedCMSFeature(@"Unknown key wrap algorithm for key agreement");
        return nil;
    }
    
    /* Did the originator include the optional UKM field? */
    NSData *ukmOctets;
    if (!(originatorFragmentDataValues[2].i.classAndConstructed & FLAG_OPTIONAL)) {
        // UKM, if present
        ukmOctets = OFASN1UnwrapOctetString(originatorFragmentAndEncryptedKey, originatorFragmentDataValues[2].i.content);
        if (!ukmOctets) {
            if (outError)
                *outError = cmsFormatError(@"ECDH KA UKM material invalid");
            return nil;
        }
    } else {
        ukmOctets = nil;
    }

    /* Construct the parameter dictionary for SecKeyCopyKeyExchangeResult(). */
    NSMutableDictionary *keyExchangeParameters = [NSMutableDictionary dictionary];
    [keyExchangeParameters setUnsignedIntValue:kekLength forKey:(__bridge NSString *)kSecKeyKeyExchangeParameterRequestedSize];
    [keyExchangeParameters setObject:cmsECCSharedInfo(keyWrappingAlgIdentifier, ukmOctets, kekLength) forKey:(__bridge NSString *)kSecKeyKeyExchangeParameterSharedInfo];

    /* Reconstitute the originator's ephemeral key. */
    /* The first byte of a BIT STRING's content is the unused bits count. The ECDH keys we support are all encoded using SECG's point format which produces an octet string, so this first byte will be 0 for any valid ECPoint. */
    NSRange ecPointRange = originatorFragmentDataValues[1].i.content;
    if (ecPointRange.length < 2) {
        if (outError) *outError = cmsFormatError(@"ephemeral ECDH key");
        return nil;
    }
    uint8_t fb[0];
    [originatorFragmentAndEncryptedKey getBytes:fb range:(NSRange){ .location = ecPointRange.location, .length = 1 }];
    if (fb[0] != 0) {
        if (outError) *outError = cmsFormatError(@"ephemeral ECDH key");
        return nil;
    }
    ecPointRange.location += 1; ecPointRange.length -= 1;  // Strip off the "unused bits" byte, but not the point-format byte
    CFErrorRef cfError = NULL;
    SecKeyRef ephemeralKey = SecKeyCreateWithData((__bridge CFDataRef)[originatorFragmentAndEncryptedKey subdataWithRange:ecPointRange],
                                                  (__bridge CFDictionaryRef)@{ (__bridge NSString *)kSecAttrKeyType: (__bridge NSString *)kSecAttrKeyTypeECSECPrimeRandom,
                                                                               (__bridge NSString *)kSecAttrKeyClass: (__bridge NSString *)kSecAttrKeyClassPublic },
                                                  &cfError);
    if (!ephemeralKey) {
        NSError *err = [NSError errorWithDomain:OFErrorDomain code:OFCMSFormatError userInfo:@{ NSUnderlyingErrorKey: (__bridge_transfer NSError *)cfError }];
        if (outError)
            *outError = err;
        return nil;
    }

    /* Now perform the actual Diffie-Hellman operation (and integrated key-derivation/stretching step) to derive the KEK. */
    cfError = NULL;
    CFDataRef ephemeralSharedSecret = SecKeyCopyKeyExchangeResult(secretKey, keyAgreementAlgApple, ephemeralKey, (__bridge CFDictionaryRef)keyExchangeParameters, &cfError);
    NSLog(@"Key agreement (%@) -> %@", keyAgreementAlgApple, [(__bridge NSData *)ephemeralSharedSecret description]);
    if (!ephemeralSharedSecret) {
        NSError *err = [NSError errorWithDomain:OFErrorDomain
                                           code:OFCMSFormatError
                                       userInfo:@{
                                                  NSUnderlyingErrorKey: (__bridge_transfer NSError *)cfError,
                                                  @"ephemeral": (__bridge_transfer NSObject *)ephemeralKey
                                                  }];
        if (outError)
            *outError = err;
        return nil;
    }
    {
        NSData *unstretchedKey = (__bridge_transfer NSData *)SecKeyCopyKeyExchangeResult(secretKey, kSecKeyAlgorithmECDHKeyExchangeStandard, ephemeralKey, (__bridge CFDictionaryRef)@{ }, NULL);
        NSLog(@"   Bare key agreement (%@) -> %@", kSecKeyAlgorithmECDHKeyExchangeStandard, [unstretchedKey description]);
    }

    CFRelease(ephemeralKey);
    
    /* And, finally, unwrap the CEK using the derived KEK. */
    NSData *encryptedKey = [originatorFragmentAndEncryptedKey subdataWithRange:(NSRange){ .location = originatorFragmentDataValues[4].startPosition, .length = NSMaxRange(originatorFragmentDataValues[4].i.content) - originatorFragmentDataValues[4].startPosition }];
    return unwrapWithAlgId([keyWrappingAlgIdentifier dataByAppendingData:encryptedKey], (__bridge_transfer NSData *)ephemeralSharedSecret, outError);
}

NSData *OFProduceRIForCMSECDHKeyAgreement(NSArray *recipientKeys, NSArray <NSData *> *recipientIdentifiers, NSData *keyAlgorithm, BOOL cofactor, NSData *CEK, NSError **outError)
{
    // Based on RFC5753. (Including IETF erratum 4777 which alters the format of the public half of the ephemeral key.)
    // See also: NIST Special Publication 800-56A, "Recommendation for Pair-Wise Key Establishment Schemes Using Discrete Logarithm Cryptography"
    
#ifdef CAN_USE_APPLE_ECDH_SUPPORT
    if (!CAN_USE_APPLE_ECDH_SUPPORT) {
        if (outError)
            *outError = [NSError errorWithDomain:OFErrorDomain code:OFUnsupportedCMSFeature userInfo:nil];
        return nil;
    }
#endif
    
    int kekSize;
    const uint8_t *keyWrapAlgOID;
    int curveSize;
    SecKeyAlgorithm agreementAlgIDApple;
    const uint8_t *agreementAlgIDCMS;
    size_t cekLength = CEK.length;
    enum OFASN1NamedCurve curve;
    
    /* CCSymmetricKeyWrap() does RFC3394 key-wrap, not RFC5649 key-wrap, which means we can only wrap things which are multiples of half the block size. */
    OBASSERT((cekLength % (kCCBlockSizeAES128/2)) == 0);
    
    {
        enum OFASN1ErrorCodes errc;
        enum OFASN1Algorithm keyAlgorithmOID = OFASN1Algorithm_Unknown;
        NSRange algorithmParameterRange = {0,0};
        
        errc = OFASN1ParseAlgorithmIdentifier(keyAlgorithm, NO, &keyAlgorithmOID, &algorithmParameterRange);
        if (errc) {
            if (outError) *outError = OFNSErrorFromASN1Error(errc, @"OFASN1ParseAlgorithmIdentifier");
            return nil;
        }
        if (keyAlgorithmOID != OFASN1Algorithm_ecPublicKey && keyAlgorithmOID != OFASN1Algorithm_ecDH) {
            if (outError) *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecParam userInfo:@{ @"key-algorithm" : keyAlgorithm }];
            return nil;
        }
        errc = OFASN1ParseAlgorithmIdentifier([keyAlgorithm subdataWithRange:algorithmParameterRange], NO, &keyAlgorithmOID, NULL);
        if (errc) {
            if (outError) *outError = OFNSErrorFromASN1Error(errc, @"OFASN1ParseAlgorithmIdentifier");
            return nil;
        }
        curve = (enum OFASN1NamedCurve)keyAlgorithmOID;
    }

    // Apple forces us to guess the key's curve based on its size. This seems fragile but we don't have a better option. (RADAR 19357823)
    // Apple provides nice constants for the sizes of the curves it supports ... but only on OSX, not iOS. Nice going, guys.
    switch (curve) {
        case OFASN1NamedCurve_secp256r1:
            curveSize = 256;
            break;
        case OFASN1NamedCurve_secp384r1:
            curveSize = 384;
            break;
        case OFASN1NamedCurve_secp521r1:
            curveSize = 521;
            break;
        default:
            if (outError)
                *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecParam userInfo:@{ @"curve" : @((int)curve) }];
            return nil;
    }
    
    // Decide on the key-wrapping parameters
    if (cekLength <= kCCKeySizeAES128 || curveSize <= 256) {
        kekSize = kCCKeySizeAES128;
        keyWrapAlgOID = der_alg_aes128_wrap;
    } else {
        kekSize = kCCKeySizeAES256;
        keyWrapAlgOID = der_alg_aes256_wrap;
    }
    
    // Decide on the key exchange and KDF algorithm. Since we're doing simple encryption, the SHA256-based KDFs are enough for all our key wrapping needs.
    if (cofactor) {
        agreementAlgIDApple = kSecKeyAlgorithmECDHKeyExchangeCofactorX963SHA256;
        agreementAlgIDCMS = der_alg_ECDH_cofactor_sha256kdf;
    } else {
        agreementAlgIDApple = kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256;
        agreementAlgIDCMS = der_alg_ECDH_standard_sha256kdf;
    }

    // Generate an ephemeral ECDH keypair.
    NSMutableDictionary *generationAttributes = [NSMutableDictionary dictionaryWithObjectsAndKeys: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyType, kCFBooleanFalse, kSecAttrIsPermanent, nil];
    [generationAttributes setIntValue:curveSize forKey:(__bridge NSString *)kSecAttrKeySizeInBits];
    SecKeyRef pubEphemeral = NULL, privEphemeral = NULL;
    OSStatus oserr = SecKeyGeneratePair((__bridge CFDictionaryRef)generationAttributes, &pubEphemeral, &privEphemeral);
    if (oserr != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:oserr userInfo: @{ @"function": @"SecKeyGeneratePair", @"parameters" : generationAttributes }];
        return nil;
    }
    OBASSERT(pubEphemeral != NULL);
    OBASSERT(privEphemeral != NULL);
    
    // Extract the ephemeral key's public point.
    // Apple's documentation only vaguely describes the result of this function as being in "SEC1 format". What they appear to mean is the result of the "Point-to-Octet-String Conversion" from SEC1. This is a non-BER format, and is usually wrapped in an OCTET STRING to get the ASN.1 ECPoint type.
    CFErrorRef cfError = NULL;
    NSData *publicEphemeralKey = (__bridge_transfer NSData *)SecKeyCopyExternalRepresentation(pubEphemeral, &cfError);
    CFRelease(pubEphemeral);
    pubEphemeral = NULL;
    if (!publicEphemeralKey) {
        CFRelease(privEphemeral);
        OB_CFERROR_TO_NS(outError, cfError);
        return nil;
    }
    
    // Generate the UKM, which is essentially an extra salt. Not absolutely needed since we're using an ephemeral key, but whatever. Maybe we'll want to do static-static someday.
    NSData *ukm = [NSData cryptographicRandomDataOfLength:16];

    
    // Next, generate the shared keys for each recipient, and use them to encrypt the CEK. Accumulate those in a buffer. Each recipient gets a structure like this:
    // RecipientEncryptedKey ::= SEQUENCE {
    //     rid KeyAgreeRecipientIdentifier,
    //     encryptedKey EncryptedKey ::= OCTET STRING
    // }

    CFNumberRef kekSizeNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &kekSize);
    NSDictionary *agreementParameters = @{ (__bridge NSString *)kSecKeyKeyExchangeParameterRequestedSize: (__bridge NSObject *)kekSizeNumber,
                                           (__bridge NSString *)kSecKeyKeyExchangeParameterSharedInfo: cmsECCSharedInfo(OFASN1AppendStructure(nil, "(+)", keyWrapAlgOID), ukm, kekSize) };
    CFRelease(kekSizeNumber);
    NSMutableData *recipientEncryptedKeys = [NSMutableData data];
    size_t wrappedKeyLength = CCSymmetricWrappedSize(kCCWRAPAES, cekLength);
    for (NSUInteger recipientIndex = 0; recipientIndex < recipientKeys.count; recipientIndex ++) {
        
        // Perform the key exchange, generating a shared secret of `kekSize` bytes
        SecKeyRef recipientPublicKey = (__bridge SecKeyRef)[recipientKeys objectAtIndex:recipientIndex];
        CFDataRef ephemeralSharedSecret = SecKeyCopyKeyExchangeResult(privEphemeral, agreementAlgIDApple, recipientPublicKey, (__bridge CFDictionaryRef)agreementParameters, &cfError);
        if (!ephemeralSharedSecret) {
            CFRelease(privEphemeral);
            OB_CFERROR_TO_NS(outError, cfError);
            return nil;
        }
        
        // We asked the KDF to produce a certain number of bytes, make sure it actually did.
        OBASSERT(CFDataGetLength(ephemeralSharedSecret) == kekSize);
        
        // Use that shared secret to encrypt the content-encryption key
        NSMutableData *wrappedKey = [NSMutableData dataWithLength:wrappedKeyLength];
        size_t wrappedLenTmp = wrappedKeyLength; /* RADAR 18206798 aka 15949620 */
        int wrapOK = CCSymmetricKeyWrap(kCCWRAPAES,
                                        CCrfc3394_iv, CCrfc3394_ivLen,
                                        CFDataGetBytePtr(ephemeralSharedSecret), CFDataGetLength(ephemeralSharedSecret),
                                        [CEK bytes], [CEK length],
                                        [wrappedKey mutableBytes], &wrappedLenTmp);
        CFRelease(ephemeralSharedSecret);
        if (wrapOK != kCCSuccess) {
            // This shouldn't ever happen, unless Apple screws up CCSymmetricKeyWrap again somehow.
            [NSException raise:NSInternalInconsistencyException format:@"CCSymmetricKeyWrap() returned %d", (int)wrapOK];
        }

        // DER-format the result
        OFASN1AppendStructure(recipientEncryptedKeys, "(d[d])", [recipientIdentifiers objectAtIndex:recipientIndex], wrappedKey);
    }
    
    CFRelease(privEphemeral);
    privEphemeral = NULL;
    
    /* Finally, produce the entire KeyAgreeRecipientInfo structure.
     KeyAgreeRecipientInfo ::= SEQUENCE {
         version CMSVersion,  -- always set to 3
         originator [0] EXPLICIT CHOICE {
             [1] IMPLICIT SEQUENCE {
                  algorithm AlgorithmIdentifier,
                  publicKey BIT STRING
             }
         },
         ukm [1] EXPLICIT OCTET STRING,
         keyEncryptionAlgorithm KeyEncryptionAlgorithmIdentifier,
         recipientEncryptedKeys SEQUENCE OF RecipientEncryptedKey
     }
     */
    return OFASN1AppendStructure(nil, "(u!(!(d<d>))!([d])(+(+))(d))",
                                 3, // Version is always 3 per RFC5753 [3.1.1]
                                 0 /* EXPLICIT TAG */ | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC,
                                 1 /* IMPLICIT TAG */ | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC,
                                 keyAlgorithm, publicEphemeralKey,
                                 1 /* EXPLICIT TAG */ | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC,
                                 ukm,
                                 agreementAlgIDCMS, keyWrapAlgOID,
                                 recipientEncryptedKeys);
}

static NSData *cmsECCSharedInfo(NSData *wrapAlg, NSData *ukm, uint32_t kekSizeBytes)
{
    // The "SharedInfo" bit string (always a byte string for us) is the auxiliary input to the X9.63 KDF, used to derive the actual key-wrapping-key from the result of the Diffie-Hellman operation. For CMS use, it's the DER encoding of this structure (which doesn't appear literally in the KARI):
    // ECC-CMS-SharedInfo ::= SEQUENCE {
    //     keyInfo         AlgorithmIdentifier,
    //     entityUInfo [0] EXPLICIT OCTET STRING OPTIONAL,
    //     suppPubInfo [2] EXPLICIT OCTET STRING
    // }
    // Oddly, suppPubInfo is kekSize (in bits) encoded as a big-endian int32, instead of as a DER INTEGER. Mysterious are the ways of standards.
    
    uint8_t suppPub[4];
    OSWriteBigInt32(suppPub, 0, kekSizeBytes * 8);
    
    // RFC 5753 [7.2]
    if (ukm) {
        return OFASN1AppendStructure(nil, "(d!([d])!([*]))", wrapAlg, 0 /* EXPLICIT TAG */, ukm, 2 /* EXPLICIT TAG */, (size_t)sizeof(suppPub), (void *)suppPub);
    } else {
        return OFASN1AppendStructure(nil, "(d!([*]))", wrapAlg, 2 /* EXPLICIT TAG */, (size_t)sizeof(suppPub), (void *)suppPub);
    }
}

#endif /* HAVE_APPLE_ECDH_SUPPORT */

#if TARGET_OS_MAC && !TARGET_OS_IPHONE

/* On Mac OS X (10.7 and later), we use the SecTransform APIs to perform a public-key operation */

static NSData *executeTransform(SecTransformRef transform, NSData *input, NSError **outError)
{
    CFErrorRef cfErr;
    Boolean secOK;
    
    // Commenting this out because, according to Apple's CryptoCompatibility sample, it "weirdly" doesn't work. Apparently not even Apple knows how this API is supposed to behave. From the comments in the official sample code: "For an RSA key the transform does PKCS#1 padding by default.  Weirdly, if we explicitly set the padding to kSecPaddingPKCS1Key then the transform fails <rdar://problem/13661366>".
    // [Wiml 2016]: Confirmed that the API still "weirdly doesn't work" (returns CSSMERR_CSP_INVALID_ATTR_PADDING) and still has no documentation explaining what's up in OSX 10.11. Re-filed as RADAR 27461697.
#if 0
    /* We want PKCS#1 v1.5 padding --- even though PKCS#1 v2.1 OAEP is better, it isn't available on iOS; and for our current document encryption use, PKCS#1v1.5 is good enough. Apple's documentation is characteristically useless, but I'm hoping that kSecPaddingPKCS1Key produces this padding. */
    cfErr = NULL;
    secOK = SecTransformSetAttribute(transform, kSecPaddingKey, kSecPaddingPKCS1Key, &cfErr);
    if (!secOK) {
        OB_CFERROR_TO_NS(outError, cfErr);
        return nil;
    }
#endif
    
    secOK = SecTransformSetAttribute(transform, kSecTransformInputAttributeName, (__bridge CFDataRef)input, &cfErr);
    if (!secOK) {
        OB_CFERROR_TO_NS(outError, cfErr);
        return nil;
    }
    
#ifdef DEBUG_wiml
    SecTransformSetAttribute(transform, kSecTransformDebugAttributeName, kCFBooleanTrue, NULL);
#endif
    
    /* Actually perform the encryption or decryption operation */
    cfErr = NULL;
    CFTypeRef transformResult = SecTransformExecute(transform, &cfErr);
    if (!transformResult) {
        OB_CFERROR_TO_NS(outError, cfErr);
        return nil;
    }
    
    /* Sanity-check the transform result. */
    if (CFGetTypeID(transformResult) != CFDataGetTypeID() ||
        CFDataGetLength(transformResult) < 16 ||
        CFDataGetLength(transformResult) >= INT_MAX) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecInternalError userInfo:@{ NSLocalizedDescriptionKey: @"Invalid result from SecTransformExecute()" }];
        CFRelease(transformResult);
        return nil;
    }
    
    return (__bridge_transfer NSData *)transformResult;
}

static NSData *rsaTransportKey(NSData *payload, SecKeyRef publicKey, NSError **outError)
{
    SecTransformRef encryptingTransform;
    
    CFErrorRef cfErr = NULL;
    encryptingTransform = SecEncryptTransformCreate(publicKey, &cfErr);
    if (!encryptingTransform) {
        OB_CFERROR_TO_NS(outError, cfErr);
        return nil;
    }
    
    NSData *result = executeTransform(encryptingTransform, payload, outError);
    
    CFRelease(encryptingTransform);
    
    return result;
}

static NSData *rsaReceiveKey(NSData *encrypted, SecKeyRef secretKey, NSError **outError)
{
    SecTransformRef decryptingTransform;
    
    CFErrorRef cfErr = NULL;
    decryptingTransform = SecDecryptTransformCreate(secretKey, &cfErr);
    if (!decryptingTransform) {
        OB_CFERROR_TO_NS(outError, cfErr);
        return nil;
    }
    
    NSData *result = executeTransform(decryptingTransform, encrypted, outError);

    CFRelease(decryptingTransform);

    return result;
}

#else

/* On iOS, we have a more limited, but simpler to invoke, API */
static NSData *rsaTransportKey(NSData *payload, SecKeyRef publicKey, NSError **outError)
{
    /* SecKeyGetBlockSize() is very vaguely documented and has in fact changed its behavior incompatibly over time, but its current behavior is to return the size, in bytes, of the block which can be encrypted by the given key. For RSA, that's the size of the output. */
    size_t byteSize = SecKeyGetBlockSize(publicKey);
    size_t bufferSize = 2 * MAX(byteSize, 128u);  // Just use an overlong buffer in case SecKeyGetBlockSize() is inaccurate somehow.
    
    NSMutableData *buffer = [[NSMutableData alloc] initWithLength:bufferSize];
    
    OSStatus oserr = SecKeyEncrypt(publicKey, kSecPaddingPKCS1, [payload bytes], [payload length], [buffer mutableBytes], &bufferSize);
    
    if (oserr != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:oserr userInfo:@{ @"function": @"SecKeyEncrypt", @"key": (__bridge NSObject *)publicKey }];
        return nil;
    }
    
    [buffer setLength:bufferSize];
    
    return buffer;
}

static NSData *rsaReceiveKey(NSData *encrypted, SecKeyRef secretKey, NSError **outError)
{
    size_t byteSize = SecKeyGetBlockSize(secretKey);
    size_t bufferSize = 2 * MAX(byteSize, 128u);  // Just use an overlong buffer in case SecKeyGetBlockSize() is inaccurate somehow.
    
    NSMutableData *buffer = [[NSMutableData alloc] initWithLength:bufferSize];
    
    OSStatus oserr = SecKeyDecrypt(secretKey, kSecPaddingPKCS1, [encrypted bytes], [encrypted length], [buffer mutableBytes], &bufferSize);
    
    if (oserr != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:oserr userInfo:@{ @"function": @"SecKeyDecrypt", @"key": (__bridge NSObject *)secretKey }];
        return nil;
    }
    
    [buffer setLength:bufferSize];
    
    return buffer;
}

#endif

#pragma mark Parsing Functions

NSError *_OFASN1ParseCMSRecipient(NSData *rinfo, enum OFCMSRecipientType *outType, NSData **outWho, NSData **outEncryptedKey)
{
    enum OFASN1ErrorCodes rc;
    struct parsedTag recip;
    
    NSUInteger inputLength = rinfo.length;
    rc = OFASN1ParseTagAndLength(rinfo, 0, inputLength, YES, &recip);
    if (rc)
        return OFNSErrorFromASN1Error(rc, @"RecipientInfo");
    if (inputLength != NSMaxRange(recip.content))
        return OFNSErrorFromASN1Error(OFASN1TrailingData, @"RecipientInfo");
    
    /* The four kinds of recipient defined in RFC 5652 [6.2]. We currently use all of them except KARI. */
    
    if (recip.classAndConstructed == (FLAG_CONSTRUCTED|CLASS_UNIVERSAL) && recip.tag == BER_TAG_SEQUENCE) {
        *outType = OFCMSRKeyTransport;
        return parseKeyTransportRecipient(rinfo, &recip, outWho, outEncryptedKey);
    } else if (recip.classAndConstructed == (FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC) && recip.tag == 1) {
        *outType = OFCMSRKeyAgreement;
        return parseKeyAgreementRecipient(rinfo, &recip, outWho, outEncryptedKey);
    } else if (recip.classAndConstructed == (FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC) && recip.tag == 2) {
        *outType = OFCMSRPreSharedKey;
        return parsePreSharedKeyRecipient(rinfo, &recip, outWho, outEncryptedKey);
    } else if (recip.classAndConstructed == (FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC) && recip.tag == 3) {
        *outType = OFCMSRPassword;
        return parsePasswordDerivationRecipient(rinfo, &recip, outWho, outEncryptedKey);
    } else if (recip.classAndConstructed == (FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC)) {
        *outType = OFCMSRUnknown;
        return nil;
    } else {
        return OFNSErrorFromASN1Error(OFASN1UnexpectedType, @"RecipientInfo");
    }
}

NSError *_OFASN1ParseCMSRecipientIdentifier(NSData *rid, enum OFCMSRecipientIdentifierType *outType, NSData **blob1, NSData **blob2)
{
    enum OFASN1ErrorCodes rc;
    struct parsedTag recip;
    NSUInteger inputLength = rid.length;

    rc = OFASN1ParseTagAndLength(rid, 0, inputLength, YES, &recip);
    if (!rc) {
        if (NSMaxRange(recip.content) < inputLength)
            rc = OFASN1Truncated;
        else if (NSMaxRange(recip.content) > inputLength)
            rc = OFASN1TrailingData;
    }
    if (rc) {
        return OFNSErrorFromASN1Error(rc, @"RecipientIdentifier");
    }
    
    if (recip.classAndConstructed == FLAG_CONSTRUCTED && recip.tag == BER_TAG_SEQUENCE) {
        /* Inverse of _OFCMSRIDFromIssuerSerial():
         
         IssuerAndSerialNumber ::= SEQUENCE {
             issuer Name,
             serialNumber CertificateSerialNumber
         }
        */
        
        static const struct scanItem isnDataItems[2] = {
            { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE },
            { FLAG_PRIMITIVE, BER_TAG_INTEGER }
        };
        struct parsedItem isnDataValues[2];
        
        rc = OFASN1ParseItemsInObject(rid, recip, YES, isnDataItems, isnDataValues);
        if (rc) {
            return OFNSErrorFromASN1Error(rc, @"RecipientIdentifier: IssuerAndSerialNumber");
        }
        
        *blob1 = [rid subdataWithRange:(NSRange){ .location = isnDataValues[0].startPosition, .length = NSMaxRange(isnDataValues[0].i.content) - isnDataValues[0].startPosition }];
        rc = OFASN1ExtractStringContents(rid, isnDataValues[1].i, blob2);
        if (rc) {
            return OFNSErrorFromASN1Error(rc, @"RecipientIdentifier: IssuerAndSerialNumber");
        }
        
        *outType = OFCMSRIDIssuerSerial;
        return nil;
    } else if (recip.classAndConstructed == (FLAG_PRIMITIVE | CLASS_CONTEXT_SPECIFIC) && recip.tag == 0) {
        /* Inverse of _OFCMSRIDFromSKI():
         [0] IMPLICIT SubjectKeyIdentifier ::= OCTET STRING
         */
        
        *blob2 = nil;
        rc = OFASN1ExtractStringContents(rid, recip, blob1);
        if (rc) {
            return OFNSErrorFromASN1Error(rc, @"RecipientIdentifier: SubjectKeyIdentifier");
        }

        *outType = OFCMSRIDSubjectKeyIdentifier;
        return nil;
    } else {
        return unsupportedCMSFeature(@"RecipientIdentifier tag 0x%02x", recip.tag);
    }
}

#pragma mark Producing RecipientIdentifiers

NSData *_OFCMSRIDFromIssuerSerial(NSData *issuer, NSData *serial)
{
    return OFASN1AppendStructure(nil, "(d![d])", issuer, BER_TAG_INTEGER, serial);
}

NSData *_OFCMSRIDFromSKI(NSData *ski)
{
    /* Implicitly tagged OCTET STRING with tag 0. */
    NSMutableData *result = [NSMutableData data];
    OFASN1AppendTagLength(result, 0 | FLAG_PRIMITIVE | CLASS_CONTEXT_SPECIFIC, [ski length]);
    [result appendData:ski];
    return result;
}

#pragma mark Local helpers

static NSError *unsupportedCMSFeature(NSString *fmt, ...)
{
    va_list argList;
    va_start(argList, fmt);
    NSString *detail = [[NSString alloc] initWithFormat:fmt arguments:argList];
    va_end(argList);
    
    NSError *result = [NSError errorWithDomain:OFErrorDomain code:OFUnsupportedCMSFeature userInfo: @{ NSLocalizedFailureReasonErrorKey: detail } ];
    
    return result;
}

static NSError *cmsFormatError(NSString *detail)
{
    return [NSError errorWithDomain:OFErrorDomain code:OFCMSFormatError userInfo: @{ NSLocalizedFailureReasonErrorKey: detail } ];
}


