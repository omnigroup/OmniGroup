// Copyright 2013-2015,2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <OmniFileExchange/OFXSyncSchedule.h>

@class OFFileMotionResult;
@class OFXFileMetadata, OFXRegistrationTable<ValueType>, OFXServerAccount, OFXContainerAgent, OFXAccountClientParameters;

@interface OFXAccountAgent : NSObject

- initWithAccount:(OFXServerAccount *)account agentMemberIdentifier:(NSString *)agentMemberIdentifier registrationTable:(OFXRegistrationTable <OFXRegistrationTable <OFXFileMetadata *> *> *)registrationTable remoteDirectoryName:(NSString *)remoteDirectoryName localAccountDirectory:(NSURL *)localAccountDirectory localPackagePathExtensions:(id <NSFastEnumeration>)localPackagePathExtensions syncPathExtensions:(id <NSFastEnumeration>)syncPathExtensions;

@property(nonatomic,readonly) OFXServerAccount *account;

@property(nonatomic,readonly) NSString *remoteDirectoryName; // For testing -- must be a plain string (no slashes)
@property(nonatomic,retain) OFXAccountClientParameters *clientParameters; // For testing -- must be set before starting the agent

@property(nonatomic,readonly) NSURL *localAccountDirectory;
@property(nonatomic,readonly) NSURL *remoteBaseDirectory; // Appends the remoteDirectoryName if set.
@property(nonatomic,readonly) NSSet *localPackagePathExtensions; // Path extensions that this app's Info.plist declares to be file packages.
@property(nonatomic,readonly) NSSet *syncPathExtensions; // Path extensions (flat or package) that this app cares about. Nil if it wants to sync all file types.

@property(nonatomic,readonly) BOOL started;
- (BOOL)start:(NSError **)outError;
- (void)stop:(void (^)(void))completionHandler;

@property(nonatomic,assign) BOOL syncingEnabled;

@property(nonatomic) BOOL automaticallyDownloadFileContents;

- (void)sync:(void (^)(void))completionHandler;

- (NSOperation *)afterAsynchronousOperationsFinish:(void (^)(void))block;

@property(nonatomic,readonly,copy) NSString *netStateRegistrationGroupIdentifier;

- (BOOL)containsLocalDocumentFileURL:(NSURL *)fileURL;

- (void)containerNeedsFileTransfer:(OFXContainerAgent *)container;
- (void)containerNeedsFileTransfer:(OFXContainerAgent *)container requestRecorded:(void (^)(void))requestRecorded;

- (void)containerPublishedFileVersionsChanged:(OFXContainerAgent *)container;
- (void)requestDownloadOfItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
- (void)deleteItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
- (void)moveItemAtURL:(NSURL *)originalFileURL toURL:(NSURL *)updatedFileURL completionHandler:(void (^)(OFFileMotionResult *moveResult, NSError *errorOrNil))completionHandler;

- (void)countPendingTransfers:(void (^)(NSError *errorOrNil, NSUInteger count))completionHandler;
- (void)countFileItemsWithLocalChanges:(void (^)(NSError *errorOrNil, NSUInteger count))completionHandler;

@property(nonatomic,copy) NSString *debugName;

#ifdef OMNI_ASSERTIONS_ON
@property(nonatomic,readonly) BOOL runningOnAccountAgentQueue;
#endif

@end
