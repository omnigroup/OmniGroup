// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFASN1-Internal.h>
#import <OmniFoundation/OFSecurityUtilities.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import "GeneratedOIDs.h"
#import <OmniBase/rcsid.h>

#import <Security/Security.h>

RCS_ID("$Id$");

struct asnWalkerState {
    NSUInteger startPosition;        // The position at which 'v' was parsed
    struct parsedTag v;              // Tag and length of the "current" object
    NSUInteger maxIndex;             // The end of the innermost definite-length object containing us (or the data buffer itself)
    BOOL containerIsIndefinite;      // YES if our immediate container is indefinite
    BOOL requireDER;                 // YES to forbid some BER-only constructs
};

static enum OFASN1ErrorCodes nextObject(NSData *buffer, struct asnWalkerState *st);
static enum OFASN1ErrorCodes objectAt(NSData *buffer, NSUInteger pos, struct asnWalkerState *st);
static enum OFASN1ErrorCodes enterObject(NSData *buffer, struct asnWalkerState *containerState, struct asnWalkerState *innerState);
static enum OFASN1ErrorCodes exitObject(NSData *buffer, struct asnWalkerState *containerState, struct asnWalkerState *innerState, BOOL allowTrailing);

static NSDateComponents *OFASN1UnDERDateContents(NSData *buf, const struct parsedTag *v);
static enum OFASN1ErrorCodes parseIdentifierAndValue(NSData *buf, struct asnWalkerState *stx, NSRange *outOIDRange, NSRange *outParameterRange);

#define MAX_BER_INDEFINITE_OBJECT_DEPTH 127 // Arbitrary. In practice we should never exceed a half-dozen or so.

static const CFStringRef asn1ErrorCodeStrings[] = {
#define E(x) [ OFASN1 ## x ] = CFSTR( #x )
    E(Success),
    E(EndOfObject),
    E(Truncated),
    E(TagOverflow),
    E(LengthOverflow),
    E(InconsistentEncoding),
    E(UnexpectedType),
    E(UnexpectedIndefinite),
    E(TrailingData)
#undef E
};

enum OFASN1ErrorCodes OFASN1ParseTagAndLength(NSData *buffer, NSUInteger where, NSUInteger maxIndex, BOOL requireDER, struct parsedTag *outTL)
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
        if (requireDER)
            return OFASN1UnexpectedType;
        
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
        
        /* Indefinite lengths are forbidden in DER */
        if (requireDER)
            return OFASN1UnexpectedIndefinite;
        
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
#define parseTagAndLength OFASN1ParseTagAndLength


/* Set up the outermost walker state, and leave it pointing at the first (usually only) object in the buffer */
static enum OFASN1ErrorCodes initializeWalkerAt(NSData *buffer, BOOL requireDER, struct asnWalkerState *st, NSUInteger location, NSUInteger length)
{
    *st = (struct asnWalkerState){
        .startPosition = location,
        .maxIndex = location + length,
        .containerIsIndefinite = NO,
        .requireDER = requireDER
    };
    
    return parseTagAndLength(buffer, location, st->maxIndex, st->requireDER, &(st->v));
}

static enum OFASN1ErrorCodes initializeWalker(NSData *buffer, BOOL requireDER, struct asnWalkerState *st)
{
    return initializeWalkerAt(buffer, requireDER, st, 0, [buffer length]);
}

/* Assuming the walker is pointing at a BIT STRING, start a sub-walker pointing at the ASN.1 encoded object inside the BIT STRING (as if the BIT STRING were a SEQUENCE or other container) */
static enum OFASN1ErrorCodes enterBitString(NSData *buffer, const struct asnWalkerState *st, struct asnWalkerState *innerSt)
{
    if (st->v.classAndConstructed != (CLASS_UNIVERSAL|FLAG_PRIMITIVE) ||
        st->v.tag != BER_TAG_BIT_STRING ||
        st->v.content.length < 1)
        return OFASN1UnexpectedType;
    
    uint8_t unusedBits;
    [buffer getBytes:&unusedBits range:(NSRange){ st->v.content.location, 1 }];
    if (unusedBits != 0) {
        /* A DER-encoded BIT STRING containing another DER-encoded value will never have any unused bits, because DER always encodes to a whole number of octets */
        return OFASN1UnexpectedType;
    }
    
    *innerSt = (struct asnWalkerState){
        .startPosition = st->v.content.location + 1,
        .maxIndex = st->v.content.location + st->v.content.length,
        .containerIsIndefinite = NO,
        .requireDER = st->requireDER
    };
    
    return parseTagAndLength(buffer, innerSt->startPosition, innerSt->maxIndex, innerSt->requireDER, &(innerSt->v));
}

/* Advance the walker to the next object */
static enum OFASN1ErrorCodes nextObject(NSData *buffer, struct asnWalkerState *st)
{
    if (st->v.indefinite) {
        NSUInteger pos;
        enum OFASN1ErrorCodes rc = OFASN1IndefiniteObjectExtent(buffer, st->v.content.location, st->maxIndex, &pos);
        if (rc)
            return rc;
        // Update the state info as if we'd called enterObject/exitObject.
        st->v.content.length = pos - st->v.content.location;
        return objectAt(buffer, pos, st);
    } else {
        return objectAt(buffer, NSMaxRange(st->v.content), st);
    }
}

/* Similar to nextObject(), but sets the walker to a particular position within its container */
static enum OFASN1ErrorCodes objectAt(NSData *buffer, NSUInteger pos, struct asnWalkerState *st)
{
    if (pos == st->maxIndex && !st->containerIsIndefinite) {
        return OFASN1EndOfObject;
    } else if (pos >= st->maxIndex) {
        return OFASN1Truncated;
    } else {
        enum OFASN1ErrorCodes rc = parseTagAndLength(buffer, pos, st->maxIndex, st->requireDER, &(st->v));
        st->startPosition = pos;
        return rc;
    }
}

static BOOL isSentinelObject(const struct parsedTag *v)
{
    return (v->tag == 0 && v->classAndConstructed == 0 && !v->indefinite);
}

enum OFASN1ErrorCodes OFASN1IndefiniteObjectExtent(NSData *buf, NSUInteger position, NSUInteger maxIndex, NSUInteger *outEndPos)
{
    enum OFASN1ErrorCodes rc;
    unsigned depth = 0;
    
    for (;;) {
        struct parsedTag t;
        rc = parseTagAndLength(buf, position, maxIndex, NO, &t);
        if (rc) {
            if (rc == OFASN1EndOfObject)
                rc = OFASN1Truncated;
            return rc;
        }
        
        if (isSentinelObject(&t)) {
            if (depth == 0) {
                *outEndPos = NSMaxRange(t.content);
                return OFASN1Success;
            } else {
                depth --;
                position = NSMaxRange(t.content);
            }
        } else if (!t.indefinite) {
            position = NSMaxRange(t.content);
        } else {
            // An embedded indefinite object.
            depth ++;
            if (depth > MAX_BER_INDEFINITE_OBJECT_DEPTH)
                return OFASN1LengthOverflow;
            position = t.content.location;
        }
    }
}

/* Similar to nextObject(), but returns an error if the new pointed-to object is not of the expected type */
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
    innerState->requireDER = containerState->requireDER;
    
    return parseTagAndLength(buffer, innerState->startPosition, innerState->maxIndex, innerState->requireDER, &(innerState->v));
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
    
        if (positionAfterContainer < nextReadPosition)
            return OFASN1InconsistentEncoding;

        if (!allowTrailing) {
            /* Make sure the object we just read was the last one in the container. */
            if (positionAfterContainer != nextReadPosition)
                return OFASN1UnexpectedType;
        }
        
        nextReadPosition = positionAfterContainer;
    }
    
    return objectAt(buffer, nextReadPosition, containerState);
}

/* Some macros for using the walker functions */

#define IS_TYPE(st, cls, tagnumber) ((st).v.classAndConstructed == (cls) && (st).v.tag == (tagnumber))
#define EXPECT_TYPE(st, cls, tagnumber) if (!IS_TYPE((st), (cls), (tagnumber))) { return OFASN1UnexpectedType; }
#define EXPLICIT_TAGGED(st, tagnumber) (st.v.classAndConstructed == (CLASS_CONTEXT_SPECIFIC|FLAG_CONSTRUCTED) && st.v.tag == (tagnumber))
#define IMPLICIT_TAGGED(st, tagnumber) ((st.v.classAndConstructed & CLASS_MASK) == CLASS_CONTEXT_SPECIFIC && st.v.tag == (tagnumber))
#define DER_FIELD_RANGE(walker) ((NSRange){ (walker).startPosition, (walker).v.content.length + ( (walker).v.content.location - (walker).startPosition)})
#define FIELD_CONTENTS_RANGE(walker) ((walker).v.content)

#define ADVANCE(buf, walker) do{ rc = nextObject(buf, &(walker)); if (rc) return rc; }while(0)
#define ADVANCE_E(buf, walker) do{ rc = nextObject(buf, &(walker)); if (rc != OFASN1Success && rc != OFASN1EndOfObject) return rc; }while(0)

#pragma mark Generic SEQUENCE scanner

enum OFASN1ErrorCodes OFASN1ParseBERSequence(NSData *buf, NSUInteger position, NSUInteger endPosition, BOOL requireDER, const struct scanItem *items, struct parsedItem *found, unsigned count)
{
    BOOL containerIsIndefinite;
    
    if (endPosition > 0) {
        containerIsIndefinite = NO;
    } else {
        endPosition = [buf length];
        containerIsIndefinite = YES;
    }
    
    enum OFASN1ErrorCodes rc;
    struct parsedTag tagBuf;
    unsigned itemIndex = 0;
    
    for (;;) {
        if (position == endPosition) {
            rc = OFASN1EndOfObject;
        } else {
            rc = parseTagAndLength(buf, position, endPosition, requireDER, &tagBuf);
        }
        if (rc == OFASN1EndOfObject) {
            if (containerIsIndefinite) {
                return OFASN1Truncated; // Should have seen an end object before running out of data!
            } else {
                // We've reached the end of the input; exit the loop.
                break;
            }
        }
        if (rc != OFASN1Success) {
            return rc;
        }
        
        // See if we're pointing at the end-of-indefinite-length-encoding sentinel object
        if (isSentinelObject(&tagBuf)) {
            if (!containerIsIndefinite) {
                return OFASN1InconsistentEncoding; // Not expecting a sentinel in a definite-length container
            }
            position = NSMaxRange(tagBuf.content);
            // We've reached the end of the input; exit the loop.
            // rc = OFASN1EndOfObject;
            break;
        }
        
        // Find the length of the object and the offset of the next object. This can be complex if the object is of indefinite length.
        NSUInteger nextPosition;
        if (!tagBuf.indefinite) {
            nextPosition = NSMaxRange(tagBuf.content);
        } else {
            // Need to traverse the object to find its length. This is less efficient than using an asnWalkerState because anyone using this object will end up having to traverse it again. But for most of our situations the structure can't be too deep.
            NSUInteger endPos = 0;
            rc = OFASN1IndefiniteObjectExtent(buf, tagBuf.content.location, endPosition, &endPos);
            if (rc)
                return rc;
            tagBuf.content.length = (endPos - BER_SENTINEL_LENGTH) - tagBuf.content.location;
            nextPosition = endPos;
        }
        
        /* Check whether the item we found matches the next item in the caller's list, skipping over optionals as needed. */
        for (;;) {
            if (!(itemIndex < count)) {
                // We've reached the end of our item list without running out of items in the incoming data.
                return OFASN1TrailingData;
            }
            
            if ((items[itemIndex].flags & FLAG_ANY_OBJECT) ||
                (tagBuf.classAndConstructed == (items[itemIndex].flags & FLAG_BER_MASK) &&
                 tagBuf.tag == items[itemIndex].tag)) {
                // The scanned item matches what we expect.
                found[itemIndex].startPosition = position;
                found[itemIndex].i = tagBuf;
                itemIndex ++;
                break;
            } else if (items[itemIndex].flags & FLAG_OPTIONAL) {
                // This is an optional item; advance past it.
                found[itemIndex].startPosition = position;
                found[itemIndex].i = (struct parsedTag){ 0, FLAG_OPTIONAL, NO, { 0, 0 } };
                itemIndex ++;
            } else {
                return OFASN1UnexpectedType;
            }
        }
        
        position = nextPosition;
    }
    
    // We've reached the end of our input. Make sure that any remaining items in the scan list are optional, and zero out their result buffers.
    while (itemIndex < count) {
        if (!(items[itemIndex].flags & FLAG_OPTIONAL)) {
            // Whoops. Non-optional item missing from the end of the sequence.
            return OFASN1UnexpectedType;
        }
        
        found[itemIndex].startPosition = position;
        found[itemIndex].i = (struct parsedTag){ 0, FLAG_OPTIONAL, NO, { 0, 0 } };
        itemIndex ++;
    }
    
    return OFASN1Success;
}

#pragma mark - ASN.1 scanning and creation utility functions

int OFASN1CertificateExtractFields(NSData *cert, NSData **serialNumber, NSData **issuer, NSData **subject, NSArray **validity, NSData **subjectKeyInformation, void (^extensions_cb)(NSData *oid, BOOL critical, NSData *value))
{
    enum OFASN1ErrorCodes rc;
    struct asnWalkerState stx;
    
    rc = initializeWalker(cert, YES, &stx);
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
            
            /* Validity is a SEQUENCE of two dates */
            EXPECT_TYPE(tbsFields, 0x20, 0x10);
            if (validity) {
                struct asnWalkerState validityFields;
                rc = enterObject(cert, &tbsFields, &validityFields);
                if (rc)
                    return rc;
                NSDate *bounds[2];
                bounds[0] /* notBefore */ = OFASN1UnDERDateContents(cert, &(validityFields.v)).date;
                ADVANCE(cert, validityFields);
                bounds[1] /* notAfter */  =  OFASN1UnDERDateContents(cert, &(validityFields.v)).date;
                if (!bounds[0] || !bounds[1])
                    return OFASN1UnexpectedType;
                *validity = [NSArray arrayWithObjects:bounds count:2];
            }
            ADVANCE(cert, tbsFields);
            
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
            
            /* The SubjectPublicKeyInfo is the last mandatory field; from here on, OFASN1EndOfObject is not an error */
            ADVANCE_E(cert, tbsFields);
            
            /* Skip the optional IMPLICIT-tagged issuerUniqueID, if it's there */
            if (rc == OFASN1Success && IMPLICIT_TAGGED(tbsFields, 1)) {
                ADVANCE_E(cert, tbsFields);
            }
            
            /* Skip the optional IMPLICIT-tagged subjectUniqueID, if it's there */
            if (rc == OFASN1Success && IMPLICIT_TAGGED(tbsFields, 2)) {
                ADVANCE_E(cert, tbsFields);
            }
            
            /* The extensions array, oddly, is explicitly tagged, not implicitly */
            if (rc == OFASN1Success && EXPLICIT_TAGGED(tbsFields, 3)) {
                
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
                    ADVANCE_E(cert, tbsFields);
                }
            }
            
            // Exit the TBSCertificate
            rc = exitObject(cert, &signatureFields, &tbsFields, YES);
            if (rc)
                return rc;
        }
        
        /* Still remaining in the Certificate are the signature algorithm identifier and the signature itself: we don't care what they contain, but let's validate that they exist. */
        /* (This function is also used as a very simple validity check for certificates, because SecCertificate will accept some forms of garbage and then crash later: see RADAR 7514859) */
        
        /* AlgorithmIdentifier is a SEQUENCE starting with an OID */
        EXPECT_TYPE(signatureFields, 0x20, 0x10); /* SEQUENCE*/
        {
            struct asnWalkerState algIdFields;
            rc = enterObject(cert, &signatureFields, &algIdFields);
            if (rc)
                return rc;
            
            EXPECT_TYPE(algIdFields, 0x00, BER_TAG_OID);
            
            rc = exitObject(cert, &signatureFields, &algIdFields, YES);
            if (rc)
                return rc;
        }
        
        /* The signature bitstring itself */
        EXPECT_TYPE(signatureFields, 0x00, BER_TAG_BIT_STRING);
        
        rc = nextObject(cert, &stx);
        if (rc != OFASN1EndOfObject)
            return ( rc? rc : OFASN1UnexpectedType );
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
    
    rc = initializeWalker(rdnseq, YES, &nameSt);
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
    
    rc = initializeWalker(payload, NO, &payloadSt);
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
            int parsedAttributeType;
            int parsedAttributeVersion;
            NSRange attributeValueLocation;
            
            if (OFASN1UnDERSmallInteger(payload, &valueSt.v, &parsedAttributeType) != OFASN1Success)
                return NO;
            if (nextObjectExpecting(payload, &valueSt, FLAG_PRIMITIVE, BER_TAG_INTEGER) != OFASN1Success)
                return NO;
            if (OFASN1UnDERSmallInteger(payload, &valueSt.v, &parsedAttributeVersion) != OFASN1Success)
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

    if (initializeWalker(pkcs7, NO, &pkcs7St))
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

int OFASN1ParseAlgorithmIdentifier(NSData *buf, BOOL expectTrailing, enum OFASN1Algorithm *outAlg, NSRange *outParameterRange)
{
    NSRange oidRange;
    int rc = OFASN1ParseIdentifierAndParameter(buf, expectTrailing, &oidRange, outParameterRange);
    if (rc)
        return rc;
    *outAlg = OFASN1LookUpOID(OFASN1Algorithm, [buf bytes] + oidRange.location, oidRange.length);
    return 0;
}

int OFASN1ParseIdentifierAndParameter(NSData *buf, BOOL expectTrailing, NSRange *outOIDRange, NSRange *outParameterRange)
{
    enum OFASN1ErrorCodes rc;
    struct asnWalkerState stx;
    rc = initializeWalker(buf, YES, &stx);
    if (rc)
        return rc;
    if (!expectTrailing && stx.maxIndex != NSMaxRange(stx.v.content))
        return OFASN1TrailingData;
    rc = parseIdentifierAndValue(buf, &stx, outOIDRange, outParameterRange);
    if (expectTrailing) {
        if (rc == OFASN1EndOfObject)
            return OFASN1Truncated;
    } else {
        if (rc == OFASN1EndOfObject)
            return OFASN1Success;
        else if (rc == OFASN1Success)
            return OFASN1TrailingData;
    }
    
    return rc;
}

/** Parses a structure of the form SEQUENCE { OBJECT IDENTIFIER, ANY OPTIONAL } */
static enum OFASN1ErrorCodes parseIdentifierAndValue(NSData *buf, struct asnWalkerState *stx, NSRange *outOIDRange, NSRange *outParameterRange)
{
    enum OFASN1ErrorCodes rc;
    
    /* We're expecting a SEQUENCE, but in some situations that sequence is implicitly tagged. So accept either a sequence, or any implicitly tagged constructed object. */
    if (!( (stx->v.classAndConstructed == FLAG_CONSTRUCTED && stx->v.tag == BER_TAG_SEQUENCE) ||
           (stx->v.classAndConstructed == (FLAG_CONSTRUCTED|CLASS_CONTEXT_SPECIFIC) ))) {
        return OFASN1UnexpectedType;
    }
    
    struct asnWalkerState walker;
    rc = enterObject(buf, stx, &walker);
    if (rc)
        return rc == OFASN1EndOfObject ? OFASN1Truncated : rc;
    
    EXPECT_TYPE(walker, FLAG_PRIMITIVE, BER_TAG_OID);
    *outOIDRange = walker.v.content;
    
    rc = nextObject(buf, &walker);
    if (rc == OFASN1EndOfObject) {
        *outParameterRange = (NSRange){ .location = walker.maxIndex, .length = 0 };
    } else if (rc != OFASN1Success) {
        return rc;
    } else {
        *outParameterRange = DER_FIELD_RANGE(walker);
        
        /* Check here that there is exactly one object in the algorithm parameters field */
        
        rc = nextObject(buf, &walker);
        if (rc == OFASN1Success)
            rc = OFASN1TrailingData;
        if (rc != OFASN1EndOfObject)
            return rc;
    }
    
    rc = exitObject(buf, stx, &walker, NO);
    
    return rc;
}

static BOOL parseNULLParameters(NSData *buf, NSRange r)
{
    if (r.length == 0) {
        // Omitted, DEFAULT NULL
        return YES;
    }
    
    if (r.length == 2) {
        char nulb[2];
        [buf getBytes:nulb range:r];
        if (nulb[0] == BER_TAG_NULL && nulb[1] == 0) {
            // Explicit NULL
            return YES;
        }
    }
    
    return NO;
}

enum OFASN1ErrorCodes OFASN1ParseSymmetricEncryptionParameters(NSData *buf, enum OFASN1Algorithm algid, NSRange range, NSData **outNonce, int *outTagSize)
{
    enum OFASN1ErrorCodes rc;

    switch (algid) {
        case OFASN1Algorithm_aes128_ccm:
        case OFASN1Algorithm_aes192_ccm:
        case OFASN1Algorithm_aes256_ccm:

        case OFASN1Algorithm_aes128_gcm:
        case OFASN1Algorithm_aes192_gcm:
        case OFASN1Algorithm_aes256_gcm:

        {
            /*
             CCMParameters ::= SEQUENCE {
                 aes-nonce         OCTET STRING (SIZE(7..13)),
                 aes-ICVlen        AES-CCM-ICVlen DEFAULT 12
             }
             
             GCMParameters ::= SEQUENCE {
                 aes-nonce        OCTET STRING,
                 aes-ICVlen       AES-GCM-ICVlen DEFAULT 12
             }
            */
            struct asnWalkerState walker, pst;
            
            rc = initializeWalkerAt(buf, YES, &walker, range.location, range.length);
            if (rc)
                return rc;
            EXPECT_TYPE(walker, FLAG_CONSTRUCTED, BER_TAG_SEQUENCE);
            rc = enterObject(buf, &walker, &pst);
            if (rc)
                return rc;
            EXPECT_TYPE(pst, FLAG_PRIMITIVE, BER_TAG_OCTET_STRING);
            rc = OFASN1ExtractStringContents(buf, pst.v, outNonce);
            if (rc)
                return rc;
            ADVANCE_E(buf, pst);
            if (rc == OFASN1Success) {
                EXPECT_TYPE(pst, FLAG_PRIMITIVE, BER_TAG_INTEGER);
                rc = OFASN1UnDERSmallInteger(buf, &pst.v, outTagSize);
                if (rc)
                    return rc;
                ADVANCE_E(buf, pst);
            } else {
                *outTagSize = 12;
            }
            
            rc = exitObject(buf, &walker, &pst, NO);
            if (rc != OFASN1EndOfObject) {
                return rc? rc : OFASN1UnexpectedType;
            }
            
            return OFASN1Success;
        }
            break;
            
        case OFASN1Algorithm_aes128_cbc:
        case OFASN1Algorithm_aes192_cbc:
        case OFASN1Algorithm_aes256_cbc:
        case OFASN1Algorithm_des_ede_cbc:
        {
            /* RFC3565: "the parameters field MUST contain a AES-IV" (aka OCTET STRING) */
            struct asnWalkerState pst;
            rc = initializeWalkerAt(buf, YES, &pst, range.location, range.length);
            if (rc)
                return rc;
            EXPECT_TYPE(pst, FLAG_PRIMITIVE, BER_TAG_OCTET_STRING);
            rc = OFASN1ExtractStringContents(buf, pst.v, outNonce);
            if (rc)
                return rc;
            ADVANCE_E(buf, pst);
            return OFASN1Success;
        }
            break;

            /* Algorithms with no parameters structure go here. We accept either an omitted parameters field or a NULL parameters field. */
        case OFASN1Algorithm_aes128_wrap:
        case OFASN1Algorithm_aes192_wrap:
        case OFASN1Algorithm_aes256_wrap:
            /* RFC3565: "In all cases the parameters field MUST be absent." */
            if (!parseNULLParameters(buf, range))
                return OFASN1UnexpectedType;
            return OFASN1Success;
            break;
            
        default:
            return OFASN1UnexpectedType;
    }
}

/* This is essentially the reverse of OFProduceDEKForCMSPWRIPBKDF2(). */
enum OFASN1ErrorCodes OFASN1ParsePBKDF2Parameters(NSData *buf, NSRange range, NSData **outSalt, int *outIterations, int *outKeyLength, enum OFASN1Algorithm *outPRF)
{
    /*
     PBKDF2-params ::= SEQUENCE {
         salt CHOICE {
             specified OCTET STRING,
             otherSource PBKDF2-SaltSourcesAlgorithmIdentifier
         },
         iterationCount INTEGER (1..MAX),
         keyLength INTEGER (1..MAX) OPTIONAL,
         prf PBKDF2-PRFsAlgorithmIdentifier DEFAULT defaultPBKDF2
     }
     */

    enum OFASN1ErrorCodes rc;
    struct asnWalkerState derivAlg;
    
    rc = initializeWalkerAt(buf, YES, &derivAlg, range.location, range.length);
    if (rc)
        return rc;
    EXPECT_TYPE(derivAlg, FLAG_CONSTRUCTED, BER_TAG_SEQUENCE);

    {
        struct asnWalkerState derivParams;
        rc = enterObject(buf, &derivAlg, &derivParams);
        
        /* salt CHOICE { specified OCTET STRING, ... } */
        if (!rc && (derivParams.v.classAndConstructed != FLAG_PRIMITIVE || derivParams.v.tag != BER_TAG_OCTET_STRING)) {
            rc = OFASN1UnexpectedType;  // The ASN.1 allows other choices, but the RFC for PBKDF2 doesn't.
        }
        if (rc)
            return rc;
        rc = OFASN1ExtractStringContents(buf, derivParams.v, outSalt);
        if (rc)
            return rc;
        
        /* iterationCount INTEGER (1..MAX) */
        rc = nextObjectExpecting(buf, &derivParams, FLAG_PRIMITIVE, BER_TAG_INTEGER);
        if (rc)
            return rc;
        rc = OFASN1UnDERSmallInteger(buf, &derivParams.v, outIterations);
        if (rc)
            return rc;
        
        /* keyLength INTEGER (1..MAX) OPTIONAL */
        rc = nextObject(buf, &derivParams);
        if (rc == OFASN1Success && derivParams.v.classAndConstructed == FLAG_PRIMITIVE && derivParams.v.tag == BER_TAG_INTEGER) {
            /* The OPTIONAL (but highly useful) key length parameter */
            rc = OFASN1UnDERSmallInteger(buf, &derivParams.v, outKeyLength);
            if (rc)
                return rc;
            rc = nextObject(buf, &derivParams);
        } else {
            *outKeyLength = 0;
        }
        
        /* prf AlgorithmIdentifier DEFAULT { algorithm hMAC-SHA1, parameters NULL } }*/
        if (rc == OFASN1Success && derivParams.v.classAndConstructed == FLAG_CONSTRUCTED && derivParams.v.tag == BER_TAG_SEQUENCE) {
            
            NSRange prfAlgorithmRange, prfParameterRange;
            rc = parseIdentifierAndValue(buf, &derivParams, &prfAlgorithmRange, &prfParameterRange);
            
            if (rc == OFASN1Success || rc == OFASN1EndOfObject) {
                /* Verify the NULL parameters. */
                if (!parseNULLParameters(buf, prfParameterRange))
                    return OFASN1UnexpectedType;
            } else {
                return rc;
            }
            
            *outPRF = OFASN1LookUpOID(OFASN1Algorithm, [buf bytes] + prfAlgorithmRange.location, prfAlgorithmRange.length);
        } else {
            *outPRF = OFASN1Algorithm_prf_hmacWithSHA1;
        }
        
        if (rc != OFASN1EndOfObject)
            return rc ? rc : OFASN1TrailingData;
        rc = exitObject(buf, &derivAlg, &derivParams, NO);
        if (rc != OFASN1EndOfObject)
            return rc ? rc : OFASN1TrailingData;
    }

    return OFASN1Success;
}

/* Extracts the contents of a string type (OCTET STRING, BIT STRING, etc.) into an NSData. For a definite-length string this is just -subdataWithRange:, but for indefinite encodings it concatenates the successive fragments. */
enum OFASN1ErrorCodes OFASN1ExtractStringContents(NSData *buf, struct parsedTag s, NSData **outData)
{
    if (!(s.indefinite)) {
        *outData = [buf subdataWithRange:s.content];
        return OFASN1Success;
    }
    
    NSUInteger position = s.content.location;
    NSUInteger maxIndex = ( s.content.length ? NSMaxRange(s.content) : [buf length] );
    NSMutableData *mbuffer = [NSMutableData data];

    for(;;) {
        struct parsedTag fragment;
        enum OFASN1ErrorCodes rc;
        rc = parseTagAndLength(buf, position, maxIndex, YES, &fragment);
        if (rc) {
            if (rc == OFASN1EndOfObject)
                return OFASN1Truncated;
            else
                return rc;
        }
        
        if (isSentinelObject(&fragment)) {
            if (s.content.length != 0 && NSMaxRange(fragment.content) != NSMaxRange(s.content)) {
                return OFASN1TrailingData; // Unexpected early sentinel?
            }
            break;
        }
        
        if (fragment.indefinite) {
            // No recursive indefinite encodings!
            return OFASN1UnexpectedIndefinite;
        }
        
        if ((s.classAndConstructed & CLASS_MASK) == CLASS_UNIVERSAL && s.tag != fragment.tag) {
            return OFASN1InconsistentEncoding;
        }
        
        if (fragment.classAndConstructed & FLAG_CONSTRUCTED) {
            return OFASN1InconsistentEncoding;
        }
        
        /* Okay, append this fragment to our buffer */
        /* TODO: Make use of dispatch_data_create_concat() to avoid copying large segments */
        [mbuffer appendData:[buf subdataWithRange:fragment.content]];
        
        position = NSMaxRange(fragment.content);
    }
    
    *outData = [[mbuffer copy] autorelease];
    return OFASN1Success;
}

#pragma mark Primitive value helpers

/* Convert a DER-encoded string to an NSString. Intended for the strings found in PKIX certificates. */
NSString *OFASN1UnDERString(NSData *derString)
{
    struct parsedTag tl;
    NSUInteger len = [derString length];
    enum OFASN1ErrorCodes rc = parseTagAndLength(derString, 0, len, NO, &tl);
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

static int v2digits(const char *cp)
{
    int h = ( cp[0] - '0' );
    int l = ( cp[1] - '0' );
    return h * 10 + l;
}

static NSDateComponents *OFASN1UnDERDateContents(NSData *buf, const struct parsedTag *v)
{
    BOOL fourDigitYear;
    
    if (v->classAndConstructed != 0 || v->indefinite)
        return nil;
    
    if (v->tag == BER_TAG_UTC_TIME) {
        fourDigitYear = NO;
    } else if (v->tag == BER_TAG_GENERALIZED_TIME) {
        fourDigitYear = YES;
    } else {
        return nil;
    }
    
    /* The longest valid date is 29 characters (YYYYMMDDHHMMSS.sssssssss+HHMM); the shortest is 8 (YYMMDDHH) */
    NSUInteger len = v->content.length;
    if (len < 8 || len > 29)
        return nil;
    char value[30];
    [buf getBytes:value range:v->content];
    value[len] = 0;

    NSTimeZone *tz;
    
    if (value[len-1] == 'Z') {
        tz = [NSTimeZone timeZoneWithName:@"UTC"];
        len --;
    } else if (value[len-5] == '+' || value[len-5] == '-') {
        /* RFC3280 [4.1.2.5] forbids the timezone offset notation in all PKIX UTCTime and GeneralizedTime values */
        /* but handling them is easy enough */
        int offset = 60 * v2digits(value + len - 4) + v2digits(value + len - 2);
        tz = [NSTimeZone timeZoneForSecondsFromGMT: (value[len-5] == '+')? offset : -offset];
        len -= 5;
    } else {
        tz = nil;
    }
    
    /* Verify that everything else is a digit */
    for (NSUInteger i = 0; i < len; i++) {
        if (value[i] == '.') {
            // We don't parse sub-seconds
            len = i;
            break;
        }
        if (value[i] < '0' || value[i] > '9') {
            // Non-digit
            return nil;
        }
    }
    if (len < 8)
        return nil;
    
    NSUInteger pos;
    NSCalendar *gregorianCalendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *result = [[NSDateComponents alloc] init];
    result.calendar = gregorianCalendar;
    if (tz)
        result.timeZone = tz;
    
    int year;
    if (fourDigitYear) {
        if (len < 10) {
            return nil;
        }
        year = v2digits(value) * 100 + v2digits(value + 2);
        pos = 4;
    } else {
        if (len < 8) {
            return nil;
        }
        year = v2digits(value);
        /* RFC3280 [4.1.2.5.1]: Where YY is greater than or equal to 50, the year SHALL be interpreted as 19YY; and where YY is less than 50, the year SHALL be interpreted as 20YY */
        if (year >= 50)
            year += 1900;
        else
            year += 2000;
        pos = 2;
    }
    result.year = year;
    
    result.month = v2digits(value + pos);
    pos += 2;
    result.day = v2digits(value + pos);
    pos += 2;
    result.hour = v2digits(value + pos);
    pos += 2;
    if (pos+2 <= len) {
        result.minute = v2digits(value + pos);
        pos += 2;
        
        if (pos+2 <= len) {
            result.second = v2digits(value + pos);
            pos += 2;
        } else {
            result.second = 0;
        }
    } else {
        result.minute = 0;
        result.second = 0;
    }
    if (pos != len) {
        // Trailing cruft
        return nil;
    }
    
    return result;
}

enum OFASN1ErrorCodes OFASN1UnDERSmallInteger(NSData *buf, const struct parsedTag *v, int *resultp)
{
    if (v->classAndConstructed != FLAG_PRIMITIVE ||
        v->tag != BER_TAG_INTEGER) {
        /* not an INTEGER */
        return OFASN1UnexpectedType;
    }
    
    if (v->indefinite) {
        return OFASN1UnexpectedIndefinite;
    }

    // WORD_BIT is defined as the number of bits in an int
    _Static_assert(WORD_BIT == 8*sizeof(*resultp), "");

    /* We assume we don't have a large number of leading zeroes; this is usually used for DER. */
    if (v->content.length > sizeof(*resultp)) {
        /* too large for a machine integer */
        return OFASN1LengthOverflow;
    }
    
    if (v->content.length == 0) {
        /* This is actually an invalid encoding */
        *resultp = 0;
        return OFASN1InconsistentEncoding;
    }
    
    uint8_t b[sizeof(*resultp)];
    memset(b, 0, sizeof(b));
    [buf getBytes:b + (sizeof(b) - v->content.length) range:v->content];
    
#if WORD_BIT == 32
    *resultp = OSReadBigInt32(b, 0);
#elif WORD_BIT == 64
    *resultp = OSReadBigInt64(b, 0);
#else
#error Unexpected word size
#endif
    return OFASN1Success;
}

NSData *OFASN1UnwrapOctetString(NSData *buf, NSRange r)
{
    struct parsedTag tagged;
    if (parseTagAndLength(buf, r.location, NSMaxRange(r), YES, &tagged) != OFASN1Success)
        return nil;
    if (tagged.tag != BER_TAG_OCTET_STRING || tagged.classAndConstructed != 0) /* We only support DER OCTET STRINGs here, not indefinite-length BER strings */
        return nil;
    if (NSMaxRange(tagged.content) != NSMaxRange(r))
        return nil;
    
    NSData *result = nil;
    if (OFASN1ExtractStringContents(buf, tagged, &result) != OFASN1Success)
        return nil;
    else
        return result;
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
    NSArray<NSString *> *parts = [s componentsSeparatedByString:@"."];
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

static unsigned bitSizeOfInteger(NSData *buffer, const struct parsedTag *st)
{
    NSRange r = st->content;
    if (!r.length) {
        return 0;
    }
    if (r.length > (UINT_MAX/8)) {
        return UINT_MAX;
    }
    
    uint8_t msb;
    [buffer getBytes:&msb range:(NSRange){ r.location, 1 }];
    int ix;
    if (msb & 0x80) {
        /* A negative integer? Okay... */
        ix = fls( ~(int)msb );
    } else {
        ix = fls( (int)msb );
    }
    
    return ( 8 * (unsigned int)(r.length - 1) ) + ix;
}

/* This determines the type and the key size of a key in an X.509 PublicKeyInfo structure. The type is returned (or ka_Failure if something went wrong). The outKeySize pointer gets the key's size which corresponds to its cryptographic strength. 
 
 For RSA keys: outKeySize is the bit size of the modulus. outOtherSize is unused.
 
 For DSA keys: the outKeySize gets parameter L (e.g. 1024 or 3072). outOtherSize gets the size of parameter N; this is equal to the size of the hash that shoud be used with this key, and is roughly half the size of a signature value computed using this key. For classic DSA keys this is 160.
 
 For ECDSA/ECDH keys: 
 
 DSA and ECDSA keys are allowed to inherit key parameters from their CA's key. In that case we just return (0, 0).
 If an elliptic curve key has explicit curve parameters or a named curve which we don't recognize, we just return (0, 0). These situations are forbidden by PKIX, though.

*/
enum OFKeyAlgorithm OFASN1KeyInfoGetAlgorithm(NSData *publicKeyInformation, unsigned int *outKeySize, unsigned int *outOtherSize)
{
    /*  Like this (expanded):
        subjectPublicKeyInfo  :=    SEQUENCE {
            algorithm                 SEQUENCE {
                algorithm               OBJECT IDENTIFIER,
                parameters              ANY DEFINED BY algorithm OPTIONAL
            },
            subjectPublicKey          BIT STRING
        }
     */

    
    enum OFASN1ErrorCodes rc, savedAlgidParamRc;
    struct asnWalkerState st, spkiSt, savedAlgParamSt;
    enum OFASN1Algorithm keyAlgorithm;
    
    rc = initializeWalker(publicKeyInformation, YES, &st);
    if (rc || !IS_TYPE(st, FLAG_CONSTRUCTED, BER_TAG_SEQUENCE))
        return ka_Failure;
    
    /* Enter the outermost SEQUENCE */
    rc = enterObject(publicKeyInformation, &st, &spkiSt);
    if (rc || !IS_TYPE(spkiSt, FLAG_CONSTRUCTED, BER_TAG_SEQUENCE))
        return ka_Failure;
    
    {
        struct asnWalkerState algidSt;
        
        /* Enter the AlgorithmIdentifier's SEQUENCE */
        rc = enterObject(publicKeyInformation, &spkiSt, &algidSt);
        if (rc || !IS_TYPE(algidSt, FLAG_PRIMITIVE, BER_TAG_OID))
            return ka_Failure;
        
        keyAlgorithm = OFASN1LookUpOID(OFASN1Algorithm,
                                       [publicKeyInformation bytes] + algidSt.v.content.location,
                                       algidSt.v.content.length);
        
        savedAlgidParamRc = nextObject(publicKeyInformation, &algidSt);
        savedAlgParamSt = algidSt;
        
        if (savedAlgidParamRc != OFASN1Success && savedAlgidParamRc != OFASN1EndOfObject)
            return ka_Failure;
        
        rc = exitObject(publicKeyInformation, &spkiSt, &algidSt, YES);
        if (rc)
            return ka_Failure;
    }
    /* spkiSt, after exiting from the algorithm identifier, should be looking at the BIT STRING which contains the actual public key */
    if (!IS_TYPE(spkiSt, FLAG_PRIMITIVE, BER_TAG_BIT_STRING))
        return ka_Failure;
            
    if (keyAlgorithm == OFASN1Algorithm_rsaEncryption_pkcs1_5) {
        if (outKeySize) {
            /*
             RSAPublicKey ::= SEQUENCE {
               modulus            INTEGER,    -- n
               publicExponent     INTEGER  }  -- e
             */
            
            struct asnWalkerState rsaPubKeySt, rsaPubKeyInner;
            if (enterBitString(publicKeyInformation, &spkiSt, &rsaPubKeySt) ||
                !IS_TYPE(rsaPubKeySt, CLASS_UNIVERSAL|FLAG_CONSTRUCTED, BER_TAG_SEQUENCE))
                return ka_Failure;
            if (enterObject(publicKeyInformation, &rsaPubKeySt, &rsaPubKeyInner) ||
                !IS_TYPE(rsaPubKeyInner, CLASS_UNIVERSAL|FLAG_PRIMITIVE, BER_TAG_INTEGER))
                return ka_Failure;
            *outKeySize = bitSizeOfInteger(publicKeyInformation, &rsaPubKeyInner.v);
        }
        return ka_RSA;
    }
    
    if (keyAlgorithm == OFASN1Algorithm_DSA) {
        if (outKeySize || outOtherSize) {
            
            /*
             Dss-Parms  ::=  SEQUENCE  {
               p             INTEGER,
               q             INTEGER,
               g             INTEGER  }
             */
            
            if (savedAlgidParamRc == OFASN1Success &&
                IS_TYPE(savedAlgParamSt, CLASS_UNIVERSAL|FLAG_CONSTRUCTED, BER_TAG_SEQUENCE)) {
                struct asnWalkerState dsaParams;
                if (enterObject(publicKeyInformation, &savedAlgParamSt, &dsaParams) ||
                    !IS_TYPE(dsaParams, CLASS_UNIVERSAL|FLAG_PRIMITIVE, BER_TAG_INTEGER))
                    return ka_Failure;
                if (outKeySize)
                    *outKeySize = bitSizeOfInteger(publicKeyInformation, &dsaParams.v);
                if (outOtherSize) {
                    if (nextObjectExpecting(publicKeyInformation, &dsaParams, CLASS_UNIVERSAL|FLAG_PRIMITIVE, BER_TAG_INTEGER))
                        return ka_Failure;
                    *outOtherSize = bitSizeOfInteger(publicKeyInformation, &dsaParams.v);
                }
            } else {
                if (outKeySize) *outKeySize = 0;
                if (outOtherSize) *outOtherSize = 0;
            }
        }
        return ka_DSA;
    }
    
    if (keyAlgorithm == OFASN1Algorithm_ecPublicKey || keyAlgorithm == OFASN1Algorithm_ecDH) {
        if (outKeySize || outOtherSize) {
            
            /*
            EcpkParameters ::= CHOICE {
                ecParameters  ECParameters,
                namedCurve    OBJECT IDENTIFIER,
                implicitlyCA  NULL }
             */
            
            if (outKeySize) *outKeySize = 0;
            if (outOtherSize) *outOtherSize = 0;
            
            if (savedAlgidParamRc == OFASN1Success && IS_TYPE(savedAlgParamSt, FLAG_PRIMITIVE|CLASS_UNIVERSAL, BER_TAG_OID)) {
                /* OBJECT IDENTIFIER identifying a named curve */
                NSRange fullOidRange = DER_FIELD_RANGE(savedAlgParamSt);
                if (fullOidRange.length > INT_MAX)
                    return ka_Failure;
                const void *pkiCurveOid = [publicKeyInformation bytes] + fullOidRange.location;
                for (const struct OFNamedCurveInfo *curve = _OFEllipticCurveInfoTable;
                     curve->derOid; curve ++) {
                    if (curve->derOidLength == fullOidRange.length &&
                        memcmp(curve->derOid, pkiCurveOid, fullOidRange.length) == 0) {
                        if (outKeySize) *outKeySize = curve->generatorSize;
                        if (outOtherSize) *outOtherSize = curve->generatorSize;
                        break;
                    }
                }
            }
        }
        return ka_EC;
    }
    
    return ka_Other;
}

#pragma mark Error helpers

NSError *OFNSErrorFromASN1Error(int errCode_, NSString *extra)
{
    NSString *detail;
    int errCode = errCode_;
    
    if (errCode >= 0 && errCode < (int)((sizeof(asn1ErrorCodeStrings)/sizeof(asn1ErrorCodeStrings[0])))) {
        detail = (__bridge NSString *)asn1ErrorCodeStrings[errCode];
    } else {
        detail = nil;
    }
    
    if (!detail) {
        detail = [NSString stringWithFormat:@"Error %d", errCode];
    }
    
    if (extra) {
        detail = [detail stringByAppendingFormat:@" (%@)", extra];
    }
    
    return [NSError errorWithDomain:OFErrorDomain code:OFASN1Error userInfo: detail ? @{NSLocalizedDescriptionKey: detail} : nil];
}



