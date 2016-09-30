// Copyright 2009-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXMLSignature.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFSecurityUtilities.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#if TARGET_OS_MAC
#import "OFASN1-Internal.h"
#endif

#include <libxml/tree.h>

#include <libxml/xmlerror.h>
#include <libxml/xmlmemory.h>
#include <libxml/xmlversion.h>

RCS_ID("$Id$");

#if TARGET_OS_OSX

#pragma mark Utility functions

static xmlNode *singleChildOrFail(const xmlNode *node, const char *nodename, const xmlChar *nsuri, NSError **outError)
{
    unsigned int count;
    xmlNode *nv = OFLibXMLChildNamed(node, nodename, nsuri, &count);
    if (count == 1)
        return nv;
    
    if (outError) {
        if (count < 1)
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"No <%s> element in <%s>", nodename, (char *)(node->name)] forKey:NSLocalizedDescriptionKey]];
        else
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Found %u <%s> elements in <%s>", count, nodename, (char *)(node->name)] forKey:NSLocalizedDescriptionKey]];
    }
    return NULL;
}

static xmlChar *getPropOrFail(xmlNode *element, const char *attrName, NSError **outError)
{
    /* Based on lessBrokenGetAttribute() in OFXMLSignature.m. This version implicitly looks for an attribute whose namespace is the same as the namespace of the element it's on, which is by far the most common case. */
    xmlAttrPtr attrNode;
    
    /* The element's namespace is the same as the namespace we're looking for, so check for an unprefixed attribute */
    attrNode = xmlHasProp(element, (const xmlChar *)attrName);
    
    if (!attrNode && element->ns) {
        /* Otherwise, check for an explicitly-namespaced attribute in the same namespace as the element */
        attrNode = xmlHasNsProp(element, (const xmlChar *)attrName, element->ns->href);
    }
    
    if (attrNode) {
        xmlChar *result = xmlNodeGetContent((xmlNode *)attrNode);
        if (result)
            return result;
    }
    
    if (outError) {
        *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"No %s attribute on <%s> element", attrName, (char *)(element->name)] forKey:NSLocalizedDescriptionKey]];
    }
    return nil;
}

/* Helper functions for elliptic-curve keys */
static NSData *getPublicKeyFromRFC4050KeyValue(xmlNode *keyvalue, int *log2_p, NSError **outError);
static NSData *getPublicKeyFromDSIG11KeyValue(xmlNode *keyvalue, int *log2_p, NSError **outError);

#if !OFXMLSigGetKeyAsCSSM

/* Terribler and terribler. There isn't a good way to import a key using the new Lion APIs (Apple's position appears to be "why would anyone ever want to create a SecKeyRef from key data?"). The best way I've found is to wrap it in a PEM-encoded OpenSSL-formatted blob. You can't use a plain DER blob, because then there's no way to specify the AlgorithmId member of the CSSM_KEY (yes, all the new APIs are just calling the old, documented-but-deprecated APIs under the hood; the easiest way to use them is to find the place they call the old APIs and work backwards to figure out how to get them to make the call you want.). */

static SecKeyRef copyKeyRefFromEncodedKey(SecExternalFormat keyFormat, const char *pemHeaderString, NSData *keyBytes, NSError **outError)
{
    SecExternalItemType itemType = kSecItemTypePublicKey;
    CFArrayRef importedItems = NULL;
    NSMutableDictionary *errInfo;
    SecKeyRef key;
    OSStatus err;
    
    /* You'd think that in order to create a SecKey from a CFData you'd use SecKeyCreateFromData(), but that only works for symmetric keys. For asymmetric keys, you have to use SecItemImport(). */
    
#if 0
    NSMutableData *pemBlob = [NSMutableData data];
    [pemBlob appendBytes:"-----BEGIN " length:11];
    //[pemBlob appendBytes:pemHeaderString length:strlen(pemHeaderString)];
    [pemBlob appendBytes:"PUBLIC KEY-----\r\n" length:17];
    [pemBlob appendData:[[keyBytes data] base64EncodedDataWithOptions:NSDataBase64Encoding64CharacterLineLength]];
    [pemBlob appendBytes:"\r\n-----END " length:11];
    //[pemBlob appendBytes:pemHeaderString length:strlen(pemHeaderString)];
    [pemBlob appendBytes:"PUBLIC KEY-----\r\n" length:17];
#endif
#if 0
    FILE *p = popen("openssl asn1parse -inform DER", "w");
    fwrite([keyBytes bytes], [keyBytes length], 1, p);
    pclose(p);
#endif
    
    SecItemImportExportKeyParameters keyParams = {
        .version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION,
        .flags = kSecKeyImportOnlyOne,
	.passphrase = NULL,
	.alertTitle = NULL,
	.alertPrompt = NULL,
	.accessRef = NULL,
        .keyUsage = (__bridge CFArrayRef)[NSArray arrayWithObject:(id)kSecAttrCanVerify],
	.keyAttributes = NULL, /* See below for rant */
    };
    
    err = SecItemImport((__bridge CFDataRef)keyBytes, NULL, &keyFormat, &itemType, 0, &keyParams, NULL, &importedItems);

    if (err != noErr) {
        errInfo = [NSMutableDictionary dictionary];
        [errInfo setObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:[NSDictionary dictionaryWithObject:@"SecItemImport" forKey:@"function"]]forKey:NSUnderlyingErrorKey];
        goto error;
    } else if (CFArrayGetCount(importedItems) == 1 &&
               (key = (SecKeyRef)CFArrayGetValueAtIndex(importedItems, 0)) != NULL &&
               CFGetTypeID(key) == SecKeyGetTypeID()) {
        // NSLog(@"SecItemImport \"%@\" (format=%d) -> %@", [keyBytes base64String], keyFormat, importedItems);
        CFRetain(key);
        CFRelease(importedItems);
        return key;
    } else {
        CFRelease(importedItems);
        errInfo = [NSMutableDictionary dictionary];
        goto error;
    }
    
error:
    if (outError) {
        [errInfo setIntValue:(int)keyFormat forKey:@"keyFormat"];
        [errInfo setIntValue:(int)itemType forKey:@"itemType"];
        [errInfo setObject:@"Could not use the key from <KeyInfo>" forKey:NSLocalizedDescriptionKey];
        *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationError userInfo:errInfo];
    }
    return NULL;
}

#endif 

static
NSData *derIntegerFromNodeChild(xmlNode *parent, const char *childName, NSError **outError)
{
    xmlNode *integerNode = singleChildOrFail(parent, childName, XMLSignatureNamespace, outError);
    if (!integerNode)
        return nil;
    return OFASN1IntegerFromBignum(OFLibXMLNodeBase64Content(integerNode));
}

/* This converts a decimal bignum to a binary (base256) bignum of a predetermined width. As it happens, this is only used for integers which end up in ECPoint values, whose width is determined by the key's generator (prime or polynomial), so we pass that width in here instead of trimming and then padding. */
static NSData *decimalToBN(const unsigned char *digits, unsigned bn_digits, NSError **outError)
{
    unsigned char *bn = malloc(bn_digits);
    bzero(bn, bn_digits);
    
    for (const unsigned char *dptr = digits; *dptr; dptr ++) {
        unsigned addin = (unsigned)((*dptr) - '0');
        
        for(unsigned i = 0; i < bn_digits; i++) {
            unsigned v = bn[ bn_digits - i - 1 ];
            v = ( v * 10 ) + addin;
            bn[ bn_digits - i - 1 ] = ( v & 0xFF );
            addin = v >> 8;
        }
        
        if (addin) {
            free(bn);
            if (outError) {
                *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Overflow converting %u-digit integer to %u-byte bignum", (unsigned)strlen((const char *)digits), bn_digits] forKey:NSLocalizedDescriptionKey]];
            }
            return nil;
        }
    }
    
    return [NSData dataWithBytesNoCopy:bn length:bn_digits freeWhenDone:YES];
}

static NSData *rawIntegerFromNodeAttribute(const xmlNode *pk, const char *nodename, const xmlChar *nsuri, unsigned bytecount, NSError **outError)
{
    xmlNode *n = singleChildOrFail(pk, nodename, nsuri, outError);
    if (!n)
        return nil;
    
    xmlChar *valueAttr = getPropOrFail(n, "Value", outError);
    if (!valueAttr)
        return nil;
    
    NSData *bn = decimalToBN(valueAttr, bytecount, outError);
    free(valueAttr);
    return bn;
}

#pragma mark Keys from key data

#define CLASS_CONSTRUCTED 0x20

#if !OFXMLSigGetKeyAsCSSM
#define rsaOidByteCount 11
static const unsigned char rsaOidBytes[rsaOidByteCount] = {
    /* tag = OBJECT IDENTIFIER */
    0x06,
    /* length = 9 */
    0x09,
    /* iso(1) member-body(2) us(840) rsadsi(113549) pkcs(1) 1 rsaEncryption(1) */
    0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01
};
#endif


#if OFXMLSigGetKeyAsCSSM
OFCSSMKey *OFXMLSigGetKeyFromRSAKeyValue(xmlNode *keyInfo, NSError **outError)
#else
SecKeyRef OFXMLSigCopyKeyFromRSAKeyValue(xmlNode *keyInfo, NSError **outError)
#endif
{
    xmlNode *kv = singleChildOrFail(keyInfo, "RSAKeyValue", XMLSignatureNamespace, outError);
    if (!kv)
        return NULL;
    
    xmlNode *modulus = singleChildOrFail(kv, "Modulus", XMLSignatureNamespace, outError);
    if (!modulus)
        return NULL;
    
    xmlNode *exponent = singleChildOrFail(kv, "Exponent", XMLSignatureNamespace, outError);
    if (!exponent)
        return NULL;
    
    NSData *modulusData = OFLibXMLNodeBase64Content(modulus);
    NSData *exponentData = OFLibXMLNodeBase64Content(exponent);
    
    /* The only key formats Apple's CSP supports are PKCS1 and X.509. PKCS1 is easier to deal with. */
    
    /* This is just a SEQUENCE containing two INTEGERs. Creating ASN.1 is much simpler than parsing it. */
    
    modulusData = OFASN1IntegerFromBignum(modulusData);
    exponentData = OFASN1IntegerFromBignum(exponentData);
    NSData *pkcs1Bytes = OFASN1CreateForSequence(modulusData, exponentData, nil);
    
#if OFXMLSigGetKeyAsCSSM
    OFCSSMKey *key = [[OFCSSMKey alloc] initWithCSP:nil];
    [key autorelease];
    
    CSSM_KEYHEADER keyHeader = { 0 };
    
    keyHeader.HeaderVersion = CSSM_KEYHEADER_VERSION;
    keyHeader.CspId = gGuidAppleCSP;
    keyHeader.BlobType = CSSM_KEYBLOB_RAW;
    keyHeader.Format = CSSM_KEYBLOB_RAW_FORMAT_PKCS1;
    keyHeader.AlgorithmId = CSSM_ALGID_RSA;
    keyHeader.KeyClass = CSSM_KEYCLASS_PUBLIC_KEY;
    keyHeader.KeyAttr = CSSM_KEYATTR_EXTRACTABLE;
    keyHeader.KeyUsage = CSSM_KEYUSE_ANY;
    
    [key setKeyHeader:&keyHeader data:pkcs1Bytes];
#else
    /* The documentation for SecItemImport() is terrible, but according to a comment in the published source code, fmt=OpenSSL+type=privkey is how you get it to import a PKCS#1-formatted key --- it just calls the same CDSA APIs we used to. (Thank god Apple is still publishing their sources for this stuff...) */
    /* Except apparently even that's not right? Only X509 is actually supported. So we wrap our (N,e) pair in a sequence containing the OID to produce an X509 SubjectPublicKeyInfo, like we do for the other key types. */
    
    /* The AlgorithmIdentifier: contains the rsaEncryption OID and a NULL */
    NSMutableData *algorithmId = OFASN1CreateForTag(BER_TAG_SEQUENCE | CLASS_CONSTRUCTED, rsaOidByteCount + 2);
    [algorithmId appendBytes:(void *)rsaOidBytes length:rsaOidByteCount];
    [algorithmId appendBytes:"\x05\x00" length:2]; // The NULL parameters object
    
    /* The wrapped Y-value, subjectPublicKey BIT STRING */
    NSMutableData *pubkeyBitString = OFASN1CreateForTag(BER_TAG_BIT_STRING, 1 + [pkcs1Bytes length]);
    [pubkeyBitString appendBytes:"" length:1]; // "Unused bits" count at beginning of BIT STRING (padding to byte boundary, none needed for us)
    [pubkeyBitString appendData:pkcs1Bytes];
    
    /* The whole shebang */
    NSMutableData *fullKey = OFASN1CreateForSequence(algorithmId, pubkeyBitString, nil);
    
    SecKeyRef key = copyKeyRefFromEncodedKey(kSecFormatOpenSSL, "RSA ", fullKey, outError);
#endif
    
    
    return key;
}

#define dssOidByteCount 9
static const unsigned char dssOidBytes[dssOidByteCount] = {
/* tag = OBJECT IDENTIFIER */
    0x06,
/* length = 7 */
    0x07,
/* iso(1) member-body(2) us(840) x9-57(10040) x9algorithm(4) 1 */
    0x2a, 0x86, 0x48, 0xce, 0x38, 0x04, 0x01
};

#if OFXMLSigGetKeyAsCSSM
OFCSSMKey *OFXMLSigGetKeyFromDSAKeyValue(xmlNode *keyInfo, NSError **outError)
#else
SecKeyRef OFXMLSigCopyKeyFromDSAKeyValue(xmlNode *keyInfo, NSError **outError)
#endif
{
    xmlNode *kv = singleChildOrFail(keyInfo, "DSAKeyValue", XMLSignatureNamespace, outError);
    if (!kv)
        return NULL;
    
    /* The only key formats Apple's CSP supports for DSA are FIPS186 and X.509. Apple says not to use FIPS186. */
    
    /*
     The X.509 format here is as described in RFC 2459 [7.3.3]. It boils down to:
        SEQUENCE {                
          SEQUENCE {             -- AlgorithmIdentifier [4.1.1.2]
            OBJECT IDENTIFIER,   -- specifying id-dsa
            SEQUENCE {           -- parameters
              p, q, g INTEGERs
            }
          }
          BIT STRING <           -- DSAPublicKey, encoded and wrapped in a BIT STRING
            y INTEGER
          >
        }
    */
    
    NSData *pData = derIntegerFromNodeChild(kv, "P", outError);
    if (!pData)
        return nil;
    NSData *qData = derIntegerFromNodeChild(kv, "Q", outError);
    if (!qData)
        return nil;
    NSData *gData = derIntegerFromNodeChild(kv, "G", outError);
    if (!gData)
        return nil;
    NSData *yData = derIntegerFromNodeChild(kv, "Y", outError);
    if (!yData)
        return nil;
    
    /* The parameters sequence tag */
    NSUInteger pqgLength = [pData length] + [qData length] + [gData length];
    NSData *paramSeq = OFASN1CreateForTag(BER_TAG_SEQUENCE | CLASS_CONSTRUCTED, pqgLength);
    
    /* The AlgorithmIdentifier */
    NSMutableData *algorithmId = OFASN1CreateForTag(BER_TAG_SEQUENCE | CLASS_CONSTRUCTED, dssOidByteCount + [paramSeq length] + pqgLength);
    [algorithmId appendBytes:dssOidBytes length:dssOidByteCount];
    [algorithmId appendData:paramSeq];
    [algorithmId appendData:pData];
    [algorithmId appendData:qData];
    [algorithmId appendData:gData];
    
    /* The wrapped Y-value, subjectPublicKey BIT STRING */
    NSMutableData *pubKey = OFASN1CreateForTag(BER_TAG_BIT_STRING, 1 + [yData length]);
    [pubKey appendBytes:"" length:1]; // "Unused bits" count at beginning of BIT STRING (padding to byte boundary, none needed for us)
    [pubKey appendData:yData];
    
    /* The whole shebang */
    NSMutableData *fullKey = OFASN1CreateForTag(BER_TAG_SEQUENCE | CLASS_CONSTRUCTED, [algorithmId length] + [pubKey length]);
    [fullKey appendData:algorithmId];
    [fullKey appendData:pubKey];
    
#if OFXMLSigGetKeyAsCSSM
    OFCSSMKey *key = [[OFCSSMKey alloc] initWithCSP:nil];
    [key autorelease];
    
    CSSM_KEYHEADER keyHeader = { 0 };
    
    keyHeader.HeaderVersion = CSSM_KEYHEADER_VERSION;
    keyHeader.CspId = gGuidAppleCSP;
    keyHeader.BlobType = CSSM_KEYBLOB_RAW;
    keyHeader.Format = CSSM_KEYBLOB_RAW_FORMAT_X509;
    keyHeader.AlgorithmId = CSSM_ALGID_DSA;
    keyHeader.KeyClass = CSSM_KEYCLASS_PUBLIC_KEY;
    keyHeader.KeyAttr = CSSM_KEYATTR_EXTRACTABLE;
    keyHeader.KeyUsage = CSSM_KEYUSE_ANY;
    
    [key setKeyHeader:&keyHeader data:fullKey];
    [key setGroupOrder:160]; /* DSA has a fixed group size of 160 bits */
#else
    SecKeyRef key = copyKeyRefFromEncodedKey(kSecFormatOpenSSL, "DSA ", fullKey, outError);
#endif
    
    
    return key;
}

#if OFXMLSigGetKeyAsCSSM
OFCSSMKey *OFXMLSigGetKeyFromEllipticKeyValue(xmlNode *keyvalue, int *outOrder, NSError **outError)
#else
SecKeyRef OFXMLSigCopyKeyFromEllipticKeyValue(xmlNode *keyvalue, int *outOrder, NSError **outError)
#endif
{
    NSData *derv = nil;
    unsigned int count;
    xmlNode *nv;
    
    nv = OFLibXMLChildNamed(keyvalue, "ECDSAKeyValue", XMLSignatureMoreNamespace, &count);
    if (count == 1) {
        derv = getPublicKeyFromRFC4050KeyValue(nv, outOrder, outError);
        if (!derv)
            return NULL;
    } else if (count == 0) {
        nv = OFLibXMLChildNamed(keyvalue, "ECKeyValue", XMLSignature11Namespace, &count);
        if (count == 1) {
            derv = getPublicKeyFromDSIG11KeyValue(nv, outOrder, outError);
            if (!derv)
                return NULL;
        }
    }
    
    if (!derv) {
        if (outError)
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationError userInfo:[NSDictionary dictionaryWithObject:@"No <ECKeyValue> or <ECDSAKeyValue>" forKey:NSLocalizedDescriptionKey]];
        return NULL;
    }

#if OFXMLSigGetKeyAsCSSM
    OFCSSMKey *key = [[OFCSSMKey alloc] initWithCSP:nil];
    [key autorelease];
    
    CSSM_KEYHEADER keyHeader = { 0 };
    
    keyHeader.HeaderVersion = CSSM_KEYHEADER_VERSION;
    keyHeader.CspId = gGuidAppleCSP;
    keyHeader.BlobType = CSSM_KEYBLOB_RAW;
    keyHeader.Format = CSSM_KEYBLOB_RAW_FORMAT_X509;
    keyHeader.AlgorithmId = CSSM_ALGID_ECDSA;
    keyHeader.KeyClass = CSSM_KEYCLASS_PUBLIC_KEY;
    keyHeader.KeyAttr = CSSM_KEYATTR_EXTRACTABLE;
    keyHeader.KeyUsage = CSSM_KEYUSE_ANY;
    
    [key setKeyHeader:&keyHeader data:derv];
    if (*outOrder > 0)
        [key setGroupOrder:*outOrder];
#else
    SecKeyRef key = copyKeyRefFromEncodedKey(kSecFormatOpenSSL, "ECDSA ", derv, outError);
#endif
    
    return key;
}

static NSData *getNamedCurve(const xmlChar *curveName, int *log2_p_out, NSError **outError)
{
    if (strncmp((const char *)curveName, "urn:oid:", 8) == 0) {
        const xmlChar *curveOIDString = curveName + 8;
        for(const struct OFNamedCurveInfo *cursor = _OFEllipticCurveInfoTable; cursor->urn; cursor++) {
            if (xmlStrcmp(curveOIDString, (xmlChar *)(cursor->urn)) == 0) {
                *log2_p_out = cursor->generatorSize;
                return [NSData dataWithBytesNoCopy:(void *)(cursor->derOid) length:(cursor->derOidLength) freeWhenDone:NO];
            }
        }
    }

    if (outError)
        *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFKeyNotAvailable userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Unknown NamedCurve \"%s\"", curveName] forKey:NSLocalizedDescriptionKey]];
    return nil;
}

static NSData *composeECPublicKeyInfo(NSData *curveName, NSData *pubkeyBitString)
{
    /*
     The X.509 format here is as described in RFC 3279 and RFC 5480. It boils down to:
     
     SEQUENCE {                
       SEQUENCE {             -- AlgorithmIdentifier (rfc2459 [4.1.1.2], rfc3279 [2.3.5])
         OBJECT IDENTIFIER,   -- specifying id-ecPublicKey
         OBJECT IDENTIFIER    -- specifying the named curve
       }
       BIT STRING <           -- ECPoint, encoded and wrapped in a BIT STRING
         0x04 || x || y       -- uncompressed point as described in X9.62 or SEC1 [2.3.3]
       >
     }
    */
    
#define ecPublicKeyOidByteCount 9
    static const unsigned char ecPublicKeyOidBytes[ecPublicKeyOidByteCount] = {
        /* tag = OBJECT IDENTIFIER */
        0x06,
        /* length = 7 */
        0x07,
        /* iso(1) member-body(2) us(840) ansi-x9-62(10045) keyType(2) ecPublicKey(1) */
        0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01
    };
    
    /* The AlgorithmIdentifier */
    NSData *algorithmId = OFASN1CreateForSequence([NSData dataWithBytesNoCopy:(void *)ecPublicKeyOidBytes length:ecPublicKeyOidByteCount freeWhenDone:NO], curveName, nil);
    
    /* The whole shebang */
    NSMutableData *fullKey = OFASN1CreateForSequence(algorithmId, pubkeyBitString, nil);
    
#if 0
    {
        FILE *ec = popen("openssl ec -inform DER -pubin -noout -text", "w");
        //FILE *ec = popen("openssl asn1parse -inform DER", "w");
        fwrite([fullKey bytes], 1, [fullKey length], ec);
        pclose(ec);
    }
#endif
    
    return fullKey;
}

/* The RFC4050 syntax for ECDSA keys is not great. See, for example, <http://lists.w3.org/Archives/Public/public-xmlsec/2008Nov/0018.html>. However, we have it here so we can test our interoperability with other peoples' test vectors. */
static NSData *getPublicKeyFromRFC4050KeyValue(xmlNode *keyvalue, int *log2_p, NSError **outError)
{
    xmlNode *parameters = singleChildOrFail(keyvalue, "DomainParameters", XMLSignatureMoreNamespace, outError);
    if (!parameters)
        return nil;
    
    /* The <DomainParameters> has one of either <ExplicitParams> or <NamedCurve>. Our test vectors are all NamedCurve, so that's the only element we support. */
    xmlNode *ncurve = singleChildOrFail(parameters, "NamedCurve", XMLSignatureMoreNamespace, outError);
    if (!ncurve)
        return nil;
    
    /* it also has <PublicKey> containing the actual point coordinates */
    xmlNode *pk = singleChildOrFail(keyvalue, "PublicKey", XMLSignatureMoreNamespace, outError);
    if (!pk)
        return nil;
    
    xmlChar *urn = getPropOrFail(ncurve, "URN", outError);
    if (!urn)
        return nil;
    NSData *curveName = getNamedCurve(urn, log2_p, outError);
    xmlFree(urn);
    if (!curveName)
        return nil;
    
    unsigned int log256_p = ( *log2_p + 7 ) / 8;
    
    /* extract the X- and Y-values. */
    NSData *xData = rawIntegerFromNodeAttribute(pk, "X", XMLSignatureMoreNamespace, log256_p, outError);
    if (!xData)
        return nil;
    NSData *yData = rawIntegerFromNodeAttribute(pk, "Y", XMLSignatureMoreNamespace, log256_p, outError);
    if (!yData)
        return nil;
    
    /* The wrapped BIT STRING */
    /* Concatenate X and Y into an uncompressed ECPoint */
    NSMutableData *pubKey = OFASN1CreateForTag(BER_TAG_BIT_STRING, 2 + [xData length] + [yData length]);
    // 0x00: "Unused bits" count at beginning of BIT STRING (padding to byte boundary, none needed for us)
    // 0x04: Uncompressed point indicator at beginning of wrapped ECPoint
    [pubKey appendBytes:"\x00\x04" length:2];
    [pubKey appendData:xData];
    [pubKey appendData:yData];
    
    NSData *result = composeECPublicKeyInfo(curveName, pubKey);
    
    
    return result;
}

/* The DSIG-1.1 syntax for ECDSA keys is a bit better. */
static NSData *getPublicKeyFromDSIG11KeyValue(xmlNode *keyvalue, int *log2_p, NSError **outError)
{
    /* The <ECKeyValue> has one of either <ECParameters> or <NamedCurve>. Our test vectors are all NamedCurve, so that's the only element we support. */
    xmlNode *ncurve = singleChildOrFail(keyvalue, "NamedCurve", XMLSignature11Namespace, outError);
    if (!ncurve)
        return nil;
    
    /* it also has <PublicKey> containing the actual point coordinates, conveniently pre-concatenated in the way P1363 describes */
    xmlNode *pk = singleChildOrFail(keyvalue, "PublicKey", XMLSignature11Namespace, outError);
    if (!pk)
        return nil;
    
    xmlChar *urn = getPropOrFail(ncurve, "URI", outError);
    if (!urn)
        return nil;
    NSData *curveName = getNamedCurve(urn, log2_p, outError);
    xmlFree(urn);
    if (!curveName)
        return nil;
    
    NSData *ecPoint = OFLibXMLNodeBase64Content(pk);
    
    OBASSERT([ecPoint length] == 1 + 2*(unsigned int)( ( *log2_p + 7 ) / 8 )); /* Only true for uncompressed points, but we're not required to support compressed points */
    
    /* The wrapped BIT STRING */
    /* Concatenate X and Y into an uncompressed ECPoint */
    NSMutableData *pubKey = OFASN1CreateForTag(BER_TAG_BIT_STRING, 1 + [ecPoint length]);
    // 0x00: "Unused bits" count at beginning of BIT STRING (padding to byte boundary, none needed for us)
    [pubKey appendBytes:"" length:1];
    [pubKey appendData:ecPoint];
    
    NSData *result = composeECPublicKeyInfo(curveName, pubKey);
    
    
    return result;
}

#endif

#if !TARGET_OS_IPHONE

static void appendPEMBlob(NSMutableData *pemBlob, const char *type, NSData *der)
{
    size_t typelen = strlen(type);
    [pemBlob appendBytes:"-----BEGIN " length:11];
    [pemBlob appendBytes:type length:typelen];
    [pemBlob appendBytes:"-----\r\n" length:7];
    [pemBlob appendData:[der base64EncodedDataWithOptions:NSDataBase64Encoding64CharacterLineLength]];
    [pemBlob appendBytes:"\r\n-----END " length:11];
    [pemBlob appendBytes:type length:typelen];
    [pemBlob appendBytes:"-----\r\n" length:7];
}

SecKeyRef OFSecCopyPrivateKeyFromPKCS1Data(NSData *keyBytes)
{
    SecExternalFormat ioFormat = kSecFormatPEMSequence;
    SecExternalItemType ioType = kSecItemTypeUnknown;
    CFArrayRef results = NULL;
    
    NSMutableData *pemBlob = [NSMutableData data];
    appendPEMBlob(pemBlob, "RSA PRIVATE KEY", keyBytes);
    
    OSStatus err = SecItemImport((__bridge CFDataRef)pemBlob, NULL, &ioFormat, &ioType, 0, NULL, NULL, &results);
    if (err || !results) {
        return nil;
    }
    
    SecKeyRef kr = (SecKeyRef)CFRetain(CFArrayGetValueAtIndex(results, 0));
    CFRelease(results);
    return kr;
}

#endif

#if TARGET_OS_OSX

#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#else
// Annoyingly, Apple's GCC doesn't understand "GCC diagnostic push". This code is at the end of the file to minimize the amount of other code unintentionally covered by the pragma here.
//#pragma GCC diagnostic push
#pragma GCC diagnostic warning "-Wdeprecated-declarations"
#endif

extern OSStatus
SecKeyCreateWithCSSMKey(const CSSM_KEY *cssmKey, SecKeyRef *keyRef);

SecKeyRef OFXMLSigCopyKeyFromHMACKey(NSString *hmacAlg, const void *bytes, unsigned int blen, NSError **outError)
{
    CSSM_ALGORITHMS keytype;
    
    if ([hmacAlg isEqualToString: (id)kSecDigestHMACSHA1]) {
        keytype = CSSM_ALGID_SHA1HMAC;
    } else if ([hmacAlg isEqualToString: (id)kSecDigestHMACMD5]) {
        keytype = CSSM_ALGID_MD5HMAC;
    } else {
        if (outError) {
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain
                                            code:OFKeyNotAvailable
                                        userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"MacOSX does not support algid <%@>", hmacAlg] forKey:NSLocalizedFailureReasonErrorKey]];
        }
        return NULL;
    }
    
    void *keyBuffer = malloc(blen);
    memcpy(keyBuffer, bytes, blen);
    
    CSSM_KEY key = {
        .KeyHeader = {
            .HeaderVersion = CSSM_KEYHEADER_VERSION,
            .CspId = gGuidAppleCSP,
            .BlobType = CSSM_KEYBLOB_RAW,
            .Format = CSSM_KEYBLOB_RAW_FORMAT_OCTET_STRING,
            .AlgorithmId = keytype,
            .KeyClass = CSSM_KEYCLASS_SESSION_KEY,
            .KeyAttr = CSSM_KEYATTR_SENSITIVE,
            .KeyUsage = CSSM_KEYUSE_VERIFY | CSSM_KEYUSE_SIGN,
            .LogicalKeySizeInBits = 8 * blen,
            .WrapAlgorithmId = CSSM_ALGID_NONE
        },
        .KeyData = {
            .Length = blen,
            .Data = keyBuffer  /* CSSM_FreeKey() will free this when the key is deallocated */
        }
    };
    
    SecKeyRef result = NULL;
    OSStatus err = SecKeyCreateWithCSSMKey(&key, &result);
    
    if (err != noErr || result == NULL) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:err
                                        userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Cannot create HMAC key <%@>", hmacAlg] forKey:NSLocalizedFailureReasonErrorKey]];
        }
        return NULL;
    } else {
        return result;
    }
}

#endif
