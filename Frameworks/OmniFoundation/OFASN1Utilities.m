// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFASN1-Internal.h>
#import <OmniFoundation/OFSecurityUtilities.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniBase/rcsid.h>

#import <Security/Security.h>

RCS_ID("$Id$");

struct parsedTag {
    unsigned short tag;              // tag
    uint8_t classAndConstructed;     // class and constructed flags bits from first octet
    BOOL indefinite;
    NSRange content;
};

struct asnWalkerState {
    NSUInteger startPosition;        // The position at which 'v' was parsed
    struct parsedTag v;              // Tag and length of the "current" object
    NSUInteger maxIndex;             // The end of the innermost definite-length object containing us (or the data buffer itself)
    BOOL containerIsIndefinite;      // YES if our immediate container is indefinite
};

static enum OFASN1ErrorCodes nextObject(NSData *buffer, struct asnWalkerState *st);
static enum OFASN1ErrorCodes objectAt(NSData *buffer, NSUInteger pos, struct asnWalkerState *st);
static enum OFASN1ErrorCodes enterObject(NSData *buffer, struct asnWalkerState *containerState, struct asnWalkerState *innerState);
static enum OFASN1ErrorCodes exitObject(NSData *buffer, struct asnWalkerState *containerState, struct asnWalkerState *innerState, BOOL allowTrailing);

static enum OFASN1ErrorCodes parseTagAndLength_(NSData *buffer, NSUInteger where, NSUInteger maxIndex, struct parsedTag *outTL)
{
    unsigned char buf[16];
    
    if (where + 2 > maxIndex) {
        return OFASN1Truncated;
    }
    
    [buffer getBytes:buf range:(NSRange){where, 2}];
    outTL->tag = buf[0] & 0x1F;
    outTL->classAndConstructed = buf[0] & 0xE0;
    
    NSUInteger lengthStartIndex;
    
    if (outTL->tag == 0x1F) {
        /* High tag number: encoded as a MEB128 integer. We punt on this here, since I've never had to deal with any of these at all. */
        if (buf[1] & 0x80) {
            return OFASN1TagOverflow;
        }
        outTL->tag = buf[1];
        
        if (where+3 >= maxIndex) {
            return OFASN1Truncated;
        }
        [buffer getBytes:buf+1 range:(NSRange){where+2, 1}];
        lengthStartIndex = where+2;
    } else {
        /* Low tag number: the length is in the next byte. */
        lengthStartIndex = where+1;
    }
    
    if ((buf[1] & 0x80) == 0) {
        /* Fast path for a common case: short, definite-length object */
        outTL->indefinite = NO;
        outTL->content.location = lengthStartIndex+1;
        outTL->content.length = buf[1];
        
        if (outTL->content.length + outTL->content.location > maxIndex)
            return OFASN1Truncated;
        
        return OFASN1Success;
    } else if (buf[1] == 0x80) {
        /* Indefinite-length object. */
        if (!(outTL->classAndConstructed & 0x20)) {
            /* A non-constructed, indefinite-length object doesn't make any sense */
            return OFASN1InconsistentEncoding;
        }
        
        outTL->indefinite = YES;
        outTL->content.location = lengthStartIndex+1;
        outTL->content.length = 0;

        return OFASN1Success;
    } else {
        /* Multi-byte length field; first byte indicates number of bytes to follow */
        unsigned lengthLength = buf[1] & 0x7F;
        NSUInteger extractedLength;
        
        if (lengthLength > sizeof(buf)) {
            return OFASN1LengthOverflow;
        }
        
        if (lengthStartIndex + 1 + lengthLength >= maxIndex) {
            return OFASN1Truncated;
        }
        
        [buffer getBytes:buf range:(NSRange){ lengthStartIndex+1, lengthLength }];
        
        extractedLength = 0;
        NSUInteger bound = (NSUIntegerMax) >> 8;
        for (unsigned octetIndex = 0; octetIndex < lengthLength; octetIndex ++) {
            if (bound < extractedLength) {
                return OFASN1LengthOverflow;
            }
            extractedLength = ( extractedLength << 8 ) + buf[octetIndex];
        }
        
        outTL->indefinite = NO;
        outTL->content.location = lengthStartIndex + 1 + lengthLength;
        outTL->content.length = extractedLength;

        if (outTL->content.length + outTL->content.location > maxIndex)
            return OFASN1Truncated;
        
        return OFASN1Success;
    }
}

#if 1
#define parseTagAndLength(b,w,m,t) parseTagAndLength_(b,w,m,t)
#else
static enum OFASN1ErrorCodes parseTagAndLength(NSData *buffer, NSUInteger where, NSUInteger maxIndex, struct parsedTag *outTL)
{
    enum OFASN1ErrorCodes rc = parseTagAndLength_(buffer, where, maxIndex, outTL);
    if (rc) {
        NSLog(@"Next object: pos=%lu err=%d", where, rc);
    } else {
        NSLog(@"Next object: pos=%lu cc=%02X tag=0x%X len=%lu", where, outTL->classAndConstructed, outTL->tag, outTL->content.length);
    }
    return rc;
}
#endif

/* Set up the outermost walker state, and leave it pointing at the first (usually only) object in the buffer */
static enum OFASN1ErrorCodes initializeWalker(NSData *buffer, struct asnWalkerState *st)
{
    *st = (struct asnWalkerState){
        .startPosition = 0,
        .maxIndex = [buffer length],
        .containerIsIndefinite = NO
    };
    
    return parseTagAndLength(buffer, 0, st->maxIndex, &(st->v));
}

/* Advance the walker to the next object */
static enum OFASN1ErrorCodes nextObject(NSData *buffer, struct asnWalkerState *st)
{
    if (st->v.indefinite) {
        enum OFASN1ErrorCodes rc;
        struct asnWalkerState innerWalker;
        rc = enterObject(buffer, st, &innerWalker);
        if (rc)
            return rc;
        rc = exitObject(buffer, st, &innerWalker, YES);
        return rc;
    } else {
        return objectAt(buffer, NSMaxRange(st->v.content), st);
    }
}

static enum OFASN1ErrorCodes objectAt(NSData *buffer, NSUInteger pos, struct asnWalkerState *st)
{
    if (pos == st->maxIndex && !st->containerIsIndefinite) {
        return OFASN1EndOfObject;
    } else if (pos >= st->maxIndex) {
        return OFASN1Truncated;
    } else {
        enum OFASN1ErrorCodes rc = parseTagAndLength(buffer, pos, st->maxIndex, &(st->v));
        st->startPosition = pos;
        return rc;
    }
}

static BOOL isSentinelObject(const struct parsedTag *v)
{
    return (v->tag == 0 && v->classAndConstructed == 0 && !v->indefinite);
}

static enum OFASN1ErrorCodes nextObjectExpecting(NSData *buffer, struct asnWalkerState *st, uint8_t expectClassAndConstructed, unsigned short expectTag)
{
    enum OFASN1ErrorCodes rc = nextObject(buffer, st);
    if (rc == OFASN1EndOfObject)
        return OFASN1UnexpectedType;
    if (rc)
        return rc;
    
    if (st->v.classAndConstructed == expectClassAndConstructed && st->v.tag == expectTag)
        return OFASN1Success;
    else
        return OFASN1UnexpectedType;
}

/* Assuming the walker is pointing at a SET or SEQUENCE, start a sub-walker pointing at its contents */
static enum OFASN1ErrorCodes enterObject(NSData *buffer, struct asnWalkerState *containerState, struct asnWalkerState *innerState)
{
    if (!(containerState->v.classAndConstructed & FLAG_CONSTRUCTED)) {
        return OFASN1UnexpectedType;
    }
    
    innerState->startPosition = containerState->v.content.location;
    if (containerState->v.indefinite) {
        innerState->containerIsIndefinite = YES;
        innerState->maxIndex = containerState->maxIndex;
    } else {
        /* Definite-length container: update maxIndex */
        innerState->containerIsIndefinite = NO;
        assert(containerState->v.content.location + containerState->v.content.length <= containerState->maxIndex);
        innerState->maxIndex = NSMaxRange(containerState->v.content);
    }
    
    return parseTagAndLength(buffer, innerState->startPosition, innerState->maxIndex, &(innerState->v));
}

/* Exit a sub-walker. The containerState will be left pointing to the object after the container we just exited. innerState should not be used after this function. */
static enum OFASN1ErrorCodes exitObject(NSData *buffer, struct asnWalkerState *containerState, struct asnWalkerState *innerState, BOOL allowTrailing)
{
    NSUInteger nextReadPosition;
    enum OFASN1ErrorCodes rc;
    
    if (innerState->containerIsIndefinite) {
        OBASSERT(containerState->v.indefinite);
        for(;;) {
            if (isSentinelObject(&(innerState->v))) {
                /* The expected case: our current object is the end marker */
                nextReadPosition = NSMaxRange(innerState->v.content);
                /* Update the indefinite-length container's content.length (which is initially 0/undefined for an indefinite object) to be the actual content length including sentinel */
                OBPRECONDITION(containerState->v.content.length == 0);
                containerState->v.content.length = nextReadPosition - containerState->v.content.length;
                innerState->v.content.length = nextReadPosition - innerState->v.content.location;
                break;
            }
            /* We're currently at an object that isn't the end marker. */
            if (!allowTrailing)
                return OFASN1UnexpectedType;
            rc = nextObject(buffer, innerState);
            if (rc == OFASN1EndOfObject) {
                /* Missing sentinel */
                return OFASN1InconsistentEncoding;
            } else if (rc != OFASN1Success) {
                return rc;
            }
        }
    } else {
        OBASSERT(!containerState->v.indefinite);
        /* Our inner state's contentLength is valid: either it's definite-length, or we updated its indefinite length when we exited its contents. Our outer state's content length is also valid because it's a definite-length object. */
        nextReadPosition = NSMaxRange(innerState->v.content);
        NSUInteger positionAfterContainer = NSMaxRange(containerState->v.content);
        
        if (!allowTrailing) {
            /* Make sure the object we just read was the last one in the container. */
            if (positionAfterContainer < nextReadPosition)
                return OFASN1UnexpectedType;
        }
        if (positionAfterContainer > nextReadPosition)
            return OFASN1InconsistentEncoding;
    }
    
    return objectAt(buffer, nextReadPosition, containerState);
}

static BOOL unDerInt(NSData *buffer, const struct parsedTag *v, int32_t *result)
{
    if (v->classAndConstructed != FLAG_PRIMITIVE ||
        v->tag != BER_TAG_INTEGER) {
        /* not an INTEGER */
        return NO;
    }
    
    if (v->content.length > 4) {
        /* too large for an int32 */
        return NO;
    }
    unsigned l = (unsigned)(v->content.length);
    if (l == 0) {
        /* invalid integer encoding */
        return NO;
    }
    
    char buf[4];
    [buffer getBytes:buf+(4-l) range:v->content];
    
    if (l < 4)
        memset(buf, ( buf[4-l] & 0x80 )? 0xFF : 0x00, 4-l);
    
    *result = OSReadBigInt32(buf, 0);
    return YES;
}

/* Some macros for using the walker functions */

#define IS_TYPE(st, cls, tagnumber) (st.v.classAndConstructed == (cls) && st.v.tag == (tagnumber))
#define EXPECT_TYPE(st, cls, tagnumber) if (!IS_TYPE(st, cls, tagnumber)) { return OFASN1UnexpectedType; }
#define EXPLICIT_TAGGED(st, tagnumber) (st.v.classAndConstructed == (CLASS_CONTEXT_SPECIFIC|FLAG_CONSTRUCTED) && st.v.tag == (tagnumber))
#define IMPLICIT_TAGGED(st, tagnumber) ((st.v.classAndConstructed & CLASS_MASK) == CLASS_CONTEXT_SPECIFIC && st.v.tag == (tagnumber))
#define DER_FIELD_RANGE(walker) ((NSRange){ walker.startPosition, walker.v.content.length + ( walker.v.content.location - walker.startPosition)})
#define FIELD_CONTENTS_RANGE(walker) (walker.v.content)

#define ADVANCE(buf, walker) do{ rc = nextObject(buf, &walker); if (rc) return rc; }while(0)

#pragma mark - ASN.1 scanning and creation utility functions

int OFASN1CertificateExtractFields(NSData *cert, NSData **serialNumber, NSData **issuer, NSData **subject, NSData **subjectKeyInformation, void (^extensions_cb)(NSData *oid, BOOL critical, NSData *value))
{
    enum OFASN1ErrorCodes rc;
    struct asnWalkerState stx;
    
    rc = initializeWalker(cert, &stx);
    if (rc)
        return rc;
    
    EXPECT_TYPE(stx, 0x20, 0x10); /* SEQUENCE */
    {
        struct asnWalkerState signatureFields;
        rc = enterObject(cert, &stx, &signatureFields);
        if (rc)
            return rc;
        
        /* The first element of Certificate is TBSCertificate */
        EXPECT_TYPE(signatureFields, 0x20, 0x10); /* SEQUENCE */
        {
            struct asnWalkerState tbsFields;
            rc = enterObject(cert, &signatureFields, &tbsFields);
            if (rc)
                return rc;
            
            /* Parse the optional VERSION. If it's there, it's contained in an [0] EXPLICIT. */
            if (EXPLICIT_TAGGED(tbsFields, 0)) {
                /* Skip the tag and the version */
                ADVANCE(cert, tbsFields);
            }
            
            /* Serial number is next: its concrete type is INTEGER */
            EXPECT_TYPE(tbsFields, 0x00, 0x02);
            if (serialNumber)
                *serialNumber = [cert subdataWithRange:FIELD_CONTENTS_RANGE(tbsFields)];
            ADVANCE(cert, tbsFields);
            
            ADVANCE(cert, tbsFields); /* Skip certificate signature algorithm identifier */
            
            /* Issuer's concrete type is SEQUENCE (of RDNs) */
            EXPECT_TYPE(tbsFields, 0x20, 0x10);
            if (issuer)
                *issuer = [cert subdataWithRange:DER_FIELD_RANGE(tbsFields)];
            ADVANCE(cert, tbsFields);
            
            ADVANCE(cert, tbsFields); /* Validity information */
            
            /* Subject's concrete type is SEQUENCE (of RDNs) */
            EXPECT_TYPE(tbsFields, 0x20, 0x10);
            if (subject)
                *subject = [cert subdataWithRange:DER_FIELD_RANGE(tbsFields)];
            ADVANCE(cert, tbsFields);
            
            /* SubjectPublicKeyInfo is also a SEQUENCE */
            EXPECT_TYPE(tbsFields, 0x20, 0x10);
            if (subjectKeyInformation) {
                *subjectKeyInformation = [cert subdataWithRange:DER_FIELD_RANGE(tbsFields)];
            }
            ADVANCE(cert, tbsFields);
            
            /* Skip the optional IMPLICIT-tagged issuerUniqueID, if it's there */
            if (IMPLICIT_TAGGED(tbsFields, 1)) {
                ADVANCE(cert, tbsFields);
            }
            
            /* Skip the optional IMPLICIT-tagged subjectUniqueID, if it's there */
            if (IMPLICIT_TAGGED(tbsFields, 2)) {
                ADVANCE(cert, tbsFields);
            }
            
            /* The extensions array, oddly, is explicitly tagged, not implicitly */
            if (EXPLICIT_TAGGED(tbsFields, 3)) {
                
                if (extensions_cb) {
                    
                    // Enter the explicit tag
                    struct asnWalkerState inExplicitTag;
                    rc = enterObject(cert, &tbsFields, &inExplicitTag);
                    if (rc)
                        return rc;
                    
                    EXPECT_TYPE(inExplicitTag, 0x20, 0x10);
                    
                    // Enter the SEQUENCE
                    struct asnWalkerState extns;
                    rc = enterObject(cert, &inExplicitTag, &extns);
                    while (rc != OFASN1EndOfObject) {
                        if (rc != OFASN1Success)
                            return rc;
                        
                        struct asnWalkerState extn;
                        
                        /* Each extension is a SEQUENCE */
                        EXPECT_TYPE(extns, 0x20, 0x10);
                        rc = enterObject(cert, &extns, &extn);
                        if (rc)
                            return rc;
                        
                        /* starting with an OID */
                        EXPECT_TYPE(extn, 0x00, 0x06);
                        NSRange extnOid = FIELD_CONTENTS_RANGE(extn);
                        ADVANCE(cert, extn);
                        
                        /* then the critical flag, which is optional and defaults to false */
                        BOOL extensionIsCritical;
                        if (IS_TYPE(extn, CLASS_UNIVERSAL, BER_TAG_BOOLEAN)) {
                            if(extn.v.content.length != 1)
                                return NO;
                            uint8_t flagBits;
                            [cert getBytes:&flagBits range:(NSRange){ extn.v.content.location, 1 }];
                            if (flagBits == 0x00)
                                extensionIsCritical = NO;
                            else if (flagBits == 0xFF)
                                extensionIsCritical = YES;
                            else
                                return NO; // Not a valid DER boolean if it isn't one of the two given values: see X.690 [11.1]
                            ADVANCE(cert, extn);
                        } else {
                            extensionIsCritical = NO;
                        }
                        
                        /* and the extension value, which is wrapped in an OCTET STRING */
                        EXPECT_TYPE(extn, 0x00, BER_TAG_OCTET_STRING);
                        NSRange extnRange = FIELD_CONTENTS_RANGE(extn);
                        
                        extensions_cb([cert subdataWithRange:extnOid], extensionIsCritical, [cert subdataWithRange:extnRange]);
                        
                        rc = exitObject(cert, &extns, &extn, YES);
                    }
                    // Exit the SEQUENCE
                    rc = exitObject(cert, &inExplicitTag, &extns, NO);
                    if (rc != OFASN1EndOfObject)
                        return (rc == OFASN1Success ? OFASN1UnexpectedType : rc);
                    // Exit the tag
                    rc = exitObject(cert, &tbsFields, &inExplicitTag, NO);
                    if (rc != OFASN1EndOfObject && rc != OFASN1Success)
                        return rc;
                    
                } else {
                    /* Caller is not interested in extensions; skip them */
                    ADVANCE(cert, tbsFields);
                }
            }
            
            // Exit the TBSCertificate
            rc = exitObject(cert, &signatureFields, &tbsFields, YES);
            if (rc != OFASN1EndOfObject && rc != OFASN1Success)
                return rc;
        }
        
        /* Still remaining in the Certificate are the signature algorithm identifier and the signature itself: we don't care. */
    }
    
    return OFASN1Success;
}

/* A NAME is a sequence of relative names, and a relative name is a SET of attribute-value pairs, where each attribute is an OID and each value is any single object.
 
 Collapsing a bunch of definitions from PKIX...88 we get:
 
 NAME ::= SEQUENCE OF 
             SET OF
                SEQUENCE {
                   type    OBJECT IDENTIFIER,
                   value   ANY }
 
 
 This function calls the callback once for each OID-value pair, with 'ix' set to the index of the pair within its RDN (so, for typical certificates, ix will always be 0)
 */

BOOL OFASN1EnumerateAVAsInName(NSData *rdnseq, void (^callback)(NSData *a, NSData *v, unsigned ix, BOOL *stop))
{
    enum OFASN1ErrorCodes rc;
    struct asnWalkerState nameSt, rdnSt, avasSt, avaSt;
    
    rc = initializeWalker(rdnseq, &nameSt);
    if (rc)
        return NO;
    
    if (!IS_TYPE(nameSt, FLAG_CONSTRUCTED, BER_TAG_SEQUENCE))
        return NO;
    
    /* Enter the outermost SEQUENCE */
    rc = enterObject(rdnseq, &nameSt, &rdnSt);
    while (rc != OFASN1EndOfObject) {
        if (rc != OFASN1Success)
            return NO;
        
        if (!IS_TYPE(rdnSt, FLAG_CONSTRUCTED, BER_TAG_SET))
            return NO;
        
        unsigned indexWithinRDN = 0;
        
        /* Enter the SET of individual AVAs */
        rc = enterObject(rdnseq, &rdnSt, &avasSt);
        while (rc != OFASN1EndOfObject) {
            if (rc != OFASN1Success)
                return NO;
            
            /* Enter the SEQUENCE which is just the 2-tuple of attribute and value */
            if (!IS_TYPE(avasSt, FLAG_CONSTRUCTED, BER_TAG_SEQUENCE))
                return NO;
            if (enterObject(rdnseq, &avasSt, &avaSt) != OFASN1Success)
                return NO;
            if (!IS_TYPE(avaSt, 0, BER_TAG_OID))
                return NO;
            NSRange oidRange = FIELD_CONTENTS_RANGE(avaSt);
            
            if (nextObject(rdnseq, &avaSt) != OFASN1Success)
                return NO;
            
            NSData *avaOid = [rdnseq subdataWithRange:oidRange];
            NSData *avaValue = [rdnseq subdataWithRange:DER_FIELD_RANGE(avaSt)];
            BOOL shouldStop = NO;
            callback(avaOid, avaValue, indexWithinRDN, &shouldStop);
            
            if (shouldStop) {
                return YES;
            }
            
            indexWithinRDN ++;
            
            rc = exitObject(rdnseq, &avasSt, &avaSt, NO);
        }
        
        /* Exit the SET OF */
        rc = exitObject(rdnseq, &rdnSt, &avasSt, NO);
    }
    
    /* Exit the outermost SEQUENCE */
    rc = exitObject(rdnseq, &nameSt, &rdnSt, NO);
    if (rc != OFASN1EndOfObject)
        return NO;
    
    return YES;
}

/* Enumerate the entries in an Apple appstore receipt. Returns NO if there were any problems parsing the structure. The structure we parse is described in the Apple docs thus:
 
    ReceiptAttribute ::= SEQUENCE {
        type    INTEGER,
        version INTEGER,
        value   OCTET STRING
    }
 
    Payload ::= SET OF ReceiptAttribute
 
 (TODO: If the 'type' is out of range for our callback, we should just ignore that attribute and continue, instead of failing.)

*/

#if 0
static const struct { int tp; int ver; } decodables[] = {
    /* These are documented by Apple */
    {  2, 1 }, // UTF8STRING - Bundle Identifier - The app’s bundle identifier
    {  3, 1 }, // UTF8STRING - App Version - The app’s version number
    { 19, 1 }, // UTF8STRING - Original Application Version - The version of the app that was originally purchased
    
    /* These are not documented by Apple, but they're there */
    {  0, 1 }, // STRING
    {  1, 1 }, // INTEGER
    {  8, 1 }, // String (looks like an ISO8601 date)
    {  9, 1 }, // INTEGER (looks like a POSIX date)
    { 10, 1 }, // String
    { 11, 1 }, // INTEGER
    { 12, 1 }, // String (looks like an ISO8601 date)
    { 13, 1 }, // INTEGER
    { 14, 1 }, // INTEGER
    { 15, 1 }, // INTEGER (but too long for us)
    { 16, 1 }, // INTEGER
    { 18, 1 }, // String (looks like an ISO8601 date)
    { 20, 1 }, // String
    { 25, 1 }, // INTEGER
};
#endif

BOOL OFASN1EnumerateAppStoreReceiptAttributes(NSData *payload, void (^callback)(int att_type, int att_version, NSRange value))
{
    enum OFASN1ErrorCodes rc;
    struct asnWalkerState payloadSt, attrSt, valueSt;
    
    rc = initializeWalker(payload, &payloadSt);
    if (rc)
        return NO;
    
    if (!IS_TYPE(payloadSt, FLAG_CONSTRUCTED, BER_TAG_SET))
        return NO;
    
    /* Enter the outermost SET */
    rc = enterObject(payload, &payloadSt, &attrSt);
    while (rc != OFASN1EndOfObject) {
        if (rc != OFASN1Success)
            return NO;
        
        /* Enter the SEQUENCE which is the 3-tuple of (type, version, value) */
        if (!IS_TYPE(attrSt, FLAG_CONSTRUCTED, BER_TAG_SEQUENCE))
            return NO;
        rc = enterObject(payload, &attrSt, &valueSt);
        if (rc != OFASN1Success)
            return NO;
        
        {
            int32_t parsedAttributeType;
            int32_t parsedAttributeVersion;
            NSRange attributeValueLocation;
            
            if (!unDerInt(payload, &valueSt.v, &parsedAttributeType))
                return NO;
            if (nextObjectExpecting(payload, &valueSt, FLAG_PRIMITIVE, BER_TAG_INTEGER) != OFASN1Success)
                return NO;
            if (!unDerInt(payload, &valueSt.v, &parsedAttributeVersion))
                return NO;
            if (nextObjectExpecting(payload, &valueSt, FLAG_PRIMITIVE, BER_TAG_OCTET_STRING) != OFASN1Success)
                return NO;
            attributeValueLocation = FIELD_CONTENTS_RANGE(valueSt);
            if (nextObject(payload, &valueSt) != OFASN1EndOfObject)
                return NO;
            
            callback(parsedAttributeType, parsedAttributeVersion, attributeValueLocation);
        }
        
        rc = exitObject(payload, &attrSt, &valueSt, NO);
    }
    
    /* Exit the outermost SEQUENCE */
    rc = exitObject(payload, &payloadSt, &attrSt, NO);
    if (rc != OFASN1EndOfObject)
        return NO;
    
    return YES;
}

#if TARGET_OS_IPHONE

/* This plucks the contents out of a PKCS#7 CMS object. On OSX, you should probably use the CMSDecoderCreate() API instead, but that API does not exist on iOS. This function does no checking of signatures or other crypto--- it simply unwraps the blob. Indefinite-length content isn't handled, either, though that could be fixed with a little work.
 
 From the ASN.1 module in RFC5652, a CMS message looks like this:
 
 SEQUENCE {
     contentType OBJECT IDENTIFIER (signedData, authenticatedData, etc.)
     cont[0] {
         -- Something depending on contentType. For signedData, we have this:
         SEQUENCE {
             version INTEGER,
             digestAlgorithms SET OF blah,
             encapContentInfo SEQUENCE {
                 contentType OBJECT IDENTIFIER
                 theActualFrigginData [0] EXPLICIT OCTET STRING
             }
         }
 
         -- Other outer contentTypes indicate other structures here, but we don't handle them.
     }
 }
 */

static uint8_t id_ct_signedData_der[]    = { 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02};  /* RFC 5652 aka PKCS#7 - 1.2.840.113549.1.7.2 */
// static uint8_t id_ct_data_der[]    = { 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01};  /* RFC 5652 aka PKCS#7 - 1.2.840.113549.1.7.1 */

static NSData *_pluckContents(NSData *pkcs7, NSData * __autoreleasing *contentType);

NSData *OFPKCS7PluckContents(NSData *pkcs7)
{
    return _pluckContents(pkcs7, NULL);
}

/* This attempts to return the contents of something. The walker state, on entry, should be pointing at the SEQUENCE which is either a ContentInfo or EncapsulatedContentInfo. */
static NSData *_pluckContents(NSData *pkcs7, NSData * __autoreleasing *contentType)
{
    struct asnWalkerState pkcs7St, inner1St, inner2St, inner3St, inner4St, inner5St;

    if (initializeWalker(pkcs7, &pkcs7St))
        return nil;
    
    if (!IS_TYPE(pkcs7St, FLAG_CONSTRUCTED, BER_TAG_SEQUENCE))
        return nil;
    if (enterObject(pkcs7, &pkcs7St, &inner1St))
        return nil;
    if (!IS_TYPE(inner1St, 0, BER_TAG_OID))
        return nil;
    const void *oidPtr = [pkcs7 bytes] + inner1St.v.content.location;
    size_t oidLen = inner1St.v.content.length;
    
    if (oidLen == sizeof(id_ct_signedData_der) &&
        !memcmp(oidPtr, id_ct_signedData_der, sizeof(id_ct_signedData_der))) {
        
         // advance to the cont[0]
        if (nextObjectExpecting(pkcs7, &inner1St, CLASS_CONTEXT_SPECIFIC | FLAG_CONSTRUCTED, 0))
            return nil;
        
        if (enterObject(pkcs7, &inner1St, &inner2St))  // point to the SignedData SEQUENCE
            return nil;
        if (!IS_TYPE(inner2St, FLAG_CONSTRUCTED, BER_TAG_SEQUENCE))
            return nil;
        if (enterObject(pkcs7, &inner2St, &inner3St))  // point to the first element of SignedData
            return nil;
        if (!IS_TYPE(inner3St, FLAG_PRIMITIVE, BER_TAG_INTEGER))
            return nil;
        if (nextObjectExpecting(pkcs7, &inner3St, FLAG_CONSTRUCTED, BER_TAG_SET)) // second element of SignedData
            return nil;
        if (nextObjectExpecting(pkcs7, &inner3St, FLAG_CONSTRUCTED, BER_TAG_SEQUENCE)) // third element of SignedData (EncapContentInfo)
            return nil;
        if (enterObject(pkcs7, &inner3St, &inner4St))
            return nil;
        if (!IS_TYPE(inner4St, FLAG_PRIMITIVE, BER_TAG_OID))
            return nil;
        if (contentType)
            *contentType = [pkcs7 subdataWithRange:inner4St.v.content];
        if (nextObjectExpecting(pkcs7, &inner4St, CLASS_CONTEXT_SPECIFIC | FLAG_CONSTRUCTED, 0))
            return nil;
        if (enterObject(pkcs7, &inner4St, &inner5St))
            return nil;
        if (!IS_TYPE(inner5St, FLAG_PRIMITIVE, BER_TAG_OCTET_STRING))
            return nil;
        
        return [pkcs7 subdataWithRange:inner5St.v.content];
    } else {
        /* Unknown */
        return nil;
    }
}

#endif

/* Convert a DER-encoded string to an NSString. Intended for the strings found in PKIX certificates. */
NSString *OFASN1UnDERString(NSData *derString)
{
    struct parsedTag tl;
    NSUInteger len = [derString length];
    enum OFASN1ErrorCodes rc = parseTagAndLength(derString, 0, len, &tl);
    if (rc != OFASN1Success || tl.content.location + tl.content.length != len || tl.indefinite || (tl.classAndConstructed & FLAG_CONSTRUCTED))
        return nil;
    
    NSData *contentData = [derString subdataWithRange:tl.content];
    
    switch (tl.tag) {
        case BER_TAG_PKIX_UTF8_STRING:
            return [NSString stringWithData:contentData encoding:NSUTF8StringEncoding];
            
        case BER_TAG_PKIX_BMP_STRING:
            /* This is declared to be the 16-bit subset of unicode, i.e., UCS-16, not UTF-16. That means that our parsing it as UTF-16 is technically wrong; we'll accept some invalid values. */
            return [NSString stringWithData:contentData encoding:NSUTF16BigEndianStringEncoding];
            
        case BER_TAG_PKIX_UNIVERSAL_STRING:
            return [NSString stringWithData:contentData encoding:NSUTF32BigEndianStringEncoding];
            
        case BER_TAG_IA5_STRING:
        case BER_TAG_ISO646_STRING: /* AKA VisibleString */
            /* ITU-T X.680-0207 [B.5.7] says: IA5String and VisibleString are mapped into UniversalString by mapping each character into the UniversalString character that has the identical (32-bit) value in the BER encoding of UniversalString as the (8-bit) value of the BER encoding of IA5String and VisibleString.
             This means they're the obvious subset of the first 256 Unicode codepoints, a.k.a Latin-1.
             Various codepoints are disallowed in these string types, but as with BMP_STRING, we go ahead and accept those invalid values.
             */
            return [NSString stringWithData:contentData encoding:NSISOLatin1StringEncoding];
            
        case BER_TAG_NUMERIC_STRING:
        case BER_TAG_PRINTABLE_STRING:
            /* ITU-T X.680-0207 [B.5.6] says:  The glyphs (printed character shapes) for characters used to form the types NumericString and PrintableString have recognizable and unambiguous mappings to a subset of the glyphs assigned to the first 128 characters of ISO/IEC 10646-1.
             The actual encoding is defined in X.690, which says: Where a character string type is specified in ITU-T Rec. X.680 | ISO/IEC 8824-1 by direct reference to an enumerating table (NumericString and PrintableString), the value of the octet string shall be that specified in 8.23.5 for a VisibleString type with the same character string value.
             So, basically, ASCII.
             */
            return [NSString stringWithData:contentData encoding:NSASCIIStringEncoding];
            
        /* Technically, we might want to support these, since T61String at least is used in older certificates (and possibly therefore some CA names). They are obsolete and being phased out, though. */
        // case BER_TAG_T61_STRING:
        // case BER_TAG_VIDEOTEX_STRING:
            
        /* These are some kind of encoding using shift characters to switch between code pages. */
        // case BER_TAG_GRAPHIC_STRING:
        // case BER_TAG_GENERAL_STRING:
            
        default:
            return nil;
    }
}

/* Convert an NSString to either a PRINTABLE STRING or a UTF8STRING, as appropriate */
NSData *OFASN1EnDERString(NSString *str)
{
    /* TODO: Apply stringprep profile from RFC4518, as mandated by RFC5280 [7.1] */
    /* Short of a real stringprep process, we just collapse all whitespace to U+0020,
     and normalize to NFKC. */
    NSCharacterSet *wspace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    str = [[[str stringByTrimmingCharactersInSet:wspace]
            stringByReplacingCharactersInSet:wspace withString:@" "]
           precomposedStringWithCompatibilityMapping]; /* Normalization form KC */
    
    NSMutableData *buf = [NSMutableData data];
    
    /* From the PKIX profile in RFC5280, page 19: we're supposed to emit only PrintableString (roughly ASCII) or UTF8String. */
    
    NSData *ASCIIish = [str dataUsingEncoding:NSASCIIStringEncoding];
    if (ASCIIish) {
        OFASN1AppendTagLength(buf, BER_TAG_PRINTABLE_STRING, [ASCIIish length]);
        [buf appendData:ASCIIish];
        return buf;
    }
    
    NSData *utf8 = [str dataUsingEncoding:NSUTF8StringEncoding];
    OFASN1AppendTagLength(buf, BER_TAG_PKIX_UTF8_STRING, [utf8 length]);
    [buf appendData:utf8];
    return buf;
}

/* Convert a DER-encoded OID to its conventional text representation (e.g. "1.3.12.42") */
NSString *OFASN1DescribeOID(const unsigned char *bytes, size_t len)
{
    if (!bytes)
        return nil;
    if (len < 1)
        return @"";
    
    // The first byte has a special encoding.
    unsigned int c0 = bytes[0] / 40;
    unsigned int c1 = bytes[0] % 40;
    
    NSMutableString *buf = [NSMutableString stringWithFormat:@"%u.%u", c0, c1];
    
    size_t p = 1;
    while(p < len) {
        size_t e = p;
        while(e < len && (bytes[e] & 0x80))
            e++;
        if (!(e < len)) {
            [buf appendString:@".*TRUNC"];
            break;
        } else {
            size_t nbytes = 1 + e - p;
            if (nbytes * 7 >= sizeof(unsigned long)*NBBY) {
                [buf appendString:@".*BIG"];
            } else {
                unsigned long value = 0;
                while(p <= e) {
                    value = ( value << 7 ) | ( bytes[p] & 0x7F );
                    p++;
                }
                [buf appendFormat:@".%lu", value];
            }
        }
    }
    
    return buf;
}

/* Convert a textual numeric OID to its DER-encoded form */
NSData *OFASN1OIDFromString(NSString *s)
{
    NSArray *parts = [s componentsSeparatedByString:@"."];
    NSUInteger partCount = [parts count];
    
    
    /* The first byte has a special encoding */
    unsigned first = [[parts objectAtIndex:0] unsignedIntValue];
    unsigned second = [[parts objectAtIndex:1] unsignedIntValue];
    if (first > 6 || second >= 40)
        return nil;
    
    /* The encoding can't be longer than its textual representation, so make a buffer that large */
    uint8_t *encoded = malloc([s length]);
    size_t encodedLen = 0;
    encoded[encodedLen++] = (uint8_t)(( first * 40 ) + second);
    
    /* The rest have a ULEB128-style encoding */
    for(NSUInteger ix = 2; ix < partCount; ix ++) {
        unsigned part = [[parts objectAtIndex:ix] unsignedIntValue];
        uint8_t inner[ (sizeof(part)*8 + 6)/7 ];
        int innerix = 0;
        do {
            inner[innerix++] = 0x7F & part;
            part >>= 7;
        } while (part);
        while (innerix > 1) {
            encoded[encodedLen++] = 0x80 | inner[--innerix];
        };
        encoded[encodedLen++] = inner[0];
    }
    
    NSMutableData *result = [NSMutableData data];
    OFASN1AppendTagLength(result, BER_TAG_OID, encodedLen);
    [result appendBytes:encoded length:encodedLen];
    free(encoded);
    return result;
}

/*" Formats the tag byte and length field of an ASN.1 item and appends the result to the passed-in buffer. Currently the 'tag' is the whole tag+class+constructed field--- we don't handle multibyte tags at all (since they don't appear in any PKIX structures). "*/
void OFASN1AppendTagLength(NSMutableData *buffer, uint8_t tag, NSUInteger byteCount)
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
    
    OBASSERT(bufUsed == OFASN1SizeOfTagLength(tag, byteCount));
    
    [buffer appendBytes:buf length:bufUsed];
}

unsigned int OFASN1SizeOfTagLength(uint8_t tag, NSUInteger byteCount)
{
    unsigned int bufUsed;
    
    bufUsed = 1;
    
    if (byteCount < 128) {
        /* Short lengths have a 1-byte direct representation */
        return bufUsed + 1;
    } else {
        /* Longer lengths have a count-and-value representation */
        uint_fast8_t n;
        uint8_t bytebuf[8];
        memset(bytebuf, 0, sizeof(bytebuf)); /// Redundant memset, but apparently clang analyze doesn't understand OSWriteLittleInt64()
        OSWriteLittleInt64(bytebuf, 0, byteCount);
        n = 7;
        while (bytebuf[n] == 0) {
            n--;
        }
        return bufUsed + 2 + n;
    }
}

NSMutableData *OFASN1AppendStructure(NSMutableData *buffer, const char *fmt, ...)
{
    struct piece {
        unsigned tagAndClass;
        size_t length;
        const uint8_t *rawBytes;
        NSData * __unsafe_unretained obj;
        
        size_t contentLength;
        int container;
        int lastContent;
        int stuffing;
    } *pieces;
    
    /* As an upper bound, there are as many pieces as characters in the format string */
    pieces = malloc(sizeof(*pieces) * strlen(fmt));
    
    int lastOpen = -1;
    int pieceCount = 0;
    const char *cp = fmt;
    
    va_list argList;
    va_start(argList, fmt);
    for (;;) {
        int tag = 0;
        BOOL stuffByte;
        
        if (!*cp)
            break;
        
        if (*cp == '!') {
            tag = va_arg(argList, int);
            cp++;
        } else {
            tag = 0;
        }
        
        switch(*cp) {
            case ' ':
                break;
            case 'd':
            {
                NSData * __unsafe_unretained obj = va_arg(argList, NSData * __unsafe_unretained);
                pieces[pieceCount++] = (struct piece){
                    .tagAndClass = 0,
                    .length = [obj length],
                    .rawBytes = NULL,
                    .obj = obj,
                    
                    .container = -1,
                    .lastContent = -1
                };
            }
                break;
                
            case '*':
            {
                size_t len = va_arg(argList, size_t);
                const uint8_t *buf = va_arg(argList, const uint8_t *);
                
                pieces[pieceCount++] = (struct piece){
                    .tagAndClass = 0,
                    .length = len,
                    .rawBytes = buf,
                    .obj = NULL,
                    
                    .container = -1,
                    .lastContent = -1
                };
            }
                break;
                
            case '(':
                if (!tag)
                    tag = BER_TAG_SEQUENCE | FLAG_CONSTRUCTED;
                stuffByte = NO;
                goto beginConstructed;
            case '{':
                if (!tag)
                    tag = BER_TAG_SET | FLAG_CONSTRUCTED;
                stuffByte = NO;
                goto beginConstructed;
            case '[':
                if (!tag)
                    tag = BER_TAG_OCTET_STRING;
                stuffByte = NO;
                goto beginConstructed;
            case '<':
                if (!tag)
                    tag = BER_TAG_BIT_STRING;
                stuffByte = YES;
                goto beginConstructed;
                
            beginConstructed:
                pieces[pieceCount] = (struct piece){
                    .tagAndClass = tag,
                    .length = 0,
                    .rawBytes = NULL,
                    .obj = nil,
                    
                    .container = lastOpen,
                    .lastContent = -1,
                    .stuffing = stuffByte? 1 : 0
                };
                lastOpen = pieceCount;
                pieceCount ++;
                break;

            case ')':
            case '}':
            case ']':
            case '>':
                assert(lastOpen >= 0);
                assert(pieceCount > lastOpen);
                pieces[lastOpen].lastContent = pieceCount-1;
                lastOpen = pieces[lastOpen].container;
                break;
                
            default:
                abort();
        }
        
        cp++;
    }
    va_end(argList);

    /* Run through backwards to compute lengths */
    size_t totalLength = 0;
    for (int pieceIndex = pieceCount-1; pieceIndex >= 0; pieceIndex --) {
        if (pieces[pieceIndex].tagAndClass) {
            size_t summedLength = 0;
            for (int ci = pieceIndex+1; ci <= pieces[pieceIndex].lastContent; ci++) {
                summedLength += pieces[ci].length;
            }
            pieces[pieceIndex].contentLength = summedLength;
            pieces[pieceIndex].length = OFASN1SizeOfTagLength(pieces[pieceIndex].tagAndClass, summedLength + pieces[pieceIndex].stuffing) + pieces[pieceIndex].stuffing;
        }
        totalLength += pieces[pieceIndex].length;
    }
    
    /* And accumulate everything into the supplied buffer */
    if (!buffer)
        buffer = [NSMutableData dataWithCapacity:totalLength];
    
    for (int pieceIndex = 0; pieceIndex < pieceCount; pieceIndex ++) {
        if (pieces[pieceIndex].tagAndClass) {
            OFASN1AppendTagLength(buffer, pieces[pieceIndex].tagAndClass, pieces[pieceIndex].contentLength + pieces[pieceIndex].stuffing);
            if (pieces[pieceIndex].stuffing)
                [buffer appendBytes:"" length:1];
        } else if (pieces[pieceIndex].rawBytes) {
            [buffer appendBytes:pieces[pieceIndex].rawBytes length:pieces[pieceIndex].length];
        } else {
            [buffer appendData:pieces[pieceIndex].obj];
        }
    }

    free(pieces);
    
    return buffer;
}
