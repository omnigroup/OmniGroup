// Copyright 2009-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLSignature.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFCDSAUtilities.h>
#import <OmniFoundation/OFSecurityUtilities.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>

#include <libxml/tree.h>

#include <libxml/c14n.h>
#include <libxml/xmlIO.h>
#include <libxml/xmlerror.h>
#include <libxml/xmlmemory.h>
#include <libxml/xmlversion.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#include <libxml/xpointer.h>

#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7 && MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7
// If we allow 10.7 API but also support 10.6, then we need to weakly import these Security.framework symbols or we won't be able to launch on 10.6.
extern CFDictionaryRef SecCertificateCopyValues(SecCertificateRef certificate, CFArrayRef keys, CFErrorRef *error) __attribute__((weak_import));
#endif

RCS_ID("$Id$");

#pragma mark ASN.1 utility routines

/* ASN.1 DER construction utility routines */

#define CLASS_CONSTRUCTED 0x20

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
        buf = OFASN1CreateForTag(BER_TAG_INTEGER, bytecount + 1);
        [buf appendBytes:"" length:1];
    } else {
        buf = OFASN1CreateForTag(BER_TAG_INTEGER, bytecount);
    }
    
    if (firstDigit == 0)
        [buf appendData:base256Number];
    else
        [buf appendData:[base256Number subdataWithRange:(NSRange){ firstDigit, bytecount }]];
    
    return [buf autorelease];
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
        uint_fast8_t n;
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
    
    NSMutableData *header = OFASN1CreateForTag(BER_TAG_SEQUENCE | CLASS_CONSTRUCTED, totalLength);
    
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
    if (bytes[0] != ( BER_TAG_SEQUENCE | CLASS_CONSTRUCTED )) {
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
    if (bytes[where] != BER_TAG_INTEGER) {
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

#pragma mark SecItem debugging


#pragma mark X.509 Certificate Utilities

#if OF_ENABLE_CDSA
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
#endif

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
    const void *desiredAttributeOIDs_[1] = { kSecOIDSubjectKeyIdentifier };
    CFArrayRef desiredAttributeOIDs = CFArrayCreate(kCFAllocatorDefault, desiredAttributeOIDs_, 1, &kCFTypeArrayCallBacks);
    CFDictionaryRef parsedCertificate = SecCertificateCopyValues(aCert, desiredAttributeOIDs, NULL);
    CFRelease(desiredAttributeOIDs);
    
    if (parsedCertificate != NULL) {
        BOOL result;
        CFDictionaryRef skiValueInfo = NULL;
        CFTypeRef skiValueType = NULL;
        CFTypeRef skiContainedValue;
        
        //NSLog(@"CertInfo(%@) -> %@", (id)aCert, [(id)parsedCertificate description]);
        
        if (!CFDictionaryGetValueIfPresent(parsedCertificate, kSecOIDSubjectKeyIdentifier, (const void **)&skiValueInfo) ||
            !CFDictionaryGetValueIfPresent(skiValueInfo, kSecPropertyKeyType, (const void **)&skiValueType)) {
            CFRelease(parsedCertificate);
            return NO;
        }
        
        /* There's no documentation on what format SecCertificateCopyValues() returns individual values in (RADAR 10430553). SKIs appear to be returned either as a kSecPropertyTypeData, or as a "section" containing 2 elements: the critical flag (returned as a string--- WTF, Apple!?!) and the SKI. */
        
        if (CFEqual(skiValueType, kSecPropertyTypeSection) &&
            CFDictionaryGetValueIfPresent(skiValueInfo, kSecPropertyKeyValue, (const void **)&skiContainedValue) &&
            CFArrayGetCount(skiContainedValue) == 2) {
            // 2-element "section" containing critical flag & actual value.
            skiValueInfo = CFArrayGetValueAtIndex(skiContainedValue, 1);
            skiValueType = CFDictionaryGetValue(skiValueInfo, kSecPropertyKeyType);
        }
        
        if (CFEqual(skiValueType, kSecPropertyTypeData)) {
            //NSLog(@"SKIv = %@", [(id)skiValueInfo description]);
            result = [subjectKeyIdentifier isEqualToData:(NSData *)CFDictionaryGetValue(skiValueInfo, kSecPropertyKeyValue)];
        } else {
            result = NO;
        }
        
        CFRelease(parsedCertificate);
        
        return result;
    }
    
#if OF_ENABLE_CDSA
    OSStatus err = errKCNotAvailable;
    if (err == errKCNotAvailable) {
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
    }
#endif
    
    // Not a fatal error, or even unexpected; this might just be an intermediate cert
    return NO;
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
        
        /* The constraints in XML-DSIG [4.4.4] end up meaning that any X509Data node containing nodes other than Certificate or CRL nodes must indicate keys to use for validation. It doesn't restrict us from having more than one such --- I suppose it's allowing for the possibility of multiple distinct certificates all certifying the same key. */
        
        /* Right now we only do SubjectKeyIdentifier lookups, so that we don't have to get into all the minutia of parsing DNs. */
        if ([parsedNode objectForKey:@"SKI"])
            [desiredKeys addObject:[parsedNode dictionaryWithObjectRemovedForKey:@"Certificate"]];
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
        NSData *knownBlob = CFBridgingRelease(SecCertificateCopyData(aCert));
        if (knownBlob != nil) {
            [certBlobs removeObject:knownBlob];
            if (fallbackBlob && [fallbackBlob isEqualToData:knownBlob])
                [testCertificates addObject:(__bridge id)aCert];
        }
    }
    
    // Create SecCertificateRefs from any remaining (non-duplicate) data blobs.
    OFForEachObject([certBlobs objectEnumerator], NSData *, aBlob) {
        SecCertificateRef certReference = SecCertificateCreateWithData(kCFAllocatorDefault, (__bridge CFDataRef)aBlob);
        if (!certReference) {
            // RADAR 10057193: There's no way to know why SecCertificateCreateWithData() failed.
            // (However, see RADAR 7514859: SecCertificateCreateFromData will accept inputs that it's documented to return NULL for, and return an unusable SecCertificateRef; I guess we're no worse off with no error-reporting API than with an error-reporting API that doesn't work.)
            osError(errorInfo, paramErr, @"SecCertificateCreateWithData");
            continue;
        }
        
        CFArrayAppendValue(auxiliaryCertificates, certReference);
        if (fallbackBlob && [fallbackBlob isEqualToData:aBlob])
            [testCertificates addObject:(__bridge id)certReference];
        CFRelease(certReference);
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
                [testCertificates addObject:(__bridge id)aCert];
            }
        }
    }
    
    [errorInfo setUnsignedIntValue:(unsigned)auxCertCount forKey:@"auxCertCount"];
    
    return testCertificates;
}

NSArray *OFReadCertificatesFromFile(NSString *path, SecExternalFormat inputFormat_, NSError **outError)
{
    NSData *pemFile = [[NSData alloc] initWithContentsOfFile:path options:0 error:outError];
    if (!pemFile)
        return nil;
    
    SecExternalFormat inputFormat;
    SecExternalItemType itemType;
    
    SecItemImportExportKeyParameters keyParams = (SecItemImportExportKeyParameters){
        .version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION,  /* Yes, both versions have the same version number */
        .flags = 0,
        .passphrase = NULL,
        .alertTitle = NULL,  /* undocumentedly does nothing: see RADAR #7530393 */
        .alertPrompt = NULL,
        .accessRef = NULL,
        .keyUsage = (CFArrayRef)[NSArray arrayWithObject:(id)kSecAttrCanVerify],
        /* The docs say to use CSSM_KEYATTR_EXTRACTABLE here, but that's clearly wrong--- apparently nobody updated the docs after updating the API to purge all references to CSSM. kSecKeyExtractable exists, but it's the wrong type and is deprecated. Anyway, certificates are generally extractable, so I guess we can rely on the default behavior being what we want here, but it would be nice if Lion's crypto were a little less half-baked.
         Update: According to the libsecurity sources, the only thing accepted in keyAttributes is kSecAttrIsPermanent. SecItemImport() just converts the strings to CSSM_FOO flags and calls SecKeychainItemImport(). (RADAR 10428209, 10274369)
         */
        .keyAttributes = NULL
    };
    CFArrayRef outItems;
    
    inputFormat = inputFormat_;
    itemType = kSecItemTypeCertificate;
    
    OSStatus err = SecItemImport((__bridge CFDataRef)pemFile, (__bridge CFStringRef)path, &inputFormat, &itemType, 0, &keyParams, NULL, &outItems);
    
    [pemFile release];
    
    if (err != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:[NSDictionary dictionaryWithObjectsAndKeys:path, NSFilePathErrorKey, @"SecKeychainItemImport", @"function", nil]];
        return nil;
    }
    
    if (!outItems)
        return [NSArray array];
    return CFBridgingRelease(outItems);
}
                                 

