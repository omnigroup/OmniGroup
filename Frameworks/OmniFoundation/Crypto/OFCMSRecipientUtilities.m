// Copyright 2016 Omni Development, Inc. All rights reserved.
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
#import <OmniFoundation/OFCMS.h>
#import "OFCMS-Internal.h"
#import "GeneratedOIDs.h"
#import "OFRFC3211Wrap.h"
#import <Foundation/NSData.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonRandom.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

static NSData *rsaTransportKey(NSData *payload, SecKeyRef publicKey, NSError **outError);
static NSData *rsaReceiveKey(NSData *encrypted, SecKeyRef secretKey, NSError **outError);
static NSError *unsupportedCMSFeature(NSString *fmt, ...) __attribute__((cold));

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
            *outError = OFNSErrorFromASN1Error(asn1err, @"parameters");
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
            *outError = [NSError errorWithDomain:OFErrorDomain code:OFCMSFormatError userInfo:@{ NSLocalizedFailureReasonErrorKey: @"Key-encryption-key length mismatch" }];
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
            *outError = [NSError errorWithDomain:OFErrorDomain code:OFCMSFormatError userInfo:@{ NSLocalizedFailureReasonErrorKey: @"Key-encryption-key length mismatch" }];
        return nil;
    }
    
    size_t wrappedKeyLength = wrappedKey.length;
    size_t unwrappedKeyLength = CCSymmetricUnwrappedSize(kCCWRAPAES, wrappedKeyLength);
    
    void *buffer = malloc(unwrappedKeyLength);
    size_t unwrappedLenTmp = unwrappedKeyLength; /* RADAR 18206798 aka 15949620 */
    int unwrapError = CCSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen, [KEK bytes], [KEK length], wrappedKey.bytes, wrappedKeyLength, buffer, &unwrappedLenTmp);
    if (unwrapError) {
        free(buffer);
        // Note that CCSymmetricKeyUnwrap() is documented to return various kCCFoo error codes, but it actually only ever returns -1. (RADAR 27463510)
        // Other than programming errors, the only error we should see here is if the AESWRAP IV didn't verify, which is an indication that the user entered the wrong password.
        if (outError)
            *outError = [NSError errorWithDomain:OFErrorDomain code:OFKeyNotApplicable userInfo:@{ @"function" : @"CCSymmetricKeyUnwrap" }];
        return nil;
    }
    
    return [NSData dataWithBytesNoCopy:buffer length:unwrappedKeyLength freeWhenDone:YES];
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
    
    if (recip.classAndConstructed == FLAG_CONSTRUCTED && recip.tag == BER_TAG_SEQUENCE) {
        *outType = OFCMSRKeyTransport;
        return parseKeyTransportRecipient(rinfo, &recip, outWho, outEncryptedKey);
    } else if (recip.classAndConstructed == (FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC) && recip.tag == 3) {
        *outType = OFCMSRPassword;
        return parsePasswordDerivationRecipient(rinfo, &recip, outWho, outEncryptedKey);
    } else if (recip.classAndConstructed == (FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC) && recip.tag == 2) {
        *outType = OFCMSRPreSharedKey;
        return parsePreSharedKeyRecipient(rinfo, &recip, outWho, outEncryptedKey);
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



