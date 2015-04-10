// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Security/Security.h>

enum OFASN1ErrorCodes {
    OFASN1Success                  = 0,
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

#define FLAG_CONSTRUCTED       0x20
#define FLAG_PRIMITIVE         0x00

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

