// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class OFXServerAccount, OFXServerAccountType;

/*
 OFXServerAccountRegistry maintains the set of accounts configured by the user.
 */

NS_ASSUME_NONNULL_BEGIN

@interface OFXServerAccountRegistry : NSObject

// The default persistent registry. Nil is only returned in error conditions.
@property(nullable,nonatomic,readonly,class) OFXServerAccountRegistry *defaultAccountRegistry;

- (nullable instancetype)initWithAccountsDirectoryURL:(NSURL *)accountsDirectoryURL
#if OMNI_BUILDING_FOR_IOS
                           legacyAccountsDirectoryURL:(NSURL *)legacyAccountsDirectoryURL
#endif
                                                error:(NSError **)outError;

@property(nonatomic,readonly,copy) NSArray <OFXServerAccount *> *allAccounts; // KVO observable
@property(nonatomic,readonly,copy) NSArray <OFXServerAccount *> *validCloudSyncAccounts; // KVO observable.
@property(nonatomic,readonly,copy) NSArray <OFXServerAccount *> *validImportExportAccounts; // KVO observable.

- (NSArray <OFXServerAccount *> *)accountsWithType:(OFXServerAccountType *)type;
- (nullable OFXServerAccount *)accountWithUUID:(NSString *)uuid;
- (nullable OFXServerAccount *)accountWithDisplayName:(NSString *)name;

// To remove accounts, call -prepareForRemoval on them.
- (BOOL)addAccount:(OFXServerAccount *)account error:(NSError **)outError;
- (void)refreshAccount:(OFXServerAccount *)account;

@end

NS_ASSUME_NONNULL_END

