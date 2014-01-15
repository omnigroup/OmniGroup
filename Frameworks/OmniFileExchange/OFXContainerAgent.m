// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXContainerAgent-Internal.h"

#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFileExchange/OFXAgent.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>

#import "OFXAccountAgent-Internal.h"
#import "OFXContainerDocumentIndex.h"
#import "OFXContainerScan.h"
#import "OFXContentIdentifier.h"
#import "OFXDownloadFileSnapshot.h"
#import "OFXFileItem-Internal.h"
#import "OFXFileSnapshotRemoteEncoding.h"
#import "OFXFileSnapshotTransfer.h"

RCS_ID("$Id$")

@interface OFXContainerAgent ()
@end

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

- initWithAccountAgent:(OFXAccountAgent *)accountAgent identifier:(NSString *)identifier metadataRegistrationTable:(OFXRegistrationTable *)metadataRegistrationTable localContainerDirectory:(NSURL *)localContainerDirectory remoteContainerDirectory:(NSURL *)remoteContainerDirectory remoteTemporaryDirectory:(NSURL *)remoteTemporaryDirectory error:(NSError **)outError;
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

    [_documentIndex invalidate];
    _documentIndex = nil;
}

- (BOOL)syncIfChanged:(ODAVFileInfo *)containerFileInfo serverDate:(NSDate *)serverDate connection:(OFXConnection *)connection error:(NSError **)outError;
{
    NSUInteger retries = 0;
    
tryAgain:
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    OBPRECONDITION(containerFileInfo);
    OBPRECONDITION(serverDate);
    OBPRECONDITION(connection);
    OBPRECONDITION([NSThread isMainThread] == NO); // We operate on a background queue managed by our agent

    // Our locally stored snapshots were scanned while starting up.
    NSURL *remoteContainerDirectory = self.remoteContainerDirectory;

    // Since the timestamp resolution on the server is limited, to avoid a race between an reader and writer, we have to sync this container if it has been modified at the same time or more recently than the last server time we did a full sync. Since the server time should move forward, our timestamp will step forward on each try (and so as long as the writer stops poking the container, we'll stop doing extra PROPFINDs).
    // If we have an unknown remote edit, go ahead and make sure we clear that.
    if (_lastSyncedServerDate && [containerFileInfo.lastModifiedDate isBeforeDate:_lastSyncedServerDate] && !_hasUnknownRemoteEdit) {
        DEBUG_SYNC(1, @"Container has last server date of %@ and container modified on %@. Skipping", _lastSyncedServerDate, containerFileInfo.lastModifiedDate);
        return YES; // Nothing to do
    }
    
    DEBUG_SYNC(1, @"Fetching document list from container %@", remoteContainerDirectory);
    
    // Ensure we create the container directory so that other clients will know that this path extension signifies a wrapper file type (rather than waiting for a file of this type to be uploaded).
    // TODO: If we have local snapshots, but the remote directory has been deleted, should we interpret that the same as the individual files being deleted? Or should we treat it as some sort of error/reset and instead upload all our documents? If two clients are out in the world, the second client will treat missing server documents as deletes for local documents. For now, treating removal of the container as removal of all the files w/in it.
    __autoreleasing NSError *error;
    NSArray *fileInfos = OFXFetchDocumentFileInfos(connection, remoteContainerDirectory, nil/*identifier*/, &error);
    if (!fileInfos) {
        if (outError)
            *outError = error;
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
        
        [self _enumerateDocumentFileInfos:fileInfos with:^(NSString *fileIdentifier, NSUInteger fileVersion, ODAVFileInfo *fileInfo){
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
            } else
                [_documentIndex forgetFileItemForRemoteDeletion:missingFileItem];
        }
    }
    
    
    __block BOOL tryAgain = NO;
    __block BOOL needsDownload = NO;
    [self _enumerateDocumentFileInfos:fileInfos with:^(NSString *fileIdentifier, NSUInteger fileVersion, ODAVFileInfo *fileInfo){
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
    
    if (needsDownload) {
        [_weak_accountAgent containerNeedsFileTransfer:self];
    }
    
    if (!tryAgain) {
        _lastSyncedServerDate = serverDate;
    }
    
    [self _updatePublishedFileVersions];
    
    OBPOSTCONDITION([self _checkInvariants]); // checks the queue too

    if (tryAgain) {
        // Nesting this call was causing infinite recursion and crash in RT 900574. Let's give up on trying to get the document altogether after an absurd number (e.g. 100) of retries
        //return [self syncIfChanged:containerFileInfo serverDate:serverDate remoteFileManager:remoteFileManager error:outError];
        retries++;
        goto tryAgain;
    } else {
        // This is definitely ideal, since we don't have complete information here (but we can't, really). If there are downloads going on, they might fix whatever name conflicts we have. But, if there is a large/slow download going on, we don't want to wait for it (and there might be more queued up after that...).
        // TODO: We could wait for a small amount of time here after detecting there is a problem before trying to resolve it. But we might also want to wait longer if there are multiple Bonjour clients on the network and we have reason to believe another might solve the problem (for example, iOS clients might want to defer to Mac clients by waiting a bit longer).
        // For now, we just won't wait.
        [self _resolveNameConflicts];
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
    
    [_documentIndex enumerateFileItems:^(NSString *identifier, OFXFileItem *fileItem) {
        DEBUG_TRANSFER(2, @"Checking document %@ %@.", identifier, fileItem.localDocumentURL);
        
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
        if (remoteState.edited || remoteState.moved) {
            OBASSERT(remoteState.moved == NO, "We don't actually know about remote renames until we download the snapshot");
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
        if (localState.edited || localState.moved) {
            DEBUG_TRANSFER(2, @"  Locally edited more moved, queuing upload.");
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
        
        OBASSERT_NOT_REACHED("Unhandled file state");
    }];
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
    OBASSERT(fileItem.remoteState.missing || fileItem.localState.edited || fileItem.localState.moved);

    OFXConnection *connection = [self _makeConnection];
    if (!connection)
        return nil;
    
    DEBUG_SYNC(1, @"Preparing upload of %@", fileItem);
        
    __autoreleasing NSError *error;
    OFXFileSnapshotTransfer *transfer = [fileItem prepareUploadTransferWithConnection:connection error:&error];
    if (!transfer)
        return NO;

    OBASSERT(fileItem.isUploading); // should be set even before the operation starts so that our queue won't start more.
    
    transfer.validateCommit = ^NSError *{
        OBPRECONDITION([self _runningOnAccountAgentQueue]);
        
        // Bail if we've been stopped since starting the transfer or if the file has been locally deleted
        if (!_started || fileItem.hasBeenLocallyDeleted)
            return [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
        
        return nil;
    };
    
    [transfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
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
                __autoreleasing NSError *error;
                NSNumber *same = [fileItem hasSameContentsAsLocalDocumentAtURL:fileItem.localDocumentURL error:&error];
                if (!same) {
                    if ([error causedByMissingFile]) {
                        // Race between uploading and a local deletion. We should have a scan queued now or soon that will set fileItem.hasBeenLocallyDeleted.
                    } else
                        NSLog(@"Error checking for changes in contents for %@: %@", fileItem.localDocumentURL, [error toPropertyList]);
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
                if (hasBeenEdited || fileItem.localState.moved) {
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
    
    return transfer;
}

- (OFXFileSnapshotTransfer *)prepareDownloadTransferForFileItem:(OFXFileItem *)fileItem error:(NSError **)outError;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    if (fileItem.hasBeenLocallyDeleted) {
        // Download requested and then locally deleted before download could start
        OBUserCancelledError(outError);
        return nil;
    }

    if (fileItem.isDownloading) {
        // If this is getting called because we've decided that we want to get the contents, and the current download is just for metadata, our re-download in the 'done' block below will be OK. But, if this is getting called because a sync noticed *another* remote edit while we are still downloading the document, we'd lose the edit. We need to catch this case.
        OBFinishPortingLater("Handle multiple quick remote edits");
        OBUserCancelledError(outError);
        return nil;
    }
    if (fileItem.isUploading) {
        // If we discover a need to download while we are already uploading, the upload should be about to hit a conflict. We'll just ignore the download request here. Once the upload figures out there is a conflict, it will revert us to be a not-downloaded file.
        OBUserCancelledError(outError);
        return nil;
    }
    
    OFXConnection *connection = [self _makeConnection];
    if (!connection)
        return nil;
    
    DEBUG_SYNC(1, @"Preparing download of %@", fileItem);
    
    // We must allow for stacked up download requests in some form. If we start a metadata download (no contents) and then start a download with contents before that is fully finished, we want the contents to actually download. Similarly, if we are downloading contents and another change happens on the server, if we start a metadata download, we don't want to discard the contents we have downloaded (some of them may be good for local copying).
    
    id <NSFilePresenter> filePresenter = _weak_filePresenter;
    
    OFXFileSnapshotTransfer *transfer = [fileItem prepareDownloadTransferWithConnection:connection filePresenter:filePresenter];
    OBASSERT(fileItem.isDownloading); // should be set even before the operation starts so that our queue won't start more.
    
    transfer.validateCommit = ^NSError *{
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
    
    NSString *originalLocalRelativePath = fileItem.localRelativePath;
    [transfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
        OBPRECONDITION([self _runningOnAccountAgentQueue]);
        DEBUG_SYNC(1, @"Finished download of %@ (committed:%d)", fileItem, (errorOrNil == nil));
        
        if (errorOrNil == nil) {
            NSString *updatedLocalRelativePath = fileItem.localRelativePath;
            if (OFNOTEQUAL(originalLocalRelativePath, updatedLocalRelativePath)) {
                // The file moved as part of the download.
                [_documentIndex fileItemMoved:fileItem fromLocalRelativePath:originalLocalRelativePath toLocalRelativePath:updatedLocalRelativePath];
            }
            
            // Check if another download request came in that wanted contents with this download only being for metadata.
            if (fileItem.contentsRequested) {
                OFXFileState *localState = fileItem.localState;
                OFXFileState *remoteState = fileItem.remoteState;
                if (localState.missing || remoteState.edited || remoteState.moved) {
                    OBASSERT(localState.missing || remoteState.edited, "We don't know about remote renames for real. We might have seen a new version on the server before our first download finished, so we might still be in the create state");
                    [_weak_accountAgent containerNeedsFileTransfer:self];
                }
            }
            OBPOSTCONDITION([self _checkInvariants]); // checks the queue too
        } else if ([errorOrNil hasUnderlyingErrorDomain:OFXErrorDomain code:OFXFileDeletedWhileDownloading]) {
            // Start the delete transfer
            [_weak_accountAgent containerNeedsFileTransfer:self];
        }
        
        return nil;
    }];
    
    return transfer;
}

- (OFXFileSnapshotTransfer *)prepareDeleteTransferForFileItem:(OFXFileItem *)fileItem error:(NSError **)outError;
{
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    
    if (fileItem.hasBeenLocallyDeleted == NO) {
        OBFinishPortingLater("Add test case");
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
    
    OFXConnection *connection = [self _makeConnection];
    if (!connection)
        return nil;
    
    DEBUG_SYNC(1, @"Preparing delete of %@", fileItem);
    
    id <NSFilePresenter> filePresenter = _weak_filePresenter;
    OFXFileSnapshotTransfer *transfer = [fileItem prepareDeleteTransferWithConnection:connection filePresenter:filePresenter];
    OBASSERT(fileItem.isDeleting); // should be set even before the operation starts so that our queue won't start more.
    
    transfer.validateCommit = ^NSError *{
        OBPRECONDITION([self _runningOnAccountAgentQueue]);
        OBPRECONDITION(fileItem.hasBeenLocallyDeleted, @"We do not resurrect file items on delete vs. edit conflict."); // Rather, we let the delete commit locally w/o committing remotely and then rescan the server. The edit then appears as a 'new' item and we treat it as such.
        
        // Bail if we've been stopped since starting the transfer
        if (!_started)
            return [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                
        return nil;
    };
    
    [transfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
        OBPRECONDITION([self _runningOnAccountAgentQueue]);
        DEBUG_SYNC(1, @"Finished delete of %@", fileItem);
        
        OBASSERT([_documentIndex hasBegunLocalDeletionOfFileItem:fileItem], @"should have begun local deletion");

        // In the remote-edit vs local-delete conflict, the file item should have gone ahead and removed its snapshot so that on the next sync we can resurrect it as if it was a new file.
        BOOL didRemove = !errorOrNil || [errorOrNil hasUnderlyingErrorDomain:OFXErrorDomain code:OFXFileUpdatedWhileDeleting];
        
        if (didRemove) {
            [_documentIndex completeLocalDeletionOfFileItem:fileItem];
            
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
    
    return transfer;
}

- (OFXFileItem *)publishedFileItemWithURL:(NSURL *)fileURL;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    OBPRECONDITION([[[self class] containerAgentIdentifierForFileURL:fileURL] isEqual:_identifier]);
    
    NSString *relativePath = [self _localRelativePathForFileURL:fileURL];
    return [_documentIndex publishedFileItemWithLocalRelativePath:relativePath];
}

// Probe used by OFXAccountAgent to determine if a rename is a directory rename.
- (void)addFileItems:(NSMutableArray *)fileItems inDirectoryWithRelativePath:(NSString *)localDirectoryRelativePath;
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

- (BOOL)finishedScan:(OFXContainerScan *)scan error:(NSError **)outError;
{
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    
    // TODO: Test exchange of two files/directories? There is nothing with NSFileCoordination to support this, but we could observe an uncoordinated exchangedata/FSExchangeObjects. Probably OK to do something a little unexpected in this case...
    
    OBPRECONDITION(OFISEQUAL(scan.documentIndexState, [_documentIndex copyIndexState]), @"No file item registration changes should have happened between the scan starting and finishing");
    NSMutableArray *newFileURLs = [NSMutableArray new];
    NSMutableDictionary *remainingLocalRelativePathToPublishedFileItem = [_documentIndex copyLocalRelativePathToPublishedFileItem];
    
    DEBUG_SCAN(1, @"Finished scan with URLs %@", scan.scannedFileURLs);

    for (NSURL *fileURL in scan.scannedFileURLs) {
        OBASSERT([[[self class] containerAgentIdentifierForFileURL:fileURL] isEqual:_identifier]);

        // Most likely this is an existing file, possibly modified. We don't try to handle the case of exchangedata/FSExchangeObjects. So, if we have urlA and urlB and whose contents get swapped, we'll treat this as content updates to both rather than swapping moves.
        NSString *localRelativePath = [self _localRelativePathForFileURL:fileURL];
        OFXFileItem *fileItem = [_documentIndex publishedFileItemWithLocalRelativePath:localRelativePath];
        if (fileItem) {
            OBASSERT(remainingLocalRelativePathToPublishedFileItem[localRelativePath] == fileItem);
            [remainingLocalRelativePathToPublishedFileItem removeObjectForKey:localRelativePath];
             
            // Don't try to upload if this is a new stub, new uploading document, or previously edited document that is still uploading.
            // We might also be in the middle of downloading and shouldn't start an upload. In this case, we may have been notified of a remote edit and have locally saved in the mean time (most commonly in test cases that are intentionally racing). In this case, when the download completes, the commit validation in the download transfer operation will notice a conflict.
            if (!fileItem.remoteState.missing && fileItem.isValidToUpload && !fileItem.isUploading && !fileItem.isDownloading) {
                __autoreleasing NSError *error;
                NSNumber *same = [fileItem hasSameContentsAsLocalDocumentAtURL:fileURL error:&error];
                if (!same) {
                    NSLog(@"Error checking for changes in contents for %@: %@", fileURL, [error toPropertyList]);
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
    
    if ([newFileURLs count] > 0 && [remainingLocalRelativePathToPublishedFileItem count] > 0) {
        DEBUG_SCAN(1, @"Attempt to infer moves based on new URLs %@ and old relative paths %@", newFileURLs, remainingLocalRelativePathToPublishedFileItem);
        
        // Possibly have some uncoordinated moves or moves that NSFileCoordinator didn't tell us about. Try to match up by inode and then a has-same-contents check.
        [self _handlePossibleMovesOfFileURLs:newFileURLs remainingLocalRelativePathToPublishedFileItem:remainingLocalRelativePathToPublishedFileItem];
    }
    
    for (NSURL *fileURL in newFileURLs) {
        // New document!
        DEBUG_SCAN(1, @"Register document for new URL %@", fileURL);
        [self _handleNewLocalDocument:fileURL];
    }
    
    __block BOOL success = YES;
    __block NSError *error;
    
    [remainingLocalRelativePathToPublishedFileItem enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, OFXFileItem *fileItem, BOOL *stop) {
        if (fileItem.localState.missing || fileItem.localState.deleted) {
            OBASSERT_NOT_REACHED("We should only get published file items (downloaded and not locally deleted), but got %@", fileItem); // Check at runtime even though this should never happen so we don't treat a missing file as a delete.
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
    
    OBPOSTCONDITION([self _checkInvariants]); // checks the queue too
    return success;
}

- (BOOL)fileItemDeleted:(OFXFileItem *)fileItem error:(NSError **)outError;
{
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    OBPRECONDITION(fileItem);
    OBPRECONDITION(fileItem.localState.missing || [_documentIndex publishedFileItemWithLocalRelativePath:fileItem.localRelativePath] == fileItem);
    
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
    OBASSERT(OFNOTEQUAL(oldRelativePath, newRelativePath));
    
    OBASSERT(fileItem.localState.missing || OFURLIsStandardizedOrMissing(newURL)); // standardizing non-existent URLS doesn't work so don't check if we are renaming something that isn't downloaded. It might have also been moved and then quickly moved again or deleted before we could process the rename.

    // If this is coming from the server, don't call back to the item (it will update itself) or provoke an upload of the move.
    if (byUser) {
        [fileItem didMoveToURL:newURL];
    }
    
    [_documentIndex fileItemMoved:fileItem fromLocalRelativePath:oldRelativePath toLocalRelativePath:newRelativePath];
    
    if (byUser) {
        OFXAccountAgent *accountAgent = _weak_accountAgent;
        OBASSERT(accountAgent);
        [accountAgent containerNeedsFileTransfer:self];
    }
    
    OBPOSTCONDITION([self _checkInvariants]);
}

- (void)_operateOnFileAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler withAction:(void (^)(OFXFileItem *))fileAction;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    NSString *relativePath = [self _localRelativePathForFileURL:fileURL];
    OFXFileItem *fileItem = [_documentIndex publishableFileItemWithLocalRelativePath:relativePath];
    
    if (!fileItem) {
        __autoreleasing NSError *error;
        OFXError(&error, OFXNoFileForURL, @"No file has the specified URL.", nil);
        if (completionHandler)
            completionHandler(error);
        return;
    }
    
    fileAction(fileItem);
}

- (void)downloadFileAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    completionHandler = [completionHandler copy];
    [self _operateOnFileAtURL:fileURL completionHandler:completionHandler withAction:^(OFXFileItem *fileItem){
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
    [self _operateOnFileAtURL:fileURL completionHandler:completionHandler withAction:^(OFXFileItem *fileItem){
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

- (BOOL)_moveFileItem:(OFXFileItem *)fileItem fromURL:(NSURL *)originalFileURL toURL:(NSURL *)updatedFileURL byUser:(BOOL)byUser error:(NSError **)outError;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    OBASSERT(OFISEQUAL(originalFileURL, fileItem.localDocumentURL));
    
    if (fileItem.localState.missing) {
        OBASSERT(OFURLContainsURL(_account.localDocumentsURL, updatedFileURL), "Attempting to move the file out of our domain?");
        
        // No local file to move; just tweak the metadata.
        TRACE_SIGNAL(OFXContainerAgent.move_item.metadata);
        [self fileItemMoved:fileItem fromURL:originalFileURL toURL:updatedFileURL byUser:byUser];
        return YES;
    } else {
        // NOTE: Case-only renames are busticated for file presenter notifications (see screed in -[NSFileCoordinator(OFExtensions) moveItemAtURL:toURL:createIntermediateDirectories:error:]). So, we have to pass a file presenter to the coordinator and will notify ourselves about the rename, at least for that one presenter). If there are multiple presenters, some of them are screwed.
        id <NSFilePresenter> filePresenter = _weak_filePresenter;
        OBASSERT(filePresenter);
        
        TRACE_SIGNAL(OFXContainerAgent.move_item.file_coordination);
        
        __autoreleasing NSError *moveError;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:filePresenter];
        if (![coordinator moveItemAtURL:originalFileURL toURL:updatedFileURL createIntermediateDirectories:YES error:&moveError]) {
            // Maybe hit in http://rt.omnigroup.com/Ticket/Display.html?id=886781 and http://rt.omnigroup.com/Ticket/Display.html?id=886777
            // Definitely hit in http://rt.omnigroup.com/Ticket/Attachment/14329504/8130862/
            // Presumably we've downloaded conflict resolution done on another machine, but there have been multiple conflicts or conflicting resolutions. Punt instead of OBFinishPorting, and we'll hopefully retry on the next sync when we have more info.
            [moveError log:@"Error moving %@ to %@", originalFileURL, updatedFileURL];
            if (outError)
                *outError = moveError;
            return NO;
        } else {
            OFXNoteContentMoved(self, originalFileURL, updatedFileURL);
            [self fileItemMoved:fileItem fromURL:originalFileURL toURL:updatedFileURL byUser:YES];
            return  YES;
        }
    }
}

- (void)moveItemAtURL:(NSURL *)originalFileURL toURL:(NSURL *)updatedFileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    completionHandler = [completionHandler copy];
    [self _operateOnFileAtURL:originalFileURL completionHandler:completionHandler withAction:^(OFXFileItem *fileItem){
        __autoreleasing NSError *moveError;
        if (![self _moveFileItem:fileItem fromURL:originalFileURL toURL:updatedFileURL byUser:YES error:&moveError])
            completionHandler(moveError);
        else
            completionHandler(nil);
    }];
}

- (void)newlyUnshadowedFileItemRequestsContents:(OFXFileItem *)fileItem;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    [_weak_accountAgent containerNeedsFileTransfer:self];
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
    NSURL *localDocumentsURL = _account.localDocumentsURL;
    OBASSERT(OFURLContainsURL(localDocumentsURL, fileURL));
    
    return OFFileURLRelativePath(localDocumentsURL, fileURL);
}

- (NSURL *)_URLForLocalRelativePath:(NSString *)relativePath isDirectory:(BOOL)isDirectory;
{
    return [_account.localDocumentsURL URLByAppendingPathComponent:relativePath isDirectory:isDirectory];
}

- (void)_fileItemDidGenerateConflict:(OFXFileItem *)fileItem;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    
    OFXAccountAgent *accountAgent = _weak_accountAgent;
    if (!accountAgent)
        return;
    
    [accountAgent _fileItemDidGenerateConflict:fileItem];
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
    
    NSURL *conflictURL = [fileItem fileURLForConflictVersion]; // This file item has the same URL as otherItem, if any, so it can generate a conflict URL.
    OBASSERT(conflictURL);
    DEBUG_CONFLICT(1, @"Making way for incoming document by moving published document aside to %@", conflictURL);

    OFXFileItem *otherItem = [self publishedFileItemWithURL:fileURL];
    OBASSERT(otherItem != fileItem);
    if (otherItem && otherItem != fileItem) {        
        // Use our API so the otherItem's URL is updated.
        __autoreleasing NSError *conflictError;
        if ([self _moveFileItem:otherItem fromURL:otherItem.localDocumentURL toURL:conflictURL byUser:YES error:&conflictError])
            return YES;
        if (outError)
            *outError = conflictError;
        OBChainError(outError);
        return NO;
    }
    
    if (!otherItem) {
        // The thing in our way appeared very recently (possibly as a result of our provoking autosave, as in -[OFXConflictTestCase testIncomingMoveVsLocalAutosaveCreation]).
        // The coordinator should have a file presenter so that this move is not interpreted as moving *us*, but sadly we have no way of asserting that here.
        __autoreleasing NSError *moveError = nil;
        if ([coordinator moveItemAtURL:fileURL toURL:conflictURL createIntermediateDirectories:NO/*sibling*/ error:&moveError])
            return YES;
        
        if (outError)
            *outError = moveError;
        OBChainError(outError);
        return NO;
    }
    
    OBASSERT_NOT_REACHED("Should have hit one of the cases above");
    return YES; // Caller will try its move again and will fail again.
}

- (NSString *)debugName;
{
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
    
    DEBUG_SYNC(1, @"Performing Snapshots scan");
    
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
            OBFinishPortingLater("Should we just remove the local snapshot in this case and redownload/upload?");
            continue;
        }
        OBASSERT(OFISEQUAL([localSnapshotURL lastPathComponent], fileItem.identifier));

        [_documentIndex registerScannedLocalFileItem:fileItem];
    }
    
    DEBUG_SYNC(2, @"_documentIndex = %@", [_documentIndex debugDictionary]);
    
    [self _updatePublishedFileVersions];
    OBPOSTCONDITION([self _checkInvariants]);
}


- (void)_handlePossibleMovesOfFileURLs:(NSMutableArray *)newFileURLs remainingLocalRelativePathToPublishedFileItem:(NSMutableDictionary *)remainingLocalRelativePathToPublishedFileItem;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);
    OBPRECONDITION([newFileURLs count] > 0);
    OBPRECONDITION([remainingLocalRelativePathToPublishedFileItem count] > 0);
    
    // We assume everything we are operating on is w/in our directory is on one filesystem (the one for our account's local documents directory).
    
    DEBUG_SYNC(2, @"Checking for possible renames");
    DEBUG_SYNC(2, @"  newFileURLs = %@", newFileURLs);
    DEBUG_SYNC(2, @"  remainingLocalRelativePathToPublishedFileItem = %@", remainingLocalRelativePathToPublishedFileItem);
    
    NSMutableDictionary *inodeToFileURL = [NSMutableDictionary new];
    for (NSURL *fileURL in newFileURLs) {
        __autoreleasing NSError *error;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:&error];
        NSNumber *inode = attributes[NSFileSystemFileNumber];
        if (!inode) {
            NSLog(@"Error getting inode for URL %@: %@", fileURL, [error toPropertyList]);
            continue;
        }
        inodeToFileURL[inode] = fileURL;
    }
    DEBUG_SYNC(3, @"inodeToFileURL = %@", inodeToFileURL);

    // Can't mutate the original, so copy first... kinda ugly.
    [[remainingLocalRelativePathToPublishedFileItem copy] enumerateKeysAndObjectsUsingBlock:^(NSString *localRelativePath, OFXFileItem *fileItem, BOOL *stop) {
        NSNumber *inode = fileItem.inode;
        NSURL *fileURL = inodeToFileURL[inode];
        if (fileURL == nil)
            return;
        
        __autoreleasing NSError *error;
        NSNumber *same = [fileItem hasSameContentsAsLocalDocumentAtURL:fileURL error:&error];
        if (!same) {
            NSLog(@"Error checking if file item %@ has same contents as %@: %@", [fileItem shortDescription], fileURL, [error toPropertyList]);
            return;
        }
        if ([same boolValue]) {
            // Uncoordinated/unreported rename. Mark this pair as handled!
            DEBUG_SYNC(2, @"Found that %@ was renamed to %@", fileItem.localDocumentURL, fileURL);

            OBASSERT(remainingLocalRelativePathToPublishedFileItem[fileItem.localRelativePath] != nil);
            [remainingLocalRelativePathToPublishedFileItem removeObjectForKey:fileItem.localRelativePath];
            [newFileURLs removeObject:fileURL];
            
            // And do the rename itself
            [self fileItemMoved:fileItem fromURL:fileItem.localDocumentURL toURL:fileURL byUser:YES];
        }
    }];
    
}

- (OFXFileItem *)_handleNewLocalDocument:(NSURL *)fileURL;
{
    OBPRECONDITION([self _checkInvariants]); // checks the queue too
    OBPRECONDITION(_documentIndex);
    
    DEBUG_SYNC(1, @"Making snapshot for new local document %@", fileURL);

    __autoreleasing NSError *error = nil;
    OFXFileItem *fileItem = [[OFXFileItem alloc] initWithNewLocalDocumentURL:fileURL container:self error:&error];
    if (!fileItem) {
        NSLog(@"Error creating file item from newly discovered docuemnt at %@: %@", fileURL, [error toPropertyList]);
        return nil;
    }

    [_documentIndex registerLocallyAppearingFileItem:fileItem];
    
    OBPOSTCONDITION([self _checkInvariants]);

    return fileItem;
}

- (OFXConnection *)_makeConnection;
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
    
    NSMutableArray *fileVersions = [NSMutableArray new];
    
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

- (void)_enumerateDocumentFileInfos:(id <NSFastEnumeration>)fileInfos with:(void (^)(NSString *fileIdentifier, NSUInteger fileVersion, ODAVFileInfo *fileInfo))applier;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    NSMutableDictionary *fileIdentifierToLatestFileInfo = [NSMutableDictionary new];
    
    
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
        BOOL newer = YES;
        
        if (otherFileInfo) {
            OBFinishPortingLater("Add superseded items to an array to remove");

            // This should be fairly rare, so we just re-parse the version
            NSUInteger otherVersion;
            if (!OFXFileItemIdentifierFromRemoteSnapshotURL(otherFileInfo.originalURL, &otherVersion, NULL)) {
                OBASSERT_NOT_REACHED("We just parsed this!");
            } else if (version < otherVersion)
                newer = NO;
            else
                OBASSERT(version > otherVersion, "Versions should not be equal");
        }
        
        if (newer)
            fileIdentifierToLatestFileInfo[identifier] = fileInfo;
        else
            OBFinishPortingLater("Add superseded items to an array to remove");
    }
    
    [fileIdentifierToLatestFileInfo enumerateKeysAndObjectsUsingBlock:^(NSString *existingIdentifier, ODAVFileInfo *fileInfo, BOOL *stop) {
        NSUInteger version;
        NSString *identifier = OFXFileItemIdentifierFromRemoteSnapshotURL(fileInfo.originalURL, &version, NULL);
        OBASSERT([identifier isEqual:existingIdentifier]); OB_UNUSED_VALUE(identifier);
        
        applier(existingIdentifier, version, fileInfo);
    }];
}

- (void)_resolveNameConflicts;
{
    OBPRECONDITION([self _runningOnAccountAgentQueue]);

    NSDictionary *losingFileItemsByWinner = [_documentIndex copyRenameConflictLoserFileItemsByWinningFileItem];
    if ([losingFileItemsByWinner count] == 0)
        return;
    
    [losingFileItemsByWinner enumerateKeysAndObjectsUsingBlock:^(OFXFileItem *winningFileItem, NSArray *losingFileItems, BOOL *stop) {
        DEBUG_CONFLICT(1, @"Resolving name conflicts for %@ -> %@", [winningFileItem shortDescription], [losingFileItems arrayByPerformingBlock:^(OFXFileItem *losingFileItem){
            return [losingFileItem shortDescription];
        }]);
        DEBUG_CONTENT(1, @"Name conflict winner %@ has content %@", [winningFileItem shortDescription], OFXLookupDisplayNameForContentIdentifier(winningFileItem.currentContentIdentifier));
        
        for (OFXFileItem *fileItem in losingFileItems) {
            DEBUG_CONTENT(1, @"Name conflict loser %@ has content %@", [fileItem shortDescription], OFXLookupDisplayNameForContentIdentifier(fileItem.currentContentIdentifier));

            NSURL *conflictURL = [fileItem fileURLForConflictVersion];
            
            // Can't use the URL-based -moveItemAtURL:toURL:completionHandler: since the losing file item might be shadowed.
            DEBUG_CONFLICT(1, @"  ... moving %@ to %@", [fileItem shortDescription], conflictURL);
            __autoreleasing NSError *moveError;
            if (![self _moveFileItem:fileItem fromURL:fileItem.localDocumentURL toURL:conflictURL byUser:YES error:&moveError])
                [moveError log:@"Error moving name conflict loser to %@", conflictURL];
        }
    }];
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
