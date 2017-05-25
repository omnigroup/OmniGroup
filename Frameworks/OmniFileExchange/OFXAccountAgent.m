// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXAccountAgent-Internal.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFeatures.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFileExchange/OFXAccountClientParameters.h>
#import <OmniFileExchange/OFXRegistrationTable.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/OFCredentials.h>

#import "OFXAccountInfo.h"
#import "OFXAgent-Internal.h"
#import "OFXContainerAgent-Internal.h"
#import "OFXContainerScan.h"
#import "OFXDAVUtilities.h"
#import "OFXFileItem-Internal.h"
#import "OFXFileItemTransfers.h"
#import "OFXFileSnapshotTransfer.h"

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>
#endif
#import <dirent.h>

RCS_ID("$Id$")

typedef NS_ENUM(NSUInteger, OFXAccountAgentState) {
    OFXAccountAgentStateCreated,
    OFXAccountAgentStateStarted,
    OFXAccountAgentStateStopped,
};

NSString * const OFXAccountAgentDidStopForReplacementNotification = @"OFXAccountAgentDidStopForReplacementNotification";

static NSString * const RemoteTemporaryDirectoryName = @"tmp";

static OFPreference *OFXRecentTransferErrorThresholdBeforeAutomaticallyStopping;

#import <OmniFoundation/OFLockFile.h>
#if (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE) && OF_LOCK_FILE_AVAILABLE
    #define OFX_USE_LOCK_FILE 1
#else
    #define OFX_USE_LOCK_FILE 0 // The account directory is in our sandbox where no other processes should be able to touch it
#endif

@interface OFXAccountAgent () <NSFilePresenter>

// As we are starting and shutting down, the foreground and background will have different ideas about whether we are running. This is complicated by the fact that NSFileCoordinator enqueues operations on our presenter queue in ways that we can't flush (+removeFilePresenter: doesn't seem to ensure that everything is queued). Our instances are one-use. That is, we get started, stopped and then discarded. When stopping the caller does need to make sure that we've acknowledged the stop request before discarding us (so that we won't be writing to our local documents directory any more).
@property(nonatomic,readonly) OFXAccountAgentState foregroundState;
@property(nonatomic,readonly) OFXAccountAgentState backgroundState;

// BOOL that propagates to the background queue from the foreground.
@property(nonatomic,readonly) BOOL foregroundSyncingEnabled;
@property(nonatomic,readonly) BOOL backgroundSyncingEnabled;

@property(nonatomic,readonly) BOOL foregroundAutomaticallyDownloadFileContents;
@property(nonatomic,readonly) BOOL backgroundAutomaticallyDownloadFileContents;

// We load the account info in the background, but only set this group identifier on the foreground.
@property(nonatomic,copy) NSString *netStateRegistrationGroupIdentifier;


@end

@implementation OFXAccountAgent
{
#if OFX_USE_LOCK_FILE
    OFLockFile *_lockFile;
#endif
    
    DIR *_localDocumentsDirectoryHandle;
    
    NSSet *_localPackagePathExtensions;
    NSSet *_syncPathExtensions;
    NSSet *_serverContainerIdentifiers;

    NSOperationQueue *_operationQueue; // Serial queue for work related to this account, bookkeeping of file items, scans, and transfer status updates.
    
    NSTimer *_metadataUpdateTimer; // Registered on the main queue, but triggers a call over the account's operation queue.
    
    NSMutableSet *_runningTransfers; // OFXFileSnapshotTransfers that are running.
    
    BOOL _hasQueuedContentsScan;
    BOOL _hasQueuedContainerNeedsFileTransfers;
    
    // Support for coalescing sync requests
    NSLock *_queuedSyncCallbacksLock;
    NSMutableArray *_locked_queuedSyncCallbacks;
    
    NSURLCredential *_credentialsForCurrentSync;
    
    // Pending/running file transfers
    OFXFileItemTransfers *_uploadFileItemTransfers;
    OFXFileItemTransfers *_downloadFileItemTransfers;
    OFXFileItemTransfers *_deleteFileItemTransfers;
    
    BOOL _needsToNilLastError; // accessed on the operation queue, used to keep from redundant blocks for setting lastError to nil on the main queue
    
    BOOL _hasRegisteredAsFilePresenter;
    BOOL _hasRelinquishedToWriter;
    NSOperationQueue *_presentedItemOperationQueue;
    
    // If we've responded to all our file edit notifications, but had an error, then the next sync needs to scan first.
    BOOL _lastScanFailed;
    
    // Keep track of edits that have happened while we have relinquished for a writer. These can be randomly ordered in bad ways (for example, we can be told of a 'did change' right before a 'delete'). Radar 10879451.
    // This is a subset of the code in ODSFileItem since we don't expect containers to be deleted while we are registered (or ever moved).
    struct {
        unsigned relinquishToWriter:1;
        unsigned changed:1;
    } _edits;

    NSArray <ODAVRedirect *> *_recentRedirects;
    
    // iOS client apps won't change their set of extensions at runtime, but the Mac agents will based on what package extensions it sees on the server.
    NSMutableDictionary <NSString *, OFXContainerAgent *> *_containerIdentifierToContainerAgent;
    
    OFXRegistrationTable <OFXRegistrationTable <OFXFileMetadata *> *> *_agentRegistrationTable;
    OFXRegistrationTable <OFXFileMetadata *> *_metadataRegistrationTable;
    
    NSString *_agentMemberIdentifier;
    OFNetStateRegistration *_stateRegistration;
    
    OFXAccountInfo *_info;
}

static NSSet <NSString *> *_lowercasePathExtensions(id <NSFastEnumeration> pathExtensions)
{
    if (!pathExtensions)
        return nil;
    
    NSMutableSet *lowercasePathExtensions = [NSMutableSet new];
    for (NSString *pathExtension in pathExtensions) {
        OBASSERT([pathExtension isEqual:[pathExtension lowercaseString]], "Path extensions should be lowercase to begin with");
        [lowercasePathExtensions addObject:[pathExtension lowercaseString]];
    }
    
    return lowercasePathExtensions;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OFXRecentTransferErrorThresholdBeforeAutomaticallyStopping = [OFPreference preferenceForKey:@"OFXRecentTransferErrorThresholdBeforeAutomaticallyStopping"];
}

- initWithAccount:(OFXServerAccount *)account agentMemberIdentifier:(NSString *)agentMemberIdentifier registrationTable:(OFXRegistrationTable <OFXRegistrationTable <OFXFileMetadata *> *> *)registrationTable remoteDirectoryName:(NSString *)remoteDirectoryName localAccountDirectory:(NSURL *)localAccountDirectory localPackagePathExtensions:(id <NSFastEnumeration>)localPackagePathExtensions syncPathExtensions:(id <NSFastEnumeration>)syncPathExtensions;
{
    OBPRECONDITION(account);
    OBPRECONDITION(account.usageMode == OFXServerAccountUsageModeCloudSync);
    OBPRECONDITION(!account.hasBeenPreparedForRemoval);
    OBPRECONDITION(![NSString isEmptyString:account.credentialServiceIdentifier]);
    OBPRECONDITION(![NSString isEmptyString:agentMemberIdentifier]);
    OBPRECONDITION(registrationTable);
    OBPRECONDITION(localAccountDirectory);
    OBPRECONDITION([localAccountDirectory checkResourceIsReachableAndReturnError:NULL]); // should exist
    OBPRECONDITION([[[localAccountDirectory URLByStandardizingPath] absoluteString] isEqualToString:[localAccountDirectory absoluteString]]); // ... and should be standardized already

    if (!(self = [super init]))
        return nil;
    
    _account = account;
    _agentMemberIdentifier = [agentMemberIdentifier copy];
    _agentRegistrationTable = registrationTable;
    _localAccountDirectory = [localAccountDirectory copy];
    _localPackagePathExtensions = [_lowercasePathExtensions(localPackagePathExtensions) copy];
    _syncPathExtensions = [_lowercasePathExtensions(syncPathExtensions) copy];
    _remoteDirectoryName = [remoteDirectoryName copy];
    
    return self;
}

- (void)dealloc;
{
    OBASSERT(_operationQueue == nil, "Should have called -stop");
    OBASSERT(_runningTransfers == nil, "Should have called -stop");
    OBASSERT(_metadataRegistrationTable == nil, "Should have called -stop");
}

- (void)setRemoteDirectoryName:(NSString *)remoteDirectoryName;
{
    OBPRECONDITION(self.foregroundState == OFXAccountAgentStateCreated, @"should only set this before being started");
    OBPRECONDITION(_operationQueue == nil, @"should only set this while stopped");
    OBPRECONDITION(!remoteDirectoryName || ![NSString isEmptyString:remoteDirectoryName], @"Don't pass an empty string");
    
    _remoteDirectoryName = [remoteDirectoryName copy];
}

- (NSURL *)remoteBaseDirectory;
{
    NSURL *url = _account.remoteBaseURL;
    
    // Should allow test cases to run in different subdirectories on the server (w/o having to make different OFXAccounts with different baseURLs for them).
    if (![NSString isEmptyString:_remoteDirectoryName])
        url = [url URLByAppendingPathComponent:_remoteDirectoryName isDirectory:YES];
    
    return url;
}

@synthesize netStateRegistrationGroupIdentifier = _netStateRegistrationGroupIdentifier;

- (NSString *)netStateRegistrationGroupIdentifier;
{
    OBPRECONDITION([NSThread isMainThread]);
    return _netStateRegistrationGroupIdentifier;
}

+ (BOOL)automaticallyNotifiesObserversOfNetStateRegistrationGroupIdentifier;
{
    return NO;
}

- (void)setNetStateRegistrationGroupIdentifier:(NSString *)netStateRegistrationGroupIdentifier;
{
    if (OFISEQUAL(_netStateRegistrationGroupIdentifier, netStateRegistrationGroupIdentifier))
        return;
    [self willChangeValueForKey:OFValidateKeyPath(self, netStateRegistrationGroupIdentifier)];
    _netStateRegistrationGroupIdentifier = [netStateRegistrationGroupIdentifier copy];
    [self didChangeValueForKey:OFValidateKeyPath(self, netStateRegistrationGroupIdentifier)];
}

@synthesize foregroundState = _foregroundState;
- (OFXAccountAgentState)foregroundState;
{
    OBPRECONDITION([NSThread isMainThread], @"Only look at the foreground state in the foreground.");
    return _foregroundState;
}

@synthesize backgroundState = _backgroundState;
- (OFXAccountAgentState)backgroundState;
{
    // Note that we don't allow looking at this on the file presenter queue since this is maintained on the _operationQueue.
    // This means the file presenter messages need to bounce to the _operationQueue and then check if the agent was stopped.
    // TODO: Maybe we should return _operationQueue as our file presenter queue and do file coordination on a different queue to avoid deadlock.
    OBPRECONDITION(!_operationQueue || [NSOperationQueue currentQueue] == _operationQueue);
    
    return _backgroundState;
}


- (BOOL)started;
{
    return self.foregroundState == OFXAccountAgentStateStarted;
}

- (NSString *)_operationQueueName;
{
    OBPRECONDITION(_account);
    return [NSString stringWithFormat:@"com.omnigroup.OmniFileExchange.OFXAccountAgent.bookkeeping account:%@ owner:%@", _account.uuid, _debugName];
}

- (BOOL)start:(NSError **)outError;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(self.foregroundState == OFXAccountAgentStateCreated, @"We are a use-once class. Stopping and then re-starting is not allowed.");
    OBPRECONDITION(_operationQueue == nil);
    OBPRECONDITION(_runningTransfers == nil);
    OBPRECONDITION(_presentedItemOperationQueue == nil);
    OBPRECONDITION(_netStateRegistrationGroupIdentifier == nil);
    OBPRECONDITION(_stateRegistration == nil);
    OBPRECONDITION(_localDocumentsDirectoryHandle == NULL);

    if (_foregroundState != OFXAccountAgentStateCreated)
        [NSException raise:NSInternalInconsistencyException format:@"Called -start on %@ while it was in state %ld", [self shortDescription], _foregroundState];

    DEBUG_SYNC(1, @"Starting");

    void (^startFailed)(void) = ^{
        if (_localDocumentsDirectoryHandle) {
            closedir(_localDocumentsDirectoryHandle);
            _localDocumentsDirectoryHandle = NULL;
        }
        
#if OFX_USE_LOCK_FILE
        [_lockFile unlockIfLocked];
        _lockFile = nil;
#endif
    };
    
    // Our caller, -[OFXAgent _validatedAccountsChanged], should have already called -resolveLocalDocumentsURL: on our behalf on the Mac.
    NSURL *localDocumentsURL = _account.localDocumentsURL;

    BOOL inTrash = NO;
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    inTrash = [[NSFileManager defaultManager] isFileInTrashAtURL:localDocumentsURL];
#endif
    
    if (inTrash) {
        __autoreleasing NSError *documentsError;
        OFXError(&documentsError, OFXLocalAccountDocumentsDirectoryMissing,
                 NSLocalizedStringFromTableInBundle(@"Cannot start account agent.", @"OmniFileExchange", OMNI_BUNDLE, @"Error description"),
                 NSLocalizedStringFromTableInBundle(@"Local account documents folder is missing.", @"OmniFileExchange", OMNI_BUNDLE, @"Error reason"));
        [_account reportError:documentsError format:@"Error starting account agent. Local account documents directory is inside the Trash %@", localDocumentsURL];
        if (outError)
            *outError = documentsError;
        startFailed();
        return NO;
    }
    
    // NOTE: We should take care to never create our documents directory as part of creating ancestor directories for containers; otherwise we might transform a missing documents directory into a delete of a whole bunch of documents");
    _localDocumentsDirectoryHandle = opendir([[localDocumentsURL path] UTF8String]);
    if (!_localDocumentsDirectoryHandle) {
        __autoreleasing NSError *documentsError;
        
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to open documents folder.", @"OmniFileExchange", OMNI_BUNDLE, @"Error description");
        OBErrorWithErrno(&documentsError, errno, "opendir", [localDocumentsURL path], description);
        
        if (errno == ENOENT) {
            // Stack a specific error here that lets the UI know it could ask the user to reconnect to the account.
            OFXError(&documentsError, OFXLocalAccountDocumentsDirectoryMissing,
                     NSLocalizedStringFromTableInBundle(@"Cannot start syncing.", @"OmniFileExchange", OMNI_BUNDLE, @"Error description"),
                     NSLocalizedStringFromTableInBundle(@"Local account documents folder is missing.", @"OmniFileExchange", OMNI_BUNDLE, @"Error reason"));
        }
        
        [_account reportError:documentsError format:@"Error starting account agent. Local account documents directory is missing %@", localDocumentsURL];
        if (outError)
            *outError = documentsError;
        startFailed();
        return NO;
    }
    
    // Check that the local documents directory otherwise still valid (doing this after our opendir, which will give a specific error for the missing case). Check this before taking out the lock since the lock creation will fail strangely if the TemporaryItems directory isn't writable.
    {
        __autoreleasing NSError *validateError;
        if (![OFXServerAccount validateLocalDocumentsURL:localDocumentsURL reason:OFXServerAccountValidateLocalDirectoryForSyncing error:&validateError]) {
            if (outError)
                *outError = validateError;
            startFailed();
            return NO;
        }
    }
    
#if OFX_USE_LOCK_FILE
    // Take out a lock on the account directory in case LaunchServices or something else tries to run two copies of OmniPresence.
    if (!_lockFile) {
        NSURL *lockURL = [_localAccountDirectory URLByAppendingPathComponent:@"Lock"];
        _lockFile = [[OFLockFile alloc] initWithURL:lockURL];
        OBASSERT(_lockFile, @"The lock object should be created even if the lock is taken or invalid.");
        
        __autoreleasing NSError *lockError = nil;
        if (![_lockFile lockWithOptions:OFLockFileLockOperationOptionsNone error:&lockError]) {
            OFXError(&lockError, OFXUnableToLockAccount, @"Cannot start syncing.", @"Unable to lock account.");
            [_account reportError:lockError format:@"Error starting account agent. Unable to lock account."];
            if (outError)
                *outError = lockError;
            startFailed();
            return NO;
        }
    }
#endif
    
    NSURL *localContainersDirectory = [self _localContainersDirectory];

    // Build an index of the container directories we had and keep track of which are actually still in use (new version of an app might stop caring about a container).
    // -[NSFileManager contentsOfDirectoryAtURL:includingPropertiesForKeys:options:error:] returns non-standardized paths even when the input parent URL is standardized. So, we cannot make a set of unused directory NSURLs. Our last path component is fine, though.
    __autoreleasing NSError *error = nil;
    NSArray *existingContainerDirectoryURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:localContainersDirectory includingPropertiesForKeys:nil options:0 error:&error];
    if (!existingContainerDirectoryURLs) {
        if ([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]) {
            error = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtURL:localContainersDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
                [_account reportError:error format:@"Error creating local container directory %@", localContainersDirectory];
                if (outError)
                    *outError = error;
                startFailed();
                return NO;
            } else {
                existingContainerDirectoryURLs = [NSArray array]; // New empty directory; no containers yet.
            }
        } else {
            [_account reportError:error format:@"Unable to get existing container directories in %@", localContainersDirectory];
            if (outError)
                *outError = error;
            startFailed();
            return NO;
        }
    }
    
    OBASSERT(_metadataRegistrationTable == nil);
    _metadataRegistrationTable = [[OFXRegistrationTable alloc] initWithName:[NSString stringWithFormat:@"Sync Account Metadata %@", self.shortDescription]];
    
    _agentRegistrationTable[OFXCopyRegistrationKeyForAccountMetadataItems(_account.uuid)] = _metadataRegistrationTable;
    
    _queuedSyncCallbacksLock = [NSLock new];
    
    _operationQueue = [[NSOperationQueue alloc] init];
    _operationQueue.name = [self _operationQueueName];
    _operationQueue.maxConcurrentOperationCount = 1;
    
    _foregroundState = OFXAccountAgentStateStarted;
      
    _presentedItemOperationQueue = [[NSOperationQueue alloc] init];
    _presentedItemOperationQueue.name = [NSString stringWithFormat:@"%@ file presenter queue", [self shortDescription]];
    _presentedItemOperationQueue.maxConcurrentOperationCount = 1;
    
    // TODO: On the Mac, if an uncoordinated write happens, we don't find out about it. udb does, possibly via FSEvents, so maybe we should sign up for that too (though then doing file coordination on the thing being written is race-y);
    // NOTE: This retains us, so we cannot wait until -dealloc to do -removeFilePresenter:!
    if (_hasRegisteredAsFilePresenter == NO) {
        _hasRegisteredAsFilePresenter = YES;
        [NSFileCoordinator addFilePresenter:self];
        DEBUG_FILE_COORDINATION(1, @"Added as file presenter");
    } else {
        OBASSERT(_hasRelinquishedToWriter ==  YES, "We remain a file presenter while stopped only if we are relinquishing to a writer breifly");
    }

    [_operationQueue addOperationWithBlock:^{
        OBASSERT(_backgroundState == OFXAccountAgentStateCreated);
        _backgroundState = OFXAccountAgentStateStarted;
        
        _runningTransfers = [NSMutableSet new];
        
        OBASSERT(_uploadFileItemTransfers == nil);
        _uploadFileItemTransfers = [OFXFileItemTransfers new];
        
        OBASSERT(_downloadFileItemTransfers == nil);
        _downloadFileItemTransfers = [OFXFileItemTransfers new];
        
        OBASSERT(_deleteFileItemTransfers == nil);
        _deleteFileItemTransfers = [OFXFileItemTransfers new];
        
        NSMutableDictionary *unusedPathExtensionToLocalContainerURL = [NSMutableDictionary dictionary];
        for (NSURL *existingContainerDirectoryURL in existingContainerDirectoryURLs) {
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE && (!defined(TARGET_IPHONE_SIMULATOR) || !TARGET_IPHONE_SIMULATOR)
            OBASSERT([[existingContainerDirectoryURL URLByStandardizingPath] isEqual:existingContainerDirectoryURL] == NO); // assert the bad behavior is still bad, fwiw (works on the simulator...)
#endif
            
            OBASSERT(unusedPathExtensionToLocalContainerURL[existingContainerDirectoryURL.lastPathComponent] == nil);
            unusedPathExtensionToLocalContainerURL[existingContainerDirectoryURL.lastPathComponent] = existingContainerDirectoryURL;
        }
        
        OBASSERT(_containerIdentifierToContainerAgent == nil);
        _containerIdentifierToContainerAgent = [NSMutableDictionary new];
        
        if (OFXShouldSyncAllPathExtensions(_syncPathExtensions)) {
            // Register all the containers we found so that our first scan will notice existing document types
            [unusedPathExtensionToLocalContainerURL enumerateKeysAndObjectsUsingBlock:^(NSString *pathExtension, NSURL *localContainerURL, BOOL *stop) {
                OBASSERT([pathExtension isEqual:OFDirectoryPathExtension] == NO);
                NSString *containerIdentifier = [OFXContainerAgent containerAgentIdentifierForPathExtension:pathExtension];
                OFXContainerAgent *containerAgent = [self _containerAgentWithIdentifier:containerIdentifier];
                OBASSERT(containerAgent.started); OB_UNUSED_VALUE(containerAgent);
            }];
            [unusedPathExtensionToLocalContainerURL removeAllObjects];
        } else {
            for (NSString *pathExtension in _syncPathExtensions) {
                OBASSERT([pathExtension isEqual:OFDirectoryPathExtension] == NO);
                NSString *containerIdentifier = [OFXContainerAgent containerAgentIdentifierForPathExtension:pathExtension];
                OFXContainerAgent *containerAgent = [self _containerAgentWithIdentifier:containerIdentifier];
                OBASSERT(containerAgent.started);
                if (containerAgent)
                    [unusedPathExtensionToLocalContainerURL removeObjectForKey:pathExtension];
            }
        }
        
        // Can we tell if these are unused before the first scan? We might have snapshots in them and would get confused if we have published documents, snapshots and we just haven't noticed what the server has yet. Leave them for now.
#if 0
        [unusedPathExtensionToLocalContainerURL enumerateKeysAndObjectsUsingBlock:^(NSString *pathExtension, NSURL *existingContainerDirectoryURL, BOOL *stop) {
            NSError *removeError;
            OBFinishPorting; // TODO: Remove unused containers atomically. What if we have unpushed changes?
        }];
#endif
        
        [self _queueContentsChanged];
    }];
    
    return YES;
}

- (void)stop:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_foregroundState != OFXAccountAgentStateStarted) {
        [NSException raise:NSInternalInconsistencyException format:@"Called -stop on %@ while state is %ld", [self shortDescription], _foregroundState];
    }
    
    _foregroundState = OFXAccountAgentStateStopped; // Disallow further operation enqueuing
    
    // If we are stopping for -relinquishPresentedItemToWriter:, we remain a file presenter. Otherwise the reacquirer block we pass to the writer doesn't get invoked. Sub-optimal design choice in NSFileCoordinator...
    if (_hasRegisteredAsFilePresenter && !_hasRelinquishedToWriter) {
        DEBUG_FILE_COORDINATION(1, @"Removed as file presenter");
        
        [NSFileCoordinator removeFilePresenter:self];
        _hasRegisteredAsFilePresenter = NO; // Set this after actually unsubscribing, in case there is any actual interlock where they ensure stuff is all enqueued/cleaned up before returning...
    }
    
    [_stateRegistration invalidate];
    _stateRegistration = nil;
    
    [_metadataUpdateTimer invalidate];
    _metadataUpdateTimer = nil;
    
    completionHandler = [completionHandler copy];
    
    [_operationQueue addOperationWithBlock:^{
        // Ignore any further enqueued operations (particularly via our NSFilePresenter registration, which we can't flush out).
        OBASSERT(_backgroundState == OFXAccountAgentStateStarted);
        _backgroundState = OFXAccountAgentStateStopped;
        
        // Cancel unfinished transfers and then discard them.
        // All the bookkeeping operating will annotate the local snapshots so that we can create the exact right operations on the next run.
        for (OFXFileSnapshotTransfer *transfer in _runningTransfers)
            [transfer cancelForShutdown:YES];
        _runningTransfers = nil;
        
        // OBASSERT(_uploadRunningFileItems == nil); We can't assert this. We could have transfer operations that we are going to abandon. Even if we did wait for them, their completion handlers would come back to the queue we are currently running on (so we couldn't wait for them). Rather than convoluting stuff to allow waiting for the operations, we need to make all their completion handlers support abandonment.
        _uploadFileItemTransfers = nil;
        _downloadFileItemTransfers = nil;
        _deleteFileItemTransfers = nil;

        [_containerIdentifierToContainerAgent enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXContainerAgent *containerAgent, BOOL *stop) {
            [containerAgent stop];
        }];
        
        OBASSERT(_locked_queuedSyncCallbacks == nil); // should be cleared as the operations filter out of _operationQueue
        _locked_queuedSyncCallbacks = nil; // but just in case...
        _queuedSyncCallbacksLock = nil;
        _hasQueuedContentsScan = NO;
        
        [_agentRegistrationTable removeObjectForKey:OFXCopyRegistrationKeyForAccountMetadataItems(_account.uuid)];
        _metadataRegistrationTable  = nil;
        
        // We don't clear _infoDictionary here since we are on the background queue and it should only change on the foreground (for KVO). Any observers should soon stop observing us anyway since we are a use-once class.
        //_infoDictionary = nil;
        _containerIdentifierToContainerAgent = nil;
        _operationQueue = nil;
        
#if OFX_USE_LOCK_FILE
        [_lockFile unlockIfLocked];
        _lockFile = nil;
#endif
        
        if (_localDocumentsDirectoryHandle) {
            closedir(_localDocumentsDirectoryHandle);
            _localDocumentsDirectoryHandle = NULL;
        }
        
        if (completionHandler)
            completionHandler();
    }];
}

@synthesize foregroundSyncingEnabled = _foregroundSyncingEnabled;
- (BOOL)foregroundSyncingEnabled;
{
    OBPRECONDITION([NSThread isMainThread]);
    return _foregroundSyncingEnabled;
}

@synthesize backgroundSyncingEnabled = _backgroundSyncingEnabled;
- (BOOL)backgroundSyncingEnabled;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);
    return _backgroundSyncingEnabled;
}

- (BOOL)syncingEnabled;
{
    return self.foregroundSyncingEnabled;
}

- (void)setSyncingEnabled:(BOOL)syncingEnabled;
{
    OBPRECONDITION([NSThread isMainThread]);

    if (_foregroundSyncingEnabled == syncingEnabled)
        return;
    
    _foregroundSyncingEnabled = syncingEnabled;
    
    if (_operationQueue == nil) {
        // Setting this before we are started up.
        OBASSERT(_backgroundSyncingEnabled != syncingEnabled);
        _backgroundSyncingEnabled = syncingEnabled;
    } else {
        [_operationQueue addOperationWithBlock:^{
            OBASSERT(_backgroundSyncingEnabled != syncingEnabled);
            _backgroundSyncingEnabled = syncingEnabled;
            
            if (_backgroundSyncingEnabled) {
                if (self.backgroundState == OFXAccountAgentStateStarted) {
                    // We might have ignored deletions, which we don't make notes for. So, we need to do a full scan in this case.
                    // This will also rebuild any other transfers we had made notes for.
                    [self _queueContentsChanged];
                } else {
                    // Will happen when we get started.
                    OBASSERT(self.backgroundState == OFXAccountAgentStateCreated);
                }
            } else {
                [self _cancelTransfers]; // Stop any transfers that were running
                [self _clearRecentErrorsOnAllFileItems];
            }
        }];
    }
}

@synthesize foregroundAutomaticallyDownloadFileContents = _foregroundAutomaticallyDownloadFileContents;
- (BOOL)foregroundAutomaticallyDownloadFileContents;
{
    OBPRECONDITION([NSThread isMainThread]);
    return _foregroundAutomaticallyDownloadFileContents;
}

@synthesize backgroundAutomaticallyDownloadFileContents = _backgroundAutomaticallyDownloadFileContents;
- (BOOL)backgroundAutomaticallyDownloadFileContents;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);
    return _backgroundAutomaticallyDownloadFileContents;
}

- (BOOL)automaticallyDownloadFileContents;
{
    return self.foregroundAutomaticallyDownloadFileContents;
}

- (void)setAutomaticallyDownloadFileContents:(BOOL)automaticallyDownloadFileContents;
{
    OBPRECONDITION([NSThread isMainThread]);

    if (_foregroundAutomaticallyDownloadFileContents == automaticallyDownloadFileContents)
        return;
    _foregroundAutomaticallyDownloadFileContents = automaticallyDownloadFileContents;
    
    if (_operationQueue == nil) {
        // Setting this before we are started up.
        OBASSERT(_containerIdentifierToContainerAgent == nil);
        _backgroundAutomaticallyDownloadFileContents = automaticallyDownloadFileContents;
    } else {
        [_operationQueue addOperationWithBlock:^{
            _backgroundAutomaticallyDownloadFileContents = automaticallyDownloadFileContents;
            [_containerIdentifierToContainerAgent enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXContainerAgent *container, BOOL *stop) {
                container.automaticallyDownloadFileContents = automaticallyDownloadFileContents;
            }];
        }];
    }
}

- (void)sync:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_operationQueue);
    OBPRECONDITION(_queuedSyncCallbacksLock);
    OBPRECONDITION(!_account.hasBeenPreparedForRemoval, "should not start new sync operations on removed accounts");
    OBPRECONDITION(![NSString isEmptyString:_account.credentialServiceIdentifier]);
    
    DEBUG_SYNC(1, @"Queuing sync");
    
    // We don't early out here if self.foregroundSyncingEnabled is NO since we need to flush out any queued completion handlers.
    if (!completionHandler)
        completionHandler = ^{};
    completionHandler = [completionHandler copy];
        
    // If there are sync operations waiting, just add our completion handler to the callbacks.
    BOOL shouldProceed = YES;
    [_queuedSyncCallbacksLock lock];
    {
        if (_locked_queuedSyncCallbacks) {
            [_locked_queuedSyncCallbacks addObject:completionHandler];
            shouldProceed = NO;
        } else {
            _locked_queuedSyncCallbacks = [[NSMutableArray alloc] initWithObjects:completionHandler, nil];
        }
    }
    [_queuedSyncCallbacksLock unlock];
    
    if (!shouldProceed)
        return;

    // Even on failure, we queue up so that our completion handler will get called in the same sequence it would otherwise.
    __autoreleasing NSError *credentialError;
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(self.account.credentialServiceIdentifier, &credentialError);
    if (!credential) {
        // If the keychain is locked and the user clicks cancel, we'll get userCanceledErr (which -[NSError(OBExtensions) causedByUserCancelling] understands.
        [credentialError log:@"Error looking up credentials for %@ with identifier %@", self.account, self.account.credentialServiceIdentifier];
    }
    
    self.account.isSyncInProgress = YES;
    
    [_operationQueue addOperationWithBlock:^{
        // Get the list of queued callbacks and clear it, signalling that any further requests start a new batch
        NSArray *callbacks;
        [_queuedSyncCallbacksLock lock];
        {
            callbacks = _locked_queuedSyncCallbacks;
            _locked_queuedSyncCallbacks = nil;
        }
        [_queuedSyncCallbacksLock unlock];

        if (!credential) {
            DEBUG_SYNC(1, @"Skipped; could not look up credentials");
        } else if (self.backgroundState != OFXAccountAgentStateStarted) {
            DEBUG_SYNC(1, @"Stopped; not performing sync");
        } else if  (!self.backgroundSyncingEnabled) {
            DEBUG_SYNC(1, @"Syncing disabled; not performing sync");
        } else {
            if (_lastScanFailed) {
                // Do a scan right now, and if it fails, don't continue (in particular, don't clear the last error on the account).
                [self _performContentsChangedScan];
            }
            if (_lastScanFailed == NO) {
                //OBASSERT(_credentialsForCurrentSync == nil);
                @synchronized(self) {
                    _credentialsForCurrentSync = credential;
                }
                [self _performSync];
                
                // We leave this set so that transfers that fire up w/o a full sync don't get an assertion/missing credentials.
                // @synchronized(self) {
                //    _credentialsForCurrentSync = nil;
                // }
            }
        }
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            for (void (^handler)(void) in callbacks)
                handler();
            self.account.isSyncInProgress = NO;
        }];
    }];
}

- (void)_performSync;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);

    if (self.backgroundState != OFXAccountAgentStateStarted) {
        OBASSERT_NOT_REACHED("Should be running");
        return;
    }
    
    DEBUG_SYNC(1, @"Performing sync");
    
    // Reset our recent redirects before making a connection so that we get fresh ones for this sync (which our containers can then use).
    // TODO: Keep redirects that have an explicit cache control that makes them still valid. For example, we get back "max-age=20, public" from sync.omnigroup.com.
    if (_recentRedirects) {
        DEBUG_SYNC(1, @"Clearing redirects from previous sync");
        _recentRedirects = nil;
    }
    
    ODAVConnection *connection = [self _makeConnection];
    if (!connection) {
        OBASSERT_NOT_REACHED("Our -_makeConnection currently always succeeds");
        return;
    }
    
    if (!OFXShouldSyncAllPathExtensions(_syncPathExtensions)) {
        // We are syncing only a specific subset of files and should have container agents for them already.
#ifdef OMNI_ASSERTIONS_ON
        for (NSString *pathExtension in _syncPathExtensions) {
            NSString *identifier = [OFXContainerAgent containerAgentIdentifierForPathExtension:pathExtension];
            OBASSERT(_containerIdentifierToContainerAgent[identifier] != nil);
        }
#endif
    }
    
    // We can be racing with other clients updating the account's Info.plist or client plists. Try this a few times if hit file-missing errors.
    __autoreleasing NSError *error;
    __autoreleasing NSDate *serverDate;
    NSArray <ODAVFileInfo *> *containerFileInfos = nil;
    for (NSUInteger try = 0; !containerFileInfos && try < 5; try++) {
        serverDate = nil;
        error = nil;
        containerFileInfos = [self _upateInfoAndCollectContainerIdentifiersWithConnection:connection serverDate:&serverDate error:&error];
        if (!containerFileInfos) {
            if ([error causedByMissingFile]) {
                // probably racing
                [NSThread sleepForTimeInterval:2*OFRandomNextDouble()];
            } else {
                break; // something else -- maybe lost connectivity
            }
        }
    }
    if (!containerFileInfos) {
        [_account reportError:error];
        return;
    } else {
        [_account clearError]; // server access appears to be working
    }
    
    // Propagate the net group to the foreground
    {
        NSString *groupIdentifier = _info.groupIdentifier;
        __weak OFXAccountAgent *weakSelf = self;
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            OFXAccountAgent *strongSelf = weakSelf;
            if (!strongSelf)
                return; // Stopped and deallocated before the info dictionary fetch finished?
            
            if (strongSelf.started == NO) // Stopped since this was queued up
                return;
            
            // Fire KVO on the main thread
            self.netStateRegistrationGroupIdentifier = groupIdentifier;
            
            if (OFNOTEQUAL(_stateRegistration.groupIdentifier, groupIdentifier)) {
                DEBUG_SYNC(1, @"Group identifier %@", groupIdentifier);
                
                [_stateRegistration invalidate];
                _stateRegistration = nil;
                
                // We publish one state for the whole account. We used to do one per container. This was nice so that iOS apps would only hear about changes to the kinds of files they could operate on, but with a Mac online with a ton of documents in its sync'd folder, we would get zillions of registrations (and could provoke errors/throttling in mDNS). Most likely, if you are working at your Mac, your iOS apps will be backgrounded or the device asleep anyway.
                if (![NSString isEmptyString:groupIdentifier])
                    _stateRegistration = [[OFNetStateRegistration alloc] initWithGroupIdentifier:self.netStateRegistrationGroupIdentifier memberIdentifier:_agentMemberIdentifier name:self.debugName state:nil];
            }
        }];
    }
    
    // Remember what identifiers the server knows about.
    NSMutableSet <NSString *> *serverContainerIdentifiers = [NSMutableSet new];
    
    for (ODAVFileInfo *containerFileInfo in containerFileInfos) {
        NSURL *remoteContainerURL = containerFileInfo.originalURL;
        OBASSERT([[remoteContainerURL pathExtension] isEqual:OFXContainerPathExtension]);
        
        NSString *identifier = [[[remoteContainerURL lastPathComponent] stringByDeletingPathExtension] lowercaseString];
        
        if ([identifier isEqual:[OFXContainerAgent containerAgentIdentifierForPathExtension:OFDirectoryPathExtension]]) {
            OBASSERT_NOT_REACHED("What happens if the server adds 'folder.container'?");
            continue;
        }

        [serverContainerIdentifiers addObject:identifier];
        
        // Start up containers for new identifiers if we are running in unfiltered mode.
        if (OFXShouldSyncAllPathExtensions(_syncPathExtensions))
            [self _containerAgentWithIdentifier:identifier];
        
        // For containers we do have, if they've changed since last sync, give them a chance to sync.
        OFXContainerAgent *containerAgent = _containerIdentifierToContainerAgent[identifier];
        if (containerAgent) {
            __autoreleasing NSError *containerError;
            if (![containerAgent syncIfChanged:containerFileInfo serverDate:serverDate connection:connection error:&containerError]) {
                NSLog(@"Error syncing container %@: %@", [containerAgent shortDescription], containerError);
            }
        }
        
        // TODO: Do we need to deal with containers that have gone missing on the server? If we don't, then the next time we're fired up, we might upload all the files again instead of treating them like deletes. Unclear how we want to clean up containers that are no longer in use.
    }
    
    _serverContainerIdentifiers = [serverContainerIdentifiers copy];
    
    // If no transfers were started already, try again. We might have some local files sitting around that need to be uploaded, but failed to due to a previous error (so no new changes, just previous failures).
    if ([_runningTransfers count] == 0 && _uploadFileItemTransfers.empty && _downloadFileItemTransfers.empty && _deleteFileItemTransfers.empty) {
        [self containerNeedsFileTransfer:nil requestRecorded:^{
            // If someone is waiting on this block, let them proceed.
            DEBUG_TRANSFER(2, @"Transfer request recorded");
        }];
    } else {
        DEBUG_TRANSFER(2, @"Already had transfers queued.");
    }
}

- (NSArray <ODAVFileInfo *> *)_upateInfoAndCollectContainerIdentifiersWithConnection:(ODAVConnection *)connection serverDate:(NSDate **)outServerDate error:(NSError **)outError;
{
    // We store the main Info.plist, client files and containers in a flat hierarchy in the remote account. This allows us to do a single PROPFIND to see everything that has changed.
    ODAVMultipleFileInfoResult *result = OFXFetchFileInfosEnsuringDirectoryExists(connection, [self _remoteSyncDirectory], outError);
    if (!result) {
        OBChainError(outError);
        return nil;
    }
    DEBUG_SYNC(1, @"Found %ld items", [result.fileInfos count]);

    // Remember the redirects we see in this initial PROPFIND. This is particularly important for writing files with our atomic MOVE pattern since a MOVE to a redirected location will sometimes just return 302, not happen, and NSURLConnection won't give us a chance to handle the redirect and for rename-only uploads which do a COPY.
    if ([result.redirects count] > 0) {
        // We clear this at the beginning of a sync so that if the user gets migrated to a new server we don't keep talking to the old one.
        _recentRedirects = [result.redirects copy];
        [connection updateBaseURLWithRedirects:_recentRedirects];

        DEBUG_SYNC(1, @"Updating connection base URL with redirects; new base URL is %@", connection.baseURL);
    }
    
    // Partition the files into their various types.
    NSMutableArray <ODAVFileInfo *> *clientFileInfos = [NSMutableArray new];
    NSMutableArray <ODAVFileInfo *> *containerFileInfos = [NSMutableArray new];
    ODAVFileInfo *accountFileInfo;
    
    ODAVFileInfo *remoteTemporaryDirectoryFileInfo;
    for (ODAVFileInfo *fileInfo in result.fileInfos) {
        NSURL *fileURL = fileInfo.originalURL;
        NSString *pathExtension = [fileURL pathExtension];
        
        if ([pathExtension isEqual:OFXContainerPathExtension])
            [containerFileInfos addObject:fileInfo];
        else if ([pathExtension isEqual:OFXClientPathExtension])
            [clientFileInfos addObject:fileInfo];
        else if ([[fileURL lastPathComponent] isEqual:OFXInfoFileName]) {
            accountFileInfo = fileInfo;
        } else if ([[fileURL lastPathComponent] isEqual:RemoteTemporaryDirectoryName]) {
            remoteTemporaryDirectoryFileInfo = fileInfo;
            // skip the temporary directory
        } else {
            NSLog(@"Unrecognized item in remote account %@", [fileInfo shortDescription]);
        }
    }
    
    if (!_info) {
        _info = [[OFXAccountInfo alloc] initWithLocalAccountDirectory:_localAccountDirectory remoteAccountURL:[self _remoteSyncDirectory] temporaryDirectoryURL:[self _remoteTemporaryDirectory] clientParameters:_clientParameters error:outError];
        if (!_info) {
            OFXError(outError, OFXAccountScanFailed, @"Error creating account info", nil);
            return nil;
        }
    }
    
    if (![_info updateWithConnection:connection accountFileInfo:accountFileInfo clientFileInfos:clientFileInfos remoteTemporaryDirectoryFileInfo:remoteTemporaryDirectoryFileInfo serverDate:result.serverDate error:outError]) {
        OFXError(outError, OFXAccountScanFailed, @"Error updating account info", nil);
        return nil;
    }
    
    if (outServerDate)
        *outServerDate = result.serverDate;
    return containerFileInfos;
}

- (BOOL)containsLocalDocumentFileURL:(NSURL *)fileURL;
{
    return OFURLContainsURL(_account.localDocumentsURL, fileURL);
}

- (void)containerNeedsFileTransfer:(OFXContainerAgent *)container;
{
    return [self containerNeedsFileTransfer:container requestRecorded:nil];
}

- (void)containerNeedsFileTransfer:(OFXContainerAgent *)transferContainer requestRecorded:(void (^)(void))requestRecorded;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);
    
    if (self.backgroundSyncingEnabled == NO) {
        // Don't buffer requested transfers here if we aren't going to do them. We call this method when syncing is unpaused, and if we do so, and the request is already queued, then our 'started' flag will be NO and we won't start the already-buffered requested transfers (we're expecting one to finish to pump the next start).
        DEBUG_TRANSFER(2, @"Syncing disabled -- not recording needed transfers.");
        if (requestRecorded)
            requestRecorded(); // as started as they are likely to get...
        return;
    }
    
    // This can get called just as a transfer is finishing (for example, we may have downloaded metadata for an remotely updated file item and now want contents). We coalesce and delay these requests so that the old transfer is cleared from the running set before we check for redundant requests.
    if (_hasQueuedContainerNeedsFileTransfers) {
        // Still need to call our completion handler after the request filters out. Chain this new operation for the next caller.
        DEBUG_TRANSFER(2, @"Transfer recording already queued, not queuing another.");
        if (requestRecorded)
            [_operationQueue addOperationWithBlock:requestRecorded];
        return;
    }
    _hasQueuedContainerNeedsFileTransfers = YES;
    
    if (requestRecorded) {
        NSOperationQueue *queue = _operationQueue; // Might get cleared if we are stopped quickly after this
        void (^originalRequestRecorded)(void) = [requestRecorded copy];
        requestRecorded = ^{
            [queue addOperationWithBlock:originalRequestRecorded];
        };
    }
    
    DEBUG_TRANSFER(2, @"Queuing transfer operation collection");
    [_operationQueue addOperationWithBlock:^{
        DEBUG_TRANSFER(2, @"Performing transfer operation collection");
        _hasQueuedContainerNeedsFileTransfers = NO;

        if (self.backgroundState != OFXAccountAgentStateStarted) {
            // Got shutdown while we were queued?
            DEBUG_TRANSFER(2, @"Stopping collection transfer -- agent not started");
            if (requestRecorded)
                requestRecorded(); // as started as they are likely to get...
            return;
        }

        if (self.backgroundSyncingEnabled == NO) {
            // Check again... might have been disabled while we were queued up.
            DEBUG_TRANSFER(2, @"Stopping collection transfer -- syncing disabled");
            if (requestRecorded)
                requestRecorded(); // as started as they are likely to get...
            return;
        }
        
        __block BOOL started = NO;
        [_containerIdentifierToContainerAgent enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXContainerAgent *container, BOOL *stop) {
            DEBUG_TRANSFER(2, @"Checking container %@", identifier);
            [container collectNeededFileTransfers:^(OFXFileItem *fileItem, OFXFileItemTransferKind kind){
                OFXFileItemTransfers *transfers;
                
                NSString *kindName;
                if (kind == OFXFileItemUploadTransferKind) {
                    // We have to handle doing an upload of missing+moved, which would otherwise not be valid for upload. The upload transfer handles this case.
                    OBASSERT(fileItem.isValidToUpload || (fileItem.localState.missing && fileItem.localState.userMoved && !fileItem.remoteState.missing && !fileItem.remoteState.deleted));
                    OBASSERT(fileItem.remoteState.missing || fileItem.localState.edited || fileItem.localState.userMoved);
                    transfers = _uploadFileItemTransfers;
                    kindName = @"upload";
                } else if (kind == OFXFileItemDownloadTransferKind) {
                    OBASSERT(fileItem.localState.missing || fileItem.remoteState.edited || fileItem.remoteState.userMoved);
                    transfers = _downloadFileItemTransfers;
                    kindName = @"download";
                } else if (kind == OFXFileItemDeleteTransferKind) {
                    OBASSERT(fileItem.localState.deleted);
                    transfers = _deleteFileItemTransfers;
                    kindName = @"delete";
                } else {
                    OBASSERT_NOT_REACHED("Unknown transfer kind %ld", kind);
                    return;
                }
                OBASSERT(transfers);
                
                // Make sure we don't start redundant transfers. When transfers end, the container should check if another is needed.
                if ([transfers containsFileItem:fileItem]) {
                    DEBUG_TRANSFER(2, @"Skipping possibly redundant request for transfer of %@", fileItem);
                    return;
                }
                
                DEBUG_TRANSFER(1, @"Requesting %@ of %@", kindName, fileItem.shortDescription);
                [transfers addRequestedFileItem:fileItem];
                
                if (!started) {
                    started = YES;
                    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
                    NSString *description;
                    if (kind == OFXFileItemDeleteTransferKind)
                        description = [NSString stringWithFormat:@"%@ %@", kindName, fileItem.identifier]; // can't ask for -localDocumentURL
                    else
                        description = [NSString stringWithFormat:@"%@ %@", kindName, fileItem.localDocumentURL]; // capture the URL as of now.
                    
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:OFXAccountTransfersNeededNotification object:_account userInfo:@{OFXAccountTransfersNeededDescriptionKey: description}];
                    }];
#endif
                }
            }];
        }];
        
        DEBUG_TRANSFER(2, @"Finished consulting containers for transfers");

        if (started) {
            DEBUG_TRANSFER(2, @"Starting transfers");
            [self _startTransferOperations];
        }
        if (requestRecorded)
            requestRecorded();
    }];
}

- (void)containerPublishedFileVersionsChanged:(OFXContainerAgent *)container;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);
    OBPRECONDITION(self.backgroundState == OFXAccountAgentStateStarted);

    NSMutableArray <NSString *> *fileVersions = [NSMutableArray new];
    [_containerIdentifierToContainerAgent enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXContainerAgent *containerAgent, BOOL *stop) {
        NSArray <NSString *> *containerFileVersions = containerAgent.publishedFileVersions;
        if (containerFileVersions)
            [fileVersions addObjectsFromArray:containerFileVersions];
    }];
    
    [fileVersions sortUsingSelector:@selector(compare:)];
    NSString *editState = [fileVersions componentsJoinedByComma];
    
    // Now that we have all the identifiers, pop over to the main queue to poke our state registration. It handles having its state set from a background serial queue (as long as there is only one writer), but we want to make lifecycle assertions
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        if (self.foregroundState != OFXAccountAgentStateStarted) {
            OBASSERT(_stateRegistration == nil);
            return;
        }
        
        // We might still not have a state registration since we might not have finished fetching our Info.plist.
        if (_stateRegistration) {
            DEBUG_SYNC(2, @"Publishing edit state \"%@\"", editState);
            _stateRegistration.localState = [editState dataUsingEncoding:NSUTF8StringEncoding];
        }
    }];
}

// Either the error handler is called (for preflight problems), or the action, but not both.
- (void)_operateOnFileAtURL:(NSURL *)fileURL errorHandler:(void (^)(NSError *error))errorHandler withAction:(void (^)(OFXContainerAgent *))containerAction;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (self.foregroundState != OFXAccountAgentStateStarted)
        [NSException raise:NSGenericException format:@"Attempted to invoke a container action while the account agent %@ was not runnning", [self shortDescription]];
    
    errorHandler = [errorHandler copy];
    containerAction = [containerAction copy];
    
    [_operationQueue addOperationWithBlock:^{
        if (self.backgroundState != OFXAccountAgentStateStarted) {
            OBASSERT_NOT_REACHED("Should be running");
            return;
        }
        
        NSString *containerIdentifier = [OFXContainerAgent containerAgentIdentifierForFileURL:fileURL];
        if ([NSString isEmptyString:containerIdentifier]) {
            if (errorHandler) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    __autoreleasing NSError *error;
                    OFXError(&error, OFXDownloadFailed, @"No container identifier.", nil);
                    errorHandler(error);
                }];
            }
            return;
        }
        
        OFXContainerAgent *containerAgent = _containerIdentifierToContainerAgent[containerIdentifier];
        if (!containerAgent) {
            if (errorHandler) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    __autoreleasing NSError *error;
                    OFXError(&error, OFXDownloadFailed, @"Attempted download of file type that this app doesn't sync.", nil);
                    errorHandler(error);
                }];
            }
        }

        // Expected to call the completion handler itself.
        containerAction(containerAgent);
    }];
}

- (void)requestDownloadOfItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);

    completionHandler = [completionHandler copy];
    
    [self _operateOnFileAtURL:fileURL errorHandler:completionHandler withAction:^(OFXContainerAgent *container){
        [container downloadFileAtURL:fileURL completionHandler:^(NSError *errorOrNil) {
            if (completionHandler) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    completionHandler(errorOrNil);
                }];
            }
        }];
    }];
}

- (void)deleteItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);

    completionHandler = [completionHandler copy];
    
    [self _operateOnFileAtURL:fileURL errorHandler:completionHandler withAction:^(OFXContainerAgent *container){
        [container deleteItemAtURL:fileURL completionHandler:^(NSError *errorOrNil) {
            if (completionHandler) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    completionHandler(errorOrNil);
                }];
            }
        }];
    }];
}

- (void)moveItemAtURL:(NSURL *)originalFileURL toURL:(NSURL *)updatedFileURL completionHandler:(void (^)(OFFileMotionResult *moveResult, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);

    completionHandler = [completionHandler copy];
    
    [self _operateOnFileAtURL:originalFileURL errorHandler:^(NSError *error){
        OBASSERT([NSThread isMainThread]);
        if (completionHandler)
            completionHandler(nil, error);
    } withAction:^(OFXContainerAgent *container){
        [container moveItemAtURL:originalFileURL toURL:updatedFileURL completionHandler:^(OFFileMotionResult *moveResult, NSError *errorOrNil) {
            if (completionHandler) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    completionHandler(moveResult, errorOrNil);
                }];
            }
        }];
    }];
}

- (NSUInteger)_countPendingTransfers;
{
    OBASSERT([self runningOnAccountAgentQueue]);
    
    // We report zero when stopped instead of an error, but we might change that later if it is more useful.
    NSUInteger count = 0;
    
    count += _uploadFileItemTransfers.numberRequested + _uploadFileItemTransfers.numberRunning;
    count += _downloadFileItemTransfers.numberRequested + _downloadFileItemTransfers.numberRunning;
    count += _deleteFileItemTransfers.numberRequested + _deleteFileItemTransfers.numberRunning;
    
    DEBUG_TRANSFER(2, @"Counting pending transfers: %lu", count);
    return count;
}

- (void)countPendingTransfers:(void (^)(NSError *errorOrNil, NSUInteger count))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);

    [_operationQueue addOperationWithBlock:^{
        NSUInteger count = [self _countPendingTransfers];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            completionHandler(nil, count);
        }];
    }];
}

- (NSUInteger)_countFileItemsWithLocalChanges;
{
    OBASSERT([self runningOnAccountAgentQueue]);

    __block NSUInteger count = 0;
    [_containerIdentifierToContainerAgent enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXContainerAgent *container, BOOL *stop) {
        [container collectNeededFileTransfers:^(OFXFileItem *fileItem, OFXFileItemTransferKind kind) {
            if (kind == OFXFileItemUploadTransferKind)
                count++;
        }];
    }];
    return count;
}

- (void)countFileItemsWithLocalChanges:(void (^)(NSError *errorOrNil, NSUInteger count))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);

    if (_operationQueue == nil) {
        __autoreleasing NSError *error = nil;
        OFXError(&error, OFXAgentNotStarted, @"Unable to count changed documents when an account isn't syncing.", nil);
        completionHandler(error, NSNotFound);
        return;
    }

    [_operationQueue addOperationWithBlock:^{
        NSUInteger count = [self _countFileItemsWithLocalChanges];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            completionHandler(nil, count);
        }];
    }];
}

// Allow callers to do something after all the currently queued operations are done.
- (NSOperation *)afterAsynchronousOperationsFinish:(void (^)(void))block;
{
    OBPRECONDITION(self.foregroundState == OFXAccountAgentStateStarted); // Don't call after stopping
    NSBlockOperation *blockOperation = [NSBlockOperation blockOperationWithBlock:block];
    
    NSOperationQueue *queue = [NSOperationQueue currentQueue];
    OBASSERT(queue);
    OBASSERT(queue != _operationQueue);
    OBASSERT(_operationQueue);
    
    // Wait for the main agent queue
    [_operationQueue addOperationWithBlock:^{
        OBASSERT(_backgroundState == OFXAccountAgentStateStarted);

        // The container agents are using our operation queue currently, so we don't ask for them to wait (which would hit assertions intended to catch deadlock).
        [queue addOperation:blockOperation];
    }];
    
    return blockOperation;
}

- (BOOL)runningOnAccountAgentQueue;
{
    NSOperationQueue *currentQueue = [NSOperationQueue currentQueue];
    
    if (_operationQueue)
        return (currentQueue == _operationQueue);

    // We are in the middle of stopping and we've nilled out our queue. This is ugly and we might be better off doing it a different way...
    return [currentQueue.name isEqualToString:[self _operationQueueName]];
}

#pragma mark - NSFilePresenter

- (NSURL *)presentedItemURL;
{
    NSURL *documentsURL = _account.localDocumentsURL;
    OBPRECONDITION(documentsURL);
    
    // This can get called on multiple threads (but our _account should never change and its localDocumentsURL is immutable as well).
    return documentsURL;
}

- (NSOperationQueue *)presentedItemOperationQueue;
{
    OBPRECONDITION(_presentedItemOperationQueue); // Otherwise NSFileCoordinator may try to enqueue blocks and they'll never get started, yielding mysterious deadlocks.
    return _presentedItemOperationQueue;
}

// This gets called when our local documents directory is the target of a coordinated operation. Importantly, this is hit when the user moves the documents folder AND when a parent folder is renamed. -presentedItemDidMoveToURL: is called in the former case, but not the latter. But we don't need the message since we have a bookmark URL. So, we relinquish here by stopping our agent (ensuring that we are not looking at the directory) and then restarting. Importantly, NSFileCoordinator does _not_ call the reacquirer block passed to the writer if you unsubscribe as a file presenter. We could maybe get around this by doing a coordinated read of the directory in our -start: method, but it isn't clear what we should perform a coordinated read on (if there is a move about to happen our bookmark might resolve to the old URL since we are racing). To avoid this, we signal that we are stopping due to relinquishing to a writer and we remain a file presenter.
- (void)relinquishPresentedItemToWriter:(void (^)(void (^reacquirer)(void)))writer;
{
    OBPRECONDITION(_hasRelinquishedToWriter == NO);
    
    DEBUG_FILE_COORDINATION(1, @"relinquishing to writer");
    
    writer = [writer copy];
    _hasRelinquishedToWriter = YES;
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self stop:^{
            writer(^{
                DEBUG_FILE_COORDINATION(1, @"reacquiring from writer");

                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    OBASSERT(_hasRelinquishedToWriter == YES);
                    OBASSERT(_hasRegisteredAsFilePresenter == YES);
                    _hasRelinquishedToWriter = NO;
                    
                    // Do this cleanup that -stop: skipped so that our reacquire block would be called.
                    if (_hasRegisteredAsFilePresenter) {
                        _hasRegisteredAsFilePresenter = NO;
                        [NSFileCoordinator removeFilePresenter:self];
                        DEBUG_FILE_COORDINATION(1, @"Removed as file presenter");
                    }
                    
                    // Yell for help for the OFXAgent to start a new agent for this account.
                    [[NSNotificationCenter defaultCenter] postNotificationName:OFXAccountAgentDidStopForReplacementNotification object:self userInfo:nil];
                }];
            });
        }];
    }];
}

- (void)presentedSubitemAtURL:(NSURL *)oldURL didMoveToURL:(NSURL *)newURL;
{
    OBPRECONDITION([oldURL isFileURL]);
    OBPRECONDITION(![oldURL isFileReferenceURL]);
    OBPRECONDITION([newURL isFileURL]);
    OBPRECONDITION([NSOperationQueue currentQueue] == _presentedItemOperationQueue);
    OBPRECONDITION(_edits.relinquishToWriter == NO); // Sadly, we don't get a writer block for sub-items. Make sure we notice if this changes.

    // De-registering file presenters has no synchronization... and sub-item notifications can be queued up.
    if (_hasRegisteredAsFilePresenter == NO)
        return;

    DEBUG_FILE_COORDINATION(1, @"presentedSubitemAtURL:%@ didMoveToURL:%@", oldURL, newURL);
    
    // On OS X, at least, we sometimes get file reference URLs here. This seems a bit goofy since they update their path in response to file system changes, but this method is to tell us about such changes. Also, I've seen cases were they stop working after a coordinated move of a file in Finder (the -path starts returning nil).
    if ([newURL isFileReferenceURL]) {
        newURL = [newURL filePathURL];
        if ([newURL path] == nil) {
            OBASSERT_NOT_REACHED("Hopefully can't go bad this soon, but if it does then just do a full scan");
            [self _queueContentsChanged];
            return;
        }
    }

    [_operationQueue addOperationWithBlock:^{
        if (self.backgroundState != OFXAccountAgentStateStarted)
            return;
        [self _handleSubitemAtURL:oldURL didMoveToURL:newURL];
    }];
}

- (void)presentedSubitemDidChangeAtURL:(NSURL *)url;
{
    // De-registering file presenters has no synchronization... and sub-item notifications can be queued up.
    if (_hasRegisteredAsFilePresenter == NO)
        return;

    // This method can be received when doing a case-only rename ("foo" to "Foo"), on both Mac and iOS, *instead* of -presentedSubitemAtURL:didMoveToURL:. The old URL is passed, but we don't have a great way to intuit the rename from this. So, we do renames with a file presenter registered and publish the rename ourselves via -[OFXFileItem didMoveToURL:].
    DEBUG_FILE_COORDINATION(1, @"presentedSubitemDidChangeAtURL: %@", [url absoluteString]);
    
    if (_edits.relinquishToWriter) {
        DEBUG_SYNC(1, @"  Inside writer; delay handling change");
        _edits.changed = YES; // Defer until we reacquire
    } else {
        [self _queueContentsChanged];
    }
}

// Doesn't get called, -presentedSubitemDidChangeAtURL: gets called with the deleted sub-item URL.
//- (void)accommodatePresentedSubitemDeletionAtURL:(NSURL *)url completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    if (_debugName)
        return [NSString stringWithFormat:@"<Account %@.%@ %p>", _debugName, _account.credentialServiceIdentifier, self];
    return [super shortDescription];
}

#pragma mark - Internal

- (ODAVConnection *)_makeConnection;
{
    ODAVConnectionConfiguration *configuration = [OFXAgent makeConnectionConfiguration];
    
    ODAVConnection *connection = [[ODAVConnection alloc] initWithSessionConfiguration:configuration baseURL:self.remoteBaseDirectory];

#ifdef DEBUG_bungi
    // Show or flakey networks (or just servers you can't reach because you're not on the vpn) will fail this.
    OBExpectDeallocation(connection); // These shouldn't be long lived...
#endif
    connection.userAgent = _debugName;
    
#if 0  // Seems redundant: if we don't implement this, we'll just bubble this error up to the invoker, who will present it if that makes sense.
    connection.validateCertificateForChallenge = ^NSURLConnection *(NSURLAuthenticationChallenge *challenge){
        // This gets called on an anonymous queue, but -reportError: just dispatches to the main queue, we we are safe
        [_account reportError:[NSError certificateTrustErrorForChallenge:challenge]];
        return nil;
    };
#endif
    
    connection.findCredentialsForChallenge = ^NSOperation <OFCredentialChallengeDisposition> *(NSURLAuthenticationChallenge *challenge){
        // This gets called on an anonymous queue, so we need to serialize access to our state
        if ([challenge previousFailureCount] <= 2) {
            NSURLCredential *credential;
            @synchronized(self) {
                credential = _credentialsForCurrentSync; // Set on the bookkeeping queue, but this will be called on a private queue for DAV operations
            }
            // This will legitimately be nil in -[OFXAgentAccountChangeTestCase testRemoveAccount] since we can have a sync running and then have removed the account before the sync finishes.
            // TODO: Still true?
            OBASSERT(credential);
            return OFImmediateCredentialResponse(NSURLSessionAuthChallengeUseCredential, credential);
        }
        return nil;
    };
    
    // Propagate the redirect from a recent top-level sync to containers that are going to try transfers.
    if (_recentRedirects) {
        [connection updateBaseURLWithRedirects:_recentRedirects];
        DEBUG_SYNC(1, @"Applying recent redirects to new connection");
    }
    
    return connection;
}

- (void)_fileItemDidDetectUnknownRemoteEdit:(OFXFileItem *)fileItem;
{
    // We need to do a scan to find the new conflict version and generate a file item for it.
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        if (self.started) // Maybe stopped in the mean time...
            [self sync:nil];
    }];
}

- (void)_containerAgentNeedsMetadataUpdate:(OFXContainerAgent *)container;
{
    OBPRECONDITION([self runningOnAccountAgentQueue]);
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        if (_foregroundState != OFXAccountAgentStateStarted) {
            // Stopped in the mean time...
            OBASSERT(_metadataUpdateTimer == nil);
            return;
        }
        
        if (!_metadataUpdateTimer) {
            // When running tests we want faster updates to metadata so we can catch files while they are downloading.
            NSTimeInterval updateInterval = _clientParameters.metadataUpdateInterval;
            
            _metadataUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:updateInterval target:self selector:@selector(_performContainerMetadataUpdates:) userInfo:nil repeats:NO];
            [_metadataUpdateTimer setTolerance:updateInterval*0.1];
        }
    }];
}

- (NSString *)debugName;
{
    return _debugName;
}

#pragma mark - Private

- (NSString *)_localRelativePathForFileURL:(NSURL *)fileURL;
{
    return OFFileURLRelativePath(_account.localDocumentsURL, fileURL);
}

- (NSString *)_localRelativePathForDirectoryURL:(NSURL *)directoryURL;
{
    NSString *relativePath = OFFileURLRelativePath(_account.localDocumentsURL, directoryURL);
    if (![relativePath hasSuffix:@"/"])
        relativePath = [relativePath stringByAppendingString:@"/"];
    return relativePath;
}

- (void)_queueContentsChanged;
{
    DEBUG_SCAN(2, @"Queuing contents changed update");
    
    // Avoid stacking up multiple scans requests. This can get called on the file presenter queue or our operation queue, so protect our lookup/assignment of _hasQueuedContentsScan.
    @synchronized(self) {
        if (_hasQueuedContentsScan)
            return;
        _hasQueuedContentsScan = YES;
        _lastScanFailed = NO;
    }
    
    // RACE: Might get notified of a change that happens right as -stop is running since +[NSFileCoordinator removeFilePresenter:]'s synchronization isn't defined.
    [_operationQueue addOperationWithBlock:^{
        @synchronized(self) {
            _hasQueuedContentsScan = NO;
        }
        
        if (self.backgroundState != OFXAccountAgentStateStarted) {
            DEBUG_SCAN(1, @"Stopped; not performing contents changed update");
            return;
        }
        [self _performContentsChangedScan];
    }];
}

- (void)_performContentsChangedScan;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);
    
    DEBUG_SCAN(2, @"Performing contents changed update with containers %@", _containerIdentifierToContainerAgent);
    
    NSMutableSet *knownPackagePathExtensions = [NSMutableSet setWithSet:_localPackagePathExtensions];
    
    NSMutableDictionary *containerIdentifierToScan = [NSMutableDictionary new];
    [_containerIdentifierToContainerAgent enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXContainerAgent *container, BOOL *stop) {
        // Treat remote containers as defining package-ness too.
        if ([OFXContainerAgent containerAgentIdentifierRepresentsPathExtension:container.identifier])
            [knownPackagePathExtensions addObject:container.identifier];
        
        containerIdentifierToScan[identifier] = [container beginScan];
    }];
    
    void (^itemBlock)(NSFileManager *fileManager, NSURL *fileURL) = ^(NSFileManager *fileManager, NSURL *fileURL){
        DEBUG_SCAN(1, @"Found document at %@", fileURL);
        
        NSString *containerIdentifier = [OFXContainerAgent containerAgentIdentifierForFileURL:fileURL];
        OFXContainerScan *scan = containerIdentifierToScan[containerIdentifier];
        if (!scan) {
            OFXContainerAgent *containerAgent = [self _containerAgentWithIdentifier:containerIdentifier];
            if (!containerAgent) {
                OBASSERT_NOT_REACHED("We have a file laying around for a container that we haven't created and refuse to create?"); // We we have the wildcard container identifier, we'll create one here
            } else {
                scan = [containerAgent beginScan];
                containerIdentifierToScan[containerIdentifier] = scan;
            }
        }
        
        [scan scannedFileAtURL:fileURL];
    };
    
    // Items could be moving around in the container, the user could have done something like `chmod 0 MyFolder`, rendering the contents invisible to us, or -- the case we've seen once in real life, the sandbox could spuriously decide to deny some of our directory scans. At any rate, if our gazing about for files might have missed some due to errors, don't interpret this as deletion!
    __block NSError *scanError = nil;
    OFScanErrorHandler errorHandler = ^(NSURL *fileURL, NSError *error){
        [error log:@"Scan failed at %@", fileURL];
        scanError = error;
        return NO;
    };
    
    OFScanPathExtensionIsPackage isPackage = OFIsPackageWithKnownPackageExtensions(knownPackagePathExtensions);
    OFScanDirectory(_account.localDocumentsURL, YES/*shouldRecurse*/, nil/*filterBlock*/, isPackage, itemBlock, errorHandler);
    
    if (scanError) {
        _lastScanFailed = YES;
        [_account reportError:scanError format:@"Error scanning local documents directory"];
        return;
    }
    
    OBASSERT([_containerIdentifierToContainerAgent count] == [containerIdentifierToScan count]);
    [_containerIdentifierToContainerAgent enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXContainerAgent *container, BOOL *stop) {
        OFXContainerScan *scan = containerIdentifierToScan[identifier];
        __autoreleasing NSError *error;
        if (![container finishedScan:scan error:&error]) {
            if ([error hasUnderlyingErrorDomain:OFXErrorDomain code:OFXLocalAccountDirectoryPossiblyModifiedWhileScanning]) {
                // Try again -- we'll have avoided doing some operations (like deletions) since we don't know for sure where things have gone due to the mutation-while-scan.
                [self _queueContentsChanged];
            } else {
                // Could be more than one error, but we'll just record the last and log all of them.
                [_account reportError:error format:@"Error finishing scan for container %@", [container shortDescription]];
            }
        }
    }];
    
    [self containerNeedsFileTransfer:nil];
}

- (void)_handleSubitemAtURL:(NSURL *)oldURL didMoveToURL:(NSURL *)newURL;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);
    
    // We don't try to rely on NSFileCoordinator move notifications being reliable/timely. We don't block the file presenter queue when we get these, so by the time we get here the file might have been moved again/deleted. Instead we could make notes about recent moves and when intuiting moves based on inode results in left-overs, we could use those hints to match up move+edited files (since the inode won't match for NSDocument-based saves).
    [self _queueContentsChanged];
}

// Flat files without a path extension should be synchronized by the Mac agent, but not directories w/o a path extension.
- (BOOL)_shouldSyncPathExtension:(NSString *)pathExtension isDirectory:(BOOL)isDirectory;
{
    OBPRECONDITION([pathExtension isEqualToString:[pathExtension lowercaseString]]);
    
    if (isDirectory && [NSString isEmptyString:pathExtension])
        return NO; // Plain folder
    
    if (OFXShouldSyncAllPathExtensions(_syncPathExtensions))
        return YES; // Mac agent syncing all file types
    
    return ([_syncPathExtensions member:pathExtension] != nil);
}

- (NSURL *)_remoteSyncDirectory;
{
    NSURL *url = self.remoteBaseDirectory;
    
    // Try to make the remote directory not visible if the user mounts the WebDAV in Finder (so they are not enouraged to mess with it or poke it accidentally).
    url = [url URLByAppendingPathComponent:@".com.omnigroup.OmniPresence" isDirectory:YES];
    
    return url;
}

- (NSURL *)_remoteTemporaryDirectory;
{
    return [[self _remoteSyncDirectory] URLByAppendingPathComponent:RemoteTemporaryDirectoryName isDirectory:YES];
}

- (NSURL *)_localContainersDirectory;
{
    OBPRECONDITION(OFURLIsStandardized(_localAccountDirectory));
    
    return [_localAccountDirectory URLByAppendingPathComponent:@"Containers" isDirectory:YES];
}

static NSString * const OFXContainerPathExtension = @"container";

- (OFXContainerAgent *)_containerAgentWithIdentifier:(NSString *)identifier;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);
    OBPRECONDITION(_containerIdentifierToContainerAgent);
    OBPRECONDITION(![NSString isEmptyString:identifier]);
    OBPRECONDITION(![NSString isEmptyString:identifier]);
    
    if (!identifier)
        return nil;

    if ([identifier isEqual:[OFXContainerAgent containerAgentIdentifierForPathExtension:OFDirectoryPathExtension]]) {
        OBASSERT_NOT_REACHED("Tried to make a continer for the explicitly-a-folder path extension");
        return nil;
    }

    OBPRECONDITION([identifier isEqual:[identifier lowercaseString]]);
    identifier = [identifier lowercaseString];
    
    OFXContainerAgent *containerAgent = _containerIdentifierToContainerAgent[identifier];
    if (!containerAgent) {
        NSURL *localContainersDirectory = [self _localContainersDirectory];
        NSURL *remoteSyncDirectory = [self _remoteSyncDirectory];
        NSURL *remoteTemporaryDirectory = [self _remoteTemporaryDirectory];

        NSURL *localContainerDirectoryURL = [localContainersDirectory URLByAppendingPathComponent:identifier isDirectory:YES];
        NSURL *remoteContainerDirectory = [remoteSyncDirectory URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:OFXContainerPathExtension] isDirectory:YES];
        
        __autoreleasing NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:localContainerDirectoryURL withIntermediateDirectories:NO attributes:nil error:&error]) {
            if (![error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EEXIST]) {
                [_account reportError:error format:@"Unable to create container directory at %@", localContainerDirectoryURL];
                return nil;
            }
        }
        
        error = nil;
        containerAgent = [[OFXContainerAgent alloc] initWithAccountAgent:self identifier:identifier metadataRegistrationTable:_metadataRegistrationTable localContainerDirectory:localContainerDirectoryURL remoteContainerDirectory:remoteContainerDirectory remoteTemporaryDirectory:remoteTemporaryDirectory error:&error];
        if (!containerAgent) {
            [_account reportError:error format:@"Unable to create container agent with identifier \"%@\" for account %@", identifier, _account];
            return nil;
        }
        
        containerAgent.automaticallyDownloadFileContents = self.backgroundAutomaticallyDownloadFileContents;
        containerAgent.filePresenter = self;
        
        if (_debugName) {
            containerAgent.debugName = [NSString stringWithFormat:@"%@.%@", _debugName, identifier];
        }
        _containerIdentifierToContainerAgent[identifier] = containerAgent;

        if (self.backgroundState == OFXAccountAgentStateStarted) {
            [containerAgent start];
            
            // We also need to queue up a scan so that we recognize any local directories for this container as being documents.
            [self _queueContentsChanged];
        }
    }
    
    return containerAgent;
}

- (void)_startTransferOperations:(OFXFileItemTransfers *)transfers ofType:(NSString *)typeName byApplier:(OFXFileSnapshotTransfer *(^)(OFXContainerAgent *containerAgent, OFXFileItem *fileItem, NSError **outError))applier;
{
    OBPRECONDITION(self.backgroundState == OFXAccountAgentStateStarted);
    
    if (!self.backgroundSyncingEnabled)
        return;
        
    while (transfers.numberRunning < 2) {
        OFXFileItem *fileItem = [transfers anyRequest];
        if (!fileItem)
            break; // Nothing to do.
        
        OFXContainerAgent *containerAgent = fileItem.container;
        if (!containerAgent) {
            // Invalidated, possibly due to shutting down.
            [transfers removeRequestedFileItem:fileItem];
            continue;
        }
        
        __autoreleasing NSError *error;
        OFXFileSnapshotTransfer *transfer = applier(containerAgent, fileItem, &error);
        if (!transfer) {
            [_account reportError:error format:@"Error starting %@ of %@", typeName, [fileItem shortDescription]];
            [transfers removeRequestedFileItem:fileItem];
            continue;
        }
        
        [transfer addDone:^NSError *(OFXFileSnapshotTransfer *xfer, NSError *errorOrNil) {
            OBASSERT([NSOperationQueue currentQueue] == _operationQueue);
            if ([_runningTransfers member:xfer] == nil) {
                // Cancelled previously. We assume that if we've been restarted since the last stop, another transfer will complete that will provoke the next -_startTransferOperations.
                OBASSERT(![transfers containsFileItem:fileItem]);
            } else {
                if ([errorOrNil causedByUserCancelling])
                    errorOrNil = nil;
                if (errorOrNil || _needsToNilLastError) {
                    _needsToNilLastError = (errorOrNil != nil);
                    [_account reportError:errorOrNil];
                }

                [transfers finishedFileItem:fileItem];
                [_runningTransfers removeObject:xfer];
                
                [_operationQueue addOperationWithBlock:^{
                    if (self.backgroundState != OFXAccountAgentStateStarted)
                        return;
                    [self _startTransferOperations];
                }];
            }
            return nil;
        }];
        
        [transfers startedFileItem:fileItem];
        [_runningTransfers addObject:transfer];
        [transfer start];
    }
}

- (void)_startTransferOperations;
{
    [self _startTransferOperations:_uploadFileItemTransfers ofType:@"upload" byApplier:^OFXFileSnapshotTransfer *(OFXContainerAgent *containerAgent, OFXFileItem *fileItem, NSError **outError) {
        return [containerAgent prepareUploadTransferForFileItem:fileItem error:outError];
    }];
    [self _startTransferOperations:_downloadFileItemTransfers ofType:@"download" byApplier:^OFXFileSnapshotTransfer *(OFXContainerAgent *containerAgent, OFXFileItem *fileItem, NSError **outError) {
        return [containerAgent prepareDownloadTransferForFileItem:fileItem error:outError];
    }];
    [self _startTransferOperations:_deleteFileItemTransfers ofType:@"delete" byApplier:^OFXFileSnapshotTransfer *(OFXContainerAgent *containerAgent, OFXFileItem *fileItem, NSError **outError) {
        return [containerAgent prepareDeleteTransferForFileItem:fileItem error:outError];
    }];
}

- (void)_cancelTransfers;
{
    OBPRECONDITION(self.backgroundState == OFXAccountAgentStateStarted);
    
    // The cancellation will call back and remove transfers immediately.
    for (OFXFileSnapshotTransfer *transfer in [_runningTransfers copy])
        [transfer cancelForShutdown:NO];
    OBASSERT([_runningTransfers count] == 0); // They should have called back...
    
    [_uploadFileItemTransfers reset];
    [_downloadFileItemTransfers reset];
    [_deleteFileItemTransfers reset];
    [_runningTransfers removeAllObjects];
}

- (void)_clearRecentErrorsOnAllFileItems;
{
    OBPRECONDITION(self.runningOnAccountAgentQueue);
    OBPRECONDITION(self.backgroundState == OFXAccountAgentStateStarted);
    
    [_containerIdentifierToContainerAgent enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXContainerAgent *container, BOOL *stop) {
        [container clearRecentErrorsOnAllFileItems];
    }];
}

- (void)_performContainerMetadataUpdates:(NSTimer *)timer;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_foregroundState != OFXAccountAgentStateStarted) {
        OBASSERT(_metadataUpdateTimer == nil);
        return;
    }
    
    [_operationQueue addOperationWithBlock:^{
        if (_backgroundState != OFXAccountAgentStateStarted)
            return;
        
        NSMutableDictionary *recentTransferErrorsByLocalRelativePath = [[NSMutableDictionary alloc] init];
        [_containerIdentifierToContainerAgent enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, OFXContainerAgent *container, BOOL *stop) {
            [container _publishMetadataUpdates];
            [container addRecentTransferErrorsByLocalRelativePath:recentTransferErrorsByLocalRelativePath];
        }];
        
        if ([recentTransferErrorsByLocalRelativePath count] > 0) {
            __block NSUInteger errorCount = 0;
            
            [recentTransferErrorsByLocalRelativePath enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, NSArray *errors, BOOL *stop) {
                errorCount += [errors count];
            }];
            
            DEBUG_SYNC(1, @"  Account %@ has %ld recent transfer errors", _account, errorCount);
            
            if (errorCount > [OFXRecentTransferErrorThresholdBeforeAutomaticallyStopping unsignedIntegerValue]) {
                __autoreleasing NSError *error;
                
                NSString *description = NSLocalizedStringFromTableInBundle(@"Too many file transfers encountered errors recently.", @"OmniFileExchange", OMNI_BUNDLE, @"Error description when syncing will be disabled due to too many recent errors");
                
                NSMutableDictionary *errorInfoByPath = [[NSMutableDictionary alloc] init];
                [recentTransferErrorsByLocalRelativePath enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, NSArray *errors, BOOL *stop) {
                    errorInfoByPath[localRelativePath] = errors = [errors arrayByPerformingBlock:^(OFXRecentError *recentError){
                        return @{@"date": recentError.date, @"error": [recentError.error toPropertyList]};
                    }];
                }];

                OFXErrorWithInfo(&error, OFXTooManyRecentFileTransferErrors, description, nil, @"errors", errorInfoByPath, nil);
                
                // -reportError: would already dispatch to the main queue, but make sure we disable further syncing before the error gets logged so that a followup sync won't clear the error (unlikely unless sync attempts are queued up closely, but...)
                NSError *strongError = error;
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    self.syncingEnabled = NO;
                    [_account reportError:strongError];
                }];
            }
        }
    }];
    _metadataUpdateTimer = nil;
}

@end
