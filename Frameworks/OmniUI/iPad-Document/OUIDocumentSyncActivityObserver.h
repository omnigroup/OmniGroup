// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#import <OmniUIDocument/OmniUIDocument-Swift.h> // For SyncActivityObserver

NS_ASSUME_NONNULL_BEGIN

@class OFXAgentActivity, OFXAccountActivity, OFXServerAccount;

@interface OUIDocumentSyncActivityObserver : NSObject <SyncActivityObserver>

- (instancetype)initWithAgentActivity:(OFXAgentActivity *)agentActivity NS_DESIGNATED_INITIALIZER;
- init NS_UNAVAILABLE;

@property(nonatomic,readonly) OFXAgentActivity *agentActivity;

// This should not be consulted during any `accountsUpdated` block.
@property(nonatomic,readonly) NSArray <OFXServerAccount *> *orderedServerAccounts;

- (nullable OFXAccountActivity *)accountActivityForServerAccount:(OFXServerAccount *)account;

@property(nonatomic,copy) void (^accountsUpdated)(NSArray <OFXServerAccount *> *updatedAccounts, NSArray <OFXServerAccount *> *addedAccounts, NSArray <OFXServerAccount *> *removedAccounts);
@property(nonatomic,copy) void (^accountChanged)(OFXServerAccount *account);

@end

NS_ASSUME_NONNULL_END
