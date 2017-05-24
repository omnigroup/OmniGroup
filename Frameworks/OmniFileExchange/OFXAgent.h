// Copyright 2013-2015,2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/OBObject.h>
#import <OmniFileExchange/OFXSyncSchedule.h>
#import <Foundation/NSEnumerator.h> // NSFastEnumeration

@class NSOperation;
@class OFPreference, OFFileMotionResult;
@class ODAVConnectionConfiguration;
@class OFXServerAccountRegistry, OFXServerAccount, OFXRegistrationTable<ValueType>, OFXAccountClientParameters, OFXFileMetadata;

@interface OFXAgent : OBObject

+ (NSArray *)wildcardSyncPathExtensions;
+ (BOOL)hasDefaultSyncPathExtensions;
+ (OFXAccountClientParameters *)defaultClientParameters;

+ (ODAVConnectionConfiguration *)makeConnectionConfiguration;

// Returns an agent configured for shared use in an app (using default account registry, info from the main bundle plist).
- init;

- initWithAccountRegistry:(OFXServerAccountRegistry *)accountRegistry remoteDirectoryName:(NSString *)remoteDirectoryName syncPathExtensions:(id <NSFastEnumeration>)syncPathExtensions;
- initWithAccountRegistry:(OFXServerAccountRegistry *)accountRegistry remoteDirectoryName:(NSString *)remoteDirectoryName syncPathExtensions:(id <NSFastEnumeration>)syncPathExtensions extraPackagePathExtensions:(id <NSFastEnumeration>)extraPackagePathExtensions;

@property(nonatomic,readonly) OFXServerAccountRegistry *accountRegistry;
@property(nonatomic,readonly) NSSet *syncPathExtensions;
@property(nonatomic,readonly) NSString *remoteDirectoryName; // For testing -- must be a plain string (no slashes)
@property(nonatomic,retain) OFXAccountClientParameters *clientParameters; // For testing -- must be set before the agent is started

@property(nonatomic,readonly) BOOL started;
- (void)applicationLaunched; // Starts syncing asynchronously
- (void)applicationWillTerminateWithCompletionHandler:(void (^)(void))completionHandler; // Waits for syncing to finish and shuts down the agent

@property(nonatomic,readonly) BOOL foregrounded;
- (void)applicationWillEnterForeground; // Reenables Bonjour and timer based sync events.
- (void)applicationDidEnterBackground; // Disables Bonjour and timer based sync events.

@property(nonatomic) OFXSyncSchedule syncSchedule; // Defaults to OFXSyncScheduleAutomatic, but can be adjusted before -applicationLaunched to prevent automatic syncing.
- (void)restoreSyncEnabledForAccount:(OFXServerAccount *)account;

@property(readonly,nonatomic) NSSet <OFXServerAccount *> *runningAccounts; // KVO observable. Updated after a OFXServerAccount is added to our OFXServerAccountRegistry, once syncing has actually started with that account. Until this point, -metadataItemRegistrationTableForAccount: is not valid.
@property(readonly,nonatomic) NSSet <OFXServerAccount *> *failedAccounts; // KVO observable. Updated after a OFXServerAccount is added to our OFXServerAccountRegistry, once syncing has been attempted and failed to start for some reason. Note that a running account can still have an error; this is for accounts that didn't even start up (missing local directory, etc).
- (OFXRegistrationTable <OFXFileMetadata *> *)metadataItemRegistrationTableForAccount:(OFXServerAccount *)account; // Returns nil until the account agent is registered
- (NSSet <OFXFileMetadata *> *)metadataItemsForAccount:(OFXServerAccount *)account; // Convenience wrapper

- (NSOperation *)afterAsynchronousOperationsFinish:(void (^)(void))block;


// Changes to this will not change in-flight downloads. Mostly this is for test cases and the Mac app.
@property(nonatomic) BOOL automaticallyDownloadFileContents;

- (BOOL)shouldAutomaticallyDownloadItemWithMetadata:(OFXFileMetadata *)metadataItem;

// Requests a sync operation (which might do nothing if we are offline).
- (void)sync:(void (^)(void))completionHandler;

// Requests that the contents of a file be downloaded. The completion handler is called to indicate whether the request to start was successful -- the download itself may still fail.
- (void)requestDownloadOfItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

// Requests deletion of the file at the specified URL, which may be present on this client, but might only be known via metadata. If the file is present locally, file coordination will be used on a background queue to perform the delete. Otherwise, the delete will simply be marked in metadata and propagated to the server.
- (void)deleteItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

// Requests a rename of the file at the specified URL, which may be present on this client, but might only be known via metadata. If the file is present locally, file coordination will be used on a background queue to perform the rename. Otherwise, the rename will simply be marked in metadata and propagated to the server.
- (void)moveItemAtURL:(NSURL *)originalFileURL toURL:(NSURL *)updatedFileURL completionHandler:(void (^)(OFFileMotionResult *result, NSError *errorOrNil))completionHandler;

// Mostly for tests, but something like this might come in handy elsewhere.
- (void)countPendingTransfersForAccount:(OFXServerAccount *)serverAccount completionHandler:(void (^)(NSError *errorOrNil, NSUInteger count))completionHandler;
- (void)countFileItemsWithLocalChangesForAccount:(OFXServerAccount *)serverAccount completionHandler:(void (^)(NSError *errorOrNil, NSUInteger count))completionHandler;

@property(nonatomic,copy) NSString *debugName;

@end
