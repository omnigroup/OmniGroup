// Copyright 1998-2005,2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFData-OFExtensions.h>

#import <CommonCrypto/CommonDigest.h>

RCS_ID("$Id$")

#define OFDataCreateDigest(ALG) \
CFDataRef OFDataCreate ## ALG ## Digest(CFAllocatorRef allocator, CFDataRef data)                 \
{                                                                                                 \
    CC_ ## ALG ## _CTX context;                                                                   \
    CC_ ## ALG ## _Init(&context);                                                                \
                                                                                                  \
    CC_ ## ALG ## _Update(&context, CFDataGetBytePtr(data), CFDataGetLength(data));               \
                                                                                                  \
    unsigned char digest[CC_ ## ALG ## _DIGEST_LENGTH];                                           \
    CC_ ## ALG ## _Final(digest, &context);                                                       \
                                                                                                  \
    return CFDataCreate(allocator, digest, sizeof(digest));                                       \
}

OFDataCreateDigest(SHA1)
OFDataCreateDigest(SHA256)
OFDataCreateDigest(MD5)


// TODO: SHA512, RIPEMD160 ... ?
// TODO: SHA-3, when it's standardized

