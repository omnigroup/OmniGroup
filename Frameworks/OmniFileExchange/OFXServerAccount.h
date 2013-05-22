// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFXServerAccountType;

// This is a terrible name, but it is better than having separate defines that are really all the same.
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // Here we just store a fixed URL that the user can't edit. So, we have a user-editable nickname for the account.
    #define OFX_MAC_STYLE_ACCOUNT 0
#else
    // This implies storing a security scoped bookmark URL for our local documents URL. This is movable by the user and its last path component provides the display name for the account
    #define OFX_MAC_STYLE_ACCOUNT 1
#endif

typedef NS_ENUM(NSUInteger, OFXServerAccountLocalDirectoryValidationReason) {
    OFXServerAccountValidateLocalDirectoryForAccountCreation, // Adding a new account
    OFXServerAccountValidateLocalDirectoryForSyncing, // Starting a sync agent on a previously created account
};

@interface OFXServerAccount : NSObject

+ (BOOL)validateLocalDocumentsURL:(NSURL *)documentsURL reason:(OFXServerAccountLocalDirectoryValidationReason)reason error:(NSError **)outError;
+ (NSURL *)signinURLFromWebDAVString:(NSString *)webdavString;
+ (NSString *)suggestedDisplayNameForAccountType:(OFXServerAccountType *)accountType url:(NSURL *)url username:(NSString *)username excludingAccount:(OFXServerAccount *)excludeAccount;

#if !OFX_MAC_STYLE_ACCOUNT
// Used by OUIServerAccountSetupViewController when creating a new account. Probably of not much use otherwise.
+ (NSURL *)generateLocalDocumentsURLForNewAccount:(NSError **)outError;

// When an account is deleted, this should be used to remove its local documents directory (only on iOS; on Mac we leave the user-visible documents alone).
+ (BOOL)deleteGeneratedLocalDocumentsURL:(NSURL *)documentsURL error:(NSError **)outError;
#endif

// New account with unique identifier -- not yet in any registry (so it can be configured and the configuration cancelled if needed).
- initWithType:(OFXServerAccountType *)type remoteBaseURL:(NSURL *)remoteBaseURL localDocumentsURL:(NSURL *)localDocumentsURL error:(NSError **)outError;

// State that cannot change while we are using an account -- have to remove the account and add a new one.
@property(nonatomic,readonly) NSString *uuid;
@property(nonatomic,readonly) OFXServerAccountType *type;
@property(nonatomic,readonly) NSURL *remoteBaseURL;
@property(nonatomic,readonly) NSString *displayName;

@property(nonatomic,readonly) NSURL *localDocumentsURL; // For document syncing; not needed for simple WebDAV access

#if OFX_MAC_STYLE_ACCOUNT
// On Mac, the user can move the local documents folder, possibly changing its name. We track these moves by storing a bookmark URL. The display name is derived: it's simply the name of the folder.
- (BOOL)resolveLocalDocumentsURL:(NSError **)outError; // Decodes the bookmark and attempts to start accessing the security scoped bookmark
- (void)clearLocalDocumentsURL; // Relinquishes the local documents directory
#else
// On iOS, the user never sees the local documents URL so it never changes. However, they need to be able to edit the display name.
@property(nonatomic,copy) NSString *nickname;
#endif

@property(nonatomic,readwrite) BOOL isCloudSyncEnabled;
@property(nonatomic,readonly) BOOL isImportExportEnabled; // Always YES for now

// The credential service identifier and credentals get set by validating the account via OFXServerAccountType
// NSURLProtectionSpace cannot be archived in 10.8 (though it conforms the resulting archive data can't be unarchived) so OFXServerAccount just records a service identifier. In 10.7 NSURLProtectionSpace didn't even claim to conform to NSCoding.
@property(nonatomic,copy) NSString *credentialServiceIdentifier;
@property(nonatomic,readonly) NSURLCredential *credential;

// Must be called before the account can be removed. The sync agent will notice this and begin the process of shutting down the account. Once that happens, the account will be removed.
- (void)prepareForRemoval;
@property(nonatomic,readonly) BOOL hasBeenPreparedForRemoval;

@property(nonatomic,readonly) NSString *importTitle;
@property(nonatomic,readonly) NSString *exportTitle;
@property(nonatomic,readonly) NSString *accountDetailsString;

@property(nonatomic,readonly) NSDictionary *propertyList;

@property(nonatomic,readonly) NSError *lastError;
- (void)reportError:(NSError *)error;
- (void)reportError:(NSError *)error format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
- (void)clearError;

// Helper that dispatches to the main queue for KVO and logs the error.

@property(nonatomic) BOOL isSyncInProgress;

- (NSComparisonResult)compareServerAccount:(OFXServerAccount *)otherAccount;

@end
