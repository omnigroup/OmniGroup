// Copyright 2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// http://www.omnigroup.com/DeveloperResources/OmniSourceLicense.html.

#import <OmniFoundation/OmniFoundation.h>
#import <OmniFoundation/OFCDSAUtilities.h>

#include <libxml/tree.h>

/* Namespace */
#define XMLSignatureNamespace                 ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#")
#define XMLExclusiveCanonicalizationNamespace ((const xmlChar *)"http://www.w3.org/2001/10/xml-exc-c14n#")

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
#define XMLPKSignaturePKCS1_v1_5     ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#rsa-sha1")
#define XMLPKSignatureRSA_SHA256     ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#rsa-sha256")
#define XMLPKSignatureRSA_SHA384     ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#rsa-sha384")
#define XMLPKSignatureRSA_SHA512     ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#rsa-sha512")
#define XMLPKSignatureRSA_RIPEMD160  ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more/rsa-ripemd160") /* sic! */
#define XMLPKSignatureECDSA_SHA256   ((const xmlChar *)"http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256")
      /* See RFC4051 for more identifiers if needed */

extern NSString *OFXMLSignatureErrorDomain; /* This is the same as the OmniFoundation error domain */

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
- initWithElement:(xmlNode *)sig inDocument:(xmlDoc *)doc;
- (BOOL)processSignatureElement:(NSError **)err;
- (BOOL)processSignatureElement:(enum OFXMLSignatureOperation)op error:(NSError **)err;

/* API */
- (NSUInteger)countOfReferenceNodes;
- (BOOL)verifyReferenceAtIndex:(NSUInteger)nodeIndex toBuffer:(xmlOutputBuffer *)outBuf error:(NSError **)outError;

/* Convenience routines */
- (NSData *)verifiedReferenceAtIndex:(NSUInteger)nodeIndex error:(NSError **)outError;
- (BOOL)isLocalReferenceAtIndex:(NSUInteger)nodeIndex;

/* Subclass opportunuties */
- (id <OFCSSMDigestionContext, NSObject>)newVerificationContextForAlgorithm:(const xmlChar *)signatureAlgorithm method:(xmlNode *)signatureMethod keyInfo:(xmlNode *)keyInfo operation:(enum OFXMLSignatureOperation)op error:(NSError **)outError;
- (id <OFCSSMDigestionContext, NSObject>)newDigestContextForMethod:(xmlNode *)digestMethodNode error:(NSError **)outError;
- (NSData *)signatureForStoredValue:(NSData *)raw algorithm:(const xmlChar *)signatureAlgorithm method:(xmlNode *)signatureMethod error:(NSError **)outError;
- (NSData *)storedValueForSignature:(NSData *)signatureValue algorithm:(const xmlChar *)signatureAlgorithm method:(xmlNode *)signatureMethod error:(NSError **)outError;
- (OFCDSAModule *)cspForKey:(OFCSSMKey *)aKey;

- (OFCSSMKey *)getPublicKey:(xmlNode *)keyInfo algorithm:(CSSM_ALGORITHMS)algid error:(NSError **)outError;
- (OFCSSMKey *)getPrivateKey:(xmlNode *)keyInfo algorithm:(CSSM_ALGORITHMS)algid error:(NSError **)outError;
- (OFCSSMKey *)getHMACKey:(xmlNode *)keyInfo algorithm:(CSSM_ALGORITHMS)algid error:(NSError **)outError;
- (BOOL)writeReference:(NSString *)externalReference type:(NSString *)referenceType to:(xmlOutputBuffer *)stream error:(NSError **)outError;
- (BOOL)computeReferenceDigests:(NSError **)outError;

/* Private API, to be moved */
- (BOOL)_writeReference:(xmlNode *)reference to:(struct OFXMLSignatureVerifyContinuation *)stream error:(NSError **)outError;

- (BOOL)_prepareTransform:(const xmlChar *)algid :(xmlNode *)transformNode from:(struct OFXMLSignatureVerifyContinuation *)fromBuf error:(NSError **)outError;

@end

/* LibXML2 utility routines */
xmlNode *OFLibXMLChildNamed(const xmlNode *node, const char *nodename, const xmlChar *nsuri, unsigned int *count);
xmlNode **OFLibXMLChildrenNamed(const xmlNode *node, const char *nodename, const xmlChar *nsuri, unsigned int *count);
NSData *OFLibXMLNodeBase64Content(const xmlNode *node);

/* ASN.1 DER construction utility routines */
NSData *OFASN1IntegerFromBignum(NSData *base256Number);
NSMutableData *OFASN1CreateForTag(uint8_t tag, NSUInteger byteCount);
NSMutableData *OFASN1CreateForSequence(NSData *item, ...)  __attribute__((sentinel));
NSUInteger OFASN1UnwrapSequence(NSData *seq, NSError **outError);
NSData *OFASN1UnwrapUnsignedInteger(NSData *buf, NSUInteger *inOutWhere, NSError **outError);

/* Routines for extracting key information from an XML signature */
NSDictionary *OFXMLSigParseX509DataNode(xmlNode *x509Data);
NSArray *OFXMLSigFindX509Certificates(xmlNode *keyInfoNode, CFMutableArrayRef auxiliaryCertificates, NSMutableDictionary *errorInfo);
OFCSSMKey *OFXMLSigGetKeyFromRSAKeyValue(xmlNode *keyInfo, NSError **outError);
OFCSSMKey *OFXMLSigGetKeyFromDSAKeyValue(xmlNode *keyInfo, NSError **outError);

/* More more */

