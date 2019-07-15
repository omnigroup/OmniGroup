// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <OmniFoundation/OFWeakReference.h>

NS_ASSUME_NONNULL_BEGIN

@interface OUIInteractionLock : NSObject

@property (nonatomic, class, readonly) NSArray<OFWeakReference<OUIInteractionLock *> *> *activeLocks NS_EXTENSION_UNAVAILABLE_IOS("Interaction lock is not available in extensions.");
@property (nonatomic, class, readonly) BOOL hasActiveLocks NS_EXTENSION_UNAVAILABLE_IOS("Interaction lock is not available in extensions.");

+ (instancetype)applicationLock NS_SWIFT_NAME(applicationLock()) NS_EXTENSION_UNAVAILABLE_IOS("Interaction lock is not available in extensions.");

- (void)unlock NS_EXTENSION_UNAVAILABLE_IOS("Interaction lock is not available in extensions.");

@end

NS_ASSUME_NONNULL_END
