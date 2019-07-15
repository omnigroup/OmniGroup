// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Security/Security.h>
#import <OmniBase/macros.h>

NS_ASSUME_NONNULL_BEGIN

enum OFASN1ErrorCodes {
    OFASN1Success                  = 0,
    OFASN1EndOfObject,
    OFASN1Truncated,
    OFASN1TagOverflow,
    OFASN1LengthOverflow,
    OFASN1InconsistentEncoding,
    OFASN1UnexpectedType,
    OFASN1UnexpectedIndefinite,
    OFASN1TrailingData,
};
NSError *OFNSErrorFromASN1Error(int errCode, NSString * _Nullable extra) __attribute__((cold)) OB_HIDDEN;

#define CLASS_MASK             0xC0
#define CLASS_UNIVERSAL        0x00
#define CLASS_APPLICATION      0x40
#define CLASS_CONTEXT_SPECIFIC 0x80

#define FLAG_CONSTRUCTED       0x20
#define FLAG_PRIMITIVE         0x00

/* These are not from BER, but we borrow some bits from the tag field to store flags when scanning sequences. */
#define FLAG_OPTIONAL          0x01 // Just for OFASN1ParseBERSequence()
#define FLAG_ANY_OBJECT        0x02 // Just for OFASN1ParseBERSequence()
#define FLAG_BER_MASK         ( CLASS_MASK | FLAG_CONSTRUCTED )

#define BER_SENTINEL_LENGTH 2

/* These are in Security.framework on the Mac, but not on iOS */
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

#define ARRAYLENGTH(a) (sizeof(a)/sizeof((a)[0]))
#define SAME_LENGTH(x, y) _Static_assert(ARRAYLENGTH(x) == ARRAYLENGTH(y), "Mismatched array lengths")

struct parsedTag {
    unsigned short tag;              // tag
    uint8_t classAndConstructed;     // class and constructed flags bits from first octet
    BOOL indefinite;
    NSRange content;
};

struct scanItem {
    uint16_t flags;
    uint16_t tag;
};

struct parsedItem {
    NSUInteger startPosition;
    struct parsedTag i;
};

enum OFASN1ErrorCodes OFASN1IndefiniteObjectExtent(NSData *buf, NSUInteger position, NSUInteger maxIndex, NSUInteger *outEndPos) OB_HIDDEN;
BOOL OFASN1IsSentinelAt(NSData *buf, NSUInteger position) OB_HIDDEN;
enum OFASN1ErrorCodes OFASN1ParseBERSequence(NSData *buf, NSUInteger position, NSUInteger endPosition, BOOL requireDER, const struct scanItem *items, struct parsedItem *found, unsigned count) OB_HIDDEN;
enum OFASN1ErrorCodes OFASN1UnDERSmallInteger(NSData *buf, const struct parsedTag *v, int *resultp) OB_HIDDEN;
enum OFASN1ErrorCodes OFASN1ParseTagAndLength(NSData *buffer, NSUInteger where, NSUInteger maxIndex, BOOL requireDER, struct parsedTag *outTL) OB_HIDDEN;
enum OFASN1ErrorCodes OFASN1EnumerateMembersAsBERRanges(NSData *buf, struct parsedTag obj, enum OFASN1ErrorCodes (NS_NOESCAPE ^cb)(NSData *samebuf, struct parsedTag item, NSRange berRange)) OB_HIDDEN;
enum OFASN1ErrorCodes OFASN1ExtractStringContents(NSData *buf, struct parsedTag s, NSData OB_NANNP outData) OB_HIDDEN;
#define OFASN1ParseItemsInObject(b, p, der, i, v)    ({ SAME_LENGTH(i, v); OFASN1ParseBERSequence(b, (p).content.location, ((p).indefinite && !(p).content.length)? 0 : NSMaxRange((p).content), der,  (i), (v), ARRAYLENGTH(i)); })

enum OFASN1ErrorCodes OFASN1ParseSymmetricEncryptionParameters(NSData *buf, enum OFASN1Algorithm algid, NSRange range, NSData OB_NANNP outNonce, int *outTagSize) OB_HIDDEN;
enum OFASN1ErrorCodes OFASN1ParsePBKDF2Parameters(NSData *buf, NSRange range, NSData OB_NANNP outSalt, int *outIterations, int *outKeyLength, enum OFASN1Algorithm *outPRF) OB_HIDDEN;

NS_ASSUME_NONNULL_END
