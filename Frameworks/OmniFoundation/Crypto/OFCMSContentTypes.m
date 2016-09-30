// Copyright 2016 Omni Development, Inc. All rights reserved.
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
static enum OFASN1ErrorCodes extractMembersAsDER(NSData *buf, struct parsedTag obj, NSMutableArray *into);
static enum OFASN1ErrorCodes enumerateMembersAsBERRanges(NSData *, struct parsedTag, enum OFASN1ErrorCodes (^cb)(NSData *, struct parsedTag, NSRange));
static NSData *OFCMSCreateMAC(NSData *hmacKey, NSData *content, NSData *contentType, NSArray<NSData *> *authenticatedAttributes, NSData **outAttrElement);

#pragma mark EnvelopedData

dispatch_data_t OFCMSCreateEnvelopedData(NSData *cek, NSArray<NSData *> *recipientInfos, NSData *innerContentType, NSData *content, NSError **outError)
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

    
    /* We're producing the following structure (see RFC5083):
     
     EnvelopedData ::= SEQUENCE {
         version INTEGER,                                      -- 0, 2, 3, or 4
         originatorInfo [0] IMPLICIT OriginatorInfo OPTIONAL,  -- Omitted by us
         recipientInfos RecipientInfos,
         encryptedContentInfo EncryptedContentInfo ::= SEQUENCE {
             contentType OBJECT IDENTIFIER,
             contentEncryptionAlgorithm ContentEncryptionAlgorithmIdentifier,
             encryptedContent [0] IMPLICIT OCTET STRING
         }
     }
     
     */
    
    unsigned int syntaxVersion = 2;  /* TODO: RFC5652 [6.1] - version number is 0 in some cases */
    
    NSMutableData *prologue = [[NSMutableData alloc] init];
    OFASN1AppendInteger(prologue, syntaxVersion);
    /* No OriginatorInfo; we can omit it */
    OFASN1AppendSet(prologue, BER_TAG_SET | FLAG_CONSTRUCTED, recipientInfos);
    
    return OFASN1MakeStructure("(dd(d(+[*])![d]))",
                               prologue,               // Version and recipientInfos
                               innerContentType,       // Wrapped content type
                               contentEncryptionAlgOID, sizeof(iv), iv,  // Algorithm structure (OID and parameters)
                               0 /* [0] EXPLICIT tag */ | FLAG_PRIMITIVE | CLASS_CONTEXT_SPECIFIC,
                               inner);
}

int OFASN1ParseCMSEnvelopedData(NSData *buf, NSRange range, int *cmsVersion, NSMutableArray *outRecipients, enum OFCMSContentType *innerContentType, NSData **algorithm, NSData **innerContent)
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
    
    return OFASN1Success;
}

#pragma mark AuthenticatedEnvelopedData

#define DEFAULT_ICV_LEN 12 /* See RFC5084 [3.1] */

dispatch_data_t OFCMSCreateAuthenticatedEnvelopedData(NSData *cek, NSArray<NSData *> *recipientInfos, NSUInteger options, NSData *innerContentType, NSData *content, NSArray <NSData *> *authenticatedAttributes, NSError **outError)
{
    BOOL ccm;
    
#ifdef OF_AEAD_GCM_ENABLED
    ccm = (options & OFCMSPreferCCM)? YES : NO;
#else
    ccm = YES;
#endif
    
    NSMutableData *algorithmIdentifier;
    OFAuthenticatedStreamEncryptorState encState;
    
    /* RFC5083 [2.1]: If the content type is not id-data, then the authenticated attributes must incude the content-type attribute */
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
         version INTEGER,                                      -- Always 0
         originatorInfo [0] IMPLICIT OriginatorInfo OPTIONAL,  -- Omitted by us
         recipientInfos RecipientInfos,
         authEncryptedContentInfo EncryptedContentInfo ::= SEQUENCE {
             contentType OBJECT IDENTIFIER,
             contentEncryptionAlgorithm ContentEncryptionAlgorithmIdentifier,
             encryptedContent [0] IMPLICIT OCTET STRING
         }
         authAttrs [1] IMPLICIT AuthAttributes OPTIONAL,
         mac OCTET STRING
     }
     
    */
    
    NSMutableData *prologue = [[NSMutableData alloc] init];
    OFASN1AppendInteger(prologue, 0); /* RFC5083: The version field is always 0 for this content-type */
    /* No OriginatorInfo; we can omit it */
    OFASN1AppendSet(prologue, BER_TAG_SET | FLAG_CONSTRUCTED, recipientInfos);
    
    return OFASN1MakeStructure("(d(dd![d])d[*])",
                               prologue, innerContentType, algorithmIdentifier,
                               0 /* [0] IMPLICIT tag */ | FLAG_PRIMITIVE | CLASS_CONTEXT_SPECIFIC,
                               encrypted,
                               authAttrs ?: [NSData data],
                               (size_t)DEFAULT_ICV_LEN, icvBuffer);
}

int OFASN1ParseCMSAuthEnvelopedData(NSData *buf, NSRange range, int *cmsVersion, NSMutableArray *outRecipients, enum OFCMSContentType *innerContentType, NSData **algorithm, NSData **innerContent, NSArray **outAuthAttrs, NSData **mac)
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
     
     Note that this is identical to the structure of ContentInfo except that the content data is OPTIONAL, and we'll need to unwrap the data from the OCTET STRING. Our parseCMSContentInfo() utility function handles optional content so we just parse this as if it were ContentInfo.
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
    
    rc0 = enumerateMembersAsBERRanges(pkcs7, outerTag, ^(NSData *buf, struct parsedTag item, NSRange berRange) {
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
        rc = parseCMSContentInfo(pkcs7, NSMaxRange(cwaValues[1].i.content), cwaValues[1].i, outContentType, outContentRange);
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

#pragma mark Top-Level CMS Data

dispatch_data_t OFCMSWrapContent(NSData *ctype, NSData *content)
{
    return OFASN1MakeStructure("(d!(d))", ctype, 0 /* EXPLICIT TAG */ | FLAG_CONSTRUCTED | CLASS_CONTEXT_SPECIFIC, content);
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
            *outError = OFNSErrorFromASN1Error(asn1err, nil);
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
                    *outError = OFNSErrorFromASN1Error(asn1err, nil);
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
    dispatch_data_t __block result = dispatch_data_empty;
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
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:nil];
        *stop = YES;
        return;
    }];
    
    return result; // May be NULL, if we hit an error in the apply loop.
}

#pragma mark CMS Parsing Helpers

static inline BOOL isSentinelObject(const struct parsedTag *v)
{
    return (v->tag == 0 && v->classAndConstructed == 0 && !v->indefinite);
}

static BOOL isSentinelAt(NSData *buf, NSUInteger position)
{
    _Static_assert(BER_SENTINEL_LENGTH == 2, "");
    
    /* The sentinel must be { 0, 0 } */
    uint8_t sentinel[BER_SENTINEL_LENGTH];
    [buf getBytes:sentinel range:(NSRange){ .location = position, .length = BER_SENTINEL_LENGTH }];
    if (sentinel[0] != 0 || sentinel[1] != 0)
        return NO;
    else
        return YES;
}

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
        if (!isSentinelAt(buf, rangeEnds - BER_SENTINEL_LENGTH))
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
 The individual items must be definite-length, but the container need not be.
 
 TODO: Test against indefinite-length containers.
 */
static enum OFASN1ErrorCodes extractMembersAsDER(NSData *buf, struct parsedTag obj, NSMutableArray *into)
{
    NSUInteger position = obj.content.location;
    NSUInteger maxIndex = ( (obj.indefinite && !obj.content.length) ? [buf length] : NSMaxRange(obj.content) );
    
    for(;;) {
        struct parsedTag member;
        enum OFASN1ErrorCodes rc;
        if (position == maxIndex) {
            if (obj.indefinite)
                return OFASN1Truncated;
            else
                break;
        }
        rc = OFASN1ParseTagAndLength(buf, position, maxIndex, YES, &member);
        if (rc)
            return rc;
        
        if (isSentinelObject(&member)) {
            if (obj.indefinite)
                break;
            else
                return OFASN1UnexpectedType;
        }
        
        if (into) {
            [into addObject:[buf subdataWithRange:(NSRange){ position, NSMaxRange(member.content) - position }]];
        }
        
        position = NSMaxRange(member.content);
    }
    
    return OFASN1Success;
}

/** Return the contained items of a composite type (SEQUENCE, SET, etc.) by invoking a callback with their parsed tags.
 The contained items may be of indefinite length.
 
 -parameter cb: Callback invoked for each contained object. Return OFASN1Success to continue enumerating, other values to quit early.
 
 TODO: Test against indefinite-length containers.
 TODO: Test against indefinite-length contained objects.
 */
static enum OFASN1ErrorCodes enumerateMembersAsBERRanges(NSData *buf, struct parsedTag obj, enum OFASN1ErrorCodes (^cb)(NSData *samebuf, struct parsedTag item, NSRange berRange))
{
    NSUInteger position = obj.content.location;
    NSUInteger maxIndex = ( (obj.indefinite && !obj.content.length) ? [buf length] : NSMaxRange(obj.content) );
    
    for(;;) {
        struct parsedTag member;
        enum OFASN1ErrorCodes rc;
        if (position == maxIndex) {
            if (obj.indefinite)
                return OFASN1Truncated;
            else
                break;
        }
        rc = OFASN1ParseTagAndLength(buf, position, maxIndex, NO, &member);
        if (rc)
            return rc;
        
        if (isSentinelObject(&member)) {
            if (obj.indefinite)
                break;
            else
                return OFASN1UnexpectedType;
        }
        
        NSUInteger endPosition;
        if (member.indefinite) {
            rc = OFASN1IndefiniteObjectExtent(buf, member.content.location, maxIndex, &endPosition);
            if (rc)
                return rc;
        } else {
            endPosition = NSMaxRange(member.content);
        }
        
        rc = cb(buf, member, (NSRange){ .location = position, .length = endPosition - position });
        if (rc)
            return rc;
        
        position = endPosition;
    }
    
    return OFASN1Success;
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
    *algorithm = [buf subdataWithRange:(NSRange){ ciDataValues[1].startPosition, NSMaxRange(ciDataValues[1].i.content) - ciDataValues[1].startPosition }];
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
     */
    
    enum OFASN1ErrorCodes rc;
    
    if (tag.classAndConstructed != (FLAG_CONSTRUCTED|CLASS_UNIVERSAL) ||
        tag.tag != BER_TAG_SEQUENCE)
        return OFASN1UnexpectedType;
    
    /* Compute the end of `tag`'s content: if it's indefinite, subtract the size of the sentinel object; otherwise, the tag gives us the info directly */
    NSUInteger containedStuffEndIndex;
    if (tag.indefinite) {
        if (berEnd < (BER_SENTINEL_LENGTH + tag.content.location))
            return OFASN1Truncated;
        
        if (!isSentinelAt(buf, berEnd - BER_SENTINEL_LENGTH))
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
    NSUInteger afterOID = NSMaxRange(oid.content);
    if (afterOID < containedStuffEndIndex) {
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
            
            if (!isSentinelAt(buf, containedStuffEndIndex - BER_SENTINEL_LENGTH))
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

#if 0
static
dispatch_data_t englobulate_dispatch_data(NSMutableData *outer, NSUInteger offset, dispatch_data_t inner)
{
    /* If there is trailing data, chop it off of the outer buffer and into its own segment */
    NSUInteger outerLength = [outer length];
    if (offset != outerLength) {
        dispatch_data_t right = dispatch_data_create([outer bytes] + offset, outerLength - offset, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        [outer setLength:offset];
        inner = dispatch_data_create_concat(inner, right);
    }
    
    /* If the middle content has a small segment at its beginning, merge it with our own still-mutable buffer. This will be common when assembling a CMS message. */
    for (;;) {
        
        size_t innerLength = dispatch_data_get_size(inner);
        if (innerLength <= 0) {
            inner = NULL;
            break;
        }
        
        /* Find the size of the first segment of 'inner' */
        size_t pfx_offset = 0;
        dispatch_data_t pfx = dispatch_data_copy_region(inner, 0, &pfx_offset);
        assert(pfx_offset == 0);
        size_t pfx_len = dispatch_data_get_size(pfx);
        
        /* If things are small enough, just copy those bytes into our buffer */
        /* These size thresholds are pretty arbitrary */
        if (pfx_len + offset <= 8192 || pfx_len < 128) {
            [outer appendData:(NSData *)pfx];
            offset += pfx_len;
            inner = dispatch_data_create_subrange(inner, pfx_len, innerLength - pfx_len);
        } else {
            break;
        }
    }
    
    /* Finally, concatenate the segments we have */
    dispatch_data_t left = dispatch_data_create([outer bytes], [outer length], NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    if (inner)
        left = dispatch_data_create_concat(left, inner);
    return left;
}
#endif

