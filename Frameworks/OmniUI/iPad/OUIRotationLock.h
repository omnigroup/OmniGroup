// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <OmniFoundation/OFWeakReference.h>

@interface OUIRotationLock : NSObject

@property (nonatomic, class, readonly) NSArray<OFWeakReference<OUIRotationLock *> *> *activeLocks;
@property (nonatomic, class, readonly) BOOL hasActiveLocks;

+ (instancetype)rotationLock;

- (void)unlock;

@end
