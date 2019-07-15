// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


/* Our key store data blob is a plist: an array of dictionaries with the following keys */

#define KeyDerivationMethodKey              @"method"   /* How to derive the document key; see below */

/* Static method: the document key is simply stored in cleartext. Insecure obviously but useful for testing. */
#define KeyDerivationStatic                 @"static"
#define StaticKeyKey                        @"key"      /* Array of key slots */

/* Use PBKDF2 to derive a wrapping key, which is then used to wrap a random key using the RFC3394 aes128-wrap / AES-WRAP algorithm. The wrapped key is then stored. */
#define KeyDerivationMethodPassword         @"password"
#define PBKDFAlgKey                         @"algorithm"
#define PBKDFAlgPBKDF2_WRAP_AES             @"PBKDF2; aes128-wrap"
#define PBKDFRoundsKey                      @"rounds"   /* integer */
#define PBKDFSaltKey                        @"salt"     /* data */
#define PBKDFPRFKey                         @"prf"      /* string (see below) */
#define DocumentKeyKey                      @"key"      /* wrapped array of key slots */

/* Values for PRF */
#define PBKDFPRFSHA1                        "sha1"
#define PBKDFPRFSHA256                      "sha256"
#define PBKDFPRFSHA512                      "sha512"


/* Constants describing the segemented encryption format */
#define SEGMENTED_IV_LEN                12        /* The length of the IV stored in front of each encrypted segment */
#define SEGMENTED_MAC_LEN               20        /* The length of the HMAC value stored with each encrypted segment */
#define SEGMENTED_MAC_KEY_LEN           16        /* The length of the HMAC key, stored in the file-key blob along with the AES key */
#define SEGMENTED_PAGE_SIZE             65536     /* Size of one encrypted segment */
#define SEGMENTED_INNER_LENGTH          ( kCCKeySizeAES128 + SEGMENTED_MAC_KEY_LEN )  /* Size of the wrapped data for inner FMT_V0_6 blob */
#define SEGMENTED_INNER_LENGTH_PADDED   (((SEGMENTED_INNER_LENGTH + 15) / 16) * 16)
#define SEGMENTED_FILE_MAC_VERSION_BYTE "\x01"
#define SEGMENTED_FILE_MAC_LEN          32        /* Length of the whole-file MAC */

#define SEGMENT_HEADER_LEN              (SEGMENTED_IV_LEN + SEGMENTED_MAC_LEN)
#define SEGMENT_ENCRYPTED_PAGE_SIZE     (SEGMENT_HEADER_LEN + SEGMENTED_PAGE_SIZE)
