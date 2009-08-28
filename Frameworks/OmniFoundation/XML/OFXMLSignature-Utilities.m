// Copyright 2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// http://www.omnigroup.com/DeveloperResources/OmniSourceLicense.html.

#import "OFXMLSignature.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFCDSAUtilities.h>

#include <libxml/tree.h>

#include <libxml/c14n.h>
#include <libxml/xmlIO.h>
#include <libxml/xmlerror.h>
#include <libxml/xmlmemory.h>
#include <libxml/xmlversion.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#include <libxml/xpointer.h>

RCS_ID("$Id$");

#pragma mark ASN.1 utility routines

/* ASN.1 DER construction utility routines */

/*" Returns an ASN.1 DER INTEGER corresponding to an (unsigned) arbitrary-precision integer. "*/
NSData *OFASN1IntegerFromBignum(NSData *base256Number)
{
    NSUInteger firstDigit = [base256Number indexOfFirstNonZeroByte];
    if (firstDigit == NSNotFound) {
        /* Hardcoded zero representation, since it's a special case */
        static const uint8_t derZero[3] = {
            0x02,  /* Tag: INTEGER */
            0x01,  /* Length: 1 byte */
            0x00   /* Value: Zero */
        };
        return [NSData dataWithBytesNoCopy:(void *)derZero length:3 freeWhenDone:NO];
    }
    NSUInteger bytecount = [base256Number length] - firstDigit;
    NSMutableData *buf;
    if (((unsigned char *)[base256Number bytes])[firstDigit] & 0x80) {
        /* Insert a zero byte, since ASN.1 integers are signed */
        buf = OFASN1CreateForTag(0x02, bytecount + 1);
        [buf appendBytes:"" length:1];
    } else {
        buf = OFASN1CreateForTag(0x02, bytecount);
    }
    [buf autorelease];
    
    if (firstDigit == 0)
        [buf appendData:base256Number];
    else
        [buf appendData:[base256Number subdataWithRange:(NSRange){ firstDigit, bytecount }]];
    
    return buf;
}

/*" Formats the tag byte and length field of an ASN.1 item. "*/
NSMutableData *OFASN1CreateForTag(uint8_t tag, NSUInteger byteCount)
{
    uint8_t buf[ 2 + sizeof(NSUInteger) ];
    unsigned int bufUsed;
    
    buf[0] = tag;
    bufUsed = 1;
    
    
    if (byteCount < 128) {
        /* Short lengths have a 1-byte direct representation */
        buf[1] = (uint8_t)byteCount;
        bufUsed = 2;
    } else {
        /* Longer lengths have a count-and-value representation */
        unsigned int n;
        uint8_t bytebuf[ sizeof(NSUInteger) ];
        for(n = 0; n < sizeof(NSUInteger); n++) {
            bytebuf[n] = ( byteCount & 0xFF );
            byteCount >>= 8;
        }
        while(bytebuf[n-1] == 0)
            n--;
        buf[bufUsed++] = 0x80 | n;
        while (n--) {
            buf[bufUsed++] = bytebuf[n];
        };
    }
    
    return [[NSMutableData alloc] initWithBytes:buf length:bufUsed];
}

/*" Wraps a set of ASN.1 items in a SEQUENCE. "*/
NSMutableData *OFASN1CreateForSequence(NSData *item, ...)
{
    NSUInteger totalLength = 0;
    
    if (item != nil) {
        va_list items;
        va_start(items, item);
        
        totalLength = [item length];
        NSData *nextItem;
        while( (nextItem = va_arg(items, NSData *)) != nil ) {
            totalLength += [nextItem length];
        }
        
        va_end(items);
    }
    
    NSMutableData *header = OFASN1CreateForTag(0x10 | 0x20, totalLength);
    
    if (item != nil) {
        va_list items;
        va_start(items, item);
        
        [header appendData:item];
        NSData *nextItem;
        while( (nextItem = va_arg(items, NSData *)) != nil ) {
            [header appendData:nextItem];
        }
        
        va_end(items);
    }
    
    return header;
}

static BOOL asnParseFailure(NSError **err, NSString *fmt, ...)
{
    if (!err)
        return NO;
    
    va_list varg;
    va_start(varg, fmt);
    NSString *descr = [[NSString alloc] initWithFormat:fmt arguments:varg];
    va_end(varg);
    
    NSString *keys[3];
    id values[3];
    NSUInteger keyCount;
    
    keys[0] = NSLocalizedDescriptionKey;
    values[0] = @"ASN.1 Parse Failure";
    
    keys[1] = NSLocalizedFailureReasonErrorKey;
    values[1] = descr;
    
    keyCount = 2;
    
    NSDictionary *uinfo = [NSDictionary dictionaryWithObjects:values forKeys:keys count:keyCount];
    [descr release];
    
    *err = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFASN1Error userInfo:uinfo];
    
    /* This return value is pointless, since this function is only called in error situations, but clang-analyze requires us to return something */
    return NO;
}

#define badvalue (~(NSUInteger)0)
static NSUInteger parseLengthField(NSData *within, NSUInteger *inOutWhere, NSError **outError)
{
    NSUInteger where = *inOutWhere;
    NSUInteger byteCount = [within length];
    
    if (byteCount < 1 || byteCount-1 < where) {
        asnParseFailure(outError, @"Truncated");
        return badvalue;
    }
    
    const UInt8 *bytes = [within bytes];
    UInt8 first = bytes[where ++];
    NSUInteger result;
    if ((first & 0x80) == 0) {
        result = first;
    } else {
        unsigned lengthLength = ( bytes[1] & 0x7F );
        if (lengthLength < 1 || lengthLength > sizeof(NSUInteger)) {
            asnParseFailure(outError, @"Unexpected length-of-length field: 0x%02X", bytes[1]);
            return badvalue;
        }
        if (lengthLength > byteCount-where) {
            asnParseFailure(outError, @"Truncated value (in length-of-length)");
            return badvalue;
        }
        result = 0;
        for(;;) {
            result |= bytes[where++];
            lengthLength --;
            if (!lengthLength) break;
            result <<= 8;
        }
    }
    
    if (byteCount-where < result) {
        asnParseFailure(outError, @"Truncated value (length exceeds buffer)");
        return badvalue;
    }
    
    *inOutWhere = where;
    return result;
}

/*" Given a BER-encoded SEQUENCE, returns the index at which its content starts, or ~0 in the case of an error. "*/
NSUInteger OFASN1UnwrapSequence(NSData *seq, NSError **outError)
{
    NSUInteger byteCount = [seq length];
    if (byteCount < 2) {
        asnParseFailure(outError, @"Sequence is short");
        return badvalue;
    }
    
    const UInt8 *bytes = [seq bytes];
    if (bytes[0] != ( 0x10 | 0x20 )) {
        asnParseFailure(outError, @"Unexpected tag: expecting SEQUENCE (0x30), found 0x%02X", bytes[0]);
        return badvalue;
    }
    
    NSUInteger startsAt = 1;
    NSUInteger lengthField = parseLengthField(seq, &startsAt, outError);
    if (lengthField == badvalue)
        return badvalue;
    
    if (lengthField != ( byteCount - startsAt )) {
        asnParseFailure(outError, @"Incorrect length for SEQUENCE (found %lu, but have %lu bytes)", (unsigned long)lengthField, (unsigned long)(byteCount - startsAt));
        return badvalue;
    }
    
    return startsAt;
}

NSData *OFASN1UnwrapUnsignedInteger(NSData *buf, NSUInteger *inOutWhere, NSError **outError)
{
    NSUInteger byteCount = [buf length];
    NSUInteger where = *inOutWhere;
    if (byteCount < 2 || byteCount-2 < where) {
        asnParseFailure(outError, @"Sequence is short");
        return nil;
    }
    
    const UInt8 *bytes = [buf bytes];
    if (bytes[where] != ( 0x02 )) {
        asnParseFailure(outError, @"Unexpected tag: expecting INTEGER (0x02), found 0x%02X", bytes[0]);
        return nil;
    }
    where ++;
    
    NSUInteger integerLength = parseLengthField(buf, &where, outError);
    if (integerLength == badvalue)
        return nil;
    
    if (integerLength > 0 && (bytes[where] & 0x80)) {
        asnParseFailure(outError, @"Unexpected negative INTEGER", bytes[0]);
        return nil;
    }
    if (integerLength > 0 && bytes[where] == 0) {
        where ++;
        integerLength --;
    }
    NSData *result = [buf subdataWithRange:(NSRange){ where, integerLength }];
    *inOutWhere = where + integerLength;
    return result;
}

#pragma mark X.509 Certificate Utilities

static NSData *getSKI(CSSM_CL_HANDLE cl, const CSSM_DATA *cert)
{
    uint32 fieldCount;
    CSSM_DATA *buf;
    CSSM_RETURN err;
    CSSM_HANDLE queryHandle;
    
    fieldCount = 0;
    buf = NULL;
    queryHandle = CSSM_INVALID_HANDLE;
    
    err = CSSM_CL_CertGetFirstFieldValue(cl, cert, &CSSMOID_SubjectKeyIdentifier,
                                         &queryHandle, &fieldCount, &buf);
    
    if (err != CSSM_OK)
        return nil;
    
    NSData *result = nil;
    
    if (fieldCount > 0 && buf && buf->Length == sizeof(CSSM_X509_EXTENSION)) {
        const CSSM_X509_EXTENSION *ext = (CSSM_X509_EXTENSION *)(buf->Data);
        const CSSM_DATA *skiBuf;
        if (ext->format == CSSM_X509_DATAFORMAT_ENCODED) {
            skiBuf = &( ext->value.tagAndValue->value );
        } else if (ext->format == CSSM_X509_DATAFORMAT_PARSED) {
            skiBuf = (CE_SubjectKeyID *)ext->value.parsedValue;
        } else
            skiBuf = NULL;
        
        if (skiBuf)
            result = [NSData dataWithBytes:skiBuf->Data length:skiBuf->Length];
    }
    
    if(buf)
        CSSM_CL_FreeFieldValue(cl, &CSSMOID_SubjectKeyIdentifier, buf);
    CSSM_CL_CertAbortQuery(cl, queryHandle);
    
    return result;
}

static void osError(NSMutableDictionary *into, OSStatus code, NSString *function)
{
    NSDictionary *userInfo;
    
    if (function)
        userInfo = [NSDictionary dictionaryWithObject:function forKey:@"function"];
    else
        userInfo = nil;
    
    [into setObject:[NSError errorWithDomain:NSOSStatusErrorDomain code:code userInfo:userInfo] forKey:NSUnderlyingErrorKey];
}

static BOOL certificateMatchesSKI(SecCertificateRef aCert, NSData *subjectKeyIdentifier)
{
    static const UInt32 desiredAttributeTags[1] = { kSecSubjectKeyIdentifierItemAttr };
    static const UInt32 desiredAttributeFormats[1] = { CSSM_DB_ATTRIBUTE_FORMAT_BLOB };
    static const SecKeychainAttributeInfo desiredAtts = {
        .count = 1,
        .tag = (UInt32 *)desiredAttributeTags,
        .format = (UInt32 *)desiredAttributeFormats
    };
    
    SecKeychainAttributeList *retrievedAtts = NULL;
    
    SecKeychainItemRef asKCItem = (SecKeychainItemRef)aCert; // Superclass, but the compiler doesn't know that for CFTypes
    OSStatus err = SecKeychainItemCopyAttributesAndData(asKCItem, (SecKeychainAttributeInfo *)&desiredAtts, NULL, &retrievedAtts, NULL, NULL);
    
    if (err == noErr) {
        BOOL result;
        
        if (retrievedAtts->count == 1 &&
            retrievedAtts->attr[0].tag == kSecSubjectKeyIdentifierItemAttr &&
            retrievedAtts->attr[0].length == [subjectKeyIdentifier length] &&
            !memcmp(retrievedAtts->attr[0].data, [subjectKeyIdentifier bytes], [subjectKeyIdentifier length])) {
            result = YES;
        } else {
            result = NO;
        }
        
        SecKeychainItemFreeAttributesAndData(retrievedAtts, NULL);
        
        return result;
    } else if (err == errKCNotAvailable) {
        // Huh. I guess we have to use CSSM directly here.
        
        CSSM_DATA buf = { 0, 0 };
        err = SecCertificateGetData(aCert, &buf);
        if (err != noErr) {
            // ?? !!
            return NO;
        }
        
        CSSM_CL_HANDLE cl = CSSM_INVALID_HANDLE;
        err = SecCertificateGetCLHandle(aCert, &cl);
        if (err != noErr || cl == CSSM_INVALID_HANDLE) {
            NSLog(@"No cert lib for %@ - %ld %ld", aCert, (long)err, (long)cl);
            return NO;
        }
        
        NSData *foundSKI = getSKI(cl, &buf);
        // NSLog(@"extracted SKI %@", foundSKI);
        return [subjectKeyIdentifier isEqualToData:foundSKI];
    } else {
        // Not a fatal error, or even unexpected; this might just be an intermediate cert
        return NO;
    } 
}

/*" Given a <KeyInfo> element, this function attempts to find the X.509 certificate(s) corresponding to the key specified by the element's <X509Foo> children. All certificates supplied by the element are appended to auxiliaryCertificates, which may also contain externally supplied certificates which are used to satisfy <X509SKI> patterns. (In the future this function may also support SubjectKeyidentifier lookups, as well as Apple Keychain searches.) "*/
NSArray *OFXMLSigFindX509Certificates(xmlNode *keyInfoNode, CFMutableArrayRef auxiliaryCertificates, NSMutableDictionary *errorInfo)
{
    unsigned int nodeCount, nodeIndex;
    xmlNode **x509Nodes = OFLibXMLChildrenNamed(keyInfoNode, "X509Data", XMLSignatureNamespace, &nodeCount);
    
    if (!nodeCount)
        return nil;
    
    NSMutableSet *certBlobs = [NSMutableSet set];  // <X509Certificate> blobs encountered in the document
    NSMutableArray *desiredKeys = [NSMutableArray array];  // Other <X509Data> entries, indicating applicable verification keys
    
    for(nodeIndex = 0; nodeIndex < nodeCount; nodeIndex ++ ) {
        NSDictionary *parsedNode = OFXMLSigParseX509DataNode(x509Nodes[nodeIndex]);
        
        if (!parsedNode)
            continue;
        
        NSArray *certs = [parsedNode objectForKey:@"Certificate"];
        if (certs)
            [certBlobs addObjectsFromArray:certs];
        
        /* The constraints in XML-DSIG [4.4.4] end up meaning that any X509Data node containing keys other than Certificate or CRL nodes must indicate keys to use for validation. It doesn't restrict us from having more than one such --- I suppose it's allowing for the possibility of multiple dictinct certificates all certifying the same key. */
        
        /* Right now we only do SubjectKeyIdentifier lookups, so that we don't have to get into all the minutia of parsing DNs. */
        if ([parsedNode objectForKey:@"SKI"])
            [desiredKeys addObject:[parsedNode dictionaryWithObject:nil forKey:@"Certificate"]];
    }
    
    free(x509Nodes);
    
    [errorInfo setObject:desiredKeys forKey:@"desiredKeys"];
    
    NSData *fallbackBlob = nil;
    if ([desiredKeys count] == 0) {
        // Huh. Well, maybe they just gave us a single cert.
        if ([certBlobs count] == 1)
            fallbackBlob = [certBlobs anyObject];
    }
    
    NSMutableArray *testCertificates = [NSMutableArray array];
    
    // Convert all of our certs (whether from the document or from our trust store) into SecCertificateRefs.
    
    // Re-use any CertificateRefs from auxiliaryCertificates --- don't create new ones.
    for(CFIndex inputCertIndex = 0; inputCertIndex < CFArrayGetCount(auxiliaryCertificates); inputCertIndex ++) {
        SecCertificateRef aCert = (SecCertificateRef)CFArrayGetValueAtIndex(auxiliaryCertificates, inputCertIndex);
        CSSM_DATA bufReference = { 0, 0 };
        if (SecCertificateGetData(aCert, &bufReference) == noErr) {
            NSData *knownBlob = [[NSData alloc] initWithBytesNoCopy:bufReference.Data length:bufReference.Length freeWhenDone:NO];
            [certBlobs removeObject:knownBlob];
            if (fallbackBlob && [fallbackBlob isEqualToData:knownBlob])
                [testCertificates addObject:(id)aCert];
            [knownBlob release];
        }
    }
    
    // Create SecCertificateRefs from any remaining (non-duplicate) data blobs.
    OFForEachObject([certBlobs objectEnumerator], NSData *, aBlob) {
        CSSM_DATA blob = { .Data = (void *)[aBlob bytes], .Length = [aBlob length] };
        SecCertificateRef certReference = NULL;
        OSStatus err = SecCertificateCreateFromData(&blob, CSSM_CERT_X_509v3, CSSM_CERT_ENCODING_BER, &certReference);
        if (err != noErr) {
            osError(errorInfo, err, @"SecCertificateCreateFromData");
        } else {
            CFArrayAppendValue(auxiliaryCertificates, certReference);
            if (fallbackBlob && [fallbackBlob isEqualToData:aBlob])
                [testCertificates addObject:(id)certReference];
            CFRelease(certReference);
        }
    }
    
    // Run through all entries we've stashed in desiredKeys and try to find a corresponding certificate in auxiliaryCertificates.
    // (This is written with the assumption that there'll usually only be one entry in desiredKeys, so it's not worth caching anything in that inner loop.)
    CFIndex auxCertCount = CFArrayGetCount(auxiliaryCertificates);
    OFForEachObject([desiredKeys objectEnumerator], NSDictionary *, spec) {
        NSData *subjectKeyIdentifier = [spec objectForKey:@"SKI"];
        if (!subjectKeyIdentifier)
            continue; // huh?
        for(CFIndex certIndex = 0; certIndex < auxCertCount; certIndex ++) {
            SecCertificateRef aCert = (SecCertificateRef)CFArrayGetValueAtIndex(auxiliaryCertificates, certIndex);
            if (certificateMatchesSKI(aCert, subjectKeyIdentifier)) {
                /* The SubjectKeyIdentifier extension matches; this cert contains a key we could use to validate */
                [testCertificates addObject:(id)aCert];
            }
        }
    }
    
    [errorInfo setUnsignedIntValue:(unsigned)auxCertCount forKey:@"auxCertCount"];
    
    return testCertificates;
}

static const struct { SecTrustResultType code; NSString *display; } results[] = {
    { kSecTrustResultInvalid, @"Invalid" },
    { kSecTrustResultProceed, @"Proceed" },
    { kSecTrustResultConfirm, @"Confirm" },
    { kSecTrustResultDeny, @"Deny" },
    { kSecTrustResultUnspecified, @"Unspecified" },
    { kSecTrustResultRecoverableTrustFailure, @"RecoverableTrustFailure" },
    { kSecTrustResultFatalTrustFailure, @"FatalTrustFailure" },
    { kSecTrustResultOtherError, @"OtherError" },
    { 0, nil }
};

static const struct { CSSM_TP_APPLE_CERT_STATUS bit; NSString *display; } statusBits[] = {
    { CSSM_CERT_STATUS_EXPIRED, @"EXPIRED" },
    { CSSM_CERT_STATUS_NOT_VALID_YET, @"NOT_VALID_YET" },
    { CSSM_CERT_STATUS_IS_IN_INPUT_CERTS, @"IS_IN_INPUT_CERTS" },
    { CSSM_CERT_STATUS_IS_IN_ANCHORS, @"IS_IN_ANCHORS" },
    { CSSM_CERT_STATUS_IS_ROOT, @"IS_ROOT" },
    { CSSM_CERT_STATUS_IS_FROM_NET, @"IS_FROM_NET" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_FOUND_USER, @"SETTINGS_FOUND_USER" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_FOUND_ADMIN, @"SETTINGS_FOUND_ADMIN" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_FOUND_SYSTEM, @"SETTINGS_FOUND_SYSTEM" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_TRUST, @"SETTINGS_TRUST" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_DENY, @"SETTINGS_DENY" },
    { CSSM_CERT_STATUS_TRUST_SETTINGS_IGNORED_ERROR, @"SETTINGS_IGNORED_ERROR" },
    { 0, nil }
};

NSString *OFSummarizeTrustResult(SecTrustRef evaluationContext)
{
    SecTrustResultType trustResult;
    CFArrayRef chain = NULL;
    CSSM_TP_APPLE_EVIDENCE_INFO *stats = NULL;
    if (SecTrustGetResult(evaluationContext, &trustResult, &chain, &stats) != noErr) {
        return @"[SecTrustGetResult failure]";
    }
    
    NSMutableString *buf = [NSMutableString stringWithFormat:@"Trust result = %d", (int)trustResult];
    for(int i = 0; results[i].display; i++) {
        if(results[i].code == trustResult) {
            [buf appendFormat:@" (%@)", results[i].display];
        }
    }

    for(CFIndex i = 0; i < CFArrayGetCount(chain); i++) {
        SecCertificateRef c = (SecCertificateRef)CFArrayGetValueAtIndex(chain, i);
        CFStringRef cert = CFCopyDescription(c);
        [buf appendFormat:@"\n   %@: status=%08x ", cert, stats[i].StatusBits];
        CFRelease(cert);
        NSMutableArray *codez = [NSMutableArray array];
        
        for(int b = 0; statusBits[b].display; b ++) {
            if ((statusBits[b].bit & stats[i].StatusBits) == statusBits[b].bit)
                [codez addObject:statusBits[b].display];
        }
        if ([codez count]) {
            [buf appendFormat:@"(%@) ", [codez componentsJoinedByComma]];
            [codez removeAllObjects];
        }
        
        for(unsigned int ret = 0; ret < stats[i].NumStatusCodes; ret++)
            [codez addObject:OFStringFromCSSMReturn(stats[i].StatusCodes[ret])];
    }
    
    CFRelease(chain);
    
    return buf;
}

#pragma mark Keys from excplicit key information

/* These key-conversion routines are really only used for the unit tests and for a command-line test utility. Maybe they should be moved out of the framework? */

OFCSSMKey *OFXMLSigGetKeyFromRSAKeyValue(xmlNode *keyInfo, NSError **outError)
{
    unsigned int count;
    xmlNode *kv = OFLibXMLChildNamed(keyInfo, "RSAKeyValue", XMLSignatureNamespace, &count);
    if (count != 1) {
        if (outError)
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationFailure userInfo:[NSDictionary dictionaryWithObject:@"No (or multiple) <RSAKeyValue> elements in <KeyValue>" forKey:NSLocalizedDescriptionKey]];
        return nil;
    }
    
    xmlNode *modulus = OFLibXMLChildNamed(kv, "Modulus", XMLSignatureNamespace, &count);
    if (count != 1) {
        if (outError)
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationFailure userInfo:[NSDictionary dictionaryWithObject:@"Cannot find RSA key in <KeyInfo>" forKey:NSLocalizedDescriptionKey]];
        return nil;
    }
    
    xmlNode *exponent = OFLibXMLChildNamed(kv, "Exponent", XMLSignatureNamespace, &count);
    if (count != 1) {
        if (outError)
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationFailure userInfo:[NSDictionary dictionaryWithObject:@"Cannot find RSA key in <KeyInfo>" forKey:NSLocalizedDescriptionKey]];
        return nil;
    }
    
    NSData *modulusData = OFLibXMLNodeBase64Content(modulus);
    NSData *exponentData = OFLibXMLNodeBase64Content(exponent);
    
    /* The only key formats Apple's CSP supports are PKCS1 and X.509. PKCS1 is easier to deal with. */
    
    /* This is just a SEQUENCE containing two INTEGERs. Creating ASN.1 is much simpler than parsing it. */
    
    modulusData = OFASN1IntegerFromBignum(modulusData);
    exponentData = OFASN1IntegerFromBignum(exponentData);
    NSMutableData *pkcs1Bytes = OFASN1CreateForTag(0x10 | 0x20, [modulusData length] + [exponentData length]);
    [pkcs1Bytes appendData:modulusData];
    [pkcs1Bytes appendData:exponentData];
    
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
    
    [pkcs1Bytes release];
    
    return key;
}

static
NSData *derIntegerFromNodeChild(xmlNode *parent, const char *childName, NSError **outError)
{
    unsigned int count;
    xmlNode *integerNode = OFLibXMLChildNamed(parent, childName, XMLSignatureNamespace, &count);
    if (count != 1) {
        if (outError)
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Found %d <%s> nodes in <%s>", count, childName, parent->name] forKey:NSLocalizedDescriptionKey]];
        return nil;
    }
    
    return OFASN1IntegerFromBignum(OFLibXMLNodeBase64Content(integerNode));
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

OFCSSMKey *OFXMLSigGetKeyFromDSAKeyValue(xmlNode *keyInfo, NSError **outError)
{
    unsigned int count;
    xmlNode *kv = OFLibXMLChildNamed(keyInfo, "DSAKeyValue", XMLSignatureNamespace, &count);
    if (count != 1) {
        if (outError)
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationFailure userInfo:[NSDictionary dictionaryWithObject:@"No (or multiple) <RSAKeyValue> elements in <KeyValue>" forKey:NSLocalizedDescriptionKey]];
        return nil;
    }
    
    /* The only key formats Apple's CSP supports for DSA are FIPS186 and X.509. Apple says not to use FIPS186. */
    
    /*
     The X.509 format here is as described in RFC 2459 [7.3.3]. It boils down to:
        SEQUENCE {                
          SEQUENCE {             -- AlgorithmIdentifier [4.1.1.2]
            OBJECT IDENTIIER,    -- specifying id-dsa
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
    NSData *paramSeq = OFASN1CreateForTag(0x10 | 0x20, pqgLength);
    
    /* The AlgorithmIdentifier */
    NSMutableData *algorithmId = OFASN1CreateForTag(0x10 | 0x20, dssOidByteCount + [paramSeq length] + pqgLength);
    [algorithmId appendBytes:dssOidBytes length:dssOidByteCount];
    [algorithmId appendData:paramSeq];
    [algorithmId appendData:pData];
    [algorithmId appendData:qData];
    [algorithmId appendData:gData];
    
    /* The wrapped Y-value, subjectPublicKey BIT STRING */
    NSMutableData *pubKey = OFASN1CreateForTag(0x03, 1 + [yData length]);
    [pubKey appendBytes:"" length:1]; // "Unused bits" count at beginning of BIT STRING (padding to byte boundary, none needed for us)
    [pubKey appendData:yData];
    
    /* The whole shebang */
    NSMutableData *fullKey = OFASN1CreateForTag(0x10 | 0x20, [algorithmId length] + [pubKey length]);
    [fullKey appendData:algorithmId];
    [fullKey appendData:pubKey];
    
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
    
    [paramSeq release];
    [algorithmId release];
    [pubKey release];
    [fullKey release];
    
    return key;
}

