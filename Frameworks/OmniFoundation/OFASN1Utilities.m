// Copyright 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/NSString-OFConversion.h>

RCS_ID("$Id$");

enum OFASN1ErrorCodes {
    OFASN1Success,
    OFASN1EndOfObject,
    OFASN1Truncated,
    OFASN1TagOverflow,
    OFASN1LengthOverflow,
    OFASN1InconsistentEncoding,
    OFASN1UnexpectedType,
};

#define CLASS_MASK             0xC0
#define CLASS_UNIVERSAL        0x00
#define CLASS_APPLICATION      0x40
#define CLASS_CONTEXT_SPECIFIC 0x80
#define CLASS_CONSTRUCTED      0x20  /* Not technically a class */

#ifndef BER_TAG_SEQUENCE

#define BER_TAG_UNKNOWN 0
#define BER_TAG_BOOLEAN 1
#define BER_TAG_INTEGER 2
#define BER_TAG_BIT_STRING 3
#define BER_TAG_OCTET_STRING 4
#define BER_TAG_NULL 5
#define BER_TAG_OID 6
#define BER_TAG_OBJECT_DESCRIPTOR 7
#define BER_TAG_EXTERNAL 8
#define BER_TAG_REAL 9
#define BER_TAG_ENUMERATED 10
#define BER_TAG_PKIX_UTF8_STRING 12
#define BER_TAG_SEQUENCE 16
#define BER_TAG_SET 17
#define BER_TAG_NUMERIC_STRING 18
#define BER_TAG_PRINTABLE_STRING 19
#define BER_TAG_T61_STRING 20
#define BER_TAG_VIDEOTEX_STRING 21
#define BER_TAG_IA5_STRING 22
#define BER_TAG_UTC_TIME 23
#define BER_TAG_GENERALIZED_TIME 24
#define BER_TAG_GRAPHIC_STRING 25
#define BER_TAG_ISO646_STRING 26
#define BER_TAG_GENERAL_STRING 27
#define BER_TAG_VISIBLE_STRING BER_TAG_ISO646_STRING
#define BER_TAG_PKIX_UNIVERSAL_STRING 28
#define BER_TAG_PKIX_BMP_STRING 30

#endif

struct parsedTag {
    unsigned short tag;                 // tag
    uint8_t classAndConstructed;         // class and constructed flags bits from first octet
    BOOL indefinite;
    NSUInteger contentStartIndex;
    NSUInteger contentLength;
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
    
    if (where + 2 >= maxIndex) {
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
        outTL->contentStartIndex = lengthStartIndex+1;
        outTL->contentLength = buf[1];
        return OFASN1Success;
    } else if (buf[1] == 0x80) {
        /* Indefinite-length object. */
        if (!(outTL->classAndConstructed & 0x20)) {
            /* A non-constructed, indefinite-length object doesn't make any sense */
            return OFASN1InconsistentEncoding;
        }
        
        outTL->indefinite = YES;
        outTL->contentStartIndex = lengthStartIndex+1;
        outTL->contentLength = 0;
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
        outTL->contentStartIndex = lengthStartIndex + 1 + lengthLength;
        outTL->contentLength = extractedLength;
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
        NSLog(@"Next object: pos=%lu cc=%02X tag=0x%X len=%lu", where, outTL->classAndConstructed, outTL->tag, outTL->contentLength);
    }
    return rc;
}
#endif

static enum OFASN1ErrorCodes initializeWalker(NSData *buffer, struct asnWalkerState *st)
{
    *st = (struct asnWalkerState){
        .startPosition = 0,
        .maxIndex = [buffer length],
        .containerIsIndefinite = NO
    };
    
    return parseTagAndLength(buffer, 0, st->maxIndex, &(st->v));
}

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
        return objectAt(buffer, st->v.contentStartIndex + st->v.contentLength, st);
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

static BOOL isSentinelObject(struct parsedTag *v)
{
    return (v->tag == 0 && v->classAndConstructed == 0 && !v->indefinite);
}

static enum OFASN1ErrorCodes enterObject(NSData *buffer, struct asnWalkerState *containerState, struct asnWalkerState *innerState)
{
    if (!(containerState->v.classAndConstructed & CLASS_CONSTRUCTED)) {
        return OFASN1UnexpectedType;
    }
    
    innerState->startPosition = containerState->v.contentStartIndex;
    if (containerState->v.indefinite) {
        innerState->containerIsIndefinite = YES;
        innerState->maxIndex = containerState->maxIndex;
    } else {
        innerState->containerIsIndefinite = NO;
        assert(containerState->v.contentStartIndex + containerState->v.contentLength <= containerState->maxIndex);
        innerState->maxIndex = containerState->v.contentStartIndex + containerState->v.contentLength;
    }
    
    return parseTagAndLength(buffer, innerState->startPosition, innerState->maxIndex, &(innerState->v));
}

static enum OFASN1ErrorCodes exitObject(NSData *buffer, struct asnWalkerState *containerState, struct asnWalkerState *innerState, BOOL allowTrailing)
{
    NSUInteger nextReadPosition;
    enum OFASN1ErrorCodes rc;
    
    if (innerState->containerIsIndefinite) {
        OBASSERT(containerState->v.indefinite);
        for(;;) {
            if (isSentinelObject(&(innerState->v))) {
                /* The expected case: our current object is the end marker */
                nextReadPosition = innerState->v.contentStartIndex + innerState->v.contentLength;
                /* Update our contentLength (which is initially 0/undefined for an indefinite object) to be the actual content length including sentinel */
                innerState->v.contentLength = nextReadPosition - innerState->v.contentStartIndex;
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
        /* Our inner state's contentLength is valid: either it's definite-length, or we updated its indefinite length when we exited its contents. */
        nextReadPosition = innerState->v.contentStartIndex + innerState->v.contentLength;
        NSUInteger positionAfterContainer = containerState->v.contentStartIndex + containerState->v.contentLength;
        
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

#define IS_TYPE(st, cls, tagnumber) (st.v.classAndConstructed == (cls) && st.v.tag == (tagnumber))
#define EXPECT_TYPE(st, cls, tagnumber) if (!IS_TYPE(st, cls, tagnumber)) { return OFASN1UnexpectedType; }
#define EXPLICIT_TAGGED(st, tagnumber) (st.v.classAndConstructed == (CLASS_CONTEXT_SPECIFIC|CLASS_CONSTRUCTED) && st.v.tag == (tagnumber))
#define IMPLICIT_TAGGED(st, tagnumber) ((st.v.classAndConstructed & CLASS_MASK) == CLASS_CONTEXT_SPECIFIC && st.v.tag == (tagnumber))
#define DER_FIELD_RANGE(walker) ((NSRange){ walker.startPosition, walker.v.contentLength + ( walker.v.contentStartIndex - walker.startPosition)})
#define FIELD_CONTENTS_RANGE(walker) ((NSRange){ walker.v.contentStartIndex, walker.v.contentLength })

#define ADVANCE(buf, walker) do{ rc = nextObject(buf, &walker); if (rc) return rc; }while(0)

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
#if 0
            if (keyAlgorithmOID != NULL) {
                struct asnWalkerState spkiFields;
                rc = enterObject(cert, &tbsFields, &spkiFields);
                if (rc)
                    return rc;
                
                /* First element should be the key's algorithm identifier, another SEQUENCE */
                EXPECT_TYPE(spkiFields, 0x20, 0x10);
                {
                    struct asnWalkerState algidFields;
                    rc = enterObject(cert, &spkiFields, &algidFields);
                    if (rc)
                        return rc;
                    
                    /* First element in that is the OID */
                    EXPECT_TYPE(algidFields, 0x00, 0x06);
                    *keyAlgorithmOID = [cert subdataWithRange:FIELD_CONTENTS_RANGE(tbsFields)];
                    
                    rc = exitObject(cert, &spkiFields, &algidFields, YES);
                    if (rc)
                        return rc;
                }
                
                /* Second element is the subject public key itself */
                EXPECT_TYPE(spkiFields, 0x00, 0x03);
                ADVANCE(cert, spkiFields);
                
                rc = exitObject(cert, &tbsFields, &spkiFields, NO);
                if (rc)
                    return rc;
            }
#endif
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
                            if(extn.v.contentLength != 1)
                                return NO;
                            uint8_t flagBits;
                            [cert getBytes:&flagBits range:(NSRange){ extn.v.contentStartIndex, 1 }];
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
                        /* First byte of an OCTET STRING is the number of unused bits; we can't handle nonzero values there */
                        if (extnRange.length < 1)
                            return NO;
                        uint8_t unusedBits;
                        [cert getBytes:&unusedBits range:(NSRange){ extnRange.location, 1 }];
                        if (unusedBits != 0)
                            return 0;
                        
                        extensions_cb([cert subdataWithRange:extnOid], extensionIsCritical, [cert subdataWithRange:(NSRange){ extnRange.location + 1, extnRange.length - 1 }]);
                        
                        rc = exitObject(cert, &extns, &extn, YES);
                    }
                    // Exit the SEQUENCE
                    rc = exitObject(cert, &inExplicitTag, &extns, NO);
                    if (rc)
                        return rc;
                    // Exit the tag
                    rc = exitObject(cert, &tbsFields, &inExplicitTag, NO);
                    if (rc)
                        return rc;
                    
                } else {
                    /* Caller is not interested in extensions; skip them */
                    ADVANCE(cert, tbsFields);
                }
            }
            
            // Exit the TBSCertificate
            rc = exitObject(cert, &signatureFields, &tbsFields, YES);
            if (rc)
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
 
 */

BOOL OFASN1EnumerateAVAsInName(NSData *rdnseq, void (^callback)(NSData *a, NSData *v, unsigned ix, BOOL *stop))
{
    enum OFASN1ErrorCodes rc;
    struct asnWalkerState nameSt, rdnSt, avasSt, avaSt;
    
    rc = initializeWalker(rdnseq, &nameSt);
    if (rc)
        return NO;
    
    if (!IS_TYPE(nameSt, CLASS_CONSTRUCTED, BER_TAG_SEQUENCE))
        return NO;
    
    /* Enter the outermost SEQUENCE */
    rc = enterObject(rdnseq, &nameSt, &rdnSt);
    while (rc != OFASN1EndOfObject) {
        if (rc != OFASN1Success)
            return NO;
        
        if (!IS_TYPE(rdnSt, CLASS_CONSTRUCTED, BER_TAG_SET))
            return NO;
        
        unsigned indexWithinRDN = 0;
        
        /* Enter the SET of individual AVAs */
        rc = enterObject(rdnseq, &rdnSt, &avasSt);
        while (rc != OFASN1EndOfObject) {
            if (rc != OFASN1Success)
                return NO;
            
            /* Enter the SEQUENCE which is just the 2-tuple of attribute and value */
            if (!IS_TYPE(avasSt, CLASS_CONSTRUCTED, BER_TAG_SEQUENCE))
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

NSString *OFASN1UnDERString(NSData *derString)
{
    struct parsedTag tl;
    NSUInteger len = [derString length];
    enum OFASN1ErrorCodes rc = parseTagAndLength(derString, 0, len, &tl);
    if (rc != OFASN1Success || tl.contentStartIndex + tl.contentLength != len || tl.indefinite || (tl.classAndConstructed & CLASS_CONSTRUCTED))
        return nil;
    
    NSRange contentRange = {
        .location = tl.contentStartIndex,
        .length = tl.contentLength
    };
    NSData *contentData = [derString subdataWithRange:contentRange];
    
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
            
            /* Technically, we might want to support these, since T61String at least is used in older certificates (and possibly therefore some CA names). */
            // case BER_TAG_T61_STRING:
            // case BER_TAG_VIDEOTEX_STRING:
            
            /* These are some kind of encoding using shift characters to switch between code pages. */
            // case BER_TAG_GRAPHIC_STRING:
            // case BER_TAG_GENERAL_STRING:
            
        default:
            return nil;
    }
}

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

