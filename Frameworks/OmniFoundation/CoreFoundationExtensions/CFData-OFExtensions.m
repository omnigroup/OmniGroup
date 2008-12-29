// Copyright 1998-2005,2007,2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFData-OFExtensions.h>

#import <CommonCrypto/CommonDigest.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/CoreFoundationExtensions/CFData-OFExtensions.m 102833 2008-07-15 00:56:16Z bungi $")

CFDataRef OFDataCreateSHA1Digest(CFAllocatorRef allocator, CFDataRef data)
{
    CC_SHA1_CTX context;
    CC_SHA1_Init(&context);
    
    CC_SHA1_Update(&context, CFDataGetBytePtr(data), CFDataGetLength(data));
    
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &context);
    
    return CFDataCreate(allocator, digest, sizeof(digest));
}

CFDataRef OFDataCreateMD5Digest(CFAllocatorRef allocator, CFDataRef data)
{
    CC_MD5_CTX context;
    CC_MD5_Init(&context);
    
    CC_MD5_Update(&context, CFDataGetBytePtr(data), CFDataGetLength(data));

    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5_Final(digest, &context);
    
    return CFDataCreate(allocator, digest, sizeof(digest));
}
