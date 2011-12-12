// Copyright 2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7

#import <Foundation/NSObject.h>
#import <Security/Security.h>
#import <OmniFoundation/OFDigestUtilities.h>

static inline BOOL OFSecSignTransformAvailable()
{
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7
    return YES;
#else
    return ( SecSignTransformCreate != NULL ) && ( SecVerifyTransformCreate != NULL );
#endif
}

@interface OFSecSignTransform : NSObject <OFDigestionContext>
{
    NSMutableData *writebuffer;
    SecKeyRef key;
    CFStringRef digestType;
    int digestLength;
    BOOL verifying;
}

- initWithKey:(SecKeyRef)aKey;

@property (readwrite,nonatomic) CFStringRef digestType;
@property (readwrite,nonatomic) int digestLength;

@end

#endif /* OSX 10.7 or later */
