// Copyright 1998-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFData-OFExtensions.h>
#import <OmniBase/rcsid.h>

#import <CommonCrypto/CommonDigest.h>
#import <Foundation/NSObjCRuntime.h> // For MIN()

RCS_ID("$Id$")

#define OFDataCreateDigest(ALG) \
CFDataRef OFDataCreate ## ALG ## Digest(CFAllocatorRef allocator, CFDataRef data) \
{ \
    CC_ ## ALG ## _CTX context; \
    CC_ ## ALG ## _Init(&context); \
    const uint8_t *bytes = CFDataGetBytePtr(data); \
    CFIndex bytesLeft = CFDataGetLength(data); \
    while (bytesLeft > 0) { \
        CC_LONG currentLengthToProcess = MIN((CC_LONG)bytesLeft, 16384u); \
        CC_ ## ALG ## _Update(&context, bytes, currentLengthToProcess); \
        bytes += currentLengthToProcess; \
        bytesLeft -= currentLengthToProcess; \
    } \
    uint8_t digest[CC_ ## ALG ## _DIGEST_LENGTH]; \
    CC_ ## ALG ## _Final(digest, &context); \
    return CFDataCreate(allocator, digest, sizeof(digest)); \
}

OFDataCreateDigest(SHA1)
OFDataCreateDigest(SHA256)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OFDataCreateDigest(MD5)
#pragma clang diagnostic pop


// TODO: SHA512, RIPEMD160 ... ?
// TODO: SHA-3, when it's standardized

