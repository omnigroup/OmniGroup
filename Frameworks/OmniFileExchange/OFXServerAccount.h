// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFXServerAccountType;

@interface OFXServerAccount : NSObject

+ (BOOL)isValidLocalDocumentsURL:(NSURL *)documentsURL error:(NSError **)outError;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// Used by OUIServerAccountSetupViewController when creating a new account. Probably of not much use otherwise.
+ (NSURL *)generateLocalDocumentsURLForNewAccount:(NSError **)outError;

// When an account is deleted, this should be used to remove its local documents directory (only on iOS; on Mac we leave the user-visible documents alone).
+ (BOOL)deleteGeneratedLocalDocumentsURL:(NSURL *)documentsURL error:(NSError **)outError;
#endif

// New account with unique identifier -- not yet in any registry (so it can be configured and the configuration cancelled if needed).
- initWithType:(OFXServerAccountType *)type remoteBaseURL:(NSURL *)remoteBaseURL localDocumentsURL:(NSURL *)localDocumentsURL;

// State that cannot change while we are using an account -- have to remove the account and add a new one.
@property(nonatomic,readonly) NSString *uuid;
@property(nonatomic,readonly) OFXServerAccountType *type;
@property(nonatomic,readonly) NSURL *remoteBaseURL;
@property(nonatomic,readonly) NSURL *localDocumentsURL; // For document syncing; not needed for simple WebDAV access

@property(nonatomic,copy) NSString *displayName;

// The credential service identifier and credentals get set by validating the account via OFXServerAccountType
// NSURLProtectionSpace cannot be archived in 10.8 (though it conforms the resulting archive data can't be unarchived) so OFXServerAccount just records a service identifier. In 10.7 NSURLProtectionSpace didn't even claim to conform to NSCoding.
@property(nonatomic,readonly) NSString *credentialServiceIdentifier;
@property(nonatomic,readonly) NSURLCredential *credential;

// Must be called before the account can be removed. The sync agent will notice this and begin the process of shutting down the account. Once that happens, the account will be removed.
- (void)prepareForRemoval;
@property(nonatomic,readonly) BOOL hasBeenPreparedForRemoval;

@property(nonatomic,readonly) NSString *importTitle;
@property(nonatomic,readonly) NSString *exportTitle;
@property(nonatomic,readonly) NSString *accountDetailsString;

@property(nonatomic,readonly) NSDictionary *propertyList;

@end
