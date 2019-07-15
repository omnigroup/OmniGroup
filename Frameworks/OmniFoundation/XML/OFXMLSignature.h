// Copyright 2009-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFDigestUtilities.h>
#import <OmniFoundation/OFCDSAUtilities.h>
#import <OmniBase/objc.h>
#if OF_ENABLE_CDSA
#import <Security/cssmtype.h>
#endif

#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7
#define OFXMLSigGetKeyAsCSSM 0
#else
#define OFXMLSigGetKeyAsCSSM 1
#endif

#include <libxml/tree.h>

@class NSArray, NSMutableArray;
@class NSData, NSMutableData;

/* Namespace */
#define XMLSignatureNamespace                 ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#")
#define XMLExclusiveCanonicalizationNamespace ((const xmlChar *)"http://www.w3.org/2001/10/xml-exc-c14n#")
#define XMLSignature11Namespace               ((const xmlChar *)"http://www.w3.org/2009/xmldsig11#")
#define XMLSignatureMoreNamespace             ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#") /* RFC 4050 */

/* Non-cryptographic transform identifiers */
#define XMLEncodingBase64            ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#base64")
#define XMLTransformXPath            ((const xmlChar *)"http://www.w3.org/TR/1999/REC-xpath-19991116")
#define XMLTransformXSLT             ((const xmlChar *)"http://www.w3.org/TR/1999/REC-xslt-19991116")
#define XMLTransformEnveloped        ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#enveloped-signature")
#define XMLTransformXPathFilter      ((const xmlChar *)"http://www.w3.org/2002/06/xmldsig-filter2")
#define XMLTransformXPointer         ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more/xptr") /* sic! */

/* Cryptographic algorithm identifiers */
/*    Digest methods */
#define XMLDigestSHA1                ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#sha1")
#define XMLDigestSHA224              ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#sha224")
#define XMLDigestSHA256              ((const xmlChar *)"http://www.w3.org/2001/04/xmlenc#sha256")
#define XMLDigestSHA384              ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#sha384")
#define XMLDigestSHA512              ((const xmlChar *)"http://www.w3.org/2001/04/xmlenc#sha512")
#define XMLDigestMD5                 ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#md5")
/*    Secret-key and public-key signature algorithms */
#define XMLSKSignatureHMAC_SHA1      ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#hmac-sha1")
#define XMLSKSignatureHMAC_SHA256    ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#hmac-sha256")
#define XMLSKSignatureHMAC_SHA384    ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#hmac-sha384")
#define XMLSKSignatureHMAC_SHA512    ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#hmac-sha512")
#define XMLSKSignatureHMAC_MD5       ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#hmac-md5")
#define XMLSKSignatureHMAC_RIPEMD160 ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#hmac-ripemd160")
#define XMLPKSignatureDSS            ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#dsa-sha1")
#define XMLPKSignatureDSS_SHA256     ((const xmlChar *)"http://www.w3.org/2009/xmldsig11#dsa-sha256") /* not implemented */
#define XMLPKSignaturePKCS1_v1_5     ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#rsa-sha1")
#define XMLPKSignatureRSA_SHA256     ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#rsa-sha256")
#define XMLPKSignatureRSA_SHA384     ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#rsa-sha384")
#define XMLPKSignatureRSA_SHA512     ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#rsa-sha512")
#define XMLPKSignatureRSA_RIPEMD160  ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more/rsa-ripemd160") /* sic! */
#define XMLPKSignatureECDSA_SHA1     ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha1")
#define XMLPKSignatureECDSA_SHA256   ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256")
#define XMLPKSignatureECDSA_SHA512   ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha512")
      /* See RFC4051 for more identifiers if needed */

#define OFXMLSignatureErrorDomain (OFErrorDomain) /* This is the same as the OmniFoundation error domain */

enum OFXMLSignatureOperation {
    OFXMLSignature_Sign = 1,
    OFXMLSignature_Verify = 2
};

@interface OFXMLSignature : OFObject
{
    // Pointers to the original libxml tree provided to init.
    // We don't own these and we don't free them when we're done.
    xmlNode *originalSignatureElt;
    xmlDoc *owningDocument;
    
    // Canonicalized, verified copy of the <SignedInfo> element from the above.
    // We own this doc.
    xmlDoc *signedInformation;
    xmlNode **referenceNodes;
    unsigned int referenceNodeCount;
    
    BOOL keepFailedSignatures;
}

/* Object lifecycle */
+ (NSArray *)signaturesInTree:(xmlDoc *)libxmlDocument;
- initWithElement:(xmlNode *)sig inDocument:(xmlDoc *)doc NS_DESIGNATED_INITIALIZER ;
- (BOOL)processSignatureElement:(NSError **)err;
- (BOOL)processSignatureElement:(enum OFXMLSignatureOperation)op error:(NSError **)err;

/* API */
- (NSUInteger)countOfReferenceNodes;
- (BOOL)verifyReferenceAtIndex:(NSUInteger)nodeIndex toBuffer:(xmlOutputBuffer *)outBuf error:(NSError **)outError;

/* Convenience routines */
- (NSData *)verifiedReferenceAtIndex:(NSUInteger)nodeIndex error:(NSError **)outError;
- (BOOL)isLocalReferenceAtIndex:(NSUInteger)nodeIndex;

/* Subclass opportunities */
- (id <OFDigestionContext, NSObject>)newVerificationContextForMethod:(xmlNode *)signatureMethod keyInfo:(xmlNode *)keyInfo operation:(enum OFXMLSignatureOperation)op error:(NSError **)outError NS_RETURNS_RETAINED;
- (id <OFDigestionContext, NSObject>)newDigestContextForMethod:(xmlNode *)digestMethodNode error:(NSError **)outError;

/* The default implementation of -newVerificationContextForMethod:... calls these methods to get a key */
- (SecKeyRef)copySecKeyForMethod:(xmlNode *)signatureMethod keyInfo:(xmlNode *)keyInfo operation:(enum OFXMLSignatureOperation)op error:(NSError **)outError CF_RETURNS_RETAINED;
#if OF_ENABLE_CDSA
/* -newVerificationContextForAlgorithm:method:keyInfo:operation:error: will call this if the CDSA APIs are available */
- (OFCSSMKey *)getCSSMKeyForMethod:(xmlNode *)signatureMethod keyInfo:(xmlNode *)keyInfo operation:(enum OFXMLSignatureOperation)op error:(NSError **)outError;
#endif /* OF_ENABLE_CDSA */

- (BOOL)writeReference:(NSString *)externalReference type:(NSString *)referenceType to:(xmlOutputBuffer *)stream error:(NSError **)outError;
- (BOOL)computeReferenceDigests:(NSError **)outError;

@end

/* LibXML2 utility routines */
xmlNode *OFLibXMLChildNamed(const xmlNode *node, const char *nodename, const xmlChar *nsuri, unsigned int *count);
xmlNode **OFLibXMLChildrenNamed(const xmlNode *node, const char *nodename, const xmlChar *nsuri, unsigned int *count);
NSData *OFLibXMLNodeBase64Content(const xmlNode *node);

/* ASN.1 DER construction utility routines */
NSData *OFASN1IntegerFromBignum(NSData *base256Number);
NSMutableData *OFASN1CreateForTag(uint8_t tag, NSUInteger byteCount) NS_RETURNS_RETAINED;
NSMutableData *OFASN1CreateForSequence(NSData *item, ...)  __attribute__((sentinel)) NS_RETURNS_RETAINED;
NSUInteger OFASN1UnwrapSequence(NSData *seq, NSError **outError);
NSData *OFASN1UnwrapUnsignedInteger(NSData *buf, NSUInteger *inOutWhere, NSError **outError);

/* Routines for extracting key information from an XML signature */
NSDictionary *OFXMLSigParseX509DataNode(xmlNode *x509Data);
NSArray *OFXMLSigFindX509Certificates(xmlNode *keyInfoNode, CFMutableArrayRef auxiliaryCertificates, NSMutableDictionary *errorInfo);
#if OFXMLSigGetKeyAsCSSM
OFCSSMKey *OFXMLSigGetKeyFromRSAKeyValue(xmlNode *keyInfo, NSError **outError);
OFCSSMKey *OFXMLSigGetKeyFromDSAKeyValue(xmlNode *keyInfo, NSError **outError);
OFCSSMKey *OFXMLSigGetKeyFromEllipticKeyValue(xmlNode *keyvalue, int *outOrder, NSError **outError);
#else
SecKeyRef OFXMLSigCopyKeyFromRSAKeyValue(xmlNode *keyInfo, NSError **outError) CF_RETURNS_RETAINED;
SecKeyRef OFXMLSigCopyKeyFromDSAKeyValue(xmlNode *keyInfo, NSError **outError) CF_RETURNS_RETAINED;
SecKeyRef OFXMLSigCopyKeyFromEllipticKeyValue(xmlNode *keyvalue, int *outOrder, NSError **outError) CF_RETURNS_RETAINED;
SecKeyRef OFXMLSigCopyKeyFromHMACKey(NSString *hmacAlg, const void *bytes, unsigned int blen, NSError **outError) CF_RETURNS_RETAINED;
#endif

#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
BOOL OFXMLSigGetKeyAttributes(NSMutableDictionary *keyusage, xmlNode *signatureMethod, enum OFXMLSignatureOperation op);
#endif
#if OF_ENABLE_CDSA
CSSM_ALGORITHMS OFXMLCSSMKeyTypeForAlgorithm(xmlNode *signatureMethod);
#endif

/* More more */

NSString *OFSecItemDescription(CFTypeRef t);
NSArray *OFReadCertificatesFromFile(NSString *path, SecExternalFormat inputFormat_, NSError **outError);



