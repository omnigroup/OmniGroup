// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

/* From the Unicode standard:
 * U+FFFD REPLACEMENT CHARACTER 
 * used to replace an incoming character whose value is unknown or unrepresentable in Unicode
 */
#define OF_UNICODE_REPLACEMENT_CHARACTER ((unichar)0xFFFD)

/* A hopefully-unused CFStringEncoding value, which we use for scanning strings which are in an unknown ASCII superset (e.g. Latin-1, UTF-8, etc.). Non-ASCII bytes are mapped up into a range in the Supplemental Use Area A. This is useful for the annoying situation in which one part of a string tells us how to interpret another part of the string, and different parts may be in different character sets; the supplemental-use area keeps the unknown bytes out of the way (and hopefully unmolested) until we can re-encode them. To re-encode a string which was scanned in the "deferred ASCII superset encoding", see -[NSString stringByApplyingDeferredEncoding:], as well as the functions in this file. */
#define OFDeferredASCIISupersetStringEncoding (0x10000001U)

#define OFDeferredASCIISupersetBase (0xFA00)  /* Base value for the deferred decoding mentioned above. Don't use this value directly; use a helper function. This is here so that it can be included in inlined helper functions. */

/* General string utilities for dealing with surrogate pairs (UTF-16 encodings of UCS-4 characters) */
enum OFIsSurrogate {
    OFIsSurrogate_No = 0,
    OFIsSurrogate_HighSurrogate = 1,
    OFIsSurrogate_LowSurrogate = 2
};

/* Determines whether a given 16-bit unichar is part of a surrogate pair */
static inline enum OFIsSurrogate OFCharacterIsSurrogate(unichar ch)
{
    /* The surrogate ranges are conveniently lined up on power-of-two boundaries.
     ** Since the common case is that a character is not a surrogate at all, we
     ** test for that first.
     */
    if (__builtin_expect((ch & 0xF800) == 0xD800, 0)) {
        if ((ch & 0x0400) == 0)
            return OFIsSurrogate_HighSurrogate;
        else
            return OFIsSurrogate_LowSurrogate;
    } else
        return OFIsSurrogate_No;
}

/* Combines a high and a low surrogate character into a 21-bit Unicode character value */
static inline UnicodeScalarValue OFCharacterFromSurrogatePair(unichar high, unichar low)
{
    return 0x10000 + (
                      ( (UnicodeScalarValue)(high & 0x3FF) << 10 ) |
                      (UnicodeScalarValue)(low & 0x3FF)
                      );
}

/* Splits a Supplementary Plane character into two UTF-16 surrogate characters */
/* Do not use this for characters in the Basic Multilinugal Plane */
static inline void OFCharacterToSurrogatePair(UnicodeScalarValue inCharacter, unichar *outUTF16)
{
    UnicodeScalarValue supplementaryPlanePoint = inCharacter - 0x10000;
    
    outUTF16[0] = 0xD800 | ( supplementaryPlanePoint & 0xFFC00 ) >> 10; /* high surrogate */
    outUTF16[1] = 0xDC00 | ( supplementaryPlanePoint & 0x003FF );       /* low surrogate */
}


// Some defines for Unicode characters
enum {
    OFLeftQuoteCharacter = 8220,
    OFRightQuoteCharacter = 8221,
};
