// Copyright 2016-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonRandom.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/OFAEADCryptor.h>
#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFASN1-Internal.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/CFData-OFCompression.h>
#import "OFCMS-Internal.h"
#import "GeneratedOIDs.h"
#include <zlib.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

static dispatch_data_t cryptorProcessData(CCCryptorRef cryptor, NSData *input, NSError **outError);
static dispatch_data_t cmsDecryptContentCBC(NSData *cek, NSData *nonce, CCAlgorithm innerAlgorithm, NSData *ciphertext, NSError **outError);
static dispatch_data_t cmsDecryptContentCCM(NSData *cek, NSData *nonce, int tagSize, NSData *ciphertext, NSArray *authenticatedAttributes, NSData *mac, NSError **outError);
#ifdef OF_AEAD_GCM_ENABLED
static dispatch_data_t cmsDecryptContentGCM(NSData *cek, NSData *nonce, int tagSize, NSData *ciphertext, NSArray *authenticatedAttributes, NSData *mac, NSError **outError);
#endif
static enum OFASN1ErrorCodes parseSequenceTagExactly(NSData *buf, NSRange range, BOOL requireDER, struct parsedTag *into);
static enum OFASN1ErrorCodes parseCMSContentInfo(NSData *buf, NSUInteger berEnd, struct parsedTag tag, enum OFCMSContentType *innerContentType, NSRange *innerContentRange);
static enum OFASN1ErrorCodes parseCMSEncryptedContentInfo(NSData *buf, const struct parsedTag *v, enum OFCMSContentType *innerContentType, NSData **algorithm, NSData **innerContent);
static enum OFASN1ErrorCodes parseSignerInfo(NSData *signerInfo, int *cmsVersion, NSData **outSid, NSData **outDigestAlg, NSData **outSignature);
static enum OFASN1ErrorCodes extractMembersAsDER(NSData *buf, struct parsedTag obj, NSMutableArray *into);
static NSData *OFCMSCreateMAC(NSData *hmacKey, NSData *content, NSData *contentType, NSArray<NSData *> *authenticatedAttributes, NSData **outAttrElement);
static BOOL typeRequiresOctetStringWrapper(enum OFCMSContentType ct);
static const uint8_t *rawCMSOIDFromContentType(enum OFCMSContentType ct);
static dispatch_data_t dispatch_of_NSData(NSData *buf) __attribute__((unused));

#define SUBDATA_OF_TAGS(der, tags, startIndex, count) [(der) subdataWithRange:(NSRange){ .location = tags[startIndex].startPosition, .length = NSMaxRange(tags[(startIndex)+(count)-1].i.content) - tags[startIndex].startPosition }]

#pragma mark EnvelopedData

static NSData *_dataForAttributesWithImplicitTag(NSArray <NSData *> * __nullable attributes, uint8_t tag)
{
    NSMutableData *data = nil;
    if (attributes != nil && attributes.count != 0) {
        data = [NSMutableData data];
        OFASN1AppendSet(data, FLAG_CONSTRUCTED | BER_TAG_SET, attributes);
        uint8_t implicit_tag[1];
        implicit_tag[0] = FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC | tag;
        [data replaceBytesInRange:(NSRange){0, 1} withBytes:implicit_tag length:1];
    }
    return data;
}


dispatch_data_t __nullable OFCMSCreateEnvelopedData(NSData *cek, NSArray<NSData *> *recipientInfos, NSData *innerContentType, NSData *content, NSArray <NSData *> * __nullable unprotectedAttributes, NSError **outError) DISPATCH_RETURNS_RETAINED
{
    const uint8_t *contentEncryptionAlgOID;
    NSUInteger cekLength = cek.length;
    
    switch(cekLength) {
        case kCCKeySizeAES128: contentEncryptionAlgOID = der_alg_aes128_cbc; break;
        case kCCKeySizeAES192: contentEncryptionAlgOID = der_alg_aes192_cbc; break;
        case kCCKeySizeAES256: contentEncryptionAlgOID = der_alg_aes256_cbc; break;
        default:
            if (outError)
                *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:(-50) userInfo:@{ NSLocalizedFailureReasonErrorKey: @"Invalid CEK key length" }];
            return nil;
    }
    
    unsigned char iv[kCCBlockSizeAES128];

    CCRNGStatus rerr = CCRandomGenerateBytes(iv, sizeof(iv));
    if (rerr != kCCSuccess)
        return nil;
    
    CCCryptorRef cryptor = NULL;
    CCCryptorStatus cerr = CCCryptorCreateWithMode(kCCEncrypt,
                                                   kCCModeCBC, kCCAlgorithmAES, ccPKCS7Padding,
                                                   iv,
                                                   [cek bytes], cekLength,
                                                   NULL, 0, 0, 0,
                                                   &cryptor);
    if (cerr != kCCSuccess)
        return nil;
    dispatch_data_t inner = cryptorProcessData(cryptor, content, outError);
    CCCryptorRelease(cryptor);
    if (!inner)
        return nil;

    NSData *unprotectedAttributeData = _dataForAttributesWithImplicitTag(unprotectedAttributes, 1);

    /* We're producing the following structure (see RFC5083):
     
        EnvelopedData ::= SEQUENCE {
            version CMSVersion,                                    -- 0, 2, 3, or 4
            originatorInfo [0] IMPLICIT OriginatorInfo OPTIONAL,   -- Omitted by us
            recipientInfos RecipientInfos,
            encryptedContentInfo EncryptedContentInfo ::= SEQUENCE {
                contentType OBJECT IDENTIFIER,
                contentEncryptionAlgorithm ContentEncryptionAlgorithmIdentifier,
                encryptedContent [0] IMPLICIT OCTET STRING
            }
            unprotectedAttrs [1] IMPLICIT UnprotectedAttributes OPTIONAL
         }

     */
    
    unsigned int syntaxVersion = 2;  /* TODO: RFC5652 [6.1] - version number is 0 in some cases */
    
    NSMutableData *prologue = [[NSMutableData alloc] init];
    OFASN1AppendInteger(prologue, syntaxVersion);
    /* No OriginatorInfo; we can omit it */
    OFASN1AppendSet(prologue, BER_TAG_SET | FLAG_CONSTRUCTED, recipientInfos);
    
    return OFASN1MakeStructure("(d(d(+[*])![d])d)",
                               prologue,               // Version and recipientInfos
                               innerContentType,       // Wrapped content type
                               contentEncryptionAlgOID, sizeof(iv), iv,  // Algorithm structure (OID and parameters)
                               0 /* [0] EXPLICIT tag */ | FLAG_PRIMITIVE | CLASS_CONTEXT_SPECIFIC,
                               inner,
                               unprotectedAttributeData);
}

int OFASN1ParseCMSEnvelopedData(NSData *buf, NSRange range, int *cmsVersion, NSMutableArray *outRecipients, enum OFCMSContentType *innerContentType, NSData **algorithm, NSData **innerContent, NSArray **outUnprotAttrs)
{
    enum OFASN1ErrorCodes rc;
    struct parsedTag outerTag;
    
    /* Per RFC5652 [6.1] */
    static const struct scanItem envDataItems[5] = {
        { FLAG_PRIMITIVE, BER_TAG_INTEGER }, /* version CMSVersion */
        { FLAG_OPTIONAL | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, 0 }, /* originatorInfo [0] IMPLICIT OriginatorInfo OPTIONAL */
        { FLAG_CONSTRUCTED, BER_TAG_SET }, /* recipientInfos RecipientInfos */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* encryptedContentInfo EncryptedContentInfo */
        { FLAG_OPTIONAL | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, 1 }, /* unprotectedAttrs [1] IMPLICIT UnprotectedAttributes OPTIONAL */
    };
    struct parsedItem envDataValues[5];
    
    rc = parseSequenceTagExactly(buf, range, NO, &outerTag);
    if (rc)
        return rc;
    
    rc = OFASN1ParseItemsInObject(buf, outerTag, NO, envDataItems, envDataValues);
    if (rc)
        return rc;
    
    rc = OFASN1UnDERSmallInteger(buf, &(envDataValues[0].i), cmsVersion);
    if (rc)
        return rc;
    
    rc = extractMembersAsDER(buf, envDataValues[2].i, outRecipients);
    if (rc)
        return rc;
    
    rc = parseCMSEncryptedContentInfo(buf, &(envDataValues[3].i), innerContentType, algorithm, innerContent);
    if (rc)
        return rc;

    if (!(envDataValues[4].i.classAndConstructed & FLAG_OPTIONAL)) {
        NSMutableArray * __autoreleasing array = [NSMutableArray array];
        rc = extractMembersAsDER(buf, envDataValues[4].i, array);
        if (rc != OFASN1Success)
            return rc;
        *outUnprotAttrs = array;
    } else {
        *outUnprotAttrs = nil;
    }

    return OFASN1Success;
}

#pragma mark AuthenticatedEnvelopedData

#define DEFAULT_ICV_LEN 12 /* See RFC5084 [3.1] */

dispatch_data_t __nullable OFCMSCreateAuthenticatedEnvelopedData(NSData *cek, NSArray<NSData *> *recipientInfos, OFCMSOptions options, NSData *innerContentType, NSData *content, NSArray <NSData *> * __nullable authenticatedAttributes, NSArray <NSData *> * __nullable unauthenticatedAttributes, NSError **outError) DISPATCH_RETURNS_RETAINED
{
    if (!innerContentType) {
        [NSException raise:NSInvalidArgumentException format:@"%s: missing innerContentType", __PRETTY_FUNCTION__];
    }
    
    BOOL ccm;
    
#ifdef OF_AEAD_GCM_ENABLED
    ccm = (options & OFCMSPreferCCM)? YES : NO;
#else
    ccm = YES;
#endif
    
    NSMutableData *algorithmIdentifier;
    OFAuthenticatedStreamEncryptorState encState;
    
    /* RFC5083 [2.1]: If the content type is not id-data, then the authenticated attributes must include the content-type attribute */
    if (![innerContentType isEqualToData:[NSData dataWithBytes:der_ct_data length:der_ct_data_len]]) {
        NSData *ctAttr = OFASN1AppendStructure(nil, "(+{d})", der_attr_contentType, innerContentType);
        if (authenticatedAttributes)
            authenticatedAttributes = [authenticatedAttributes arrayByAddingObject:ctAttr];
        else
            authenticatedAttributes = [NSArray arrayWithObject:ctAttr];
    }

    /* Produce the authAttrs field, if non-empty, and the AAD, which is the same except for the first byte (in the output structure it is implicitly tagged, but as AAD it does not have the implicit tag) */
    NSMutableData *authAttrs = nil;
    NSData *aad = nil;
    if (authenticatedAttributes && [authenticatedAttributes count]) {
        authAttrs = [NSMutableData data];
        OFASN1AppendSet(authAttrs, FLAG_CONSTRUCTED | BER_TAG_SET, authenticatedAttributes);
        aad = [authAttrs copy];
        static const uint8_t implicit_tag_1[1] = { FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC | 1 };
        [authAttrs replaceBytesInRange:(NSRange){0, 1} withBytes:implicit_tag_1 length:1];
    }

    NSData *unauthAttrs = _dataForAttributesWithImplicitTag(unauthenticatedAttributes, 2);

    /* Figure out our algorithm identifier */
    const uint8_t *algorithmOID;
    switch(cek.length) {
        case kCCKeySizeAES128: algorithmOID = ccm? der_alg_aes128_ccm : der_alg_aes128_gcm; break;
        case kCCKeySizeAES192: algorithmOID = ccm? der_alg_aes192_ccm : der_alg_aes192_gcm; break;
        case kCCKeySizeAES256: algorithmOID = ccm? der_alg_aes256_ccm : der_alg_aes256_gcm; break;
        default:
            if (outError)
                *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:(-50) userInfo:@{ NSLocalizedFailureReasonErrorKey: @"Invalid CEK key length" }];
            return nil;
    }

    if (ccm) {
        unsigned char nonce[7]; /* From RFC5084, the nonce is 15-L octets, where L is the length of the length field, which is "recommended" to be 8 bytes */
        
        CCRNGStatus rerr = CCRandomGenerateBytes(nonce, sizeof(nonce));
        if (rerr != kCCSuccess)
            return nil;
            
        /* AlgorithmIdentifier for CCM is:
         SEQUENCE {
             algorithm OBJECT IDENTIFIER,
             parameters CCMParameters ::= SEQUENCE {
                 aes-nonce         OCTET STRING (SIZE(7..13)),
                 aes-ICVlen        INTEGER DEFAULT 12
             }
         }
         */
        algorithmIdentifier = OFASN1AppendStructure(nil, "(+([*]))", algorithmOID, sizeof(nonce), nonce);

        encState = NULL;
        CCCryptorStatus cerr = OFCCMBeginEncryption(cek.bytes, (unsigned)cek.length,
                                                    nonce, sizeof(nonce),
                                                    content.length,
                                                    DEFAULT_ICV_LEN, (__bridge CFDataRef)aad,
                                                    &encState);
        if (cerr != kCCSuccess) {
            if (outError)
                *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:nil];
            return nil;
        }
    } else /* gcm */ {
#ifdef OF_AEAD_GCM_ENABLED
        unsigned char nonce[12]; /* From RFC5084, the recommended size is 12 bytes */
        
        CCRNGStatus rerr = CCRandomGenerateBytes(nonce, sizeof(nonce));
        if (rerr != kCCSuccess)
            return nil;
        
        /* AlgorithmIdentifier for GCM is:
         SEQUENCE {
             algorithm OBJECT IDENTIFIER,
             parameters GCMParameters ::= SEQUENCE {
                 aes-nonce        OCTET STRING, -- recommended size is 12 octets
                 aes-ICVlen       AES-GCM-ICVlen DEFAULT 12
             }
         }
         */
        algorithmIdentifier = OFASN1AppendStructure(nil, "(+([*]))", algorithmOID, sizeof(nonce), nonce);
        
        encState = NULL;
        CCCryptorStatus cerr = OFGCMBeginEncryption(cek.bytes, (unsigned)cek.length,
                                                    nonce, sizeof(nonce),
                                                    (__bridge CFDataRef)aad,
                                                    &encState);
        if (cerr != kCCSuccess) {
            if (outError)
                *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:nil];
            return nil;
        }
#else
        [NSException raise:NSInternalInconsistencyException format:@"Unreachable"];
#endif
    }
    
    /* Perform the encryption and the computation of the authentication tag (aka ICV) */
    uint8_t icvBuffer[DEFAULT_ICV_LEN];

    dispatch_data_t encrypted __block = dispatch_data_empty;
    int (^consumer)(dispatch_data_t) = ^(dispatch_data_t encryptedBit){
        encrypted = dispatch_data_create_concat(encrypted, encryptedBit);
        return 0;
    };
    
    CCCryptorStatus ccerr __block = kCCSuccess;
    [content enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
        ccerr = encState->update(encState, bytes, byteRange.length, consumer);
        if (ccerr != kCCSuccess) {
            *stop = YES;
        }
    }];
    CCCryptorStatus fcerr = encState->final(encState, icvBuffer, DEFAULT_ICV_LEN);
    
    if (ccerr != kCCSuccess || fcerr != kCCSuccess) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:(ccerr? ccerr : fcerr) userInfo:nil];
        return nil;
    }
    
    /* We're producing the following structure (see RFC5083):
    
        AuthEnvelopedData ::= SEQUENCE {
            version CMSVersion,                                    -- Must be 0
            originatorInfo [0] IMPLICIT OriginatorInfo OPTIONAL,   -- Omitted by us
            recipientInfos RecipientInfos,
            authEncryptedContentInfo EncryptedContentInfo ::= SEQUENCE {
                contentType ContentType,
                contentEncryptionAlgorithm ContentEncryptionAlgorithmIdentifier,
                encryptedContent [0] IMPLICIT EncryptedContent OPTIONAL
            },
            authAttrs [1] IMPLICIT AuthAttributes OPTIONAL,
            mac MessageAuthenticationCode,
            unauthAttrs [2] IMPLICIT UnauthAttributes OPTIONAL
        }

    */
    
    NSMutableData *prologue = [[NSMutableData alloc] init];
    OFASN1AppendInteger(prologue, 0); /* RFC5083: The version field is always 0 for this content-type */
    /* No OriginatorInfo; we can omit it */
    OFASN1AppendSet(prologue, BER_TAG_SET | FLAG_CONSTRUCTED, recipientInfos);
    
    return OFASN1MakeStructure("(d(dd![d])d[*]d)",
                               prologue, innerContentType, algorithmIdentifier,
                               0 /* [0] IMPLICIT tag */ | FLAG_PRIMITIVE | CLASS_CONTEXT_SPECIFIC,
                               encrypted,
                               authAttrs ?: [NSData data],
                               (size_t)DEFAULT_ICV_LEN, icvBuffer,
                               unauthAttrs ?: [NSData data]);
}

int OFASN1ParseCMSAuthEnvelopedData(NSData *buf, NSRange range, int *cmsVersion, NSMutableArray *outRecipients, enum OFCMSContentType *innerContentType, NSData **algorithm, NSData **innerContent, NSArray **outAuthAttrs, NSData **mac, NSArray **outUnauthenticatedAttrs)
{
    enum OFASN1ErrorCodes rc;
    struct parsedTag outerTag;
    
    /* Per RFC5083 [2.1] */
    static const struct scanItem envDataItems[7] = {
        { FLAG_PRIMITIVE, BER_TAG_INTEGER }, /* version CMSVersion */
        { FLAG_OPTIONAL | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, 0 }, /* originatorInfo [0] IMPLICIT OriginatorInfo OPTIONAL */
        { FLAG_CONSTRUCTED, BER_TAG_SET }, /* recipientInfos RecipientInfos */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* encryptedContentInfo EncryptedContentInfo */
        { FLAG_OPTIONAL | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, 1 }, /* authAttrs [1] IMPLICIT AuthAttributes OPTIONAL */
        { FLAG_PRIMITIVE, BER_TAG_OCTET_STRING },  /* mac OCTET STRING */
        { FLAG_OPTIONAL | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, 2 }, /* unauthAttrs [2] IMPLICIT UnauthAttributes OPTIONAL */
    };
    struct parsedItem envDataValues[7];
    
    
    rc = parseSequenceTagExactly(buf, range, NO, &outerTag);
    if (rc)
        return rc;
    
    rc = OFASN1ParseItemsInObject(buf, outerTag, NO, envDataItems, envDataValues);
    if (rc)
        return rc;
    
    rc = OFASN1UnDERSmallInteger(buf, &(envDataValues[0].i), cmsVersion);
    if (rc)
        return rc;
    
    rc = extractMembersAsDER(buf, envDataValues[2].i, outRecipients);
    if (rc)
        return rc;
    
    rc = parseCMSEncryptedContentInfo(buf, &(envDataValues[3].i), innerContentType, algorithm, innerContent);
    if (rc)
        return rc;
    
    if (!(envDataValues[4].i.classAndConstructed & FLAG_OPTIONAL)) {
        NSMutableArray * __autoreleasing array = [NSMutableArray array];
        rc = extractMembersAsDER(buf, envDataValues[4].i, array);
        if (rc)
            return rc;
        *outAuthAttrs = array;
    } else {
        *outAuthAttrs = nil;
    }
    
    rc = OFASN1ExtractStringContents(buf, envDataValues[5].i, mac);
    if (rc)
        return rc;
    
    if (!(envDataValues[6].i.classAndConstructed & FLAG_OPTIONAL)) {
        NSMutableArray * __autoreleasing array = [NSMutableArray array];
        rc = extractMembersAsDER(buf, envDataValues[6].i, array);
        if (rc != OFASN1Success)
            return rc;
        *outUnauthenticatedAttrs = array;
    } else {
        *outUnauthenticatedAttrs = nil;
    }

    return OFASN1Success;
}

#pragma mark AuthenticatedData

dispatch_data_t OFCMSCreateAuthenticatedData(NSData *hmacKey, NSArray<NSData *> *recipientInfos, NSUInteger options, NSData *innerContentType, NSData *content, NSArray <NSData *> *authenticatedAttributes, NSError **outError)
{
    
    static const unsigned char der_macHmacWithSha256_digestSha256[] = {
    /* macAlgorithm MessageAuthenticationCodeAlgorithm (AlgorithmIdentifier) */
        0x30, 0x0A, // SEQUENCE
            0x06, 0x08, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x09,  // From RFC4231: OID 1.2.840.113549.2.9
    /* digestAlgorithm [1] DigestAlgorithmIdentifier */
        0xA1, 0x0B, // [1] IMPLICIT SEQUENCE
            0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, // From ANSI X9.84: OID 2.16.840.1.101.3.4.2.1
    };
    
    NSData * __autoreleasing derAttributes;
    NSData *authenticationCode = OFCMSCreateMAC(hmacKey, content, innerContentType, authenticatedAttributes, &derAttributes);
    
    NSMutableData *recipients = [NSMutableData data];
    OFASN1AppendSet(recipients, BER_TAG_SET|FLAG_CONSTRUCTED, recipientInfos);
    
    return OFASN1MakeStructure("(ud*(d[d])dd)",
                               0u,          // Version number (always 0)
                               recipients,  // Recipient information
                               sizeof(der_macHmacWithSha256_digestSha256), der_macHmacWithSha256_digestSha256,  // MAC algorithm and digest algorithm
                               innerContentType, content,
                               derAttributes, authenticationCode);
}

static NSData *OFCMSCreateMAC(NSData *hmacKey, NSData *content, NSData *contentType, NSArray<NSData *> *authenticatedAttributes, NSData **outAttrElement)
{
    char hmacValue[CC_SHA256_DIGEST_LENGTH];
    NSData *authenticatedAttributesElement;
    
    if (!authenticatedAttributes) {
        /* If there are no authenticated attributes, the MAC is simply over the raw content. */
        CCHmacContext hmacContext, *hmacContextPointer;
        CCHmacInit(&hmacContext, kCCHmacAlgSHA256, [hmacKey bytes], [hmacKey length]);
        hmacContextPointer = &hmacContext;
        [content enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
            CCHmacUpdate(hmacContextPointer, bytes, byteRange.length);
        }];
        CCHmacFinal(&hmacContext, hmacValue);
        authenticatedAttributesElement = nil;
    } else {
        /* If there are authenticated attributes, we add a hash (not a hmac) attribute to the set of authenticated attributes, and the MAC is just over the authenticated attributes (thus indirectly protecting the raw content). */
        
        CC_SHA256_CTX hashContext, *hashContextPtr;
        CC_SHA256_Init(&hashContext);
        hashContextPtr = &hashContext;
        [content enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
            NSUInteger byteCount = byteRange.length;
            while (byteCount) {
                CC_LONG chunk = ( byteCount > 0x10000000 ) ? 0x10000000 : (CC_LONG)byteCount;
                CC_SHA256_Update(hashContextPtr, bytes, chunk);
                bytes += chunk;
                byteCount -= chunk;
            }
        }];
        
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256_Final(hash, &hashContext);
        
        NSMutableArray *attributes = [authenticatedAttributes mutableCopy];
        
        [attributes addObject:OFASN1AppendStructure(nil, "(+{[*]})", der_attr_messageDigest, (size_t)CC_SHA256_DIGEST_LENGTH, hash)];
        
        [attributes addObject:OFASN1AppendStructure(nil, "(+{d})", der_attr_contentType, contentType)];
        
        NSMutableData *attributeSet = [NSMutableData data];
        OFASN1AppendSet(attributeSet, BER_TAG_SET | FLAG_CONSTRUCTED, attributes);
        
        CCHmac(kCCHmacAlgSHA256, [hmacKey bytes], [hmacKey length], [attributeSet bytes], [attributeSet length], hmacValue);
        
        /* Rewrite the attribute set into its implicitly-tagged form for inclusion in the actual output */
        OBASSERT(((const uint8_t *)[attributeSet bytes])[0] == (BER_TAG_SET | FLAG_CONSTRUCTED));
        ((uint8_t *)[attributeSet mutableBytes])[0] = (2 | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC); /* Tag with [2] IMPLICIT */
        authenticatedAttributesElement = attributeSet;
    }
    
    *outAttrElement = authenticatedAttributesElement;
    
    return OFASN1AppendStructure(nil, "[*]", (size_t)CC_SHA256_DIGEST_LENGTH, hmacValue);
}

#pragma mark Signed Data

int OFASN1ParseCMSSignedData(NSData *pkcs7, NSRange range, int *cmsVersion, NSMutableArray *outCertificates, NSMutableArray *outSignatures, enum OFCMSContentType *innerContentType, NSRange *innerContentObjectLocation)
{
    enum OFASN1ErrorCodes rc;
    struct parsedTag outerTag;
    
    /* Per RFC5652 [5.1] (SignedData struct) */
    static const struct scanItem signedDataItems[6] = {
        { FLAG_PRIMITIVE, BER_TAG_INTEGER }, /* version CMSVersion */
        { FLAG_CONSTRUCTED, BER_TAG_SET }, /* digestAlgorithms SET OF DigestAlgorithmIdentifier */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* encapContentInfo EncapsulatedContentInfo */
        { FLAG_OPTIONAL | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, 0 }, /* certificates [0] IMPLICIT CertificateSet OPTIONAL */
        { FLAG_OPTIONAL | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, 1 }, /* crls [1] IMPLICIT RevocationInfoChoices OPTIONAL */
        { FLAG_CONSTRUCTED, BER_TAG_SET }, /* signerInfos SET OF SignerInfo */
    };
    struct parsedItem signedDataValues[6];
    
    rc = parseSequenceTagExactly(pkcs7, range, NO, &outerTag);
    if (rc)
        return rc;
    
    rc = OFASN1ParseItemsInObject(pkcs7, outerTag, NO, signedDataItems, signedDataValues);
    if (rc)
        return rc;
    
    rc = OFASN1UnDERSmallInteger(pkcs7, &signedDataValues[0].i, cmsVersion);
    if (rc)
        return rc;
    
    /* We don't look at the digestAlgorithms since we aren't implementing streaming verification, and there's no requirement that the digestAlgorithms are sufficient for the signatures --- they're just a hint. */
    
    /* From RFC5652 [5.2]:
     
       EncapsulatedContentInfo ::= SEQUENCE {
           eContentType ContentType,
           eContent [0] EXPLICIT OCTET STRING OPTIONAL
       }
     
     Note that this is identical to the structure of ContentInfo except that the content data is OPTIONAL, and we'll always need to unwrap the data from the OCTET STRING. Our parseCMSContentInfo() utility function handles optional content so we just parse this as if it were ContentInfo.
     */
    rc = parseCMSContentInfo(pkcs7, NSMaxRange(signedDataValues[2].i.content), signedDataValues[2].i, innerContentType, innerContentObjectLocation);
    if (rc)
        return rc;
    
    /* Enforce that the content, if it exists, is in fact an OCTET STRING */
    struct parsedTag innerContentTag;
    if (innerContentObjectLocation->length) {
        NSUInteger rangeEnds = NSMaxRange(*innerContentObjectLocation);
        rc = OFASN1ParseTagAndLength(pkcs7, innerContentObjectLocation->location, rangeEnds, NO, &innerContentTag);
        if (rc)
            return rc;
        
        if (innerContentTag.tag != BER_TAG_OCTET_STRING ||
            (innerContentTag.classAndConstructed & CLASS_MASK) != CLASS_UNIVERSAL)
            return OFASN1UnexpectedType;
        
        if (!innerContentTag.indefinite) {
            NSUInteger tagEnds = NSMaxRange(innerContentTag.content);
            if (tagEnds < rangeEnds)
                return OFASN1TrailingData;
            if (tagEnds > rangeEnds)
                return OFASN1Truncated;
        }
    }
    
    /* Optional SET OF CertificateChoices */
    if (!(signedDataValues[3].i.classAndConstructed & FLAG_OPTIONAL) && outCertificates != nil) {
        rc = extractMembersAsDER(pkcs7, signedDataValues[3].i, outCertificates);
        if (rc)
            return rc;
    }
    
    /* (We ignore the RevocationInfoChoices) */
    
    if (outSignatures != nil) {
        rc = extractMembersAsDER(pkcs7, signedDataValues[5].i, outSignatures);
        if (rc)
            return rc;
    }
    
    return OFASN1Success;
}

dispatch_data_t OFCMSCreateSignedData(NSData *innerContentType, NSData *content, NSArray *certificates, NSArray *signatures)
{
    unsigned cmsVersion = 1;
    
    /* Content types other than id-data require version 3 (or higher) */
    if (innerContentType.length != der_ct_data_len ||
        ![innerContentType isEqualToData:[NSData dataWithBytesNoCopy:(void *)der_ct_data length:der_ct_data_len freeWhenDone:NO]])
        cmsVersion = 3;

    NSMutableArray *digestIdentifiers = [NSMutableArray array];

    // Run through the signatures; MAX our version with theirs. (RFC5652 5.1)
    // At the same time, populate the digestIdentifiers hint field.
    for (NSData *signerInfo in signatures) {
        int signerInfoSyntaxVersion = 0;
        NSData *digestAlg = 0;
        if (parseSignerInfo(signerInfo, &signerInfoSyntaxVersion, NULL, &digestAlg, NULL) == 0) {
            if (signerInfoSyntaxVersion > 0 && (unsigned)signerInfoSyntaxVersion > cmsVersion)
                cmsVersion = signerInfoSyntaxVersion;
            [digestIdentifiers addObjectIfAbsent:digestAlg];
        }
    }
    
    NSMutableData *digestAlgSet = [NSMutableData data];
    OFASN1AppendSet(digestAlgSet, FLAG_CONSTRUCTED | BER_TAG_SET, digestIdentifiers);
    
    NSMutableData *suffix = [NSMutableData data];
    if (certificates.count) {
        OFASN1AppendSet(suffix, FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC | 0, certificates);
    }
    OFASN1AppendSet(suffix, FLAG_CONSTRUCTED | BER_TAG_SET, signatures);

    /* We're creating this sequence (see RFC5652 [5.1] and [5.2]):
     
     SignedData ::= SEQUENCE {
         version CMSVersion,
         digestAlgorithms DigestAlgorithmIdentifiers,
         encapContentInfo EncapsulatedContentInfo = SEQUENCE {
             eContentType ContentType,
             eContent [0] EXPLICIT OCTET STRING OPTIONAL
         }
         certificates [0] IMPLICIT CertificateSet OPTIONAL,
         -- Omitted: crls [1] IMPLICIT RevocationInfoChoices OPTIONAL,
         signerInfos SignerInfos
     }
     
     "suffix" already contains both the certificates and signerInfos fields.
    */
    
    dispatch_data_t result;
    if (content) {
        result = OFASN1MakeStructure("(ud(d!([d]))d)", cmsVersion, digestAlgSet, innerContentType, CLASS_CONTEXT_SPECIFIC | FLAG_CONSTRUCTED | 0, content, suffix);
    } else {
        result = OFASN1MakeStructure("(ud(d)d)", cmsVersion, digestAlgSet, innerContentType, suffix);
    }

    return result;
}

static enum OFASN1ErrorCodes parseSignerInfo(NSData *signerInfo, int *cmsVersion, NSData **outSid, NSData **outDigestAlg, NSData **outSignature)
{
    /* Per RFC5652 [5.3] (SignedData struct) */
    static const struct scanItem signatureItems[7] = {
        { FLAG_PRIMITIVE, BER_TAG_INTEGER },         /* version CMSVersion */
        { FLAG_CONSTRUCTED | FLAG_ANY_OBJECT, 0 },   /* sid SignerIdentifier := CHOICE { ... } */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE },      /* DigestAlgorithmIdentifier SEQUENCE */
        { FLAG_OPTIONAL | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, 0 }, /* signedAttrs [0] IMPLICIT SignedAttributes OPTIONAL */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE },      /* signatureAlgorithm SEQUENCE */
        { FLAG_CONSTRUCTED, BER_TAG_OCTET_STRING },  /* signature SignatureValue */
        { FLAG_OPTIONAL | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, 1 }, /* unsignedAttrs [1] IMPLICIT UnsignedAttributes OPTIONAL */
    };
    struct parsedItem signatureValues[7];
    
    enum OFASN1ErrorCodes rc;
    struct parsedTag outerTag;
    rc = parseSequenceTagExactly(signerInfo, (NSRange){0, signerInfo.length}, NO, &outerTag);
    if (rc)
        return rc;
    
    rc = OFASN1ParseItemsInObject(signerInfo, outerTag, NO, signatureItems, signatureValues);
    if (rc)
        return rc;
    
    if (cmsVersion) {
        rc = OFASN1UnDERSmallInteger(signerInfo, &(signatureValues[0].i), cmsVersion);
        if (rc)
            return rc;
    }
    
    if (outSid) {
        *outSid = SUBDATA_OF_TAGS(signerInfo, signatureValues, 1, 1);
    }
    
    if (outDigestAlg) {
        *outDigestAlg = SUBDATA_OF_TAGS(signerInfo, signatureValues, 2, 1);
    }
    
    if (outSignature) {
        *outSignature = SUBDATA_OF_TAGS(signerInfo, signatureValues, 3, 4);
    }
    
    return OFASN1Success;
}

#pragma mark Multipart Data

int OFASN1ParseCMSMultipartData(NSData *pkcs7, NSRange range, int (^cb)(enum OFCMSContentType innerContentType, NSRange innerContentRange))
{
    struct parsedTag outerTag;
    enum OFASN1ErrorCodes rc0 = OFASN1ParseTagAndLength(pkcs7, range.location, NSMaxRange(range), NO, &outerTag);
    if (rc0)
        return rc0;
    
    /* RFC4073: ContentCollection is simply a SEQUENCE of ContentInfo */
    
    if (outerTag.classAndConstructed != (FLAG_CONSTRUCTED|CLASS_UNIVERSAL) ||
        outerTag.tag != BER_TAG_SEQUENCE)
        return OFASN1UnexpectedType;
    
    rc0 = OFASN1EnumerateMembersAsBERRanges(pkcs7, outerTag, ^(NSData *buf, struct parsedTag item, NSRange berRange) {
        /* Each embedded ContentInfo is, likewise, a SEQUENCE (see OFASN1ParseCMSContent() for what we're doing here) */
        if (item.classAndConstructed != (FLAG_CONSTRUCTED|CLASS_UNIVERSAL) ||
            item.tag != BER_TAG_SEQUENCE)
            return OFASN1UnexpectedType;
        
        enum OFCMSContentType cType;
        NSRange cRange;
        
        enum OFASN1ErrorCodes rc = parseCMSContentInfo(pkcs7, NSMaxRange(berRange), item, &cType, &cRange);
        if (rc)
            return rc;
        
        return (enum OFASN1ErrorCodes)cb(cType, cRange);
    });
    
    return rc0;
}

dispatch_data_t OFCMSCreateMultipart(NSArray <NSData *> *parts)
{
    // This is just a SEQUENCE wrapped around the parts. The caller is responsible for putting everything into ContentInfo structures (unlike OFASN1ParseCMSMultipartData).
    return OFASN1MakeStructure("(a)", parts);
}

#pragma mark Attributed content

int OFASN1ParseCMSAttributedContent(NSData *pkcs7, NSRange range, enum OFCMSContentType *outContentType, NSRange *outContentRange, NSArray **outAttrs)
{
    enum OFASN1ErrorCodes rc;
    struct parsedTag outerTag;
    
    /* Per RFC4073 [3] (ContentWithAttributes struct) */
    static const struct scanItem cwaItems[2] = {
        { CLASS_UNIVERSAL|FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* content ContentInfo */
        { CLASS_UNIVERSAL|FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* attrs SEQUENCE */
    };
    struct parsedItem cwaValues[2];
    
    rc = parseSequenceTagExactly(pkcs7, range, NO, &outerTag);
    if (rc)
        return rc;
    
    rc = OFASN1ParseItemsInObject(pkcs7, outerTag, NO, cwaItems, cwaValues);
    if (rc)
        return rc;
    
    if (outContentType || outContentRange) {
        rc = parseCMSContentInfo(pkcs7, NSMaxRange(cwaValues[0].i.content), cwaValues[0].i, outContentType, outContentRange);
        if (rc)
            return rc;
    }
    
    if (outAttrs) {
        NSMutableArray *attributes = [NSMutableArray array];
        rc = extractMembersAsDER(pkcs7, cwaValues[1].i, attributes);
        if (rc)
            return rc;
        *outAttrs = [attributes copy];
    }
    
    return OFASN1Success;
}

dispatch_data_t OFCMSWrapIdentifiedContent(enum OFCMSContentType ct, NSData *content, NSData *cid)
{
    // This is a one-shot for:
    //   - Wrapping (oid+content) to get a ContentInfo
    //   - Creating a ContentIdentifier attribute from cid
    //   - Wrapping the contentinfo and the (single) attribute in a ContentWithAttributes
    //   - Bundling that with its oid to get a ContentInfo
    
    /*
    SEQUENCE {     --  ContentInfo
        contentType OBJECT IDENTIFIER = id-ct-contentWithAttributes,
        content [0] EXPLICIT SEQUENCE { --  ContentWithAttributes
            content SEQUENCE { -- ContentInfo
                contentType OBJECT IDENTIFIER,
                content [0] EXPLICIT ANY,
            },
            attrs SEQUENCE { -- of Attribute
                SEQUENCE { -- the first attribute
                    attrType OBJECT IDENTIFIER = id-aa-contentIdentifier,
                    attrValues SET OF OCTET STRING -- cid is an octet string
                }
            }
        }
     }
     */
    
    const char *fmt = typeRequiresOctetStringWrapper(ct)?
        "(+!(((+!([d]))((+{[d]})))))" :
        "(+!(((+!( d ))((+{[d]})))))";
    
    const uint8_t *oid = rawCMSOIDFromContentType(ct);
    
    return OFASN1MakeStructure(fmt,
                               der_ct_contentWithAttributes, 0 /* EXPLICIT TAG */ | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC,
                               oid, 0 /* EXPLICIT TAG */ | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, content,
                               der_attr_contentIdentifier, cid);
}

#pragma mark Compressed Data

dispatch_data_t OFCMSCreateCompressedData(NSData *ctype, NSData *content, NSError **outError)
{
    NSData *buf;
#if HAVE_OF_DATA_TRANSFORM
    dispatch_data_t __block buf = dispatch_data_empty;
    OFDataTransform *xform = [[OFLibSystemCompressionTransform alloc] initWithAlgorithm:COMPRESSION_ZLIB operation:COMPRESSION_STREAM_ENCODE];
    buf = [xform transformData:content options:OFDataTransformOptionChunked error:outError];
    if (!buf)
        return nil;
#else
    CFErrorRef cfError = NULL;
    buf = (__bridge_transfer NSData *)OFDataCreateCompressedGzipData((__bridge CFDataRef)content, FALSE, 9, &cfError);
    if (!buf) {
        OB_CFERROR_TO_NS(outError, cfError);
        return nil;
    }
#endif
    
    /* See RFC3274 [1.1] and RFC5652 [5.2] */
    return OFASN1MakeStructure("(u(+)(d!([d])))",
                               0u, /* CMSVersion */
                               der_alg_zlibCompress,
                               ctype,
                               0 /* EXPLICIT TAG */ | CLASS_CONTEXT_SPECIFIC | FLAG_CONSTRUCTED,
                               buf);
}

int OFASN1ParseCMSCompressedData(NSData *pkcs7, NSRange range, int *outSyntaxVersion, enum OFASN1Algorithm *outCompressionAlgorithm, enum OFCMSContentType *outContentType, NSRange *outContentRange)
{
    enum OFASN1ErrorCodes rc;
    struct parsedTag outerTag;
    
    /* Per RFC3274 (CompressedData struct) */
    static const struct scanItem cdItems[3] = {
        { CLASS_UNIVERSAL|FLAG_PRIMITIVE,   BER_TAG_INTEGER  }, /* version CMSVersion */
        { CLASS_UNIVERSAL|FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* compressionAlgorithm */
        { CLASS_UNIVERSAL|FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* encapContentInfo EncapsulatedContentInfo */
    };
    struct parsedItem cdValues[3];
    
    rc = parseSequenceTagExactly(pkcs7, range, NO, &outerTag);
    if (rc)
        return rc;
    
    rc = OFASN1ParseItemsInObject(pkcs7, outerTag, NO, cdItems, cdValues);
    if (rc)
        return rc;
    
    rc = OFASN1UnDERSmallInteger(pkcs7, &cdValues[0].i, outSyntaxVersion);
    if (rc)
        return rc;

    rc = OFASN1ParseAlgorithmIdentifier(SUBDATA_OF_TAGS(pkcs7, cdValues, 1, 1), NO, outCompressionAlgorithm, NULL);
    if (rc)
        return rc;
    
    return parseCMSContentInfo(pkcs7, NSMaxRange(outerTag.content), cdValues[2].i, outContentType, outContentRange);
}

dispatch_data_t OFCMSDecompressContent(NSData *pkcs7, NSRange contentRange, enum OFASN1Algorithm compressionAlgorithm, NSError **outError)
{
    if (compressionAlgorithm != OFASN1Algorithm_zlibCompress) {
        if (outError)
            *outError = [NSError errorWithDomain:OFErrorDomain
                                            code:OFUnsupportedCMSFeature
                                        userInfo:@{
                                                   NSLocalizedDescriptionKey: NSLocalizedStringFromTableInBundle(@"Unknown compression algorithm", @"OmniFoundation", OMNI_BUNDLE, @"error message - CMS object has an unknown algorithm identifier for compression of its content") }];

        return NULL;
    }
    
    NSData *zlibData = OFASN1UnwrapOctetString(pkcs7, contentRange);
    if (!zlibData) {
        if (outError)
            *outError = OFNSErrorFromASN1Error(OFASN1UnexpectedType, @"CompressedData.Content");
        return NULL;
    }
    
#if HAVE_OF_DATA_TRANSFORM
    return [[[OFLibSystemCompressionTransform alloc] initWithAlgorithm:COMPRESSION_ZLIB operation:COMPRESSION_STREAM_DECODE]
            transformData:zlibData options:OFDataTransformOptionChunked error:outError];
#else
    CFErrorRef cfError = NULL;
    CFDataRef cfbuf = OFDataCreateDecompressedGzipData(kCFAllocatorDefault, (__bridge CFDataRef)zlibData, FALSE, &cfError);
    if (!cfbuf) {
        OB_CFERROR_TO_NS(outError, cfError);
        return nil;
    }
    
    return dispatch_of_NSData((__bridge_transfer NSData *)cfbuf);
#endif
}

#pragma mark Top-Level CMS Data

dispatch_data_t OFCMSWrapContent(enum OFCMSContentType ctype, NSData *content)
{
    const char *fmt = typeRequiresOctetStringWrapper(ctype)? "(+!([d]))" : "(+!(d))";
    const uint8_t *oid = rawCMSOIDFromContentType(ctype);
    return OFASN1MakeStructure(fmt, oid, 0 /* EXPLICIT TAG */ | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, content);
}

int OFASN1ParseCMSContent(NSData *buf, enum OFCMSContentType *innerContentType, NSRange *innerContentRange)
{
    /*
     ContentInfo ::= SEQUENCE {
         contentType ContentType,
         content [0] EXPLICIT ANY DEFINED BY contentType
     }
     */
    enum OFASN1ErrorCodes rc;
    struct parsedTag tag;
    
    NSUInteger messageLength = [buf length];
    
    rc = parseSequenceTagExactly(buf, (NSRange){0, messageLength}, NO, &tag);
    if (rc)
        return rc;
    
    return parseCMSContentInfo(buf, messageLength, tag, innerContentType, innerContentRange);
}

#pragma mark - Cryptography Helpers

/* This function looks at the algorithm identifier and dispatches to cmsDecryptContentCBC() or cmsDecryptContentAEAD() as appropriate. */
dispatch_data_t OFCMSDecryptContent(NSData *contentEncryptionAlgorithm, NSData *contentEncryptionKey, NSData *encryptedContent, NSArray *authenticatedAttributes, NSData *mac, NSError **outError)
{
    enum OFASN1Algorithm algId = OFASN1Algorithm_Unknown;
    NSRange algParams;
    
    int asn1err = OFASN1ParseAlgorithmIdentifier(contentEncryptionAlgorithm, NO, &algId, &algParams);
    if (asn1err) {
        if (outError) {
            *outError = OFNSErrorFromASN1Error(asn1err, @"encrypted content algorithm");
        }
        return nil;
    }
    
    static const struct {
        enum OFASN1Algorithm algId;
        enum {
            aMode_CBC,
            aMode_CCM,
            aMode_GCM
        } mode;
        CCAlgorithm innerAlgorithm;
        unsigned short keySize;
        unsigned short blockSize;
    } algInfo[] = {
        { OFASN1Algorithm_aes128_cbc, aMode_CBC, kCCAlgorithmAES, kCCKeySizeAES128, kCCBlockSizeAES128 },
        { OFASN1Algorithm_aes128_ccm, aMode_CCM, kCCAlgorithmAES, kCCKeySizeAES128, kCCBlockSizeAES128 },
        { OFASN1Algorithm_aes128_gcm, aMode_GCM, kCCAlgorithmAES, kCCKeySizeAES128, kCCBlockSizeAES128 },
        { OFASN1Algorithm_aes192_cbc, aMode_CBC, kCCAlgorithmAES, kCCKeySizeAES192, kCCBlockSizeAES128 },
        { OFASN1Algorithm_aes192_ccm, aMode_CCM, kCCAlgorithmAES, kCCKeySizeAES192, kCCBlockSizeAES128 },
        { OFASN1Algorithm_aes192_gcm, aMode_GCM, kCCAlgorithmAES, kCCKeySizeAES192, kCCBlockSizeAES128 },
        { OFASN1Algorithm_aes256_cbc, aMode_CBC, kCCAlgorithmAES, kCCKeySizeAES256, kCCBlockSizeAES128 },
        { OFASN1Algorithm_aes256_ccm, aMode_CCM, kCCAlgorithmAES, kCCKeySizeAES256, kCCBlockSizeAES128 },
        { OFASN1Algorithm_aes256_gcm, aMode_GCM, kCCAlgorithmAES, kCCKeySizeAES256, kCCBlockSizeAES128 },
        
        { OFASN1Algorithm_des_ede_cbc, aMode_CBC, kCCAlgorithm3DES, kCCKeySize3DES, kCCBlockSize3DES },
    };
    static const int algInfoCount = sizeof(algInfo)/sizeof(algInfo[0]);

    for (int i = 0; i < algInfoCount; i++) {
        if (algInfo[i].algId == algId) {

            /* Make sure the algId matches the key size */
            if ([contentEncryptionKey length] != algInfo[i].keySize) {
                if (outError) {
                    *outError = [NSError errorWithDomain:OFErrorDomain code:OFCMSFormatError userInfo:@{ @"keySize": @(contentEncryptionKey.length) }];
                }
                return nil;
            }
            
            /* Make sure that the alg was used in the correct context (Enveloped or AuthEnveloped) */
            if (algInfo[i].mode == aMode_CCM || algInfo[i].mode == aMode_GCM) {
                /* AEAD algorithms have some optional authenticated attributes and a MAC tag */
                if (mac == nil) {
                    if (outError) {
                        *outError = [NSError errorWithDomain:OFErrorDomain code:OFCMSFormatError userInfo:nil];
                    }
                    return nil;
                }
            } else {
                /* CBC does not have any authentication */
                if (authenticatedAttributes != nil || mac != nil) {
                    if (outError) {
                        *outError = [NSError errorWithDomain:OFErrorDomain code:OFCMSFormatError userInfo:nil];
                    }
                    return nil;
                }
            }
            
            /* Parse the encryption parameters */
            NSData *nonce = nil;
            int tagSize = 0;
            asn1err = OFASN1ParseSymmetricEncryptionParameters(contentEncryptionAlgorithm, algId, algParams, &nonce, &tagSize);
            if (asn1err) {
                if (outError) {
                    *outError = OFNSErrorFromASN1Error(asn1err, @"symmetric parameters");
                }
                return nil;
            }
            
            /* Validate the IV length for CBC modes */
            if (algInfo[i].mode == aMode_CBC) {
                if ([nonce length] != algInfo[i].blockSize) {
                    if (outError)
                        *outError = [NSError errorWithDomain:OFErrorDomain code:OFCMSFormatError userInfo:@{ @"IV length": @(nonce.length) }];
                    return nil;
                }
            }
            
            /* Dispatch to the mode-specific decryptor */
            switch (algInfo[i].mode) {
                case aMode_CBC:
                    return cmsDecryptContentCBC(contentEncryptionKey, nonce, algInfo[i].innerAlgorithm, encryptedContent, outError);
                case aMode_CCM:
                    return cmsDecryptContentCCM(contentEncryptionKey, nonce, tagSize, encryptedContent, authenticatedAttributes, mac, outError);
#ifdef OF_AEAD_GCM_ENABLED
                case aMode_GCM:
                    return cmsDecryptContentGCM(contentEncryptionKey, nonce, tagSize, encryptedContent, authenticatedAttributes, mac, outError);
#endif
                default:
                    break;
            }
            break;
        }
    }
    
    /* We fall through to here if we don't recognize the algorithm identifier */
    
    if (outError) {
        // This one's localized because it's something a user might plausibly encounter in use.
        *outError = [NSError errorWithDomain:OFErrorDomain code:OFUnsupportedCMSFeature userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringFromTableInBundle(@"Unsupported encryption algorithm", @"OmniFoundation", OMNI_BUNDLE, @"error message - CMS object has an unknown algorithm identifier for encryption of its content") }];
    }
    return nil;
}

static dispatch_data_t cmsDecryptContentCBC(NSData *cek, NSData *nonce, CCAlgorithm innerAlgorithm, NSData *ciphertext, NSError **outError)
{
    CCCryptorRef cr = NULL;
    CCCryptorStatus cerr = CCCryptorCreateWithMode(kCCDecrypt,
                                                   kCCModeCBC, innerAlgorithm, ccPKCS7Padding,
                                                   [nonce bytes],
                                                   [cek bytes], [cek length],
                                                   NULL, 0, 0, 0,
                                                   &cr);
    if (cerr != kCCSuccess) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:@{ @"function": @"CCCryptorCreateWithMode", @"alg" : @(innerAlgorithm), @"keySize": @(cek.length) }];
        return nil;
    }
    
    dispatch_data_t plaintext = cryptorProcessData(cr, ciphertext, outError);
    
    CCCryptorRelease(cr);
    
    return plaintext;
}

static CFDataRef copyAADForAttributes(NSArray *authenticatedAttributes)
{
    if (authenticatedAttributes == nil) {
        /* The AEAD algorithms distinguish between having no authenticated attributes (AAD is zero byes) and having an empty set of authenticated attributes (AAD is 0x31 0x00) */
        return NULL;
    }
    
    /* See RFC5083 [2.2]. The AAD given to the AEAD algorithm is the DER-encoding of SET OF attributes, which is not the same as the bytes in the actual CMS message (the normal tag is used instead of the CLASS_CONTEXT_SPECIFIC tag, and the order must be according to DER even though that is not required by the CMS format). */
    NSMutableData *buffer = [[NSMutableData alloc] init];
    OFASN1AppendSet(buffer, FLAG_CONSTRUCTED | BER_TAG_SET, authenticatedAttributes);
    return CFBridgingRetain(buffer);
}

static dispatch_data_t cmsDecryptContentCCM(NSData *cek, NSData *nonce, int tagSize, NSData *ciphertext, NSArray *authenticatedAttributes, NSData *mac, NSError **outError)
{
    CCCryptorStatus cerr;
    OFAuthenticatedStreamDecryptorState st = NULL;
    
    CFDataRef aad = copyAADForAttributes(authenticatedAttributes);
    cerr = OFCCMBeginDecryption([cek bytes], (unsigned)[cek length],
                                [nonce bytes], (unsigned)[nonce length],
                                [ciphertext length], tagSize,
                                aad,
                                &st);
    if (aad)
        CFRelease(aad);
    
    if (cerr != kCCSuccess) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:@{ @"function": @"OFCCMBeginDecryption" }];
        return nil;
    }
    
    return OFAuthenticatedStreamDecrypt(st, ciphertext, mac, outError);
}

#ifdef OF_AEAD_GCM_ENABLED
static dispatch_data_t cmsDecryptContentGCM(NSData *cek, NSData *nonce, int tagSize, NSData *ciphertext, NSArray *authenticatedAttributes, NSData *mac, NSError **outError)
{
    CCCryptorStatus cerr;
    OFAuthenticatedStreamDecryptorState st = NULL;
    
    CFDataRef aad = copyAADForAttributes(authenticatedAttributes);
    cerr = OFGCMBeginDecryption([cek bytes], (unsigned)[cek length],
                                [nonce bytes], (unsigned)[nonce length],
                                aad,
                                &st);
    if (aad)
        CFRelease(aad);

    if (cerr != kCCSuccess) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:@{ @"function": @"OFGCMBeginDecryption" }];
        return nil;
    }
    
    return OFAuthenticatedStreamDecrypt(st, ciphertext, mac, outError);
}
#endif

static dispatch_data_t cryptorProcessData(CCCryptorRef cryptor, NSData *input, NSError **outError)
{
    __block dispatch_data_t result = dispatch_data_empty;
    __block NSError *error = nil;

    NSUInteger inputLength = input.length;
    [input enumerateByteRangesUsingBlock:^(const void * __nonnull buf, NSRange pos, BOOL * __nonnull stop){
        bool isLast = ( NSMaxRange(pos) >= inputLength );
        size_t blockLength = CCCryptorGetOutputLength(cryptor, pos.length, isLast);
        char *outputBuffer = malloc(blockLength);
        
        size_t amountWritten = 0;
        CCCryptorStatus cerr = CCCryptorUpdate(cryptor, buf, pos.length, outputBuffer, blockLength, &amountWritten);
        if (cerr != kCCSuccess) {
            goto fail_out;
        }
        
        if (isLast) {
            size_t offset = amountWritten;
            amountWritten = 0;
            cerr = CCCryptorFinal(cryptor, outputBuffer + offset, blockLength - offset, &amountWritten);
            if (cerr != kCCSuccess) {
                goto fail_out;
            }
            amountWritten = offset + amountWritten;
        }
        
        result = dispatch_data_create_concat(result, dispatch_data_create(outputBuffer, amountWritten, NULL, DISPATCH_DATA_DESTRUCTOR_FREE));
        return;
        
    fail_out:
        free(outputBuffer);
        result = NULL;
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:nil];
        *stop = YES;
        return;
    }];

    if (result == NULL) {
        if (outError)
            *outError = error;
    }

    return result; // May be NULL, if we hit an error in the apply loop.
}

#pragma mark CMS Parsing Helpers

/** Parse a SEQUENCE tag which is expected to exactly fill a specified range.
 */
static enum OFASN1ErrorCodes parseSequenceTagExactly(NSData *buf, NSRange range, BOOL requireDER, struct parsedTag *into)
{
    enum OFASN1ErrorCodes rc;
    
    NSUInteger rangeEnds = NSMaxRange(range);
    rc = OFASN1ParseTagAndLength(buf, range.location, rangeEnds, requireDER, into);
    if (rc)
        return rc;
    
    // Check that it is in fact a SEQUENCE tag
    if (into->classAndConstructed != (CLASS_UNIVERSAL|FLAG_CONSTRUCTED))
        return OFASN1UnexpectedType;
    if (into->tag != BER_TAG_SEQUENCE)
        return OFASN1UnexpectedType;
    
    if (into->indefinite) {
        // If it's indefinite, just check that the specified range ends with the sentinel object.
        NSUInteger tagContentStarts = into->content.location;
        if (tagContentStarts + BER_SENTINEL_LENGTH > rangeEnds)
            return OFASN1Truncated;
        if (!OFASN1IsSentinelAt(buf, rangeEnds - BER_SENTINEL_LENGTH))
            return OFASN1InconsistentEncoding;
        into->content.length = rangeEnds - BER_SENTINEL_LENGTH - tagContentStarts;
    } else {
        // Otherwise, check that the tag length matches the range we were given to expect.
        NSUInteger tagEnds = NSMaxRange(into->content);
        if (tagEnds < rangeEnds)
            return OFASN1TrailingData;
        if (tagEnds > rangeEnds)
            return OFASN1Truncated;
    }
    
    return OFASN1Success;
}

/** Return the contained items of a composite type (SEQUENCE, SET, etc.) as an array of NSDatas.
 */
static enum OFASN1ErrorCodes extractMembersAsDER(NSData *buf, struct parsedTag obj, NSMutableArray *into)
{
    return OFASN1EnumerateMembersAsBERRanges(buf, obj, ^enum OFASN1ErrorCodes(NSData *samebuf, struct parsedTag item, NSRange berRange) {
        if (into) {
            [into addObject:[samebuf subdataWithRange:berRange]];
        }
        return OFASN1Success;
    });
}

static enum OFASN1ErrorCodes parseCMSEncryptedContentInfo(NSData *buf, const struct parsedTag *v, enum OFCMSContentType *innerContentType, NSData **algorithm, NSData **innerContent)
{
    /* From RFC5652 [6.1] */
    static const struct scanItem ciDataItems[3] = {
        { FLAG_PRIMITIVE, BER_TAG_OID }, /* contentType ContentType */
        { FLAG_CONSTRUCTED, BER_TAG_SEQUENCE }, /* contentEncryptionAlgorithm ContentEncryptionAlgorithmIdentifier */
        { FLAG_OPTIONAL | CLASS_CONTEXT_SPECIFIC, 0 } /* encryptedContent [0] IMPLICIT OCTET STRING OPTIONAL */
    };
    struct parsedItem ciDataValues[3];
    
    enum OFASN1ErrorCodes rc = OFASN1ParseItemsInObject(buf, *v, NO, ciDataItems, ciDataValues);
    if (rc)
        return rc;
    
    NSData *contentTypeOID = [buf subdataWithRange:ciDataValues[0].i.content];
    *innerContentType = OFASN1LookUpOID(OFCMSContentType, contentTypeOID.bytes, contentTypeOID.length);
    *algorithm = SUBDATA_OF_TAGS(buf, ciDataValues, 1, 1);
    if (!(ciDataValues[2].i.classAndConstructed & FLAG_OPTIONAL)) {
        rc = OFASN1ExtractStringContents(buf, ciDataValues[2].i, innerContent);
        if (rc)
            return rc;
    } else {
        *innerContent = nil;
    }
    
    return OFASN1Success;
}

/* The returned innerContentRange is the range of the BER-encoded content object within the [0] EXPLICIT tag */
static enum OFASN1ErrorCodes parseCMSContentInfo(NSData *buf, NSUInteger berEnd, struct parsedTag tag, enum OFCMSContentType *innerContentType, NSRange *innerContentRange)
{
    /* From RFC5652 [3]
     ContentInfo ::= SEQUENCE {
         contentType ContentType,
         content [0] EXPLICIT ANY DEFINED BY contentType
     }
     
     We also use this to parse the very similar EncapsulatedContentInfo type from [5.2]:
     
     EncapsulatedContentInfo ::= SEQUENCE {
         eContentType ContentType,
         eContent [0] EXPLICIT OCTET STRING OPTIONAL
     }
     
     in which case the returned object is always an OCTET STRING.
     */
    
    enum OFASN1ErrorCodes rc;
    
    if (tag.classAndConstructed != (FLAG_CONSTRUCTED|CLASS_UNIVERSAL) ||
        tag.tag != BER_TAG_SEQUENCE)
        return OFASN1UnexpectedType;
    
    /* Compute the end of `tag`'s content: if it's indefinite (and its length hasn't already been computed by our caller), assume it continues to the end of the buffer and subtract the size of the sentinel object; otherwise, the tag gives us the info directly */
    NSUInteger containedStuffEndIndex;
    if (tag.indefinite && (tag.content.length == 0)) {
        if (berEnd < (BER_SENTINEL_LENGTH + tag.content.location))
            return OFASN1Truncated;
        
        if (!OFASN1IsSentinelAt(buf, berEnd - BER_SENTINEL_LENGTH))
            return OFASN1InconsistentEncoding;
        
        containedStuffEndIndex = berEnd - BER_SENTINEL_LENGTH;
    } else {
        containedStuffEndIndex = NSMaxRange(tag.content);
    }
    
    /* Get the inner member's content type */
    struct parsedTag oid;
    
    rc = OFASN1ParseTagAndLength(buf, tag.content.location, containedStuffEndIndex, YES, &oid);
    if (rc)
        return rc;
    if (oid.classAndConstructed != (FLAG_PRIMITIVE|CLASS_UNIVERSAL) || oid.tag != BER_TAG_OID)
        return OFASN1UnexpectedType;
    
    if (innerContentType) {
        NSData *subdata = [buf subdataWithRange:oid.content];
        *innerContentType = OFASN1LookUpOID(OFCMSContentType, subdata.bytes, subdata.length);
    }
    
    /* The content, if any (it's not optional for us, but we are reused by the SignedData parser) will be wrapped in an explicit context tag 0 */
    /* Check whether the content-type OID was at the end of its container */
    NSUInteger afterOID = NSMaxRange(oid.content);
    if (afterOID < containedStuffEndIndex) {
        /* Parse the [0] CONT EXPLICIT tag */
        struct parsedTag explicit;
        rc = OFASN1ParseTagAndLength(buf, afterOID, containedStuffEndIndex, NO, &explicit);
        if (rc)
            return rc;
        if (explicit.classAndConstructed != (FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC) || explicit.tag != 0)
            return OFASN1UnexpectedType;
        
        if (explicit.indefinite) {
            /* Check that the sentinel of the indefinite-length [0] EXPLICIT tag is where we expect it to be, and slice it off */
            if (containedStuffEndIndex < (BER_SENTINEL_LENGTH + explicit.content.location))
                return OFASN1Truncated;
            
            if (!OFASN1IsSentinelAt(buf, containedStuffEndIndex - BER_SENTINEL_LENGTH))
                return OFASN1InconsistentEncoding;
            
            if (innerContentRange) {
                innerContentRange->location = explicit.content.location;
                innerContentRange->length = containedStuffEndIndex - BER_SENTINEL_LENGTH - explicit.content.location;
            }
        } else {
            if (NSMaxRange(explicit.content) < containedStuffEndIndex)
                return OFASN1TrailingData;
            if (NSMaxRange(explicit.content) > containedStuffEndIndex)
                return OFASN1Truncated;
            if (innerContentRange) {
                *innerContentRange = explicit.content;
            }
        }
    } else {
        /* No content */
        if (innerContentRange) {
            innerContentRange->location = afterOID;
            innerContentRange->length = 0;
        }
    }
    
    return OFASN1Success;
}

NSData *OFCMSOIDFromContentType(enum OFCMSContentType ct)
{
    for (int i = 0; i < oid_lut_OFCMSContentType_size; i++) {
        if (oid_lut_OFCMSContentType[i].nid == (int)ct) {
            return [NSData dataWithBytesNoCopy:(void *)oid_lut_OFCMSContentType[i].der length:oid_lut_OFCMSContentType[i].der_len freeWhenDone:NO];
        }
    }
    return nil;
}

static const uint8_t *rawCMSOIDFromContentType(enum OFCMSContentType ct)
{
    for (int i = 0; i < oid_lut_OFCMSContentType_size; i++) {
        if (oid_lut_OFCMSContentType[i].nid == (int)ct) {
            return oid_lut_OFCMSContentType[i].der;
        }
    }
    return NULL;
}

static BOOL typeRequiresOctetStringWrapper(enum OFCMSContentType ct)
{
    // There's a slight irregularity in the CMS format that isn't really called out in the spec. When a given CMS content type occurs in a ContentInfo, it's either stored directly as the tagged object, or if it isn't an ASN.1-formatted value it's stored in an OCTET STRING. However, when it occurs as the result of decrypting (or decompressing) a blob of data, it is not wrapped in an OCTET STRING, it's just stored directly; same if it's stored out-of-line in a detached signature. So in order to correctly wrap up a piece of data in a ContentInfo, we need to know this bit of information about the type.
    
    switch (ct) {
        case OFCMSContentType_data:
        case OFCMSContentType_XML:
            /* If we support other non-CMS data types in the future they will need to be added here */
            return YES;
            
        default:
            /* signedData, compressedData, contentCollection, etc. */
            return NO;
    }
}

#pragma mark Attribute parsing

NSError *OFCMSParseAttribute(NSData *buf, enum OFCMSAttribute *outAttr, unsigned int *outRelevantIndex, NSData **outRelevantData)
{
    NSRange oidRange, valueRange;
    enum OFASN1ErrorCodes rc = OFASN1ParseIdentifierAndParameter(buf, NO, &oidRange, &valueRange);
    if (rc)
        return OFNSErrorFromASN1Error(rc, @"Attribute");

    enum OFCMSAttribute attr = OFASN1LookUpOID(OFCMSAttribute, [buf bytes] + oidRange.location, oidRange.length);
    
    /* The Attribute syntax allows every attribute to be associated wth a SET OF values of that attribute. */
    struct parsedTag setTag;
    rc = OFASN1ParseTagAndLength(buf, valueRange.location, NSMaxRange(valueRange), YES, &setTag);
    if (!rc) {
        if (setTag.classAndConstructed != (FLAG_CONSTRUCTED|CLASS_UNIVERSAL) || setTag.tag != BER_TAG_SET)
            rc = OFASN1UnexpectedType;
        else if (NSMaxRange(setTag.content) != NSMaxRange(valueRange))
            rc = OFASN1TrailingData;
    }
    if (rc)
        return OFNSErrorFromASN1Error(rc, @"Attribute value");
    
    *outAttr = attr;

    if (attr == OFCMSAttribute_Unknown) {
        *outRelevantIndex = 0;
        *outRelevantData = nil;
        return nil;
    }
    
    /* The attributes we handle are required to have exactly one value in their set (although some, like signingTime, might sensibly admit multiples, that's forbidden by the format). The RFCs that define id-aa-contentIdentifier don't actually specify whether a signed message can have more than one identifier, but we'll assume that's the case for now. */
    if (setTag.content.length == 0) {
        return [NSError errorWithDomain:OFErrorDomain code:OFCMSFormatError userInfo:@{ @"attribute" : OFASN1DescribeOID([buf bytes] + oidRange.location, oidRange.length),
                                                                                        NSLocalizedFailureReasonErrorKey: @"Empty attribute value set" }];
    }
    struct parsedTag valueTag;
    rc = OFASN1ParseTagAndLength(buf, setTag.content.location, NSMaxRange(setTag.content), YES, &valueTag);
    if (rc)
        return OFNSErrorFromASN1Error(rc, @"Attribute value");
    if (NSMaxRange(valueTag.content) != NSMaxRange(setTag.content)) {
        return [NSError errorWithDomain:OFErrorDomain code:OFCMSFormatError userInfo:@{ @"attribute" : OFASN1DescribeOID([buf bytes] + oidRange.location, oidRange.length),
                                                                                        NSLocalizedFailureReasonErrorKey: @"Multiple attribute values" }];
    }
    
    // NSLog(@"Value of attribute %@ is %@", OFASN1DescribeOID([buf bytes] + oidRange.location, oidRange.length), [[buf subdataWithRange:setTag.content] description]);
    
    switch(attr) {
        case OFCMSAttribute_contentType:  /* RFC5652 [11.1] - an OBJECT IDENTIFIER */
        {
            if (valueTag.classAndConstructed != (FLAG_PRIMITIVE|CLASS_UNIVERSAL) || valueTag.tag != BER_TAG_OID) {
                rc = OFASN1UnexpectedType;
                break;
            }
            *outRelevantIndex = OFASN1LookUpOID(OFCMSContentType, [buf bytes] + valueTag.content.location, valueTag.content.length);
            *outRelevantData = nil;
            break;
        }
        
        case OFCMSAttribute_messageDigest:      /* RFC5652 [11.2] - OCTET STRING */
        case OFCMSAttribute_contentIdentifier:  /* RFC2634 / RFC5035 - OCTET STRING */
        case OFCMSAttribute_omniHint:           /* OCTET STRING */
        {
            if (valueTag.classAndConstructed != (FLAG_PRIMITIVE|CLASS_UNIVERSAL) || valueTag.tag != BER_TAG_OCTET_STRING) {
                rc = OFASN1UnexpectedType;
                break;
            }
            *outRelevantIndex = 0;
            *outRelevantData = [buf subdataWithRange:valueTag.content /* Just the content octets */];
            break;
        }

        case OFCMSAttribute_signingTime:        /* RFC5652 [11.3] - UTCTime or GeneralizedTime */
        {
            if (valueTag.classAndConstructed != (FLAG_PRIMITIVE|CLASS_UNIVERSAL) ||
                !(valueTag.tag == BER_TAG_UTC_TIME || valueTag.tag == BER_TAG_GENERALIZED_TIME)) {
                rc = OFASN1UnexpectedType;
                break;
            }
            *outRelevantIndex = 0;
            *outRelevantData = [buf subdataWithRange:setTag.content /* The entire value object including its tag */];
            break;
        }

        default:
        {
            *outAttr = OFCMSAttribute_Unknown;
            break;
        }
    }
    
    if (rc == OFASN1UnexpectedType) {
        return [NSError errorWithDomain:OFErrorDomain code:OFCMSFormatError userInfo:@{ @"attribute" : OFASN1DescribeOID([buf bytes] + oidRange.location, oidRange.length),
                                                                                        @"valueTag" : @( valueTag.tag ) }];
    }
    if (rc)
        return OFNSErrorFromASN1Error(rc, @"Attribute value");
    
    return nil;
}

NSData *OFCMSIdentifierAttribute(NSData *cid)
{
    return OFASN1AppendStructure(nil, "(+{[d]})", der_attr_contentIdentifier, cid);
}

NSData *OFCMSHintAttribute(NSData *cid)
{
    return OFASN1AppendStructure(nil, "(+{[d]})", der_attr_omniHint, cid);
}

static dispatch_data_t dispatch_of_NSData(NSData *buf)
{
    if ([buf conformsToProtocol:@protocol(OS_dispatch_data)]) {
        return (dispatch_data_t)buf;
    } else {
        CFDataRef retainedBuf = CFBridgingRetain([buf copy]);
        return dispatch_data_create(CFDataGetBytePtr(retainedBuf), CFDataGetLength(retainedBuf), NULL, ^{ CFRelease(retainedBuf); });
    }
}

