// Copyright 2011-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <Security/Security.h>
#import <OmniFoundation/OFDigestUtilities.h>

@interface OFSecSignTransform : NSObject <OFDigestionContext>

- initWithKey:(SecKeyRef)aKey;

- (void)setPackDigestsWithGroupOrder:(int)sizeInBits;

@property (readwrite,nonatomic) CFStringRef digestType;
@property (readwrite,nonatomic) int digestLength;

@end
