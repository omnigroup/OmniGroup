// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <CoreFoundation/CFString.h>

typedef struct _OFCaseConversionBuffer {
    CFMutableStringRef   string;
    UniChar             *buffer;
    CFIndex              bufferSize;
} OFCaseConversionBuffer;

extern void OFCaseConversionBufferInit(OFCaseConversionBuffer *caseBuffer);
extern void OFCaseConversionBufferDestroy(OFCaseConversionBuffer *caseBuffer);

extern CFStringRef OFCreateStringByLowercasingCharacters(OFCaseConversionBuffer *caseBuffer, const UniChar *characters, CFIndex count);
extern CFHashCode OFCaseInsensitiveHash(const UniChar *characters, CFIndex length);

// Case-insensitve comparison and hash suitable for collection callbacks
extern Boolean OFCaseInsensitiveStringIsEqual(const void *value1, const void *value2);
extern CFHashCode OFCaseInsensitiveStringHash(const void *value);

/* A simple convenience function which calls CFStringGetBytes() for the specified range and appends the bytes to the CFMutableData buffer. Returns the number of characters of "range" converted, which should always be the same as range.length. */
CFIndex OFAppendStringBytesToBuffer(CFMutableDataRef buffer, CFStringRef source, CFRange range, CFStringEncoding encoding, UInt8 lossByte, Boolean isExternalRepresentation);

/* The built-in hash function on NSString/CFString behaves astoundingly poorly on certain classes of input (such as URLs). This is an alternative hash which gives better results on our test data sets (and is quick to compute). */
/* Note that the hash depends on the string's representation as a sequence of UTF-16 points, and unicode normalization may be necessary before hashing depending on how you're using the strings. */
unsigned long OFStringHash_djb2(CFStringRef string);
