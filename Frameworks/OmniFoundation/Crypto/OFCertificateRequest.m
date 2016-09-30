// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSecurityUtilities.h>

#import <TargetConditionals.h> // for TARGET_OS_IPHONE

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFASN1-Internal.h>
#import <OmniFoundation/OFSecurityUtilities.h>

#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonRandom.h>
#import <Security/Security.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

#define MAYBE_UNUSED __attribute__((unused))

static NSData *wrapInSignature(NSData *payload, NSData *publicKeyInfo, BOOL shorterHash, SecKeyRef privateKey, NSMutableString *log, NSError **outError);

/* Pre-encoded algorithm identifier objects for the signature types we use. These are as set out in RFC 5754, which references RFCs 3370 and 4055. */

/* A SEQUENCE containing the OID 1.2.840.113549.1.1.11 followed by the NULL object, as set out in RFC 5754 [3.2] */
static const uint8_t alg_sha256WithRSAEncryption[] MAYBE_UNUSED = {
    0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00
};
/* Ditto, with the OID 1.2.840.113549.1.1.13 */
static const uint8_t alg_sha512WithRSAEncryption[] MAYBE_UNUSED = {
    0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0d, 0x05, 0x00
};
/* AlgorithmIdentifier for RSAPSS with hash function SHA512, mask function MGF1, and MGF1 hash function SHA512; see RFC3447 [A.2.3]
     SEQUENCE {
         OID 1.2.840.113549.1.1.10,                 -- RSAPSS algorithm
         SEQUENCE {
             [0] SEQUENCE { id-sha512 },            -- Message hash algorithm: SHA512
             [1] SEQUENCE {                         -- Mask generation function
                     id-mgf1,                       -- ...is MGF1
                     SEQUENCE { id-sha512 }         -- ...using SHA512
                          }
         }
     }
 
     id-RSASSA-PSS = 1.2.840.113549.1.1.10          -- pkcs-1 10
     id-sha512     = 2.16.840.1.101.3.4.2.3         -- From the NIST-SHA2 ASN.1 module
     id-mgf1       = 1.2.840.113549.1.1.8           -- pkcs-1 8
 
     Notes:
 
     RFC3447 reinforces that the NULL algorithm parameters for the hash algorithms should be omitted (that is, default to NULL, rather than explicit NULL) although consumers should still accept an explicit NULL.
*/
static const uint8_t alg_sha512WithRSAPSSSignature[] MAYBE_UNUSED = {
    0x30, 0x38,
    0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0A,   /* id-RSASSA-PSS */
    0x30, 0x2B,                                                         /* SEQUENCE { ... */
    0xA0, 0x0D, 0x30, 0x0B,                                             /* [0] EXPLICIT SEQUENCE { ... */
    0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03,   /* id-sha512 */
    0xA1, 0x1A, 0x30, 0x18,                                             /* [1] EXPLICIT SEQUENCE { ... */
    0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x08,   /* id-mgf1 */
    0x30, 0x0B,                                                         /* SEQUENCE { ... */
    0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03    /* id-sha512 */
};
/* A SEQUENCE containing only the OID 1.2.840.10040.4.3, as set out in RFC 3370 [3.1] */
static const uint8_t alg_sha1WithDSA[] = {
    0x30, 0x09, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x38, 0x04, 0x03
};
/* A SEQUENCE containing only the OID 1.2.840.10045.4.3.2, as set out in RFC 5754 [3.3] */
static const uint8_t alg_sha256WithECDSA[] = {
    0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02
};
/* A SEQUENCE containing only the OID 1.2.840.10045.4.3.3, as set out in RFC 5754 [3.3] */
static const uint8_t alg_sha384WithECDSA[] = {
    0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03
};
/* A SEQUENCE containing only the OID 1.2.840.10045.4.3.4, as set out in RFC 5754 [3.3] */
static const uint8_t alg_sha512WithECDSA[] = {
    0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x04
};

#if TARGET_OS_IPHONE

/* Partial DER encodings of the DigestInfo structures used in RSASSA signatures. Since the digest is of fixed length and is always at the end of the structure, we can prepend a fixed buffer containing the tags, algorithm OID and parameter, etc. These encodings are from RFC3447 [9.2] Note 1, and therefore include the explicit NULL parameter in the AlgorithmIdentifier. This is arguably incorrect according to the ASN.1 definition of the AlgorithmIdentifier structure, but a history of inconsistency in the encoding of that field has led to an explicit NULL being the correct encoding for these particular algorithms. */
static const uint8_t digestInfoPrefix_sha256[] = {
    /* SEQUENCE { SEQUENCE { OID(2.16.840.1.101.3.4.2.1), NULL }, OCTET STRING(...) } */
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20
};
static const uint8_t digestInfoPrefix_sha512[] = {
    /* SEQUENCE { SEQUENCE { OID(2.16.840.1.101.3.4.2.3), NULL }, OCTET STRING(...) } */
    0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40
};

#endif

NSData *OFGenerateCertificateRequest(NSData *derName, NSData *publicKeyInfo, SecKeyRef privateKey, NSArray *derAttributes, NSMutableString *log, NSError **outError)
{
/*
 
   We're building the following structure:
 
   CertificationRequestInfo ::= SEQUENCE {
     version                     INTEGER,
     subject                     Name,
     subjectPublicKeyInfo        SEQUENCE {
         algorithm                   AlgorithmIdentifier,
         subjectPublicKey            BIT STRING },
     attributes              [0] IMPLICIT SET OF Attribute }
*/
    
    /* Attributes, a DER-encoded SET with implicit tag 0 */
    NSMutableData *attrSet = [NSMutableData data];
    OFASN1AppendSet(attrSet, 0 | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, derAttributes);
    
    NSData *toBeSigned = OFASN1AppendStructure(nil, "(*ddd)",
                                               /* Version, INTEGER, 0 because we're not using any features not defined in the original specification. */
                                               (size_t)3, "\x02\x01\x00",
                                               
                                               /* Name, DER-encoded by our caller */
                                               derName,
                                               
                                               /* SubjectPublicKeyInfo, a sequence containing an algorithm identifier and the public key parameters, produced by Security.framework */
                                               publicKeyInfo,
                                               
                                               /* Attributes, a DER-encoded SET with implicit tag 0 */
                                               attrSet);
    
    /* Next generate a signature */
    return wrapInSignature(toBeSigned, publicKeyInfo, NO, privateKey, log, outError);
}

#if TARGET_OS_MAC && !TARGET_OS_IPHONE

/* On Mac OS X (10.7 and later), we use the SecTransform APIs to perform a public-key operation */

static NSData *wrapInSignature(NSData *payload, NSData *publicKeyInfo, BOOL shorterHash, SecKeyRef privateKey, NSMutableString *log, NSError **outError)
{
    CFErrorRef cfErr;
    SecTransformRef signingTransform;
    Boolean secOK;
    unsigned keySizeBits, keyOpSizeBits;
    
    cfErr = NULL;
    signingTransform = SecSignTransformCreate(privateKey, &cfErr);
    if (!signingTransform) {
        OB_CFERROR_TO_NS(outError, cfErr);
        return nil;
    }
    
    /* We're letting Security.framework do both the digesting and the PK operation */
    cfErr = NULL;
    secOK = SecTransformSetAttribute(signingTransform, kSecInputIsAttributeName, kSecInputIsPlainText, &cfErr);
    if (!secOK) {
    secTransformErrorOut1:
        CFRelease(signingTransform);
        OB_CFERROR_TO_NS(outError, cfErr);
        return nil;
    }
    
    secOK = SecTransformSetAttribute(signingTransform, kSecTransformInputAttributeName, (__bridge CFDataRef)payload, &cfErr);
    if (!secOK) {
        goto secTransformErrorOut1;
    }
    
    /* Figure out what signature algorithm we're using and choose its parameters */
    
    const uint8_t *infoObject;
    size_t infoObjectLength;
    CFTypeRef digestCF;
    int digestLength;
    keySizeBits = keyOpSizeBits = 0;
    enum OFKeyAlgorithm algorithm = OFASN1KeyInfoGetAlgorithm(publicKeyInfo, &keySizeBits, &keyOpSizeBits);
    
    switch (algorithm) {
        case ka_RSA:
            /* Apple does not actually document what kSecPaddingPKCS1Key does, but hopefully it does PKCS#1-v1.5 padding with the digest algorithm specified under kSecDigestType/kSecDigestLength */
            secOK = SecTransformSetAttribute(signingTransform, kSecPaddingKey, kSecPaddingPKCS1Key, &cfErr);
            if (!secOK) {
                goto secTransformErrorOut1;
            }
            if (shorterHash) {
                infoObject = alg_sha256WithRSAEncryption;
                infoObjectLength = sizeof(alg_sha256WithRSAEncryption);
                digestLength = 256;
            } else {
                infoObject = alg_sha512WithRSAEncryption;
                infoObjectLength = sizeof(alg_sha512WithRSAEncryption);
                digestLength = 512;
            }
            digestCF = kSecDigestSHA2;
            break;
        case ka_DSA:
            infoObject = alg_sha1WithDSA;
            infoObjectLength = sizeof(alg_sha1WithDSA);
            digestLength = 160;
            digestCF = kSecDigestSHA1;
            break;
        case ka_EC:
            /* These hash algorithm choices are in accordance with NSA publication "Suite B Implementer's Guide to FIPS 186-3 (ECDSA)", Feb 3, 2010, which references NIST FIPS186-3 and NSA Suite B as underlying standards. Other hash algorithms are acceptable (e.g., we could use SHA512/224 instead pf SHA256/224 with a secp224r1 key) but we choose these for maximum interoperability. (Apple's frameworks make it hard to use digests like SHA512/224 anyway.) */
            if (keyOpSizeBits < 320) {
                infoObject = alg_sha256WithECDSA;
                infoObjectLength = sizeof(alg_sha256WithECDSA);
                digestLength = 256;
            } else if (keyOpSizeBits < 448) {
                infoObject = alg_sha384WithECDSA;
                infoObjectLength = sizeof(alg_sha384WithECDSA);
                digestLength = 384;
            } else {
                infoObject = alg_sha512WithECDSA;
                infoObjectLength = sizeof(alg_sha512WithECDSA);
                digestLength = 512;
            }
            digestCF = kSecDigestSHA2;
            break;
        default:
            if (outError)
                *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:@{ NSLocalizedDescriptionKey: @"Unsupported PK algorithm" }];
            CFRelease(signingTransform);
            return nil;
    }
    
    cfErr = NULL;
    secOK = SecTransformSetAttribute(signingTransform, kSecDigestTypeAttribute, digestCF, &cfErr);
    if (!secOK) {
        goto secTransformErrorOut1;
    }
    
    cfErr = NULL;
    CFNumberRef d = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &digestLength);
    secOK = SecTransformSetAttribute(signingTransform, kSecDigestLengthAttribute, d, &cfErr);
    CFRelease(d);
    if (!secOK) {
        goto secTransformErrorOut1;
    }
    
    /* Actually generate the signature for this payload */
    cfErr = NULL;
    CFTypeRef transformResult = SecTransformExecute(signingTransform, &cfErr);
    if (!transformResult) {
        goto secTransformErrorOut1;
    }
    
    /* Sanity-check the transform result. */
    if (CFGetTypeID(transformResult) != CFDataGetTypeID() ||
        CFDataGetLength(transformResult) <= 16 ||
        CFDataGetLength(transformResult) >= INT_MAX) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecInternalError userInfo:@{ NSLocalizedDescriptionKey: @"Invalid result from SecTransformExecute()" }];
        CFRelease(transformResult);
        CFRelease(signingTransform);
        return nil;
    }
    
    /* Finally, create the signed object: a SEQUENCE containing the payload, algorithm identifier, and BIT-STRING-wrapped signature value. */
    NSMutableData *result = OFASN1AppendStructure(nil, "(d*<d>)",
                                                  payload,
                                                  (size_t)infoObjectLength, infoObject,
                                                  transformResult);
    
    CFRelease(signingTransform);
    CFRelease(transformResult);
    
    return result;
}

#else

/* On iOS, the SecTranform API is not available; instead there is a simpler SecKey**() API for doing public-key operations (which is not available on OSX). In some ways, this API is a bit nicer because there's not as much pointless abstraction between us and the operation we're trying to perform; on the other hand, it's often missing features which we then have to implement ourselves. */

static inline BOOL randomBytes(uint8_t *buffer, size_t bufferLength)
{
#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
    CCRNGStatus randomErr = CCRandomGenerateBytes(buffer, bufferLength);
    if (randomErr) {
        return NO;
    } else {
        return YES;
    }
#else
    if (SecRandomCopyBytes(NULL, bufferLength, buffer) != 0) {
        return NO;
    } else {
        return YES;
    }
#endif
}

/* This is the padding method for RSASSA-PKCS1-v1_5, which is the padding mechanism that the sha256WithRSAEncryption / sha512WithRSAEncryption OIDs indicate. Algorithm is as described in RFC3447 [9.2]. */
static inline BOOL emsaPKCS1_v1_5_SHA2(uint8_t *outBuf, size_t emLen, const void *message, CC_LONG messageLength, unsigned int hLen)
{
    size_t tLen;
    
    memset(outBuf, 0, emLen);
    if (hLen == CC_SHA256_DIGEST_LENGTH) {
        if (CC_SHA256_DIGEST_LENGTH + sizeof(digestInfoPrefix_sha256) + 4 > emLen)
            return NO;
        CC_SHA256(message, messageLength, outBuf + emLen - CC_SHA256_DIGEST_LENGTH);
        memcpy(outBuf + emLen - CC_SHA256_DIGEST_LENGTH - sizeof(digestInfoPrefix_sha256), digestInfoPrefix_sha256, sizeof(digestInfoPrefix_sha256));
        tLen = sizeof(digestInfoPrefix_sha256) + CC_SHA256_DIGEST_LENGTH;
    } else if (hLen == CC_SHA512_DIGEST_LENGTH) {
        if (CC_SHA512_DIGEST_LENGTH + sizeof(digestInfoPrefix_sha512) + 4 > emLen)
            return NO;
        CC_SHA512(message, messageLength, outBuf + emLen - CC_SHA512_DIGEST_LENGTH);
        memcpy(outBuf + emLen - CC_SHA512_DIGEST_LENGTH - sizeof(digestInfoPrefix_sha512), digestInfoPrefix_sha512, sizeof(digestInfoPrefix_sha512));
        tLen = sizeof(digestInfoPrefix_sha512) + CC_SHA512_DIGEST_LENGTH;
    } else {
        return NO;
    }
    
    outBuf[1] = 0x01;
    memset(outBuf + 2, 0xFF, emLen - tLen - 3);
    
    return YES;
}

/* And here's an implementation of RSA-PSS as described in PKCS#1 v2.1 / RFC3447 [9.1.1]. 
 * Inputs are:
 *    outBuf: Buffer into which to write the result, of length ceil(emLenBits/8)
 *    emLenBits, (named emBits in RFC3447): the maximum length in bits we can use to create an integer for the RSA operation; equal to floor(log2(N))
 *    message, messageLength: the octet string to sign
 *    hLen: The length of the hash in octets; must be either 32 (for SHA256) or 64 (for SHA512)
 *    saltLen: The length of salt to use, in octets
 */
static BOOL emsaPSSEncode_SHA2_MGF1(uint8_t *outBuf, CC_LONG emLenBits, const void *message, CC_LONG messageLength, unsigned int hLen, unsigned int saltLen, NSMutableString *log)
{
    unsigned char *(*hashf)(const void *, CC_LONG, unsigned char *);
    uint8_t Hbuf[CC_SHA512_DIGEST_LENGTH /* the longer of the hashes we support */ + 4 /* Counter for when we're using this for MGF1 */];

    CC_LONG emLen = ( emLenBits + 7 ) / 8;  /* We round up the length and generate an integer number of bytes of mask data; in step 11 we trim off the excess bits if any. */
    
    [log appendFormat:@"PSS: emLenBits=%lu emLen=%lu\n", (unsigned long)emLenBits, (unsigned long)emLen];
    
    if (hLen == CC_SHA256_DIGEST_LENGTH)
        hashf = CC_SHA256;
    else if (hLen == CC_SHA512_DIGEST_LENGTH)
        hashf = CC_SHA512;
    else
        return NO;

    /* step 3 */
    if (emLen < hLen + hLen + saltLen + 8 + 1)
        return NO;  /* Not enough room for a salt + hash + eight zeroes for steps 5 and 6 followed by the other hash and trailer byte in the final output */
    
    /* We'll construct M' in the same buffer we use for output. We position it so that there's room after it for H (its own hash) and the trailer byte. */
    CC_LONG Mprimelen = 8 + hLen + saltLen;
    unsigned char *Mprime = outBuf + emLen - 1 - Mprimelen - hLen; // Leave room for trailer byte after the salt

    [log appendFormat:@"PSS: Mprimelen=%lu\n", (unsigned long)Mprimelen];
    
    /* step 4: generate the salt (or seed) */
    if (!randomBytes(Mprime + 8 + hLen, saltLen))
        return NO;
    
    /* steps 2 and 5: generate M' = [eight zero octets] || msg hash || salt */
    hashf(message, messageLength, Mprime + 8);
    memset(Mprime, 0, 8);
    
    /* step 6: generate H = hash(M'). */
    hashf(Mprime, Mprimelen, Hbuf);
    // memcpy(outBuf - emLen - 1 - hLen, Hbuf, hLen);
    
    /* steps 7 and 8. Construct the string DB. We reuse the salt which is already in there. This consists of prepending the salt with 00 00 00 ... 01 so that its total length is (emLen - hLen - 1). */
    memset(outBuf, 0, emLen - saltLen - hLen - 2);
    outBuf[emLen - saltLen - hLen - 2] = 0x01;
    
    /* Steps 9 and 10: generate dbMask using MGF1<hashf>(seed = H, maskLen = emLen - hLen - 1), and XOR it with the contents of outBuf[]. */
    /* MGF1 is described in RFC3447 [B.2.1]. */
    CC_LONG maskLen = emLen - hLen - 1;
    for (CC_LONG ix = 0, pos = 0; pos < maskLen; ix ++) {
        OSWriteBigInt32(Hbuf, hLen, ix); /* step 3a */
        uint8_t mgfHbuf[CC_SHA512_DIGEST_LENGTH /* the longer of the hashes we support */];
        hashf(Hbuf, hLen + 4, mgfHbuf);
        CC_LONG endPos = MIN(maskLen, pos + hLen);
        unsigned hpos = 0;
        while (pos < endPos) {
            outBuf[pos ++] ^= mgfHbuf[hpos ++];
        }
    }
    
    [log appendFormat:@"PSS: maskLen=%lu\n", (unsigned long)maskLen];

    /* Step 11: Lop off any excess bits */
    uint8_t oldByte0 = outBuf[0];
    unsigned excessBits = ( 8 * emLen ) - emLenBits;
    if (excessBits) {
        outBuf[0] &= ( 1 << (8-excessBits) ) - 1;
    }
    
    [log appendFormat:@"PSS: excessBits=%u  First octet was 0x%02X now 0x%02X\n", excessBits, oldByte0, outBuf[0]];
    
    /* Step 12: Concatenate hash H and the trailer byte */
    memcpy(outBuf + maskLen, Hbuf, hLen);
    outBuf[emLen - 1] = 0xBC; /* Constant trailer byte */
    
    return YES;
}

static NSData *wrapInSignature(NSData *payload, NSData *publicKeyInfo, BOOL shorterHash, SecKeyRef privateKey, NSMutableString *log, NSError **outError)
{
    /* Figure out what signature algorithm we're using and choose its parameters */
    
    /* Whoever added SecKeyGetBlockSize() to the API apparently never decided what it should actually do. On older OSX, it returns the group size in bits (e.g., the modulus size of an RSA key, or the curve size for an EC key). On newer OSX, it returns the size in bytes. On iOS, it returns the size *of a signature* in bytes--- that's the same for RSA keys, but for EC keys a signature as returned by SecKey* functions is slightly more than twice the modulus size (it's two modulus-sized integers wrapped in some DER). (If anyone at Apple ever reads this: guys, I can probably work with whatever you put out, but please *document* what it is and don't change semantics midstream! Also, it'd be cool if you looked at the RADARs every now and then.) */

    const uint8_t *infoObject;
    size_t infoObjectLength;
    int digestLength;
#define MAX_DIGEST_LENGTH CC_SHA512_DIGEST_LENGTH
    uint8_t digestBuffer[MAX_DIGEST_LENGTH];
    size_t signatureBufferSize, paddedSize;
    uint8_t *signatureBuffer;
    OSStatus signErr;
    BOOL padOK;
    unsigned keySizeBits, keyOpSizeBits;
    
    keySizeBits = keyOpSizeBits = 0;
    enum OFKeyAlgorithm algorithm = OFASN1KeyInfoGetAlgorithm(publicKeyInfo, &keySizeBits, &keyOpSizeBits);
    [log appendFormat:@"alg=%d ks=%u kopsz=%u\n", algorithm, keySizeBits, keyOpSizeBits];
    
    /* CC_LONG (the parameter to the CC digest functions, which is typedef'd to a uint32_t, not necessarily a long) is shorter than NSUInteger (the size of an NSData). This will never be an issue in practice since certificates won't be 4 gigabytes long, but let's go ahead and check anyway. */
    NSUInteger payloadLength = [payload length];
    if (payloadLength > (uint32_t)0xFFFFFFFFu) {
        if (outError)
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:EFBIG userInfo:@{ NSLocalizedDescriptionKey: @"Hash function failure" }];
        return nil;
    }
    CC_LONG ccPayloadLength = (CC_LONG)payloadLength;
    const void *payloadBytes = [payload bytes];
    
    switch (algorithm) {
        case ka_RSA:
            signatureBufferSize = (8+keySizeBits)/8 + 1;
            signatureBuffer = malloc(signatureBufferSize);
            if (shorterHash) {
                paddedSize = ( 7 + keySizeBits ) / 8;
                infoObject = alg_sha256WithRSAEncryption;
                infoObjectLength = sizeof(alg_sha256WithRSAEncryption);
                padOK = emsaPKCS1_v1_5_SHA2(signatureBuffer, paddedSize, payloadBytes, ccPayloadLength, CC_SHA256_DIGEST_LENGTH);
                if (!padOK) {
                    if (outError)
                        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecParam userInfo:@{ NSLocalizedDescriptionKey: @"RSASSA padding failure" }];
                    free(signatureBuffer);
                    return nil;
                }
                signErr = SecKeyRawSign(privateKey, kSecPaddingNone, signatureBuffer, paddedSize, signatureBuffer, &signatureBufferSize);
            } else {
                paddedSize = ( 7 + keySizeBits - 1 ) / 8;
                infoObject = alg_sha512WithRSAPSSSignature;
                infoObjectLength = sizeof(alg_sha512WithRSAPSSSignature);
                padOK = emsaPSSEncode_SHA2_MGF1(signatureBuffer, keySizeBits-1, payloadBytes, ccPayloadLength, CC_SHA512_DIGEST_LENGTH, 20 /* RFC3447 recommendation (also what our infoObject specifies) */, log);
                if (!padOK) {
                    if (outError)
                        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecParam userInfo:@{ NSLocalizedDescriptionKey: @"RSAPSS padding failure" }];
                    free(signatureBuffer);
                    return nil;
                }
                signErr = SecKeyRawSign(privateKey, kSecPaddingNone, signatureBuffer, paddedSize, signatureBuffer, &signatureBufferSize);
            }
            break;
        case ka_DSA:
            infoObject = alg_sha1WithDSA;
            infoObjectLength = sizeof(alg_sha1WithDSA);
            CC_SHA1(payloadBytes, ccPayloadLength, digestBuffer);
            digestLength = CC_SHA1_DIGEST_LENGTH;
            signatureBufferSize = 2 * (keyOpSizeBits/8) + 16;  /* Two keyOpSizeBits-sized integers plus generous allowance for DER overhead */
            signatureBuffer = malloc(signatureBufferSize);
            signErr = SecKeyRawSign(privateKey, kSecPaddingNone, digestBuffer, digestLength, signatureBuffer, &signatureBufferSize);
            break;
        case ka_EC:
            /* These hash algorithm choices are in accordance with NSA publication "Suite B Implementer's Guide to FIPS 186-3 (ECDSA)", Feb 3, 2010, which references NIST FIPS186-3 and NSA Suite B as underlying standards. Other hash algorithms are acceptable (e.g., we could use SHA512/224 with a secp224r1 key) but we choose these for maximum interoperability. */
            signatureBufferSize = 2 * (keyOpSizeBits/8) + 16;  /* Two keyOpSizeBits-sized integers plus generous allowance for DER overhead */
            signatureBuffer = malloc(signatureBufferSize);
            if (keyOpSizeBits < 320) {
                infoObject = alg_sha256WithECDSA;
                infoObjectLength = sizeof(alg_sha256WithECDSA);
                CC_SHA256(payloadBytes, ccPayloadLength, digestBuffer);
                digestLength = CC_SHA256_DIGEST_LENGTH;
            } else if (keyOpSizeBits < 448) {
                infoObject = alg_sha384WithECDSA;
                infoObjectLength = sizeof(alg_sha384WithECDSA);
                CC_SHA384(payloadBytes, ccPayloadLength, digestBuffer);
                digestLength = CC_SHA384_DIGEST_LENGTH;
            } else {
                infoObject = alg_sha512WithECDSA;
                infoObjectLength = sizeof(alg_sha512WithECDSA);
                CC_SHA512(payloadBytes, ccPayloadLength, digestBuffer);
                digestLength = CC_SHA512_DIGEST_LENGTH;
            }
            /* No padding is done for ECDSA */
            signErr = SecKeyRawSign(privateKey, kSecPaddingNone, digestBuffer, digestLength, signatureBuffer, &signatureBufferSize);
            break;
        default:
            if (outError)
                *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:@{ NSLocalizedDescriptionKey: @"Unsupported PK algorithm" }];
            return nil;
    }
    
    if (signErr != errSecSuccess) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:signErr userInfo:@{ @"function": @"SecKeyRawSign" }];
        free(signatureBuffer);
        return nil;
    }
    
    /* Finally, create the signed object: a SEQUENCE containing the payload, algorithm identifier, and BIT-STRING-wrapped signature value. */
    NSMutableData *result = OFASN1AppendStructure(nil, "(d*<*>)",
                                                  payload,
                                                  (size_t)infoObjectLength, infoObject,
                                                  (size_t)signatureBufferSize, signatureBuffer);
    
    free(signatureBuffer);
    
    return result;
}


#endif

