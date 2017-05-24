// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <OmniFoundation/OFCMS.h>

NS_ASSUME_NONNULL_BEGIN

#define NANNP * __nullable __autoreleasing * __nonnull  // Nullable autoreleasing object, non-nullable pointer

/* PBE functions callable from Swift */
NSData *OFGeneratePBKDF2AlgorithmInfo(NSUInteger keyLength, unsigned int iterations) OB_HIDDEN;
NSData * __nullable OFDeriveKEKForCMSPWRI(NSData *password, NSData *encodedAlgInfo, NSError **outError) OB_HIDDEN;
NSData * __nullable OFProduceRIForCMSPWRI(NSData *KEK, NSData *CEK, NSData *algInfo, OFCMSOptions options) OB_HIDDEN;
NSData * __nullable OFProduceRIForCMSKEK(NSData *KEK, NSData *CEK, NSData *keyIdentifier, OFCMSOptions options) OB_HIDDEN;
NSData * __nullable OFUnwrapRIForCMSPWRI(NSData *wrappedKey, NSData *KEK, NSError **outError) OB_HIDDEN;

/* Asymmetric key transport functions callable from Swift */
NSData * __nullable OFProduceRIForCMSRSAKeyTransport(SecKeyRef publicKey, NSData *recipientIdentifier, NSData *CEK, NSError **error) OB_HIDDEN;
NSData * __nullable OFUnwrapRIForCMSKeyTransport(SecKeyRef privateKey, NSData *encrypted, NSError **outError) OB_HIDDEN;
#if HAVE_APPLE_ECDH_SUPPORT
NSData * __nullable OFProduceRIForCMSECDHKeyAgreement(NSArray *recipientKeys, NSArray <NSData *> *recipientIdentifiers, NSData *keyAlgorithm, BOOL cofactor, NSData *CEK, NSError **outError) OB_HIDDEN;
NSData * __nullable OFUnwrapRIForCMSKeyAgreement(SecKeyRef secretKey, NSData *originatorFragmentAndEncryptedKey, NSError **outError) OB_HIDDEN;
#endif

NSData *_OFCMSRIDFromIssuerSerial(NSData *issuer, NSData *serial) OB_HIDDEN;
NSData *_OFCMSRIDFromSKI(NSData *ski) OB_HIDDEN;
/* PKCS#7 recipient parsing */
NSError * __nullable _OFASN1ParseCMSRecipient(NSData *buf, enum OFCMSRecipientType *outType, NSData NANNP outWho, NSData NANNP outEncryptedKey) /* OB_HIDDEN */;
NSArray <NSArray *> * __nullable _OFASN1UnzipKeyAgreementRecipients(NSData *originatorFragment, NSData *seq, NSError **outError) OB_HIDDEN;
enum OFCMSRecipientIdentifierType { OFCMSRIDIssuerSerial, OFCMSRIDSubjectKeyIdentifier };
NSError * __nullable _OFASN1ParseCMSRecipientIdentifier(NSData *buf, enum OFCMSRecipientIdentifierType *outType, NSData NANNP blob1, NSData NANNP blob2) OB_HIDDEN;

/* Functions for creating portions of a CMS message */
dispatch_data_t __nullable OFCMSCreateCompressedData(NSData *ctype, NSData *content, NSError **outError) DISPATCH_RETURNS_RETAINED OB_HIDDEN;
dispatch_data_t OFCMSWrapContent(enum OFCMSContentType ct, NSData *content) DISPATCH_RETURNS_RETAINED /* OB_HIDDEN */;
dispatch_data_t __nullable OFCMSCreateAuthenticatedData(NSData *hmacKey, NSArray<NSData *> *recipientInfos, OFCMSOptions options, NSData *innerContentType, NSData *content, NSArray <NSData *> * __nullable authenticatedAttributes, NSError **outError) DISPATCH_RETURNS_RETAINED OB_HIDDEN;
dispatch_data_t __nullable OFCMSCreateEnvelopedData(NSData *CEK, NSArray<NSData *> *recipientInfos, NSData *innerContentType, NSData *content, NSError **outError) DISPATCH_RETURNS_RETAINED /* OB_HIDDEN */;
dispatch_data_t __nullable OFCMSCreateAuthenticatedEnvelopedData(NSData *CEK, NSArray<NSData *> *recipientInfos, OFCMSOptions options, NSData *innerContentType, NSData *content, NSArray <NSData *> * __nullable authenticatedAttributes, NSError **outError) DISPATCH_RETURNS_RETAINED OB_HIDDEN;
dispatch_data_t OFCMSCreateSignedData(NSData *innerContentType, NSData * __nullable content, NSArray * __nullable certificates, NSArray * __nullable signatures) OB_HIDDEN;
dispatch_data_t OFCMSCreateMultipart(NSArray<NSData *> *parts) DISPATCH_RETURNS_RETAINED OB_HIDDEN;
dispatch_data_t OFCMSCreateAttributedContent(NSData *oid, NSData *content, NSArray<NSData *> *attributes) DISPATCH_RETURNS_RETAINED OB_HIDDEN;
NSData *OFCMSIdentifierAttribute(NSData *cid) OB_HIDDEN;
dispatch_data_t OFCMSWrapIdentifiedContent(enum OFCMSContentType ct, NSData *content, NSData *cid) DISPATCH_RETURNS_RETAINED OB_HIDDEN;  // A convenience on top of OFCMSCreateAttributedContent()

/* CMS content parsing */
int OFASN1ParseCMSEnvelopedData(NSData *buf, NSRange range, int *cmsVersion, NSMutableArray *outRecipients, enum OFCMSContentType *innerContentType, NSData NANNP algorithm, NSData NANNP innerContent) OB_HIDDEN;
int OFASN1ParseCMSAuthEnvelopedData(NSData *buf, NSRange range, int *cmsVersion, NSMutableArray *outRecipients, enum OFCMSContentType *innerContentType, NSData NANNP algorithm, NSData NANNP innerContent, NSArray NANNP outAuthAttrs, NSData NANNP mac) OB_HIDDEN;
int OFASN1ParseCMSSignedData(NSData *pkcs7, NSRange range, int *cmsVersion, NSMutableArray * __nullable outCertificates, NSMutableArray * __nullable outSignatures, enum OFCMSContentType *innerContentType, NSRange *innerContentObjectLocation) /* OB_HIDDEN */;
int OFASN1ParseCMSCompressedData(NSData *pkcs7, NSRange range, int *outSyntaxVersion, enum OFASN1Algorithm *outCompressionAlgorithm, enum OFCMSContentType *outContentType, NSRange *outContentRange) OB_HIDDEN;

int OFASN1ParseCMSMultipartData(NSData *pkcs7, NSRange range, int (NS_NOESCAPE ^cb)(enum OFCMSContentType innerContentType, NSRange innerContentRange)) OB_HIDDEN;
int OFASN1ParseCMSAttributedContent(NSData *pkcs7, NSRange range, enum OFCMSContentType *outContentType, NSRange *outContentRange, NSArray * __nullable __autoreleasing * __nullable outAttrs) OB_HIDDEN;
int OFASN1ParseCMSContent(NSData *buf, enum OFCMSContentType *innerContentType, NSRange * __nullable innerContentRange) /* OB_HIDDEN */;
NSError * __nullable OFCMSParseAttribute(NSData *buf, enum OFCMSAttribute *outAttr, unsigned int *outRelevantIndex, NSData NANNP outRelevantData) OB_HIDDEN;

/* Decryption helper. Most of the file format logic is in Swift, but the bit-wrangling lives in C. */
dispatch_data_t __nullable OFCMSDecryptContent(NSData *contentEncryptionAlgorithm, NSData *contentEncryptionKey, NSData *encryptedContent, NSArray * __nullable authenticatedAttributes, NSData * __nullable mac, NSError **outError)  DISPATCH_RETURNS_RETAINED OB_HIDDEN;
dispatch_data_t __nullable OFCMSDecompressContent(NSData *pkcs7, NSRange contentRange, enum OFASN1Algorithm compressionAlgorithm, NSError **outError) DISPATCH_RETURNS_RETAINED OB_HIDDEN;

NSData * __nullable OFCMSOIDFromContentType(enum OFCMSContentType ct) OB_HIDDEN;

static inline NSData *OFNSDataFromDispatchData(dispatch_data_t d) {
    // dispatch_data is toll-free-bridged to a concrete subclass of NSData, but Swift doesn't know that.
    return (NSData *)d;
}

static inline dispatch_data_t OFConcatDispatchData(dispatch_data_t left, dispatch_data_t right) DISPATCH_RETURNS_RETAINED {
    // For some reason, concat isn't exposed to Swift either
    return dispatch_data_create_concat(left, right);
}

#undef NANNP

NS_ASSUME_NONNULL_END

