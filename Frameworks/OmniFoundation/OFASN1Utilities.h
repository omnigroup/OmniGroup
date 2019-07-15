// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSecurityUtilities.h>

NS_ASSUME_NONNULL_BEGIN

@class NSData, NSMutableData, NSString;

/* These routines parse out interesting parts of some common DER/BER-encoded objects, which is especially useful on iOS where we can't rely on Security.framework to do it for us. */
/* The routines which return 'int' actually return an enum OFASN1ErrorCodes, but Swift can't import declarations involving forward-declared enums (and C++ can't include headers involving them), so we declare them all as int. The int can be passed to OFNSErrorFromASN1Error(), or compared against 0 (success). */
int OFASN1CertificateExtractFields(NSData *cert, NSData OB_NANP serialNumber, NSData OB_NANP issuer, NSData OB_NANP subject, NSArray OB_NANP validity, NSData OB_NANP subjectKeyInformation, void (NS_NOESCAPE ^ _Nullable extensions_cb)(NSData *oid, BOOL critical, NSData *value));
BOOL OFASN1EnumerateAVAsInName(NSData *rdnseq, void (NS_NOESCAPE ^callback)(NSData *a, NSData *v, unsigned ix, BOOL *stop));
BOOL OFASN1EnumerateAppStoreReceiptAttributes(NSData *payload, void (NS_NOESCAPE ^callback)(int attributeType, int attributeVersion, NSRange valueRange));

/* PKCS#7 parsing */
#if TARGET_OS_IPHONE
NSData * _Nullable OFPKCS7PluckContents(NSData *pkcs7);  /* (On OSX, use CMSDecoder) */
#endif

/* Converting between NSString and PKIX-profile DER */
NSString * _Nullable OFASN1UnDERString(NSData *derString);
NSData *OFASN1EnDERString(NSString *str);

/* OIDs */
NSString * _Nullable OFASN1DescribeOID(const unsigned char *bytes, size_t len); // Textual description for debugging
NSData * _Nullable OFASN1OIDFromString(NSString *s);  // Return DER-encoded OID from a dotted-integers string - not really intended for user-supplied strings

/* DER unsigned integers */
NSData *OFASN1EnDERInteger(uint64_t i);

/* DER dates */
// NSDate *OFASN1UnDERDate(NSData *derString);

/* Octet strings */
NSData * _Nullable OFASN1UnwrapOctetString(NSData *derValue, NSRange r);

/* This determines the algorithm and key size from an X.509 public key info structure */
extern enum OFKeyAlgorithm OFASN1KeyInfoGetAlgorithm(NSData *publicKeyInformation, unsigned int * _Nullable outKeySize, unsigned int * _Nullable outOtherSize, NSData OB_NANP outAlgorithmIdentifier);

/* Used for constructing DER-encoded objects */
void OFASN1AppendTagLength(NSMutableData *buffer, uint8_t tag, NSUInteger byteCount);
unsigned int OFASN1SizeOfTagLength(uint8_t tag, NSUInteger byteCount); // Number of bytes that OFASN1AppendTagLength() will produce
void OFASN1AppendTagIndefinite(NSMutableData *buffer, uint8_t tag);
void OFASN1AppendInteger(NSMutableData *buffer, uint64_t i);

/* Notes on the format strings used by OFASN1*():
    '!' allows the caller to override the tag+class value of the next object. (This is mostly useful for implicit context tagging.)
    ' ' ignored
    'd' Raw bytes, as an NSData
    'a' Raw bytes, as an array of NSDatas
    '*' Raw bytes, as a (size_t, const uint8_t *) pair of arguments
    '+' Similar to '*', but we read the object's length from its DER tag
    'p' A placeholder. The first arg is a size_t indicating the length of the data which will be inserted. The second arg is a (size_t *) into which we will store the offset at which the placeholder data should be inserted in the returned buffer to produce the final value.
    'u' An unsigned integer. We format it into stuffData[]. We can currently hold numbers up to 2^31-1; it's the caller's responsibility to make sure the number is in that range.
    Container types, whose length field depends on other pieces:
    '(...)' BER_TAG_SEQUENCE | FLAG_CONSTRUCTED
    '{...}' BER_TAG_SET | FLAG_CONSTRUCTED
    '[...]' BER_TAG_OCTET_STRING
    '<...>' BER_TAG_BIT_STRING [stuffs bytes]
*/

NSMutableData *OFASN1AppendStructure(NSMutableData * _Nullable buffer, const char *fmt, ...);
dispatch_data_t OFASN1MakeStructure(const char *fmt, ...);
void OFASN1AppendSet(NSMutableData *buffer, unsigned char tagByte, NSArray *derElements);

/* Numerical OID shorthand conveniences */
enum OFASN1Algorithm {
    OFASN1Algorithm_Unknown,

    /* The various AES modes */
    OFASN1Algorithm_aes128_cbc,
    OFASN1Algorithm_aes128_ccm,
    OFASN1Algorithm_aes128_gcm,
    OFASN1Algorithm_aes128_wrap,
    OFASN1Algorithm_aes192_cbc,
    OFASN1Algorithm_aes192_ccm,
    OFASN1Algorithm_aes192_gcm,
    OFASN1Algorithm_aes192_wrap,
    OFASN1Algorithm_aes256_cbc,
    OFASN1Algorithm_aes256_ccm,
    OFASN1Algorithm_aes256_gcm,
    OFASN1Algorithm_aes256_wrap,
    
    /* 3DES, which we only use for test vectors */
    OFASN1Algorithm_des_ede_cbc,
    
    /* Asymmetric algorithms and their parameters */
    OFASN1Algorithm_rsaEncryption_pkcs1_5,
    OFASN1Algorithm_rsaEncryption_OAEP,
    OFASN1Algorithm_mgf_1,
    OFASN1Algorithm_DSA,
    OFASN1Algorithm_ecPublicKey,
    OFASN1Algorithm_ecDH,
    OFASN1Algorithm_ECDH_standard_sha1kdf,
    OFASN1Algorithm_ECDH_standard_sha256kdf,
    OFASN1Algorithm_ECDH_standard_sha512kdf,
    OFASN1Algorithm_ECDH_cofactor_sha1kdf,
    OFASN1Algorithm_ECDH_cofactor_sha256kdf,
    OFASN1Algorithm_ECDH_cofactor_sha512kdf,

    /* The AlgorithmIdentifier structure is also used for a bunch of algorithms other than symmetric crypto; for convenience we parse them with the same function. */
    OFASN1Algorithm_zlibCompress,
    OFASN1Algorithm_PBKDF2,
    OFASN1Algorithm_PWRI_KEK,
    OFASN1Algorithm_prf_hmacWithSHA1,
    OFASN1Algorithm_prf_hmacWithSHA256,
    OFASN1Algorithm_prf_hmacWithSHA512,
};
enum OFCMSContentType {
    OFCMSContentType_Unknown,

    OFCMSContentType_data,
    OFCMSContentType_signedData,
    OFCMSContentType_envelopedData,
    OFCMSContentType_authenticatedData,
    OFCMSContentType_compressedData,
    OFCMSContentType_contentCollection,
    OFCMSContentType_contentWithAttributes,
    OFCMSContentType_authenticatedEnvelopedData,
    OFCMSContentType_XML,
};
enum OFCMSAttribute {
    OFCMSAttribute_Unknown,
    
    OFCMSAttribute_contentType,
    OFCMSAttribute_messageDigest,
    OFCMSAttribute_signingTime,
    OFCMSAttribute_contentIdentifier,
    OFCMSAttribute_binarySigningTime,  // RFC 6019
    OFCMSAttribute_omniHint,
};

/* Parsing helper for some Algorithm structures */
int OFASN1ParseAlgorithmIdentifier(NSData *buf, BOOL allowTrailing, enum OFASN1Algorithm *outAlg, NSRange * _Nullable outParameterRange);
int OFASN1ParseIdentifierAndParameter(NSData *buf, BOOL allowTrailing, NSRange *outOIDRange, NSRange * _Nullable outParameterRange);

NS_ASSUME_NONNULL_END

