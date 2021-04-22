// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXContainerAgent-Internal.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFileExchange/OFXAgent.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXFileMetadata.h>
#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFFileMotionResult.h>

#import "OFXAccountAgent-Internal.h"
#import <OmniFileExchange/OFXAccountClientParameters.h>
#import "OFXContainerDocumentIndex.h"
#import "OFXContainerScan.h"
#import "OFXContentIdentifier.h"
#import "OFXDownloadFileSnapshot.h"
#import "OFXFileItem-Internal.h"
#import "OFXFileSnapshotRemoteEncoding.h"
#import "OFXFileSnapshotTransfer.h"
#import <OmniFileExchange/OFXRegistrationTable.h>

RCS_ID("$Id$")

@interface OFXContainerAgent ()
@end

static OFPreference *OFXFileItemSkipTransfersWithErrorsInTimeInterval;

static NSURL *_createContainerSubdirectory(NSURL *localContainerDirectory, NSString *name, NSError **outError) NS_RETURNS_RETAINED;
static NSURL *_createContainerSubdirectory(NSURL *localContainerDirectory, NSString *name, NSError **outError)
{
    NSURL *url = [[[localContainerDirectory URLByAppendingPathComponent:name] absoluteURL] copy];
    
    __autoreleasing NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:NO attributes:nil error:&error]) {
        if (![error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EEXIST]) {
            NSLog(@"Error creating container subdirectory at %@: %@", url, [error toPropertyList]);
            if (outError)
                *outError = error;
            return nil;
        }
    }
    
    return [url absoluteURL];
}

@implementation OFXContainerAgent
{
    __weak OFXAccountAgent *_weak_accountAgent;
    __weak id <NSFilePresenter> _weak_filePresenter;
    
    // A directory's ETag won't necessarily change if one of the members is replaced, but the modification date should. But, the server timestamp resolution is coarse enough that if we are racing vs. another client we might not see its edit. So, we only trust our cached date if the PROPFIND returns a Date header that is newer than it.
    NSDate *_lastSyncedServerDate;
    
    // One of our file items has told us that it couldn't download a snapshot version from the server. This may be due to the file being deleted or updated, but either way, starting a new download of it will just result in another failure. In this case, we'll avoid starting any more transfers of any kinds until we've done a scan.
    BOOL _hasUnknownRemoteEdit;
    
    OFXContainerDocumentIndex *_documentIndex;
    
    BOOL _hasScheduledMetadataUpdate;
    NSMutableSet <OFXFileItem *> *_fileItemsNeedingMetadataUpdate;
    NSMutableSet <OFXFileItem *> *_fileItemsNeedingMetadataRemoved;
    
    BOOL _hasScheduledDeferredTransferRequestForPreviouslySkippedFiles;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OFXFileItemSkipTransfersWithErrorsInTimeInterval = [OFPreference preferenceForKey:@"OFXFileItemSkipTransfersWithErrorsInTimeInterval"];
}

// We have to allow empty path extensions (for example "README"), so we can't use a plain path extension (since an empty string isn't a valid path component).
// One problem with this approach is that if we have goofy file names like "data.01", we'll make a container for them and will possibly end up with a whole ton of containers (which might not scale well since we do PROPFIND per container). We might try moving towards a scheme where if we don't know a UTI for a path extension and nothing on the server claims it, we put it in a single "unknown kind" container. We'd need to have support for rescuing such files from that bucket in the case that a new app is installed that adds support for that file extension (and that app wouldn't be able to see the names of files in the bucket by default, but the Mac app would since it downloads everything...).
// We include a "." in the identifier here so that there is no possible path extension that can get grouped with it.

static NSString * const OFXNoPathExtensionContainerIdentifier = @"no.extension";
+ (BOOL)containerAgentIdentifierRepresentsPathExtension:(NSString *)containerIdentifier;
{
    OBPRECONDITION(![NSString isEmptyString:containerIdentifier]);
    
    return ![OFXNoPathExtensionContainerIdentifier isEqual:containerIdentifier];
}

+ (NSString *)containerAgentIdentifierForPathExtension:(NSString *)pathExtension;
{
    if ([NSString isEmptyString:pathExtension])
        return @"no.extension";
    
    return [pathExtension lowercaseString];
}

+ (NSString *)containerAgentIdentifierForFileURL:(NSURL *)fileURL;
{
    return [self containerAgentIdentifierForPathExtension:[fileURL pathExtension]];
}

- initWithAccountAgent:(OFXAccountAgent *)accountAgent identifier:(NSString *)identifier metadataRegistrationTable:(OFXRegistrationTable <OFXFileMetadata *> *)metadataRegistrationTable localContainerDirectory:(NSURL *)localContainerDirectory remoteContainerDirectory:(NSURL *)remoteContainerDirectory remoteTemporaryDirectory:(NSURL *)remoteTemporaryDirectory error:(NSError **)outError;
{
    OBPRECONDITION(accountAgent);
    OBPRECONDITION(![NSString isEmptyString:identifier]);
    OBPRECONDITION([identifier isEqual:[identifier lowercaseString]]);
    OBPRECONDITION(metadataRegistrationTable);
    OBPRECONDITION([localContainerDirectory checkResourceIsReachableAndReturnError:NULL]); // should exist already
    OBPRECONDITION([[[localContainerDirectory URLByStandardizingPath] absoluteString] isEqual:[localContainerDirectory absoluteString]]); // and be standardized
    OBPRECONDITION(remoteContainerDirectory);
    OBPRECONDITION(remoteTemporaryDirectory);
    OBPRECONDITION(!OFURLEqualsURL(remoteContainerDirectory, remoteTemporaryDirectory));

    if (!(self = [super init]))
        return nil;
    
    // Hold onto this for upcalls (few, hopefully)
    _weak_accountAgent = accountAgent;
    OBASSERT([self _runningOnAccountAgentQueue]);
    
    // But then grab some stuff strongly from it that we need more frequently
    _account = accountAgent.account;
    OBASSERT([_account.localDocumentsURL checkResourceIsReachableAndReturnError:NULL]);

    _clientParameters = accountAgent.clientParameters;
    
    _identifier = [[identifier lowercaseString] copy];
    _metadataRegistrationTable = metadataRegistrationTable;
    
    _localContainerDirectory = [[localContainerDirectory absoluteURL] copy];
    _remoteContainerDirectory = [[remoteContainerDirectory absoluteURL] copy];
    
    if (!(_localSnapshotsDirectory = _createContainerSubdirectory(_localContainerDirectory, @"Snapshots", outError)))
        return nil;
    
    _remoteTemporaryDirectory = [[remoteTemporaryDirectory absoluteURL] copy];
    
    return self;
}

@synthesize filePresenter = _weak_filePresenter;

- (void)start;
{
    OBPRECONDITION(_started == NO);
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    OFXAccountAgent *accountAgent = _weak_accountAgent;
    if (!accountAgent) {
        OBASSERT_NOT_REACHED("Started while the account agent is disappearing?");
        return;
    }
    
    _started = YES;

    // This needs to be synchronous w.r.t starting up so that we know what our local snapshots are before the account agent possibly tells us that it scanned a URL. Otherwise, we'd think that it was a new URL.
    [self _scanLocalSnapshots];
}

- (void)stop;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    _started = NO;

    [_documentIndex enumerateFileItems:^(NSString *identifier, OFXFileItem *fileItem) {
        [self _fileItemNeedsMetadataRemoved:fileItem];
    }];
    _documentIndex = nil;
}

- (BOOL)syncIfChanged:(ODAVFileInfo *)containerFileInfo serverDate:(NSDate *)serverDate connection:(ODAVConnection *)connection error:(NSError **)outError;
{
    NSUInteger retries = 0;
    
tryAgain:
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    OBPRECONDITION(containerFileInfo);
    OBPRECONDITION(serverDate);
    OBPRECONDITION(connection);
    OBPRECONDITION([NSThread isMainThread] == NO); // We operate on a background queue managed by our agent

    // Our locally stored snapshots were scanned while starting up.
    NSURL *remoteContainerDirectory = [connection suggestRedirectedURLForURL:self.remoteContainerDirectory];

    // Since the timestamp resolution on the server is limited, to avoid a race between an reader and writer, we have to sync this container if it has been modified at the same time or more recently than the last server time we did a full sync. Since the server time should move forward, our timestamp will step forward on each try (and so as long as the writer stops poking the container, we'll stop doing extra PROPFINDs).
    // If we have an unknown remote edit, go ahead and make sure we clear that.
    if (_lastSyncedServerDate && [containerFileInfo.lastModifiedDate isBeforeDate:_lastSyncedServerDate] && !_hasUnknownRemoteEdit) {
        DEBUG_SYNC(1, @"Container has last server date of %@ and container modified on %@. Skipping", _lastSyncedServerDate, containerFileInfo.lastModifiedDate);
        return YES; // Nothing to do
    }
    
    DEBUG_SYNC(1, @"Fetching document list from container %@", remoteContainerDirectory);
    
    // Ensure we create the container directory so that other clients will know that this path extension signifies a wrapper file type (rather than waiting for a file of this type to be uploaded).
    // TODO: If we have local snapshots, but the remote directory has been deleted, should we interpret that the same as the individual files being deleted? Or should we treat it as some sort of error/reset and instead upload all our documents? If two clients are out in the world, the second client will treat missing server documents as deletes for local documents. For now, treating removal of the container as removal of all the files w/in it.
    __autoreleasing NSError *fetchError;
    NSArray <ODAVFileInfo *> *fileInfos = OFXFetchDocumentFileInfos(connection, remoteContainerDirectory, nil/*identifier*/, &fetchError);
    if (!fileInfos) {
        if (outError)
            *outError = fetchError;
        OBChainError(outError);
        return NO;
    }
    
    // We are sure it exists now.
    [self _hasCreatedRemoteDirectory];
    
    id <NSFilePresenter> filePresenter = _weak_filePresenter;

    // Handle incoming deletes before downloads. Consider the case of a file being remotely deleted and a new file placed at the same path (while we are offline). We want to make way for the new file right away. This doesn't handle all name conflicts (two clients renaming two different files to the same name, for example), but it is a start.
    // This deletion handling can create conflict documents, if we had local edits.
    {
        NSMutableSet *documentIdentifiersNowMissingOnServer = [_documentIndex copyRegisteredFileItemIdentifiers];
        
        [self _enumerateDocumentFileInfos:fileInfos collectStaleFileInfoVersions:nil applier:^(NSString *fileIdentifier, NSUInteger fileVersion, ODAVFileInfo *fileInfo){
            [documentIdentifiersNowMissingOnServer removeObject:fileIdentifier];
        }];
        

        for (NSString *documentIdentifier in documentIdentifiersNowMissingOnServer) {
            OFXFileItem *missingFileItem = [_documentIndex fileItemWithIdentifier:documentIdentifier];
            if (missingFileItem.remoteState.missing) {
                // This may be our first upload of the item, so we wouldn't expect it to appear in the server side first.
                continue;
            }
            
            // We don't have a 'download delete' transfer, so we need to do the notification here for the benefit of background syncing
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
            NSString *description = [NSString stringWithFormat:@"delete %@", missingFileItem.localDocumentURL];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [[NSNotificationCenter defaultCenter] postNotificationName:OFXAccountTransfersNeededNotification object:_account userInfo:@{OFXAccountTransfersNeededDescriptionKey:description}];
            }];
#endif

            __autoreleasing NSError *error;
            if (![missingFileItem handleIncomingDeleteWithFilePresenter:filePresenter error:&error]) {
                NSLog(@"Error handling incoming delete of %@ <%@>: %@", missingFileItem, missingFileItem.localDocumentURL, [error toPropertyList]);
            } else {
                [_documentIndex forgetFileItemForRemoteDeletion:missingFileItem];
                [self _fileItemNeedsMetadataRemoved:missingFileItem];
            }
        }
    }
    
    
    __block BOOL tryAgain = NO;
    __block BOOL needsDownload = NO;
    
    NSMutableArray <ODAVFileInfo *> *staleFileInfoVersions = [[NSMutableArray alloc] init];
    
    [self _enumerateDocumentFileInfos:fileInfos collectStaleFileInfoVersions:staleFileInfoVersions applier:^(NSString *fileIdentifier, NSUInteger fileVersion, ODAVFileInfo *fileInfo){
        OFXFileItem *fileItem = [_documentIndex fileItemWithIdentifier:fileIdentifier];
        if (fileItem) {
            if (fileItem.version == fileVersion) {
                DEBUG_SYNC(1, @"File item hasn't changed");
                // remote document is the same as we last left it, but we might want to download the contents anyway.
                if (_automaticallyDownloadFileContents && fileItem.presentOnServer && !fileItem.isDownloaded && !fileItem.hasBeenLocallyDeleted) {
                    needsDownload = YES;
                    DEBUG_SYNC(2, @"needs download at %d", __LINE__);
                }
            } else {
                DEBUG_SYNC(2, @"File item changed");

                // Note the remote edit. We might have a local edit or delete that will conflict, but the transfer operations will handle that.
                __autoreleasing NSError *error;
                if (![fileItem markAsRemotelyEditedWithNewestRemoteVersion:fileVersion error:&error]) {
                    NSLog(@"Error marking file item as remotely edited %@: %@", [fileItem shortDescription], [error toPropertyList]);
                } else {
                    OBASSERT(fileItem.remoteState.edited);
                }

                // ... and download the updated metadata (or possibly contents if we'd previously downloaded them).
                needsDownload = YES;
                DEBUG_SYNC(2, @"needs download at %d", __LINE__);
            }
        } else {
            // New remote document
            
            DEBUG_TRANSFER(2, @"Initializing new snapshot by fetching %@", fileInfo.originalURL);
            
            __autoreleasing NSError *documentError = nil;
            fileItem = [[OFXFileItem alloc] initWithNewRemoteSnapshotAtURL:fileInfo.originalURL container:self filePresenter:filePresenter connection:connection error:&documentError];
            if (!fileItem) {
                if ([documentError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND] && retries < 100) {
                    // Modified while fetching
                    tryAgain = YES;
                    NSLog(@"Expected version missing while fetching remote document at %@ ... will try again", [fileInfo.originalURL absoluteString]);
                } else {
                    NSLog(@"Unable to create file item for remote document at %@: %@", [fileInfo.originalURL absoluteString], [documentError toPropertyList]);
                }
                return;
            }
            
            OFXFileItem *previouslyRegisteredFileItem = [_documentIndex fileItemWithLocalRelativePath:fileItem.localRelativePath];
            if (previouslyRegisteredFileItem) {
                __autoreleasing NSError *relocateError = nil;
                
                // We don't need to know about any possible move this does since we'll update our state immediately.
                NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self.filePresenter];
                if (![self _relocateFileAtURL:previouslyRegisteredFileItem.localDocumentURL toMakeWayForFileItem:fileItem coordinator:coordinator error:&relocateError]) {
                    [relocateError log:@"Error relocating previously known file item %@ to make room for incoming file item %@", previouslyRegisteredFileItem, fileItem];
                    return;
                }
            }
            
            [self _fileItemNeedsMetadataUpdated:fileItem];
            [_documentIndex registerRemotelyAppearingFileItem:fileItem];
            
            if (_automaticallyDownloadFileContents) {
                needsDownload = YES;
                DEBUG_SYNC(2, @"needs download at %d", __LINE__);
            }
        }
    }];

    // Permit the transfers we are about to ask for...
    if (_hasUnknownRemoteEdit) {
        _hasUnknownRemoteEdit = NO;
        DEBUG_TRANSFER(1, @"Unknown remote edit should be known now.");
    }

    [self _generateAutomaticMovesToAvoidNameConflicts];
    
    if (needsDownload) {
        [_weak_accountAgent containerNeedsFileTransfer:self];
    }
    
    if (!tryAgain) {
        _lastSyncedServerDate = serverDate;
    }
    
    [self _updatePublishedFileVersions];
    
    // If there are stall versions of files, clean them up. If there are multiple old versions for a single file, we don't delete them in any particular order (since we have version N around to keep these superseded). If a full delete of a file and all its versions is going on concurrently, they'll get deleted oldest-first (so some of the delete attempts there may get 404) and they'll delete the newest version last (which we don't do at all). So, there should be no race between these activities.
    if (_clientParameters.deleteStaleFileVersionsWhenSyncing) {
        for (ODAVFileInfo *fileInfo in staleFileInfoVersions) {
            TRACE_SIGNAL(OFXContainerAgent.delete_stale_version_during_sync);
            [connection deleteURL:fileInfo.originalURL withETag:nil completionHandler:nil];
        }
    }
    
    OBPOSTCONDITION([self _checkInvariants]); // checks the queue too

    if (tryAgain) {
        // Nesting this call was causing infinite recursion and crash in RT 900574. Let's give up on trying to get the document altogether after an absurd number (e.g. 100) of retries
        //return [self syncIfChanged:containerFileInfo serverDate:serverDate remoteFileManager:remoteFileManager error:outError];
        retries++;
        goto tryAgain;
    } else {
        return YES;
    }
}

- (void)collectNeededFileTransfers:(void (^)(OFXFileItem *fileItem, OFXFileItemTransferKind kind))addTransfer;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    // We don't want to start more transfers until we know the state of the remote side. We could process deletes of locally created files, but that isn't critical.
    if (_hasUnknownRemoteEdit) {
        DEBUG_TRANSFER(1, @"Bailing on new transfers while we have an unknown remote edit.");
        return;
    }
    
    NSTimeInterval skipFilesWithLastErrorAfterTimeInterval = [NSDate timeIntervalSinceReferenceDate] - [OFXFileItemSkipTransfersWithErrorsInTimeInterval doubleValue];
    
    __block BOOL skippedFile = NO;
    __block NSTimeInterval nextRetryInterval = 0;

    [_documentIndex enumerateFileItems:^(NSString *identifier, OFXFileItem *fileItem){
        DEBUG_TRANSFER(2, @"Checking document %@ %@.", identifier, fileItem.localDocumentURL);
        
        // If we have a very recent transfer error, skip this transfer rather than pounding the server. But we let the caller know that there was a skip so that it can ask again later.
        OFXRecentError *recentError = fileItem.mostRecentTransferError;
        if (recentError) {
            DEBUG_TRANSFER(2, @"  Most recent error is at %@", recentError.date);
            NSTimeInterval errorTimeInterval = [recentError.date timeIntervalSinceReferenceDate];
            NSTimeInterval fileRetryInterval = errorTimeInterval - skipFilesWithLastErrorAfterTimeInterval;
            DEBUG_TRANSFER(2, @"  fileRetryInterval %f", fileRetryInterval);
            if (fileRetryInterval < 0) {
                // Go ahead and do it now, this error was long enough ago.
            } else {
                if (!skippedFile) {
                    skippedFile = YES;
                    nextRetryInterval = fileRetryInterval;
                } else {
                    // Try again when the next file will be ready
                    nextRetryInterval = MIN(nextRetryInterval, fileRetryInterval);
                }
                
                // We might not have wanted to do anything, but lets delay since we had a recent error. This certainly isn't perfect (the operation we are going to try now might be different enough to clear up the error), but better than pounding the server.
                return;
            }
        }
        
        OFXFileState *localState = fileItem.localState;
        OFXFileState *remoteState = fileItem.remoteState;
        
        if (localState.normal && remoteState.normal) {
            DEBUG_TRANSFER(2, @"  Already downloaded, no remote updates.");
            return;
        }
        // Do local deletes before downloads so that delete/missing will actually push a delete rather than trying a download.
        if (localState.deleted) {
            // If the remote side is edited, this will result in a conflict in the transfer itself.
            DEBUG_TRANSFER(2, @"  Locally deleted, queuing remote delete.");
            OBASSERT(fileItem.hasBeenLocallyDeleted);
            addTransfer(fileItem, OFXFileItemDeleteTransferKind);
            return;
        }

        // Preferring download of remote edits to uploads for now. In the case of a remote edit + local move our upload will fail due to ETag preconditions (when two clients are fighting over resolving a name vs. name conflict).
        OBASSERT(remoteState.autoMoved == NO, "The server only has user intended moves");
        if (remoteState.edited || remoteState.userMoved) {
            OBASSERT(remoteState.userMoved == NO, "We don't actually know about remote renames until we download the snapshot");
            // May have a local edit or locally created file -- we resolve conflicts when committing the download
            //OBASSERT(localState.normal || localState.moved, "Handle content conflicts before this. We preserve local renames for name v. name conflict resolution.");
            DEBUG_TRANSFER(2, @"  Remotely edited or moved, queuing download.");
            addTransfer(fileItem, OFXFileItemDownloadTransferKind);
            return;
        }
        
        if (remoteState.missing) {
            DEBUG_TRANSFER(2, @"  Locally added, queuing upload.");
            addTransfer(fileItem, OFXFileItemUploadTransferKind);
            return;
        }

        if (localState.edited || localState.userMoved) {
            DEBUG_TRANSFER(2, @"  Locally edited or moved, queuing upload.");
            addTransfer(fileItem, OFXFileItemUploadTransferKind);
            return;
        }

        // This goes at the end (or at least after local.move so that we can upload a rename of a local.missing item). Also, don't do redundant metadata downloads of local missing file items. We only need to do this download if the file is actually missing.
        if (localState.missing) {
            if (fileItem.contentsRequested) {
                DEBUG_TRANSFER(2, @"  Remotely added and contents requested, downloading");
                addTransfer(fileItem, OFXFileItemDownloadTransferKind);
            } else {
                // No worries, it can just hang out on the server.
            }
            return;
        }
        
        if (localState.autoMoved) {
            DEBUG_TRANSFER(2, @"  Just locally automatically moved.");
            return;
        }

        if (remoteState.deleted) {
            DEBUG_TRANSFER(2, @"  Remotely deleted.");
            // This case gets handled by -[OFXFileItem handleIncomingDeleteWithFilePresenter:error:]. If that fails to handle the delete for some reason, we'll fail an assertion there with "The item will likely be resurrected" and then also hit this condition here. (But we don't really need to fail a second assertion here for every failed assertion there.)
            return;
        }

        OBASSERT_NOT_REACHED("Unhandled file state");
    }];
    
    // Register our desire to start transfers again in the future
    if (skippedFile && !_hasScheduledDeferredTransferRequestForPreviouslySkippedFiles) {
        _hasScheduledDeferredTransferRequestForPreviouslySkippedFiles = YES;
        
        NSOperationQueue *queue = [NSOperationQueue currentQueue]; // This is the account operation's queue, asserted above
        __weak OFXContainerAgent *weakSelf = self;
        
        nextRetryInterval += 0.01;
        DEBUG_TRANSFER(2, @"  Requesting transfers again in %f seconds.", nextRetryInterval);

        // Jump to the main thread so that our request lives on it's runloop and will survive
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            OFAfterDelayPerformBlock(nextRetryInterval, ^{
                [queue addOperationWithBlock:^{
                    OFXContainerAgent *strongSelf = weakSelf;
                    if (strongSelf) {
                        OBASSERT(strongSelf->_hasScheduledDeferredTransferRequestForPreviouslySkippedFiles);
                        strongSelf->_hasScheduledDeferredTransferRequestForPreviouslySkippedFiles = NO;
                        [strongSelf->_weak_accountAgent containerNeedsFileTransfer:strongSelf];
                    }
                }];
            });
        }];
    }
}

- (OFXFileSnapshotTransfer *)prepareUploadTransferForFileItem:(OFXFileItem *)fileItem error:(NSError **)outError;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    OBPRECONDITION([_documentIndex fileItemWithIdentifier:fileItem.identifier] == fileItem);
    
    if (fileItem.hasBeenLocallyDeleted) {
        // Edited and then deleted quickly before the upload could start
        OBUserCancelledError(outError);
        return nil;
    }
    OBASSERT(fileItem.remoteState.missing || fileItem.localState.edited || fileItem.localState.userMoved);

    ODAVConnection *connection = [self _makeConnection];
    if (!connection)
        return nil;
    
    DEBUG_SYNC(1, @"Preparing upload of %@, connection baseURL %@", fileItem, connection.baseURL);
        
    __autoreleasing NSError *prepareUploadError;
    OFXFileSnapshotTransfer *uploadTransfer = [fileItem prepareUploadTransferWithConnection:connection error:&prepareUploadError];
    if (!uploadTransfer) {
        if (outError)
            *outError = prepareUploadError;
        return nil;
    }

    OBASSERT(fileItem.isUploading); // should be set even before the operation starts so that our queue won't start more.
    
    uploadTransfer.validateCommit = ^NSError *{
        OBPRECONDITION([self _runningOnAccountAgentQueue]);
        
        // Bail if we've been stopped since starting the transfer or if the file has been locally deleted
        if (!_started || fileItem.hasBeenLocallyDeleted)
            return [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
        
        return nil;
    };
    
    [uploadTransfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
        DEBUG_SYNC(1, @"Finished upload of %@", fileItem);
        
        OBASSERT([self _runningOnAccountAgentQueue]);
        
        if (errorOrNil == nil) {
            // If the upload worked, our remote directory is definitely there.
            [self _hasCreatedRemoteDirectory];
            [self _updatePublishedFileVersions];
            
            // Check if there were more changes since this upload snapshotted the document (but be careful of the item having been deleted in the mean time). The file item might have also been reverted to the non-downloaded state if there was a conflict discovered while doing the upload (in that case the local contents to be uploaded will have been renamed to a new document).
            // Note that we don't check whether the file is at the same path. The move path should start a transfer even if there are no changes in content.
            if (!fileItem.hasBeenLocallyDeleted && !fileItem.localState.missing) {
                BOOL hasBeenEdited = NO;
                __autoreleasing NSError *sameContentsError;
                NSNumber *same = [fileItem hasSameContentsAsLocalDocumentAtURL:fileItem.localDocumentURL error:&sameContentsError];
                if (same == nil) {
                    if ([sameContentsError causedByMissingFile]) {
                        // Race between uploading and a local deletion. We should have a scan queued now or soon that will set fileItem.hasBeenLocallyDeleted.
                    } else
                        NSLog(@"At end of transfer, error checking for changes in contents for %@: %@", fileItem.localDocumentURL, [sameContentsError toPropertyList]);
                } else {
                    if ([same boolValue] == NO) {
                        __autoreleasing NSError *error;
                        if (![fileItem markAsLocallyEdited:&error]) {
                            // Not the end of the world, but not ideal... We should do a full scan on the next launch.
                            NSLog(@"Error marking file as locally edited %@: %@", [fileItem shortDescription], [error toPropertyList]);
                        } else {
                            hasBeenEdited = YES;
                        }
                    }
                }
                
                // Might also have been moved while the upload was going on.
                if (hasBeenEdited || fileItem.localState.userMoved) {
                    OFXAccountAgent *accountAgent = _weak_accountAgent;
                    OBASSERT(accountAgent);
                    [accountAgent containerNeedsFileTransfer:self];
                }
            }
        } else {
            TRACE_SIGNAL(OFXContainerAgent.upload_did_not_commit);
        }
        OBPOSTCONDITION([self _checkInvariants]); // checks the queue too
        return nil;
    }];
    
    return uploadTransfer;
}

- (OFXFileSnapshotTransfer *)prepareDownloadTransferForFileItem:(OFXFileItem *)fileItem error:(NSError **)outError;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    if (fileItem.hasBeenLocallyDeleted) {
        // Download requested and then locally deleted before download could start
        TRACE_SIGNAL(OFXContainerAgent.reject_download_while_uploading);
        OBUserCancelledError(outError);
        return nil;
    }

    if (fileItem.isDownloading) {
        // If this is getting called because we've decided that we want to get the contents, and the current download is just for metadata, our re-download in the 'done' block below will be OK. But, if this is getting called because a sync noticed *another* remote edit while we are still downloading the document, we'd lose the edit. We need to catch this case.
        TRACE_SIGNAL(OFXContainerAgent.reject_download_while_downloading);
        OBUserCancelledError(outError);
        return nil;
    }
    if (fileItem.isUploading) {
        // If we discover a need to download while we are already uploading, the upload should be about to hit a conflict. We'll just ignore the download request here. Once the upload figures out there is a conflict, it will revert us to be a not-downloaded file.
        OBUserCancelledError(outError);
        return nil;
    }
    
    ODAVConnection *connection = [self _makeConnection];
    if (!connection)
        return nil;
    
    DEBUG_SYNC(1, @"Preparing download of %@", fileItem);
    
    // We must allow for stacked up download requests in some form. If we start a metadata download (no contents) and then start a download with contents before that is fully finished, we want the contents to actually download. Similarly, if we are downloading contents and another change happens on the server, if we start a metadata download, we don't want to discard the contents we have downloaded (some of them may be good for local copying).
    
    id <NSFilePresenter> filePresenter = _weak_filePresenter;
    
    OFXFileSnapshotTransfer *downloadTransfer = [fileItem prepareDownloadTransferWithConnection:connection filePresenter:filePresenter];
    OBASSERT(fileItem.isDownloading); // should be set even before the operation starts so that our queue won't start more.
    
    downloadTransfer.validateCommit = ^NSError *{
        OBPRECONDITION([self _runningOnAccountAgentQueue]);
        // Bail if we've been stopped since starting the transfer
        if (!_started)
            return [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
        
        if (fileItem.hasBeenLocallyDeleted) {
            // Deleted locally before the download could finish. We need to push up the delete now.
            __autoreleasing NSError *error;
            OFXError(&error, OFXFileDeletedWhileDownloading, nil, nil);
            return error;
        }
        
        return nil;
    };

    [downloadTransfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
        OBPRECONDITION([self _runningOnAccountAgentQueue]);
        DEBUG_SYNC(1, @"Finished download of %@ (committed:%d)", fileItem, (errorOrNil == nil));
        
        OFXAccountAgent *accountAgent = _weak_accountAgent;
        if (errorOrNil == nil) {
            // Check if another download request came in that wanted contents with this download only being for metadata.
            if (fileItem.contentsRequested) {
                OFXFileState *localState = fileItem.localState;
                OFXFileState *remoteState = fileItem.remoteState;
                if (localState.missing || remoteState.edited || remoteState.userMoved) {
                    OBASSERT(localState.missing || remoteState.edited, "We don't know about remote renames for real. We might have seen a new version on the server before our first download finished, so we might still be in the create state");
                    [accountAgent containerNeedsFileTransfer:self];
                }
            }
            OBPOSTCONDITION([self _checkInvariants]); // checks the queue too
        } else if ([errorOrNil hasUnderlyingErrorDomain:OFXErrorDomain code:OFXFileDeletedWhileDownloading]) {
            // Start the delete transfer
            [accountAgent containerNeedsFileTransfer:self];
        }
        
        return nil;
    }];
    
    return downloadTransfer;
}

- (OFXFileSnapshotTransfer *)prepareDeleteTransferForFileItem:(OFXFileItem *)fileItem error:(NSError **)outError;
{
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    
    if (fileItem.hasBeenLocallyDeleted == NO) {
        OBFinishPortingLater("<bug:///147877> (iOS-OmniOutliner Engineering: Add test case for -[OFXContainerAgent prepareDeleteTransferForFileItem:error:] when !fileItem.hasBeenLocallyDeleted)");
        // Started a delete and the file was resurrected (maybe a new remote edit?)
        OBUserCancelledError(outError);
        return nil;
    }
    
    if (fileItem.isDownloading) {
        OBASSERT(fileItem.hasCurrentTransferBeenCancelled);
        // Need to wait for the download to be cancelled.
        OBUserCancelledError(outError);
        return nil;
    }
    if (fileItem.isUploading) {
        OBASSERT(fileItem.hasCurrentTransferBeenCancelled);
        // Need to wait for the upload to be cancelled.
        OBUserCancelledError(outError);
        return nil;
    }
    
    ODAVConnection *connection = [self _makeConnection];
    if (!connection)
        return nil;
    
    DEBUG_SYNC(1, @"Preparing delete of %@", fileItem);
    
    id <NSFilePresenter> filePresenter = _weak_filePresenter;
    OFXFileSnapshotTransfer *deleteTransfer = [fileItem prepareDeleteTransferWithConnection:connection filePresenter:filePresenter];
    OBASSERT(fileItem.isDeleting); // should be set even before the operation starts so that our queue won't start more.
    
    deleteTransfer.validateCommit = ^NSError *{
        OBPRECONDITION([self _runningOnAccountAgentQueue]);
        OBPRECONDITION(fileItem.hasBeenLocallyDeleted, @"We do not resurrect file items on delete vs. edit conflict."); // Rather, we let the delete commit locally w/o committing remotely and then rescan the server. The edit then appears as a 'new' item and we treat it as such.
        
        // Bail if we've been stopped since starting the transfer
        if (!_started)
            return [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                
        return nil;
    };
    
    [deleteTransfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
        OBPRECONDITION([self _runningOnAccountAgentQueue]);
        DEBUG_SYNC(1, @"Finished delete of %@", fileItem);
        
        OBASSERT([_documentIndex hasBegunLocalDeletionOfFileItem:fileItem], @"should have begun local deletion");

        // In the remote-edit vs local-delete conflict, the file item should have gone ahead and removed its snapshot so that on the next sync we can resurrect it as if it was a new file.
        BOOL didRemove = !errorOrNil || [errorOrNil hasUnderlyingErrorDomain:OFXErrorDomain code:OFXFileUpdatedWhileDeleting];
        
        if (didRemove) {
            [_documentIndex completeLocalDeletionOfFileItem:fileItem];
            [self _fileItemNeedsMetadataRemoved:fileItem];

            if (errorOrNil == nil) {
                // Only publish a new identifier if the *remote* delete happened.
                [self _updatePublishedFileVersions];
            } else {
                // Start a new sync to download metadata for the remotely updated file. Have to clear our last sync date to make sure we don't spuriously ignore this.
                _lastSyncedServerDate = nil;
                OFXAccountAgent *accountAgent = _weak_accountAgent;
                OBASSERT(accountAgent);
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    if (accountAgent.started) // Maybe stopped in the mean time...
                        [accountAgent sync:nil];
                }];
            }
        } else {
            // The file item logs a message in its 'done' block. We'll try again later via our delete note.
        }
        
        OBPOSTCONDITION([self _checkInvariants]); // checks the queue too
        return nil;
    }];
    
    return deleteTransfer;
}

- (void)addRecentTransferErrorsByLocalRelativePath:(NSMutableDictionary <NSString *, NSArray <OFXRecentError *> *> *)recentErrorsByLocalRelativePath;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    [_documentIndex enumerateFileItems:^(NSString *identifier, OFXFileItem *fileItem) {
        [fileItem addRecentTransferErrorsByLocalRelativePath:recentErrorsByLocalRelativePath];
    }];
}

- (void)clearRecentErrorsOnAllFileItems;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    // Clear this too so that we'll look again rather than just bailing on making new transfers
    _hasUnknownRemoteEdit = NO;
    
    [_documentIndex enumerateFileItems:^(NSString *identifier, OFXFileItem *fileItem) {
        [fileItem clearRecentTransferErrors];
    }];
}

- (OFXFileItem *)fileItemWithURL:(NSURL *)fileURL;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    OBPRECONDITION([[[self class] containerAgentIdentifierForFileURL:fileURL] isEqual:_identifier]);
    
    NSString *relativePath = [self _localRelativePathForFileURL:fileURL];
    return [_documentIndex fileItemWithLocalRelativePath:relativePath];
}

// Probe used by OFXAccountAgent to determine if a rename is a directory rename.
- (void)addFileItems:(NSMutableArray <OFXFileItem *> *)fileItems inDirectoryWithRelativePath:(NSString *)localDirectoryRelativePath;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    [_documentIndex addFileItems:fileItems inDirectoryWithRelativePath:localDirectoryRelativePath];
}

- (OFXContainerScan *)beginScan;
{
    OBPRECONDITION([self _checkInvariants]); // checks the queue too

    DEBUG_SCAN(1, @"Begin scan");
    
    NSObject <NSCopying> *indexState;
#ifdef OMNI_ASSERTIONS_ON
    indexState = [_documentIndex copyIndexState];
#endif
    
    return [[OFXContainerScan alloc] initWithDocumentIndexState:indexState];
}

- (BOOL)finishedScan:(OFXContainerScan *)_scan error:(NSError **)outError;
{
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    
    // TODO: Test exchange of two files/directories? There is nothing with NSFileCoordination to support this, but we could observe an uncoordinated exchangedata/FSExchangeObjects. Probably OK to do something a little unexpected in this case...
    
    OBPRECONDITION(OFISEQUAL(_scan.documentIndexState, [_documentIndex copyIndexState]), @"No file item registration changes should have happened between the scan starting and finishing");
    
    DEBUG_SCAN(1, @"Finished scan with URLs %@", _scan.scannedFileURLs);
    
    // Experimentally, if we create 1000 files, remove them and then immediately create 1000 more, inodes continue to increase in number. Presumably at some point they'll be recycled, but the system does seem to want to make inodes be at least short-term unique identifiers for files.
    // Build an index of inode->relative path for the scanned items. We assume everything we are operating on is w/in our directory is on one filesystem (the one for our account's local documents directory).

    NSMutableDictionary *inodeToScannedURL = [NSMutableDictionary dictionary];
    for (NSURL *fileURL in _scan.scannedFileURLs) {
        __autoreleasing NSError *error;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:&error];
        NSNumber *inode = attributes[NSFileSystemFileNumber];
        if (inode == nil) {
            // Something was moved/deleted while we were scanning -- try again.
            if ([error causedByMissingFile]) {
                DEBUG_SCAN(2, @"   ... file missing at %@, must rescan", fileURL);
                NSString *reason = [NSString stringWithFormat:@"Local file at %@ has been removed or renamed.", fileURL];
                OFXError(outError, OFXLocalAccountDirectoryPossiblyModifiedWhileScanning, @"Local account directory has been modified since scan began.", reason);
            } else {
                NSLog(@"Error getting inode for URL %@: %@", fileURL, [error toPropertyList]);
                
                if (outError)
                    *outError = error;
            }
            return NO;
        }
        inodeToScannedURL[inode] = fileURL;
    }
    
    // Check for renames (same inode) so that we don't mistakenly create new files when we have a move of a->b and a creation of something new at "a". Also handle swapping renames by doing these in bulk.
    {
        __block NSMutableDictionary *fileItemToUpdatedURL = nil;
        
        [[_documentIndex copyLocalRelativePathToFileItem] enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, OFXFileItem *fileItem, BOOL *stop) {
            NSNumber *inode = fileItem.inode;
            if (inode == nil)
                return; // Locally missing
            NSURL *updatedURL = inodeToScannedURL[inode];
            if (!updatedURL)
                return; // New file, likely
            
            // Same root inode, so these are the same item.
            if (OFNOTEQUAL(fileItem.localDocumentURL, updatedURL)) {
                if (!fileItemToUpdatedURL)
                    fileItemToUpdatedURL = [[NSMutableDictionary alloc] init];
                fileItemToUpdatedURL[fileItem] = updatedURL;
            }
        }];
        
        if (fileItemToUpdatedURL) {
            NSMutableArray *intendedRelativePathsResolved = [[NSMutableArray alloc] init];
            [self _fileItemsMoved:fileItemToUpdatedURL intendedRelativePathsResolved:intendedRelativePathsResolved];
            
            // If any files have been moved from a conflict URL to their original intended relative path, then the user is picking a winner and the other conflict names are to be made real.
            [self _finalizeConflictNamesForFilesIntendingToBeAtRelativePaths:intendedRelativePathsResolved];
        }
    }
    
    // Now look for edits and creation of new files
    NSMutableArray <NSURL *> *newFileURLs = [NSMutableArray new];
    NSMutableDictionary <NSString *, OFXFileItem *> *remainingLocalRelativePathToFileItem = [_documentIndex copyLocalRelativePathToFileItem];
    
    for (NSURL *fileURL in _scan.scannedFileURLs) {
        OBASSERT([[[self class] containerAgentIdentifierForFileURL:fileURL] isEqual:_identifier]);

        // Most likely this is an existing file, possibly modified. We don't try to handle the case of exchangedata/FSExchangeObjects. So, if we have urlA and urlB and whose contents get swapped, we'll treat this as content updates to both rather than swapping moves.
        NSString *localRelativePath = [self _localRelativePathForFileURL:fileURL];
        OFXFileItem *fileItem = [_documentIndex fileItemWithLocalRelativePath:localRelativePath];
        if (fileItem) {
            OBASSERT(remainingLocalRelativePathToFileItem[localRelativePath] == fileItem);
            [remainingLocalRelativePathToFileItem removeObjectForKey:localRelativePath];
             
            // Don't try to upload if this is a new stub, new uploading document, or previously edited document that is still uploading.
            // We might also be in the middle of downloading and shouldn't start an upload. In this case, we may have been notified of a remote edit and have locally saved in the mean time (most commonly in test cases that are intentionally racing). In this case, when the download completes, the commit validation in the download transfer operation will notice a conflict.
            if (!fileItem.remoteState.missing && fileItem.isValidToUpload && !fileItem.isUploading && !fileItem.isDownloading) {
                __autoreleasing NSError *hasSameContentsError;
                NSNumber *same = [fileItem hasSameContentsAsLocalDocumentAtURL:fileURL error:&hasSameContentsError];
                if (same == nil) {
                    // The file might have been renamed or deleted and we need to rescan. Or, there might be a sandbox-induced permission error, in which case we should hopefully pause on the next rescan due to the error.
                    NSError *strongError = hasSameContentsError;
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        [strongError log:@"While scanning, error checking for changes in contents for %@", fileURL];
                    }];

                    NSString *reason = [NSString stringWithFormat:@"Error checking for changes in local file at %@.", fileURL];
                    OFXError(outError, OFXLocalAccountDirectoryPossiblyModifiedWhileScanning, @"Local account directory may been modified since scan began.", reason);
                    return NO;
                } else {
                    if ([same boolValue] == NO && !fileItem.localState.edited) {
                        __autoreleasing NSError *error;
                        if (![fileItem markAsLocallyEdited:&error]) {
                            // Not the end of the world, but not ideal... We should do a full scan on the next launch.
                            NSLog(@"Error marking file as locally edited %@: %@", [fileItem shortDescription], [error toPropertyList]);
                        }
                    }
                }
            } else {
                // Undownloaded remote file, new uploading document, or previously edited document that is still uploading.
                OBASSERT(fileItem.localState.missing == NO, @"File created where a non-downloaded file would go if it were downloaded");
            }
        } else {
            [newFileURLs addObject:fileURL];
        }
    }
    
    for (NSURL *fileURL in newFileURLs) {
        // New document!
        DEBUG_SCAN(1, @"Register document for new URL %@", fileURL);
        [self _handleNewLocalDocument:fileURL];
    }
    
    __block BOOL success = YES;
    __block NSError *error;
    
    [remainingLocalRelativePathToFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, OFXFileItem *fileItem, BOOL *stop) {
        if (fileItem.localState.missing || fileItem.localState.deleted) {
            // We don't expect this file to exist on disk, so its absense doesn't indicate a deletion.
            return;
        }
        
        DEBUG_SCAN(1, @"Mark file item deleted %@", fileItem.shortDescription);

        __autoreleasing NSError *deleteError;
        if (![self fileItemDeleted:fileItem error:&deleteError]) {
            // The only case this should happen is if we fail to write our updated metadata for the file item. Maybe our container is marked read-only, or sandboxing has denied permission, or the disk is full. In this case, log the error and the next time we scan we will try again.
            NSLog(@"Error posting delete of file at %@: %@", fileItem.localDocumentURL, [deleteError toPropertyList]);
            success = NO;
            error = deleteError;
        }
    }];
    
    [self _publishMetadataUpdates];

    OBPOSTCONDITION([self _checkInvariants]); // checks the queue too
    return success;
}

- (BOOL)fileItemDeleted:(OFXFileItem *)fileItem error:(NSError **)outError;
{
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    OBPRECONDITION(fileItem);
    OBPRECONDITION(fileItem.localState.missing || [_documentIndex fileItemWithLocalRelativePath:fileItem.localRelativePath] == fileItem);
    
    OFXAccountAgent *accountAgent = _weak_accountAgent;
    if (!accountAgent) {
        OBASSERT_NOT_REACHED("Account agent didn't wait for background operations to finish?");
        return NO;
    }
    
    // We almost don't have to to make local delete notes, but if we are running-but-paused, we do. We need to stop publishing metadata for the file, but we need to hold onto the snapshot and delete it later.
    if (![fileItem markAsLocallyDeleted:outError])
        return NO;
    
    [_documentIndex beginLocalDeletionOfFileItem:fileItem];
    
    [accountAgent containerNeedsFileTransfer:self];
    
    OBPOSTCONDITION([self _checkInvariants]);
    return YES;
}

// Called by OFXAccountAgent when it notices a simple rename of a document (byUser = YES) and by OFXFileItem when it downloads a new snapshot that causes a move invoked by the server.
// We require the caller to pass in the fileItem since they may want to move an unpublished document (not yet downloaded or the subject of a name conflict).
- (void)fileItemMoved:(OFXFileItem *)fileItem fromURL:(NSURL *)oldURL toURL:(NSURL *)newURL byUser:(BOOL)byUser;
{
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    OBPRECONDITION(fileItem);

    // TODO: Case insensitivity restrictions?
    NSString *oldRelativePath = [self _localRelativePathForFileURL:oldURL];
    NSString *newRelativePath = [self _localRelativePathForFileURL:newURL];

    BOOL pathChanged = OFNOTEQUAL(oldRelativePath, newRelativePath);
    OBASSERT((fileItem.localState.autoMoved && byUser) || pathChanged, "Unless we are finalizing a conflict name, this should be an automove getting finalized");
    
    OBASSERT(fileItem.localState.missing || OFURLIsStandardizedOrMissing(newURL)); // standardizing non-existent URLS doesn't work so don't check if we are renaming something that isn't downloaded. It might have also been moved and then quickly moved again or deleted before we could process the rename.

    // If this is coming from the server, don't call back to the item (it will update itself) or provoke an upload of the move.
    [fileItem markAsMovedToURL:newURL source:byUser ? OFXFileItemMoveSourceLocalUser : OFXFileItemMoveSourceAutomatic];
    
    if (pathChanged)
        [_documentIndex fileItemMoved:fileItem fromLocalRelativePath:oldRelativePath toLocalRelativePath:newRelativePath];
    
    if (byUser) {
        OFXAccountAgent *accountAgent = _weak_accountAgent;
        OBASSERT(accountAgent);
        [accountAgent containerNeedsFileTransfer:self];
    }
    
    OBPOSTCONDITION([self _checkInvariants]);
}

// Bulk move that handles swapping renames. All moves are "by-user"
- (void)_fileItemsMoved:(NSDictionary *)fileItemToUpdatedURL intendedRelativePathsResolved:(NSMutableArray *)intendedRelativePathsResolved;
{
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    
    if ([fileItemToUpdatedURL count] == 0)
        return;

    DEBUG_LOCAL_RELATIVE_PATH(1, @"Preparing bulk moves for %@", fileItemToUpdatedURL);

    NSMutableArray *fileItemMoves = [[NSMutableArray alloc] init];
    [fileItemToUpdatedURL enumerateKeysAndObjectsUsingBlock:^(OFXFileItem *fileItem, NSURL *updatedFileURL, BOOL *stop) {
        NSString *updatedRelativePath = [self _localRelativePathForFileURL:updatedFileURL];

        OBASSERT(fileItem.localState.missing || OFURLIsStandardizedOrMissing(updatedFileURL)); // standardizing non-existent URLS doesn't work so don't check if we are renaming something that isn't downloaded. It might have also been moved and then quickly moved again or deleted before we could process the rename.
        
        // Capture the file item's current relative path before updating it...
        OFXContainerDocumentIndexMove *move = [OFXContainerDocumentIndexMove new];
        move.fileItem = fileItem;
        move.originalRelativePath = fileItem.localRelativePath;
        move.updatedRelativePath = updatedRelativePath;
        [fileItemMoves addObject:move];

        DEBUG_LOCAL_RELATIVE_PATH(1, @"  %@ -> %@", move.originalRelativePath, move.updatedRelativePath);

        // If the file item is being moved by the user to its original non-conflict operation, this isn't a publishable move.
        OFXFileItemMoveSource moveSource = OFXFileItemMoveSourceLocalUser;
        
        OBASSERT_NOTNULL(updatedRelativePath);
        if (fileItem.localState.autoMoved && OFISEQUAL(updatedRelativePath, fileItem.intendedLocalRelativePath)) {
            [intendedRelativePathsResolved addObject:updatedRelativePath]; // Let the caller know that *other* items wanting this relative path have been told they can't have it.
            moveSource = OFXFileItemMoveSourceAutomatic;
        }
        
        [fileItem markAsMovedToURL:updatedFileURL source:moveSource];
    }];
    
    [_documentIndex fileItemsMoved:fileItemMoves];
    
    OFXAccountAgent *accountAgent = _weak_accountAgent;
    OBASSERT(accountAgent);
    [accountAgent containerNeedsFileTransfer:self];
    
    OBPOSTCONDITION([self _checkInvariants]);
}

// Either the error handler is called (for preflight problems), or the action, but not both.
- (void)_operateOnFileAtURL:(NSURL *)fileURL errorHandler:(void (^)(NSError *error))errorHandler withAction:(void (^)(OFXFileItem *))fileAction;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    NSString *relativePath = [self _localRelativePathForFileURL:fileURL];
    OFXFileItem *fileItem = [_documentIndex fileItemWithLocalRelativePath:relativePath];
    
    if (!fileItem) {
        __autoreleasing NSError *error;
        OFXError(&error, OFXNoFileForURL, @"No file has the specified URL.", nil);
        if (errorHandler)
            errorHandler(error);
        return;
    }
    
    fileAction(fileItem);
}

- (void)downloadFileAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    completionHandler = [completionHandler copy];
    [self _operateOnFileAtURL:fileURL errorHandler:completionHandler withAction:^(OFXFileItem *fileItem){
        [fileItem setContentsRequested];
        
        OFXAccountAgent *accountAgent = _weak_accountAgent;
        if (!accountAgent) {
            // Stopped before a download could start?
            if (completionHandler) {
                __autoreleasing NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                OBChainError(&error);
                completionHandler(error);
            }
        }
        [accountAgent containerNeedsFileTransfer:self requestRecorded:^{
            OBASSERT([self _runningOnAccountAgentQueue]);
            completionHandler(nil);
        }];
    }];
}

// Called due to a user requested delete of a file that may or may not be downloaded. If it is downloaded, use file coordination so that presenters will be notified. Otherwise, mark the file as deleted and start a push to the server.
- (void)deleteItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    completionHandler = [completionHandler copy];
    [self _operateOnFileAtURL:fileURL errorHandler:completionHandler withAction:^(OFXFileItem *fileItem){
        if (fileItem.localState.missing) {
            // No local file to delete; just tweak the metadata.
            TRACE_SIGNAL(OFXContainerAgent.delete_item.metadata);
            __autoreleasing NSError *deleteError;
            if ([self fileItemDeleted:fileItem error:&deleteError])
                completionHandler(nil);
            else
                completionHandler(deleteError);
        } else {
            // Use file coordination. Our account will get poked via its file presenter and will update the metadata.
            // TODO: Is there a benefit to us taking our account as a file presenter here and poking the metadata directly?
            TRACE_SIGNAL(OFXContainerAgent.delete_item.file_coordination);
            __autoreleasing NSError *deleteError;
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            BOOL success = [coordinator removeItemAtURL:fileURL error:&deleteError byAccessor:^BOOL(NSURL *newURL, NSError **outError) {
                return [[NSFileManager defaultManager] removeItemAtURL:newURL error:outError];
            }];
            if (!success) {
                [deleteError log:@"Error deleting %@", [fileURL absoluteString]];
                completionHandler(deleteError);
            } else
                completionHandler(nil);
        }
    }];
}

- (OFFileMotionResult *)_performMoveFromURL:(NSURL *)originalFileURL toURL:(NSURL *)updatedFileURL error:(NSError **)outError;
{
    // NOTE: Case-only renames send a different sequence of file presenter messages, *not* including -presentedSubitemAtURL:didMoveToURL:. See screed in -[NSFileCoordinator(OFExtensions) moveItemAtURL:toURL:createIntermediateDirectories:error:]). So, we have to pass a file presenter to the coordinator and will notify ourselves about the rename, at least for that one presenter). If there are multiple presenters, some of them are screwed.
    id <NSFilePresenter> filePresenter = _weak_filePresenter;
    OBASSERT(filePresenter);
    
    TRACE_SIGNAL(OFXContainerAgent.move_item.file_coordination);
    
    __autoreleasing NSError *moveError;
    __block OFFileEdit *resultFileEdit = nil;
    __block NSError *fileEditError = nil;

    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:filePresenter];
    BOOL success = [coordinator moveItemAtURL:originalFileURL toURL:updatedFileURL createIntermediateDirectories:YES error:&moveError success:^(NSURL *resultURL) {
        __autoreleasing NSError *error;
        resultFileEdit = [[OFFileEdit alloc] initWithFileURL:resultURL error:&error];
        if (!resultFileEdit) {
            OBASSERT_NOT_REACHED("Success shouldn't have been called if the move was a success");
            fileEditError = error;
            [fileEditError log:@"Error making file edit when moving %@ to %@", originalFileURL, updatedFileURL];
        }
    }];
    
    if (success) {
        if (!resultFileEdit) {
            // Again, this shouldn't happen, but just in case...
            if (outError)
                *outError = fileEditError;
            return nil;
        }
        
        // The file coordinator might have given us a temporary URL. Make sure we are reporting the state that should have existed at the moment the coordinated move finished (though of course, by now, racing edits may have changed things).
        resultFileEdit = [[OFFileEdit alloc] initWithFileURL:updatedFileURL fileModificationDate:resultFileEdit.fileModificationDate inode:resultFileEdit.inode isDirectory:resultFileEdit.directory];
        
        return [[OFFileMotionResult alloc] initWithFileEdit:resultFileEdit];
    }

    // Maybe hit in http://rt.omnigroup.com/Ticket/Display.html?id=886781 and http://rt.omnigroup.com/Ticket/Display.html?id=886777
    // Definitely hit in http://rt.omnigroup.com/Ticket/Attachment/14329504/8130862/
    // Presumably we've downloaded conflict resolution done on another machine, but there have been multiple conflicts or conflicting resolutions. Punt instead of OBFinishPorting, and we'll hopefully retry on the next sync when we have more info.
    [moveError log:@"Error moving %@ to %@", originalFileURL, updatedFileURL];
    if (outError)
        *outError = moveError;
    return nil;
}

- (OFFileMotionResult *)_moveFileItem:(OFXFileItem *)fileItem fromURL:(NSURL *)originalFileURL toURL:(NSURL *)updatedFileURL byUser:(BOOL)byUser error:(NSError **)outError;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    OBASSERT(OFISEQUAL(originalFileURL, fileItem.localDocumentURL));
    
    if (fileItem.localState.missing) {
        OBASSERT(OFURLContainsURL(_account.localDocumentsURL, updatedFileURL), "Attempting to move the file out of our domain?");
        
        // No local file to move; just tweak the metadata.
        TRACE_SIGNAL(OFXContainerAgent.move_item.metadata);
        [self fileItemMoved:fileItem fromURL:originalFileURL toURL:updatedFileURL byUser:byUser];
        
        return [[OFFileMotionResult alloc] initWithPromisedFileURL:updatedFileURL];
    } else {
        OFFileMotionResult *result;
        if (OFURLEqualsURL(originalFileURL, updatedFileURL)) {
            // This can happen when we are called from -_finalizeConflictNamesForFilesIntendingToBeAtRelativePaths:.
            OBFinishPortingLater("<bug:///147947> (iOS-OmniOutliner Engineering: Not sure this can be hit any more - case in -[OFXContainerAgent _moveFileItem:fromURL:toURL:byUser:error:])"); // Tested fixing conflicts between two non-missing files and this is called with the two 'conflict' names.
            OBASSERT(fileItem.localState.autoMoved);
            
            OFXFileMetadata *metadata = [fileItem _makeMetadata]; // A bit heavy handed way to get the info we need, but this path should be pretty rare.
            OFFileEdit *fileEdit = [[OFFileEdit alloc] initWithFileURL:updatedFileURL fileModificationDate:metadata.fileModificationDate inode:[metadata.inode unsignedIntegerValue] isDirectory:metadata.directory];
            result = [[OFFileMotionResult alloc] initWithFileEdit:fileEdit];
        } else {
            result = [self _performMoveFromURL:originalFileURL toURL:updatedFileURL error:outError];
        }
        if (result) {
            OFXNoteContentMoved(self, originalFileURL, updatedFileURL);
            [self fileItemMoved:fileItem fromURL:originalFileURL toURL:updatedFileURL byUser:byUser];
        }
        return result;
    }
}

- (void)moveItemAtURL:(NSURL *)originalFileURL toURL:(NSURL *)updatedFileURL completionHandler:(void (^)(OFFileMotionResult *result, NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    completionHandler = [completionHandler copy];
    [self _operateOnFileAtURL:originalFileURL errorHandler:^(NSError *error){
        OBASSERT([NSThread isMainThread]);
        if (completionHandler)
            completionHandler(nil, error);
    } withAction:^(OFXFileItem *fileItem){
        __autoreleasing NSError *moveError;
        OFFileMotionResult *moveResult = [self _moveFileItem:fileItem fromURL:originalFileURL toURL:updatedFileURL byUser:YES error:&moveError];
        if (!moveResult)
            completionHandler(nil, moveError);
        else
            completionHandler(moveResult, nil);
    }];
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    if (_debugName)
        return [NSString stringWithFormat:@"<Container %@ %p>", _debugName, self];

    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, self.identifier];
}

#pragma mark - Internal

- (NSString *)_localRelativePathForFileURL:(NSURL *)fileURL;
{
    // We shouldn't need to standardize the URL here since the localDocumentsURL should already be standardized. Also, we aren't acting under file coordination here, so we shouldn't look at the filesystem (which standardization does).
    NSURL *localDocumentsURL = _account.localDocumentsURL;

    return OFFileURLRelativePath(localDocumentsURL, fileURL);
}

- (NSURL *)_URLForLocalRelativePath:(NSString *)relativePath isDirectory:(BOOL)isDirectory;
{
    return [_account.localDocumentsURL URLByAppendingPathComponent:relativePath isDirectory:isDirectory];
}

- (void)_fileItem:(OFXFileItem *)fileItem didGenerateConflictAtURL:(NSURL *)conflictURL coordinator:(NSFileCoordinator *)coordinator;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    // Make a new file item to take over the snapshot the original file item (which is about to get -didGiveUpLocalContents:). Record the conflict location as the automatically assigned relative path, but keep the same user desired path.
    __autoreleasing NSError *error = nil;
    OFXFileItem *conflictItem = [[OFXFileItem alloc] initWithNewLocalDocumentURL:conflictURL asConflictGeneratedFromFileItem:fileItem coordinator:coordinator container:self error:&error];
    if (!conflictURL) {
        // If the file real is there and we can eventually read it, we'll end up making a new document that has the conflictURL is its user-intended location.
        [error log:@"Error creating new file item for conflict version at %@", conflictURL];
        return;
    }

    [conflictItem self];
    
    [self _fileItemNeedsMetadataUpdated:conflictItem];
    [_documentIndex registerScannedLocalFileItem:conflictItem];

    [self _updatePublishedFileVersions];
    OBPOSTCONDITION([self _checkInvariants]);
}

// We don't know what the remote version is in this case. The container needs to scan to find out.
- (void)_fileItemDidDetectUnknownRemoteEdit:(OFXFileItem *)fileItem;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    OFXAccountAgent *accountAgent = _weak_accountAgent;
    if (!accountAgent)
        return;
    
    // Stop further transfers until our next scan (which will be queued by our call to the account agent next).
    DEBUG_TRANSFER(1, @"Unknown remote edit noted by file item %@.", fileItem.shortDescription);
    _hasUnknownRemoteEdit = YES;
    
    [accountAgent _fileItemDidDetectUnknownRemoteEdit:fileItem];
}

- (BOOL)_relocateFileAtURL:(NSURL *)fileURL toMakeWayForFileItem:(OFXFileItem *)fileItem coordinator:(NSFileCoordinator *)coordinator error:(NSError **)outError;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    OBPRECONDITION(fileURL);
    OBPRECONDITION(fileItem);
    OBPRECONDITION(coordinator);

    DEBUG_CONFLICT(1, @"Making way for incoming document at %@", fileURL);
    DEBUG_CONFLICT(1, @"  fileItem moving there %@", [fileItem shortDescription]);

    OFXFileItem *otherItem = [self fileItemWithURL:fileURL];
    DEBUG_CONFLICT(1, @"  otherItem currently there %@", [otherItem shortDescription]);
    if (otherItem == fileItem) {
        // There is something in the way of this item, which is the registered owner for this path.
        otherItem = nil;
    }

    NSURL *conflictURL;
    if (otherItem) {
        // Call -fileURLForConflictVersion on this item, since that will use the receiver's intended relative path, which might differ.
        conflictURL = [otherItem fileURLForConflictVersion];
    } else {
        conflictURL = [fileItem fileURLForConflictVersion];
    }
    OBASSERT(conflictURL);

    if (!otherItem) {
        // The thing in our way appeared very recently (possibly as a result of our provoking autosave, as in -[OFXConflictTestCase testIncomingMoveVsLocalAutosaveCreation]).
        // Make a file item for it right now and mark it as auto-moved immediately, so that we record the user's intended name, rather than doing a conflict move here and promoting that name to the user intended name).
        __autoreleasing NSError *error = nil;
        if (!(otherItem = [[OFXFileItem alloc] initWithNewLocalDocumentURL:fileURL container:self error:&error])) {
            // Well, we tried. Move aside the file by itself -- thus promoting the file name to the user intended name, but at least preserving the contents.
            // The coordinator should have a file presenter so that this move is not interpreted as moving *us*, but sadly we have no way of asserting that here.
            __autoreleasing NSError *moveError = nil;
            if ([coordinator moveItemAtURL:fileURL toURL:conflictURL createIntermediateDirectories:NO/*sibling*/ error:&moveError])
                return YES;
            
            if (outError)
                *outError = moveError;
            OBChainError(outError);
            return NO;
        }
        
        // Move the existing file aside before registering this item.
        __autoreleasing NSError *moveError = nil;
        if (![self _performMoveFromURL:fileURL toURL:conflictURL error:&moveError]) {
            // Hopefully someone else moved/delete the file...
            if (outError)
                *outError = moveError;
            OBChainError(outError);
            return NO;
        }

        // Tell the item about the move, but don't go through our -fileItemMoved:fromURL:toURL:byUser: since that also updates the index (and the item isn't in there yet).
        OFXNoteContentMoved(self, fileURL, conflictURL);
        [otherItem markAsMovedToURL:conflictURL source:OFXFileItemMoveSourceAutomatic];
        
        // Then, register it under its new name.
        [self _fileItemNeedsMetadataUpdated:otherItem];
        [_documentIndex registerLocallyAppearingFileItem:otherItem];
        return YES;
    } else {
        // Use our API so the otherItem's URL is updated.
        __autoreleasing NSError *conflictError;
        if ([self _moveFileItem:otherItem fromURL:otherItem.localDocumentURL toURL:conflictURL byUser:NO error:&conflictError])
            return YES;
        if (outError)
            *outError = conflictError;
        OBChainError(outError);
        return NO;
    }
}

- (void)_fileItemNeedsMetadataUpdated:(OFXFileItem *)fileItem;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    if (fileItem.localState.deleted && (fileItem.remoteState.missing || fileItem.remoteState.deleted)) {
        // This was never uploaded, or has been deleted remotely too, so the "delete" transfer isn't going to actually do any network work (which is why we delay clearing the metadata -- so we can show the number of delete operations that need to be performed). Also, if we generate metadata here, we'll hit assertions.
        DEBUG_METADATA(1, @"Needs to remove metadata for never-uploaded %@", [fileItem shortDescription]);
        [self _fileItemNeedsMetadataRemoved:fileItem];
    } else if (fileItem.localState.missing && fileItem.remoteState.deleted) {
        // This got deleted while we were downloading it for the first time.
        DEBUG_METADATA(1, @"Needs to remove metadata for never-downloaded %@", [fileItem shortDescription]);
        [self _fileItemNeedsMetadataRemoved:fileItem];
    } else {
        DEBUG_METADATA(1, @"Needs to update metadata for %@", [fileItem shortDescription]);
        if (!_fileItemsNeedingMetadataUpdate)
            _fileItemsNeedingMetadataUpdate = [[NSMutableSet alloc] init];
        [_fileItemsNeedingMetadataRemoved removeObject:fileItem];
        [_fileItemsNeedingMetadataUpdate addObject:fileItem];
    }

    [self _scheduleMetadataUpdate];
}

- (void)_fileItemNeedsMetadataRemoved:(OFXFileItem *)fileItem;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    DEBUG_METADATA(1, @"Needs to clear metadata for %@", [fileItem shortDescription]);
    if (!_fileItemsNeedingMetadataRemoved)
        _fileItemsNeedingMetadataRemoved = [[NSMutableSet alloc] init];
    [_fileItemsNeedingMetadataUpdate removeObject:fileItem];
    [_fileItemsNeedingMetadataRemoved addObject:fileItem];

    [self _scheduleMetadataUpdate];
}

- (void)_scheduleMetadataUpdate;
{
    if (_hasScheduledMetadataUpdate)
        return;
    
    _hasScheduledMetadataUpdate = YES;
    
    DEBUG_METADATA(1, @"Scheduling metadata update");
    
    // Schedule a delayed timer to perform the update, if we don't do it manually.
    OFXAccountAgent *accountAgent = _weak_accountAgent;
    [accountAgent _containerAgentNeedsMetadataUpdate:self];
}

- (void)_publishMetadataUpdates;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    OBPRECONDITION([_fileItemsNeedingMetadataUpdate intersectsSet:_fileItemsNeedingMetadataRemoved] == NO, "Removals and updates should be disjoint");
    
    DEBUG_METADATA(1, @"Publishing metadata removals for %@", _fileItemsNeedingMetadataRemoved);
    DEBUG_METADATA(1, @"Publishing metadata updates for %@", _fileItemsNeedingMetadataUpdate);

    // Might get reset during conflict resolution.
    _hasScheduledMetadataUpdate = NO;
    
    // Make sure we don't publish two file items that say they are at the same file URL.
    [self _generateAutomaticMovesToAvoidNameConflicts];
    
    // Don't expect reentrant updates, but let's check
    NSSet <OFXFileItem *> *removals = _fileItemsNeedingMetadataRemoved;
    _fileItemsNeedingMetadataRemoved = nil;
    
    NSSet <OFXFileItem *> *updates = _fileItemsNeedingMetadataUpdate;
    _fileItemsNeedingMetadataUpdate = nil;
    
    // Do these updates in bulk. Otherwise, we run the risk of publishing two items with the same URL. For example, -[OFXRenameTestCase testRenameOfFileAndCreationOfNewFileAsSamePathWhileNotRunning] would occassionally do so.
    NSMutableArray <NSString *> *removeIdentifiers = [[NSMutableArray alloc] init];
    for (OFXFileItem *fileItem in removals)
        [removeIdentifiers addObject:fileItem.identifier];
    NSMutableDictionary <NSString *, OFXFileMetadata *> *addItems = [[NSMutableDictionary alloc] init];
    for (OFXFileItem *fileItem in updates) {
        OFXFileMetadata *metadata = [fileItem _makeMetadata];
        addItems[fileItem.identifier] = metadata;
    }

    [_metadataRegistrationTable removeObjectsWithKeys:removeIdentifiers setObjectsWithDictionary:addItems];
    
    OBPOSTCONDITION(_fileItemsNeedingMetadataRemoved == nil);
    OBPOSTCONDITION(_fileItemsNeedingMetadataUpdate == nil);
}

- (NSString *)debugName;
{
    if (![NSString isEmptyString:_debugName])
        return _debugName;

    OFXAccountAgent *accountAgent = _weak_accountAgent;
    OBASSERT(accountAgent);
    return accountAgent.debugName;
}

#pragma mark - Private

/*
 The Snapshots directory is a flat list of uuid document directories. Each contains:
 
 - Info.plist, with a copy of the server information for this document
 - Version.plist, with info about the last version we grabbed (PROPFIND ETags and sizes)
 - if edited, the document contents as a 'contents' flat file or folder. The contents are in the client-defined structure, as opposed to the server flat UUID->content map
 */
- (void)_scanLocalSnapshots;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    OBPRECONDITION(_documentIndex == nil);
    
    DEBUG_SCAN(1, @"Performing Snapshots scan");
    
    id <NSFilePresenter> filePresenter = _weak_filePresenter;
    
    _documentIndex = [[OFXContainerDocumentIndex alloc] initWithContainerAgent:self];
    
    __autoreleasing NSError *error = nil;
    NSArray *localSnapshotURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_localSnapshotsDirectory includingPropertiesForKeys:nil options:0 error:&error];
    if (!localSnapshotURLs) {
        NSLog(@"Unable to determine contents of Snapshots directory %@: %@", _localSnapshotsDirectory, [error toPropertyList]);
        return;
    }
    
    for (__strong NSURL *localSnapshotURL in localSnapshotURLs) {
        // -contentsOfDirectoryAtURL:... returns non-standardized URLs even when the input is standardized. Sigh.
        localSnapshotURL = [localSnapshotURL URLByStandardizingPath];
        
        __autoreleasing NSError *fileError = nil;
        OFXFileItem *fileItem = [[OFXFileItem alloc] initWithExistingLocalSnapshotURL:localSnapshotURL container:self filePresenter:filePresenter error:&fileError];
        if (!fileItem) {
            NSLog(@"Error creating file item from local snapshot at %@: %@", localSnapshotURL, fileError);
            OBFinishPortingLater("<bug:///147844> (iOS-OmniOutliner Engineering: Should we just remove the local snapshot in this case and redownload/upload? in -[OFXContainerAgent _scanLocalSnapshots])");
            continue;
        }
        OBASSERT(OFISEQUAL([localSnapshotURL lastPathComponent], fileItem.identifier));

        if (fileItem.localState.deleted == NO) // Would just try to remove the metadata, if the local snapshot represents an un-pushed delete, but we haven't generated any metadata yet.
            [self _fileItemNeedsMetadataUpdated:fileItem];
        
        [_documentIndex registerScannedLocalFileItem:fileItem];
    }
    
    DEBUG_SCAN(2, @"_documentIndex = %@", [_documentIndex debugDictionary]);
    
    [self _updatePublishedFileVersions];
    OBPOSTCONDITION([self _checkInvariants]);
}

- (OFXFileItem *)_handleNewLocalDocument:(NSURL *)fileURL;
{
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    OBPRECONDITION(_documentIndex);
    
    DEBUG_SCAN(1, @"Making snapshot for new local document %@", fileURL);

    __autoreleasing NSError *error = nil;
    OFXFileItem *fileItem = [[OFXFileItem alloc] initWithNewLocalDocumentURL:fileURL container:self error:&error];
    if (!fileItem) {
        NSLog(@"Error creating file item from newly discovered docuemnt at %@: %@", fileURL, [error toPropertyList]);
        return nil;
    }

    [self _fileItemNeedsMetadataUpdated:fileItem];
    [_documentIndex registerLocallyAppearingFileItem:fileItem];
    
    OBPOSTCONDITION([self _checkInvariants]);

    return fileItem;
}

- (ODAVConnection *)_makeConnection;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    OFXAccountAgent *accountAgent = _weak_accountAgent;
    if (!accountAgent) {
        OBASSERT_NOT_REACHED("Account agent didn't wait for background operations to finish?");
        return nil;
    }
    return [accountAgent _makeConnection];
}

- (void)_hasCreatedRemoteDirectory;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    // TODO: What happens if we create the directory, another agent removes it somehow, a third agent starts up and doesn't see the directory, but sees some files of that type (but doesn't itself have any app that defines the UTI)? Terrible, probably.
    if (!_hasCreatedRemoteContainerDirectory) {
        _hasCreatedRemoteContainerDirectory = YES;
        [self _updatePublishedFileVersions];
    }
}

- (void)_updatePublishedFileVersions;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    // Only publish state for the containers that have created their remote directory. If we publish too early, other agents may try to sync in response to the net state notification and will not see the remote container (racing vs. creation possibly). Then, they wouldn't get notified again since the state wouldn't change. This would clean itself up on the timed sync, but better to do it right the first time!
    if (!_hasCreatedRemoteContainerDirectory)
        return;
    
    NSMutableArray <NSString *> *fileVersions = [NSMutableArray new];
    
    // This (intentionally) includes identifiers for locally deleted file items. We don't claim a new state until the *server* is changed.
    [_documentIndex enumerateFileItems:^(NSString *identifier, OFXFileItem *fileItem) {
        // Don't include new files until they've been uploaded once, or remotely deleted files that we haven't yet cleaned up. We'll be called again at the end of -_queueUploadOfFileItem: to publish this item.
        if (!fileItem.presentOnServer)
            return;

        [fileVersions addObject:fileItem.publishedFileVersion];
    }];
    
    if (OFNOTEQUAL(_publishedFileVersions, fileVersions)) {
        _publishedFileVersions = [fileVersions copy];
        
        OFXAccountAgent *accountAgent = _weak_accountAgent;
        [accountAgent containerPublishedFileVersionsChanged:self];
    }
}

- (void)_enumerateDocumentFileInfos:(id <NSFastEnumeration>)fileInfos collectStaleFileInfoVersions:(NSMutableArray <ODAVFileInfo *> *)staleFileInfos applier:(void (^)(NSString *fileIdentifier, NSUInteger fileVersion, ODAVFileInfo *fileInfo))applier;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    NSMutableDictionary <NSString *, ODAVFileInfo *> *fileIdentifierToLatestFileInfo = [NSMutableDictionary new];
    
    for (ODAVFileInfo *fileInfo in fileInfos) {
        if (!fileInfo.isDirectory) {
            NSLog(@"%@: Found flat file %@ where only document directories were expected", [self shortDescription], fileInfo.originalURL);
            continue;
        }
        
        NSURL *remoteURL = fileInfo.originalURL;

        __autoreleasing NSError *error;
        NSUInteger version;
        NSString *identifier = OFXFileItemIdentifierFromRemoteSnapshotURL(remoteURL, &version, &error);
        if (!identifier) {
            [error log:@"Error parsing remoteURL %@ as remote snapshot URL", remoteURL];
            continue;
        }
        
        ODAVFileInfo *otherFileInfo = fileIdentifierToLatestFileInfo[identifier];
        if (otherFileInfo) {
            // This should be fairly rare, so we just re-parse the version
            NSUInteger otherVersion;
            if (!OFXFileItemIdentifierFromRemoteSnapshotURL(otherFileInfo.originalURL, &otherVersion, NULL)) {
                OBASSERT_NOT_REACHED("We just parsed this!");
            } else if (version < otherVersion) {
                // This version we just found is older and superseded
                [staleFileInfos addObject:fileInfo];
            } else {
                // This version is newer and the one we had before is superseded
                OBASSERT(version > otherVersion, "Versions should not be equal");
                [staleFileInfos addObject:otherFileInfo];
                fileIdentifierToLatestFileInfo[identifier] = fileInfo;
            }
        } else {
            fileIdentifierToLatestFileInfo[identifier] = fileInfo;
        }
    }
    
    [fileIdentifierToLatestFileInfo enumerateKeysAndObjectsUsingBlock:^(NSString *existingIdentifier, ODAVFileInfo *fileInfo, BOOL *stop) {
        NSUInteger version;
        NSString *identifier = OFXFileItemIdentifierFromRemoteSnapshotURL(fileInfo.originalURL, &version, NULL);
        OBASSERT([identifier isEqual:existingIdentifier]); OB_UNUSED_VALUE(identifier);
        
        applier(existingIdentifier, version, fileInfo);
    }];
}

// If we have multpile file items that want to be at a given relative path, update the local filename (and move the file if they are actually published). We will *not* upload these renames to the server since they don't reflect the user's intent and since doing so can cause a rename storm.
- (void)_generateAutomaticMovesToAvoidNameConflicts;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    NSDictionary <NSString *, NSArray <OFXFileItem *> *> *intendedLocalRelativePathToFileItems = [_documentIndex copyIntendedLocalRelativePathToFileItems];
    [intendedLocalRelativePathToFileItems enumerateKeysAndObjectsUsingBlock:^(NSString *relativePath, NSArray *fileItems, BOOL *stop) {
        if ([fileItems count] < 2) {
            // Check if there is a automatic rename that can be undone now that we have a single document intending to be at that location
            OFXFileItem *fileItem = [fileItems lastObject];
            OBASSERT(fileItem);
            
            if (fileItem.localState.autoMoved) {
                DEBUG_CONTENT(1, @"Name conflict for %@ has been resolved to %@", relativePath, [fileItem shortDescription]);
                
                NSURL *intendedLocalURL = [fileItem _intendedLocalDocumentURL];

                // Note that we pass byUser:NO even though we are renaming to the user-intended file. This is an automatic move that should remove the 'autoMove' state flag.
                DEBUG_CONFLICT(1, @"  ... moving %@ to %@", [fileItem shortDescription], intendedLocalURL);
                TRACE_SIGNAL(OFXContainerAgent.conflict_automove_undone);
                
                __autoreleasing NSError *moveError;
                if (![self _moveFileItem:fileItem fromURL:fileItem.localDocumentURL toURL:intendedLocalURL byUser:NO error:&moveError])
                    [moveError log:@"Error moving name conflict winner to %@", intendedLocalURL];
                else {
                    OBASSERT(fileItem.localState.autoMoved == NO);
                }
            }
            
            return;
        }
        
        DEBUG_CONFLICT(1, @"Checking for name conflicts for %@ -> %@", relativePath, [fileItems arrayByPerformingBlock:^(OFXFileItem *fileItem){
            return [fileItem shortDescription];
        }]);
        
        for (OFXFileItem *fileItem in fileItems) {
            if (fileItem.localState.autoMoved)
                continue; // Already relocated
            
            DEBUG_CONTENT(1, @"Conflicting file %@ has content %@", [fileItem shortDescription], OFXLookupDisplayNameForContentIdentifier(fileItem.currentContentIdentifier));

            NSURL *conflictURL = [fileItem fileURLForConflictVersion];
            
            // Can't use the URL-based -moveItemAtURL:toURL:completionHandler: since by definition all have the same desired local URL right now.
            DEBUG_CONFLICT(1, @"  ... moving %@ to %@", [fileItem shortDescription], conflictURL);
            TRACE_SIGNAL(OFXContainerAgent.conflict_automove_done);
            __autoreleasing NSError *moveError;
            if (![self _moveFileItem:fileItem fromURL:fileItem.localDocumentURL toURL:conflictURL byUser:NO error:&moveError])
                [moveError log:@"Error moving name conflict loser to %@", conflictURL];
        }
    }];
}

// This is called when the user renames an automoved file to have its original name, thus declaring which file is the winner of the conflict. At that point, all the other files that were intending to be at that path have their automoved conflict paths made their intended path (and pushed to the server and other clients).
- (void)_finalizeConflictNamesForFilesIntendingToBeAtRelativePaths:(NSArray <NSString *> *)relativePaths;
{
    if ([relativePaths count] == 0)
        return;
    
    NSDictionary <NSString *, NSArray <OFXFileItem *> *> *intendedLocalRelativePathToFileItems = [_documentIndex copyIntendedLocalRelativePathToFileItems];

    for (NSString *relativePath in relativePaths) {
        for (OFXFileItem *fileItem in intendedLocalRelativePathToFileItems[relativePath]) {
            if (!fileItem.localState.autoMoved) {
                continue; // The winner still intends to have this path
            }
            
            // Note that the source and destination URL are the same here so the lower level methods need to accept that.
            NSURL *finalizedURL = fileItem.localDocumentURL;
            
            __autoreleasing NSError *error = nil;
            if (![self _moveFileItem:fileItem fromURL:finalizedURL toURL:finalizedURL byUser:YES error:&error]) {
                [error log:@"Error finalizing file item's path at %@", fileItem.localDocumentURL];
            }
        }
    }
}

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_runningOnAccountAgentQueue;
{
    OFXAccountAgent *accountAgent = _weak_accountAgent;
    if (!accountAgent) {
        OBASSERT_NOT_REACHED("Got called while account agent is shutting down?"); // Should probably just ignore it in the new no-wait-shutdown model.
        return YES;
    }
    return accountAgent.runningOnAccountAgentQueue;
}

- (BOOL)_checkInvariants;
{
    OBASSERT([self _runningOnAccountAgentQueue]); // since we're looking at state that is read/written on this queue.
    
    OBINVARIANT([_documentIndex _checkInvariants]);
    
    [_documentIndex enumerateFileItems:^(NSString *identifier, OFXFileItem *fileItem) {
        if (fileItem.localState.deleted == NO) {
            OBINVARIANT(OFISEQUAL(fileItem.localRelativePath, [self _localRelativePathForFileURL:fileItem.localDocumentURL]));
            OBINVARIANT(OFISEQUAL(_identifier, [[self class] containerAgentIdentifierForFileURL:fileItem.localDocumentURL])); // Can't ask a deleted item for its localDocumentURL
        }
    }];
        
    return YES;
}
#endif

@end
