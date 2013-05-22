// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/OBObject.h>

@class OFNetReachability;
@class OFXServerAccountRegistry, OFXServerAccount, OFXRegistrationTable, OFXAccountClientParameters;

@interface OFXAgent : OBObject

+ (NSArray *)wildcardSyncPathExtensions;
+ (BOOL)hasDefaultSyncPathExtensions;
+ (OFXAccountClientParameters *)defaultClientParameters;

+ (BOOL)isCellularSyncEnabled;
+ (void)setCellularSyncEnabled:(BOOL)cellularSyncEnabled;

// Returns an agent configured for shared use in an app (using default account registry, info from the main bundle plist).
- init;

- initWithAccountRegistry:(OFXServerAccountRegistry *)accountRegistry remoteDirectoryName:(NSString *)remoteDirectoryName syncPathExtensions:(id <NSFastEnumeration>)syncPathExtensions;
- initWithAccountRegistry:(OFXServerAccountRegistry *)accountRegistry remoteDirectoryName:(NSString *)remoteDirectoryName syncPathExtensions:(id <NSFastEnumeration>)syncPathExtensions extraPackagePathExtensions:(id <NSFastEnumeration>)extraPackagePathExtensions;

@property(nonatomic,readonly) OFNetReachability *netReachability;

@property(nonatomic,readonly) OFXServerAccountRegistry *accountRegistry;
@property(nonatomic,readonly) NSSet *syncPathExtensions;
@property(nonatomic,readonly) NSString *remoteDirectoryName; // For testing -- must be a plain string (no slashes)
@property(nonatomic,retain) OFXAccountClientParameters *clientParameters; // For testing -- must be set before the agent is started

@property(nonatomic,readonly) BOOL started;
- (void)applicationLaunched; // Starts syncing asynchronously
- (void)applicationWillEnterForeground; // Pauses syncing
- (void)applicationDidEnterBackground; // Resumes syncing
- (void)applicationWillTerminateWithCompletionHandler:(void (^)(void))completionHandler; // Waits for syncing to finish and shuts down the agent

@property(readonly,nonatomic) NSSet *runningAccounts; // KVO observable. Updated after a OFXServerAccount is added to our OFXServerAccountRegistry, once syncing has actually started with that account. Until this point, -metadataItemRegistrationTableForAccount: is not valid.
- (OFXRegistrationTable *)metadataItemRegistrationTableForAccount:(OFXServerAccount *)account; // Returns nil until the account agent is registered
- (NSSet *)metadataItemsForAccount:(OFXServerAccount *)account; // Convenience wrapper

- (NSOperation *)afterAsynchronousOperationsFinish:(void (^)(void))block;

@property(nonatomic) BOOL syncingEnabled; // Turn off timer and net state based automatic sync. This will be initialized to YES by default, but can be turned off before -applicationLaunched to prevent automatic syncing.

- (void)deleteCloudContentsForAccount:(OFXServerAccount *)account;

// Changes to this will not change in-flight downloads. Mostly this is for test cases and the Mac app.
@property(nonatomic) BOOL automaticallyDownloadFileContents;

// Requests a sync operation (which might do nothing if we are offline).
- (void)sync:(void (^)(void))completionHandler;

// Requests that the contents of a file be downloaded. The completion handler is called to indicate whether the request to start was successful -- the download itself may still fail.
- (void)requestDownloadOfItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

// Requests deletion of the file at the specified URL, which may be present on this client, but might only be known via metadata. If the file is present locally, file coordination will be used on a background queue to perform the delete. Otherwise, the delete will simply be marked in metadata and propagated to the server.
- (void)deleteItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

// Requests a rename of the file at the specified URL, which may be present on this client, but might only be known via metadata. If the file is present locally, file coordination will be used on a background queue to perform the rename. Otherwise, the rename will simply be marked in metadata and propagated to the server.
- (void)moveItemAtURL:(NSURL *)originalFileURL toURL:(NSURL *)updatedFileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

// Mostly for tests, but something like this might come in handy elsewhere.
- (void)countPendingTransfersForAccount:(OFXServerAccount *)serverAccount completionHandler:(void (^)(NSError *errorOrNil, NSUInteger count))completionHandler;
- (void)countFileItemsWithLocalChangesForAccount:(OFXServerAccount *)serverAccount completionHandler:(void (^)(NSError *errorOrNil, NSUInteger count))completionHandler;

@property(nonatomic,copy) NSString *debugName;

@end
