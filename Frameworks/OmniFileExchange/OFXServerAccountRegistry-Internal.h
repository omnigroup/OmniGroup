// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXServerAccountRegistry.h>

@class OFXServerAccount;

@interface OFXServerAccountRegistry ()

@property(nonatomic,readonly) NSURL *accountsDirectoryURL;
#if OMNI_BUILDING_FOR_IOS
@property(nonatomic,readonly) NSURL *legacyAccountsDirectoryURL;
#endif

- (NSURL *)localStoreURLForAccount:(OFXServerAccount *)account; // Where we put our metadata and the containers.

- (void)_cleanupAccountAfterRemoval:(OFXServerAccount *)account;

@end
