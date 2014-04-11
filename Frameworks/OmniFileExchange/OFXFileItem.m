// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileItem-Internal.h"

#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFileExchange/OFXRegistrationTable.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/OFFilePresenterEdits.h>
#import <OmniFoundation/OFXMLIdentifier.h>

#import "OFXConnection.h"
#import "OFXContainerAgent-Internal.h"
#import "OFXContentIdentifier.h"
#import "OFXDAVUtilities.h"
#import "OFXDownloadFileSnapshot.h"
#import "OFXFileMetadata-Internal.h"
#import "OFXFileSnapshot.h"
#import "OFXFileSnapshotDeleteTransfer.h"
#import "OFXFileSnapshotDownloadTransfer.h"
#import "OFXFileSnapshotRemoteEncoding.h"
#import "OFXFileSnapshotUploadContentsTransfer.h"
#import "OFXFileSnapshotUploadRenameTransfer.h"
#import "OFXUploadContentsFileSnapshot.h"

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIDevice.h>
#import <OmniDocumentStore/ODSScope.h>
#endif

RCS_ID("$Id$")

@interface OFXFileItem ()
#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
#endif
@end

static const NSUInteger OFXFileItemUnknownVersion = NSUIntegerMax;

@implementation OFXFileItem
{
    OFXRegistrationTable *_metadataRegistrationTable;
    OFXFileSnapshot *_snapshot;
    OFXFileSnapshotTransfer *_currentTransfer;

    // If we get a 404, record the version here and refuse to try to fetch that version again until the next scan tells us what our new version is. Set to OFXFileItemUnknownVersion if we know of no missing version.
    NSUInteger _newestMissingVersion;
    
    // During a remote scan, our container will tell us our latest version number. Set to OFXFileItemUnknownVersion if we don't know of any newer version than _snapshot.version
    NSUInteger _newestRemoteVersion;
}

static NSURL *_makeLocalSnapshotURL(OFXContainerAgent *containerAgent, NSString *identifier)
{
    OBPRECONDITION(containerAgent);
    OBPRECONDITION(![NSString isEmptyString:identifier]);
    
    return [containerAgent.localSnapshotsDirectory URLByAppendingPathComponent:identifier isDirectory:YES];
}

#ifdef OMNI_ASSERTIONS_ON
static BOOL _stringIsWebDAVSafe(NSString *string)
{
    // Take a conservative approach to safety since so many WebDAV servers have problems with double-quoting, and quoting at all.
    if (OFNOTEQUAL(string, [string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]))
        return NO;
    if ([string rangeOfCharactersNotRepresentableInCFEncoding:kCFStringEncodingASCII].length > 0)
        return NO;
    
    // Some servers hate '+' characters, thinking that they are search field separators that mean ' '.
    
    return YES;
}
#endif

#ifdef OMNI_ASSERTIONS_ON
static BOOL _isValidIdentifier(NSString *identifier)
{
    OBASSERT(![NSString isEmptyString:identifier]);
    OBASSERT([identifier containsString:OFXRemoteFileIdentifierToVersionSeparator] == NO, @"Should not contain our separator");
    OBASSERT([[identifier stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] isEqual:identifier], @"Should not require URL encoding");
    return YES;
}
#endif

NSString *OFXFileItemIdentifierFromRemoteSnapshotURL(NSURL *remoteSnapshotURL, NSUInteger *outVersion, NSError **outError)
{
    static dispatch_once_t onceToken;
    static NSCharacterSet *NonDigitSet;
    dispatch_once(&onceToken, ^{
        // +decimalDigitCharacterSet includes things other than ASCII 0..9 (Indic, Arabic digits).
        // <bug:///87630> (Try to make %lu format integers as Indic, Arabic or other non 0..9 formats)
        NonDigitSet = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    });
    
    NSArray *components = [remoteSnapshotURL.lastPathComponent componentsSeparatedByString:OFXRemoteFileIdentifierToVersionSeparator];
    if ([components count] != 2) {
        OFXError(outError, OFXSnapshotCorrupt, ([NSString stringWithFormat:@"Document URL has a last path component of \"%@\" which does not match the format \"id"OFXRemoteFileIdentifierToVersionSeparator"version\".", remoteSnapshotURL.lastPathComponent]), nil);
        return nil;
    }
    NSString *fileIdentifier = components[0];
    
    NSString *versionString = components[1];
    if ([versionString rangeOfCharacterFromSet:NonDigitSet].length > 0) {
        OFXError(outError, OFXSnapshotCorrupt, ([NSString stringWithFormat:@"Document URL has a last path component of \"%@\" which does not have a valid version number.", remoteSnapshotURL.lastPathComponent]), nil);
        return NO;
    }
    
    if (outVersion)
        *outVersion = [versionString unsignedLongValue];
    
    return fileIdentifier;
}


NSArray *OFXFetchDocumentFileInfos(OFXConnection *connection, NSURL *containerURL, NSString *identifier, NSError **outError)
{
    __autoreleasing NSError *error;
    NSArray *fileInfos = OFXFetchFileInfosEnsuringDirectoryExists(connection, containerURL, NULL/*outServerDate*/, &error);
    if (!fileInfos) {
        if (outError)
            *outError = error;
        OBChainError(outError);
        return NO;
    }
    
    // Don't require full parsing of the id~version.
    NSString *identifierPrefix;
    if (identifier) {
        identifierPrefix = [NSString stringWithFormat:@"%@" OFXRemoteFileIdentifierToVersionSeparator, identifier];
    }
    
    // Winnow down our list to what we expect to find
    fileInfos = [fileInfos select:^BOOL(ODAVFileInfo *fileInfo) {
        if (!fileInfo.isDirectory)
            return NO;
        
        NSURL *remoteURL = fileInfo.originalURL;
        if (![NSString isEmptyString:[remoteURL pathExtension]])
            return NO;
        
        if (identifierPrefix && ![[remoteURL lastPathComponent] hasPrefix:identifierPrefix])
            return NO;
        
        return YES;
    }];
    
    return fileInfos;
}

NSComparisonResult OFXCompareFileInfoByVersion(ODAVFileInfo *fileInfo1, ODAVFileInfo *fileInfo2)
{
    __autoreleasing NSError *error;
    
    NSUInteger version1;
    NSString *identifier1 = OFXFileItemIdentifierFromRemoteSnapshotURL(fileInfo1.originalURL, &version1, &error);
    OBASSERT_NOTNULL(identifier1);
    
    NSUInteger version2;
    NSString *identifier2 = OFXFileItemIdentifierFromRemoteSnapshotURL(fileInfo2.originalURL, &version2, &error);
    OBASSERT_NOTNULL(identifier2);

    OBASSERT([identifier1 isEqual:identifier2]);
    
    if (version1 < version2)
        return NSOrderedAscending;
    if (version1 > version2)
        return NSOrderedDescending;
    
    OBASSERT_NOT_REACHED("Should have unique versions");
    return NSOrderedSame;
}

static NSString *_makeRemoteSnapshotDirectoryNameWithVersion(OFXFileItem *fileItem, NSUInteger fileVersion)
{
    OBPRECONDITION(fileItem);
    
    NSString *fileIdentifier = fileItem.identifier;
    
    OBASSERT(_isValidIdentifier(fileIdentifier));

    // <bug:///87630> (Try to make %lu format integers as Indic, Arabic or other non 0..9 formats)
    NSString *directoryName = [NSString stringWithFormat:@"%@" OFXRemoteFileIdentifierToVersionSeparator @"%lu", fileIdentifier, fileVersion];
    OBASSERT(_stringIsWebDAVSafe(directoryName));
    
    return directoryName;
}

static NSString *_makeRemoteSnapshotDirectoryName(OFXFileItem *fileItem, OFXFileSnapshot *snapshot)
{
    OBPRECONDITION(fileItem);
    OBPRECONDITION(snapshot);
    
    if (snapshot.remoteState.missing) {
        // Not yet uploaded, so we have no remote snapshot at all
        return nil;
    }
    return _makeRemoteSnapshotDirectoryNameWithVersion(fileItem, snapshot.version);
}

static NSURL *_makeRemoteSnapshotURLWithVersion(OFXContainerAgent *containerAgent, OFXFileItem *fileItem, NSUInteger fileVersion)
{
    OBPRECONDITION(containerAgent);
    OBPRECONDITION(fileVersion != OFXFileItemUnknownVersion);
    
    NSString *directoryName = _makeRemoteSnapshotDirectoryNameWithVersion(fileItem, fileVersion);
    
    return [containerAgent.remoteContainerDirectory URLByAppendingPathComponent:directoryName isDirectory:YES];
}

static NSURL *_makeRemoteSnapshotURL(OFXContainerAgent *containerAgent, OFXFileItem *fileItem, OFXFileSnapshot *snapshot)
{
    OBPRECONDITION(containerAgent);

    NSString *directoryName = _makeRemoteSnapshotDirectoryName(fileItem, snapshot);
    if (!directoryName)
        return nil;
    
    return [containerAgent.remoteContainerDirectory URLByAppendingPathComponent:directoryName isDirectory:YES];
}

- _initWithIdentifier:(NSString *)identifier snapshot:(OFXFileSnapshot *)snapshot localDocumentURL:(NSURL *)localDocumentURL  container:(OFXContainerAgent *)container error:(NSError **)outError;
{
    OBPRECONDITION(![NSString isEmptyString:identifier]);
    OBPRECONDITION([identifier containsString:OFXRemoteFileIdentifierToVersionSeparator] == NO, @"Should split out the file identifier");
    OBPRECONDITION(snapshot);
    OBPRECONDITION(snapshot.localSnapshotURL);
    OBPRECONDITION(([snapshot.localSnapshotURL checkResourceIsReachableAndReturnError:NULL]));
    OBPRECONDITION(localDocumentURL);
    OBPRECONDITION([[snapshot.localSnapshotURL lastPathComponent] isEqual:identifier]);
    OBPRECONDITION(container);
        
    // Locally deleted files should be missing ... but we can't assert this since the document might have been removed while we weren't running
    // OBPRECONDITION(snapshot.localState.deleted ^ [localDocumentURL checkResourceIsReachableAndReturnError:NULL]);
    OBASSERT_IF([localDocumentURL checkResourceIsReachableAndReturnError:NULL], OFURLIsStandardized(localDocumentURL), @"If the URL exists, it should be standardized (otherwise it has been deleted and we are or are about to be marked as deleted");
    
    if (!(self = [super init]))
        return nil;
        
    _weak_container = container;
    
    _metadataRegistrationTable = container.metadataRegistrationTable;
    OBASSERT(_metadataRegistrationTable);

    _identifier = [identifier copy];
    _snapshot = snapshot;
    _newestMissingVersion = OFXFileItemUnknownVersion;
    _newestRemoteVersion = OFXFileItemUnknownVersion;
    
    _localRelativePath = [[container _localRelativePathForFileURL:localDocumentURL] copy];
    OBASSERT([_localRelativePath isEqual:snapshot.localRelativePath]);
    
    // The current URL of the document we represent. This might not yet exist if the download got killed off before we could make the stub.
    _localDocumentURL = [localDocumentURL copy];
    OBASSERT([_localDocumentURL isEqual:[container _URLForLocalRelativePath:snapshot.localRelativePath isDirectory:snapshot.directory]]);

    // Start out with the right content greediness.
    _contentsRequested = container.automaticallyDownloadFileContents;

    DEBUG_SYNC(1, @"starting with snapshot %@", [snapshot shortDescription]);
    
    return self;
}

// Used when the container agent has detected a new local file. The returned instance will have a local snapshot, but nothing will exist on the server.
- (id)initWithNewLocalDocumentURL:(NSURL *)localDocumentURL container:(OFXContainerAgent *)container error:(NSError **)outError;
{
    NSString *identifier = OFXMLCreateID();
    NSURL *localSnapshotURL = _makeLocalSnapshotURL(container, identifier);
    NSString *localRelativePath = [container _localRelativePathForFileURL:localDocumentURL];

    // Immediately create our snapshot so that we can check if further edits should provoke another upload.
    OFXFileSnapshot *snapshot = [[OFXFileSnapshot alloc] initWithTargetLocalSnapshotURL:localSnapshotURL forNewLocalDocumentAtURL:localDocumentURL localRelativePath:localRelativePath error:outError];
    if (!snapshot)
        return nil;
    OBASSERT(snapshot.remoteState.missing);
    
    // Move it from its temporary location to the real location immediately.
    OBASSERT(OFNOTEQUAL(snapshot.localSnapshotURL, localSnapshotURL));
    if (![[NSFileManager defaultManager] moveItemAtURL:snapshot.localSnapshotURL toURL:localSnapshotURL error:outError])
        return nil;
    
    [snapshot didMoveToTargetLocalSnapshotURL:localSnapshotURL];

    if (!(self = [self _initWithIdentifier:identifier snapshot:snapshot localDocumentURL:localDocumentURL container:container error:outError]))
        return nil;
    
    // Publish the starting version of our metadata
    _metadataRegistrationTable[_identifier] = [self _makeMetadata];

    OBPOSTCONDITION([self _checkInvariants]);
    return self;
}

// Used when a new item has appeared in the remote container
- (id)initWithNewRemoteSnapshotAtURL:(NSURL *)remoteSnapshotURL container:(OFXContainerAgent *)container filePresenter:(id <NSFilePresenter>)filePresenter connection:(OFXConnection *)connection error:(NSError **)outError;
{
    // We're going to use file coordination and don't want deadlock
    OBPRECONDITION(![NSThread isMainThread]);
    OBPRECONDITION(remoteSnapshotURL);
    OBPRECONDITION(container);
    OBPRECONDITION(filePresenter);
    OBPRECONDITION(connection);
    

    NSURL *temporaryLocalDirectory = [[NSFileManager defaultManager] temporaryDirectoryForFileSystemContainingURL:container.localSnapshotsDirectory error:outError];
    if (!temporaryLocalDirectory) {
        OBChainError(outError);
        return nil;
    }
    
    NSURL *temporaryLocalSnapshotURL = [temporaryLocalDirectory URLByAppendingPathComponent:OFXMLCreateID() isDirectory:YES];
    
    __autoreleasing NSString *fileIdentifier;
    if (![OFXDownloadFileSnapshot writeSnapshotToTemporaryURL:temporaryLocalSnapshotURL byFetchingMetadataOfRemoteSnapshotAtURL:remoteSnapshotURL fileIdentifier:&fileIdentifier connection:connection error:outError]) {
        OBChainError(outError);
        return nil;
    }

    // Load the snapshot from its temporary location. This has the side effect of validating it (which we want to do before we move it into public view).
    OFXFileSnapshot *snapshot = [[OFXFileSnapshot alloc] initWithExistingLocalSnapshotURL:temporaryLocalSnapshotURL error:outError];
    if (!snapshot) {
        [[NSFileManager defaultManager] removeItemAtURL:temporaryLocalSnapshotURL error:NULL];
        OBChainError(outError);
        return nil;
    }
    OBASSERT(snapshot.localState.missing);

    // Move the snapshot into public view now that it is validated.
    NSURL *localSnapshotURL = _makeLocalSnapshotURL(container, fileIdentifier);
    if (![[NSFileManager defaultManager] moveItemAtURL:temporaryLocalSnapshotURL toURL:localSnapshotURL error:outError]) {
        [[NSFileManager defaultManager] removeItemAtURL:temporaryLocalSnapshotURL error:NULL];
        OBChainError(outError);
        return nil;
    }
    [snapshot didMoveToTargetLocalSnapshotURL:localSnapshotURL];
    
    NSURL *localDocumentURL = [container _URLForLocalRelativePath:snapshot.localRelativePath isDirectory:snapshot.directory];
    OBASSERT([container.identifier isEqualToString:[OFXContainerAgent containerAgentIdentifierForFileURL:localDocumentURL]]);
    
    if (!(self = [self _initWithIdentifier:fileIdentifier snapshot:snapshot localDocumentURL:localDocumentURL container:container error:outError]))
        return nil;
    
    // Publish the starting version of our metadata; further changes will be kicked off by file presenter notifications
    _metadataRegistrationTable[_identifier] = [self _makeMetadata];
    
    OBPOSTCONDITION([self _checkInvariants]);
    return self;
}

- (id)initWithExistingLocalSnapshotURL:(NSURL *)localSnapshotURL container:(OFXContainerAgent *)container filePresenter:(id <NSFilePresenter>) filePresenter error:(NSError **)outError;
{
    OBPRECONDITION(localSnapshotURL);
    OBPRECONDITION([localSnapshotURL checkResourceIsReachableAndReturnError:NULL]);
    OBPRECONDITION(OFURLIsStandardized(localSnapshotURL));
    OBPRECONDITION(container);
    OBPRECONDITION(filePresenter);
    
    OFXFileSnapshot *snapshot = [[OFXFileSnapshot alloc] initWithExistingLocalSnapshotURL:localSnapshotURL error:outError];
    if (!snapshot)
        return nil;
    
    // The current URL of the document we represent. This might not exist if we haven't been downloaded, or if this file item is a deletion note that hasn't been pushed to the server. In fact, in the deletion case, there might be someone living at our old URL already!
    NSURL *localDocumentURL = [container _URLForLocalRelativePath:snapshot.localRelativePath isDirectory:snapshot.directory];
    OBASSERT([container.identifier isEqualToString:[OFXContainerAgent containerAgentIdentifierForFileURL:localDocumentURL]]);

    if (!(self = [self _initWithIdentifier:[localSnapshotURL lastPathComponent] snapshot:snapshot localDocumentURL:localDocumentURL container:container error:outError]))
        return nil;
        
    if (snapshot.localState.deleted == NO) {
        // Publish the starting version of our metadata; further changes will be kicked off by file presenter notifications
        _metadataRegistrationTable[_identifier] = [self _makeMetadata];
    }
    
    OBPOSTCONDITION([self _checkInvariants]);
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(_metadataRegistrationTable == nil); // -invalidate should have been called so we'll remove our item
    OBPRECONDITION(_weak_container == nil);
}

- (void)invalidate;
{
    [_metadataRegistrationTable removeObjectForKey:_identifier];
    _metadataRegistrationTable = nil;
    
    _weak_container = nil;
}

@synthesize container = _weak_container;

- (NSUInteger)version;
{
    OBPRECONDITION(_snapshot);
    
    return _snapshot.version;
}

- (void)setShadowedByOtherFileItem:(BOOL)shadowedByOtherFileItem;
{
    if (_shadowedByOtherFileItem == shadowedByOtherFileItem)
        return;
    
    _shadowedByOtherFileItem = shadowedByOtherFileItem;
    
    // Shadowed items don't own their local document URL, so we better have already been set to not have any contents (moving any local edits aside as a conflict version).
    OBASSERT_IF(_shadowedByOtherFileItem, self.localState.missing || self.localState.deleted);
    
    [self _updatedMetadata];
    
    if (!_shadowedByOtherFileItem && _contentsRequested && self.localState.missing) {
        // We may have rejected download requests before, but now it would be OK.
        OFXContainerAgent *container = _weak_container;
        [container newlyUnshadowedFileItemRequestsContents:self];
    }
}

@synthesize localDocumentURL = _localDocumentURL;
- (NSURL *)localDocumentURL;
{
    OBPRECONDITION(_snapshot.localState.deleted == NO, @"Don't ask for a deleted document's published document URL.");
    
    return _localDocumentURL;
}

@synthesize localRelativePath = _localRelativePath;
- (NSString *)localRelativePath;
{
    OBPRECONDITION(_localRelativePath);
    OBPRECONDITION(_snapshot.localState.deleted == NO, @"Don't ask for a deleted document's local relative path.");
    
    return _localRelativePath;
}

- (NSString *)requestedLocalRelativePath;
{
    OBPRECONDITION(_localRelativePath);
    return _localRelativePath;
}

- (NSDate *)userCreationDate;
{
    OBPRECONDITION(_snapshot);
    
    return _snapshot.userCreationDate;
}

- (NSNumber *)inode;
{
    OBPRECONDITION(_snapshot);
    
    return _snapshot.inode;
}

- (BOOL)hasBeenLocallyDeleted;
{
    OBPRECONDITION(_snapshot);

    return _snapshot.localState.deleted;
}

- (BOOL)isUploading;
{
    return [_currentTransfer isKindOfClass:[OFXFileSnapshotUploadTransfer class]];
}

- (BOOL)isUploadingContents;
{
    return [_currentTransfer isKindOfClass:[OFXFileSnapshotUploadContentsTransfer class]];
}

- (BOOL)isUploadingRename;
{
    return [_currentTransfer isKindOfClass:[OFXFileSnapshotUploadRenameTransfer class]];
}

- (BOOL)isDownloading;
{
    return [_currentTransfer isKindOfClass:[OFXFileSnapshotDownloadTransfer class]];
}

- (BOOL)isDeleting;
{
    return [_currentTransfer isKindOfClass:[OFXFileSnapshotDeleteTransfer class]];
}

- (BOOL)isDownloadingContent;
{
    if (self.isDownloading) {
        OFXFileSnapshotDownloadTransfer *download = (OFXFileSnapshotDownloadTransfer *)_currentTransfer;
        if (download.isContentDownload)
            return YES; // We are actually downloading *contents*, not just metadata.
    }
    return NO;
}

// This can only go to YES from NO so that race conditions between automatically downloading updated metadata during a sync and explicit downloads eventually settle on downloading the full document.
- (void)setContentsRequested;
{
    _contentsRequested = YES;
}

- (OFXFileState *)localState;
{
    OBPRECONDITION(_snapshot);
    return _snapshot.localState;
}

- (OFXFileState *)remoteState;
{
    OBPRECONDITION(_snapshot);
    return _snapshot.remoteState;
}

- (BOOL)markAsLocallyEdited:(NSError **)outError;
{
    OBPRECONDITION(_snapshot);
    
    return [_snapshot markAsLocallyEdited:outError];
}

- (BOOL)markAsRemotelyEditedWithNewestRemoteVersion:(NSUInteger)newestRemoteVersion error:(NSError **)outError;
{
    OBPRECONDITION(_snapshot);
    
    // We don't currently step the _newestRemoteVersion forward when committing an upload. The '>=' protects vs. that, but it would be nice to go ahead and step it forward.
    if (_newestRemoteVersion != OFXFileItemUnknownVersion && _newestRemoteVersion >= newestRemoteVersion)
        return YES; // We already know about this version

    _newestRemoteVersion = newestRemoteVersion;
    
    OFXFileState *remoteState = self.remoteState;
    if (remoteState.edited)
        return YES;

    return [_snapshot markAsRemotelyEdited:outError];
}

- (BOOL)markAsLocallyDeleted:(NSError **)outError;
{
    OBPRECONDITION(_snapshot);
    
    // Stop any upload or download. We can't issue the delete until the transfer is finished (since the delete will back off and wait for any upload/download to figure out what is going on).
    // In the case of a local edit, the user has explicitly said they don't want to preserve it on the server by doing the deletion. In the case of a download, we might be fetching a new version of the document, so there is a conflict. But in this case, the delete will only delete up to the latest known version. We'll remove the local snapshot, do another scan, and the latest version of the file will appear as "new".
    if (_currentTransfer && !_currentTransfer.cancelled) {
        OBASSERT([_currentTransfer isKindOfClass:[OFXFileSnapshotUploadTransfer class]] || [_currentTransfer isKindOfClass:[OFXFileSnapshotDownloadTransfer class]]);
        [_currentTransfer cancelForShutdown:NO];
    }

    // If we were never uploaded, we might end up in local=deleted, remote=missing. That's OK. Our deletion transfer will handle it.
    if (![_snapshot markAsLocallyDeleted:outError])
        return NO;
    
    [self _updatedMetadata];
    
    return YES;
}

- (BOOL)markAsRemotelyDeleted:(NSError **)outError;
{
    OBPRECONDITION(_snapshot);
    return [_snapshot markAsRemotelyDeleted:outError];
}

// We expect that our container will ask us to upload a snapshot after this.
- (void)didMoveToURL:(NSURL *)localDocumentURL;
{
    OBPRECONDITION([localDocumentURL isFileURL]);
    OBPRECONDITION(![localDocumentURL isFileReferenceURL]);
    OBPRECONDITION(OFNOTEQUAL(_localDocumentURL, localDocumentURL));
    OBPRECONDITION(self.localState.missing || OFURLIsStandardizedOrMissing(localDocumentURL)); // Allow for missing URLs since it might get moved again quickly or deleted
    
    OFXContainerAgent *container = _weak_container;
    if (!container) {
        OBASSERT_NOT_REACHED("Move notification not processed before invalidation?");
        return;
    }
    
    _localRelativePath = [[container _localRelativePathForFileURL:localDocumentURL] copy];
    _localDocumentURL = [localDocumentURL copy];
    DEBUG_SYNC(2, @"File item moved, -didMoveToURL: %@ / %@", _localRelativePath, _localDocumentURL);

    // Record the updated relative path in the snapshot's Version.plist so that if the move doesn't happen before we shutdown we can remember it for the next time we have a chance to sync.
    __autoreleasing NSError *error;
    if (![_snapshot markAsLocallyMovedToRelativePath:_localRelativePath error:&error]) {
        // This isn't fatal but could cause data duplication. If we don't push this move to the server before we a quit/restart cycle, our startup scan on the next launch will see a file in a new location (treating it as an add) and see a missing file in the old location (treating it as a delete). If other clients had edits to the file that was deleted, the conflict resolution should resurrect those files.
        NSLog(@"Error marking snapshot for item %@ as being a moved to %@: %@", [self shortDescription], _localRelativePath, [error toPropertyList]);
    }
    
    [self _updatedMetadata];
}

- (NSNumber *)hasSameContentsAsLocalDocumentAtURL:(NSURL *)localDocumentURL error:(NSError **)outError;
{
    OBPRECONDITION([self _checkInvariants]);

    // All our callers want dirty reads. But we might want to take their file presenter. We might also want to change the name of this method to make it clear we are only looking at the current state on disk.
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    
    return [_snapshot hasSameContentsAsLocalDocumentAtURL:localDocumentURL coordinator:coordinator withChanges:NO error:outError];
}

// Snapshots the current state of the local document, uploads it to the server, replaces the previous local snapshot, and updates the {Info,Version}.plist on the receiver.
- (OFXFileSnapshotTransfer *)prepareUploadTransferWithConnection:(OFXConnection *)connection error:(NSError **)outError;
{
    OBPRECONDITION([self _checkInvariants]);
    OBPRECONDITION(_currentTransfer == nil, "Shouldn't start an upload while still doing another transfer");
    OBPRECONDITION(self.hasBeenLocallyDeleted == NO, "Shouldn't try to upload something that is deleted");
    
    OFXContainerAgent *containerAgent = _weak_container;
    if (!containerAgent) {
        OBASSERT_NOT_REACHED("The container should be calling us, so shouldn't have gone away");
        return nil;
    }

    OBASSERT([_snapshot.localSnapshotURL isEqual:_makeLocalSnapshotURL(containerAgent, _identifier)]);

    OFXFileState *localState = _snapshot.localState;
#ifdef OMNI_ASSERTIONS_ON
    OFXFileState *remoteState = _snapshot.remoteState;
#endif
    OBASSERT(remoteState.missing || localState.edited || localState.moved, @"Why are we uploading, otherwise?");

    NSURL *currentRemoteSnapshotURL = _makeRemoteSnapshotURL(containerAgent, self, _snapshot);
    
    DEBUG_CONTENT(1, @"Starting upload with content \"%@\"", OFXLookupDisplayNameForContentIdentifier(_snapshot.currentContentIdentifier));
    
    OFXFileSnapshotUploadTransfer *transfer;
    if (localState.missing && localState.moved)
        // Doing a rename of a file that hasn't been downloaded. In this case, we don't have a local copy of the document to use as the basis for an upload (and there is no chance of its contents having been changed).
        transfer = [[OFXFileSnapshotUploadRenameTransfer alloc] initWithConnection:connection currentSnapshot:_snapshot remoteTemporaryDirectory:containerAgent.remoteTemporaryDirectory currentRemoteSnapshotURL:currentRemoteSnapshotURL error:outError];
    else
        transfer = [[OFXFileSnapshotUploadContentsTransfer alloc] initWithConnection:connection currentSnapshot:_snapshot forUploadingVersionOfDocumentAtURL:_localDocumentURL localRelativePath:_localRelativePath remoteTemporaryDirectory:containerAgent.remoteTemporaryDirectory error:outError];
    if (!transfer)
        return nil;
    transfer.debugName = self.debugName;

    __weak OFXFileSnapshotUploadTransfer *weakTransfer = transfer;
    
    [self _transferStarted:transfer];

    transfer.transferProgress = ^{
        [self _updatedMetadata];
    };
    transfer.commit = ^BOOL(NSError **outError){
#ifdef OMNI_ASSERTIONS_ON
        BOOL movedWhileUploading = NO;
#endif
        
        // Commit the upload remotely and locally.
        {
            OFXFileSnapshotUploadTransfer *strongTransfer = weakTransfer;
            if (!strongTransfer) {
                OBASSERT_NOT_REACHED("Shouldn't be invoked after transfer is deallocated");
                if (outError)
                    *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                return NO;
            }

            OFXFileSnapshot *uploadingSnapshot = strongTransfer.uploadingSnapshot;
            
            // Since the upload has worked as far as the transfer is concerned, this URL is now ours to cleanup if we fail to commit.
            void (^cleanup)(void) = ^{
                NSURL *uploadingSnapshotURL = uploadingSnapshot.localSnapshotURL;
                __autoreleasing NSError *cleanupError;
                if (![[NSFileManager defaultManager] removeItemAtURL:uploadingSnapshotURL error:&cleanupError]) {
                    [cleanupError log:@"Error cleaning up local uploading snapshot %@", uploadingSnapshot];
                }
            };
            
            OBASSERT_IF(_snapshot.remoteState.missing, uploadingSnapshot.version == 0, @"New documents should start at version zero");
            OBASSERT_IF(!_snapshot.remoteState.missing, uploadingSnapshot.version == _snapshot.version + 1, @"Version number should step forward");
            NSURL *targetRemoteSnapshotURL = _makeRemoteSnapshotURL(containerAgent, self, uploadingSnapshot);
            DEBUG_TRANSFER(1, @"Committing upload remotely to content version URL %@", targetRemoteSnapshotURL);

            NSURL *temporaryRemoteSnapshotURL = strongTransfer.temporaryRemoteSnapshotURL; // The operation clears callbacks, so this retain cycle will be broken.
            
            // Move the new remote snapshot version into place. If this fails due to something being there already, there is a conflict.
            __autoreleasing NSError *moveError;
            targetRemoteSnapshotURL = OFXMoveURLToMissingURLCreatingContainerIfNeeded(connection, temporaryRemoteSnapshotURL, targetRemoteSnapshotURL, &moveError);
            if (!targetRemoteSnapshotURL) {
                if ([moveError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED]) {
                    // Another client has already made this version. Conflict (but we'll let the download path deal with it). We could make the conflict document here via _generateConflictDocumentFromLocalContentsAndRevertToLocallyMissingWithCoordinator: if it turns out to be convenient.
                    [containerAgent _fileItemDidDetectUnknownRemoteEdit:self];
                } else {
                    [moveError log:@"Unable to commit remote snapshot"];
                }
                
                // Clean up the file we couldn't publish
                [connection deleteURL:temporaryRemoteSnapshotURL withETag:nil completionHandler:nil];
                cleanup();
                
                if (outError)
                    *outError = moveError;
                OBChainError(outError);
                return NO;
            }
            
            if (currentRemoteSnapshotURL) {
                /*
                 
                 Delete the old version on the server. Don't need to first move it into the tmp directory since even if the delete is only partially successful, the newer version will shadow the old one. We do need to signal conflict if this delete fails, though, since it means that another client has moved the version forward on us (or deleted the file).
                
                 Consider:
                 - client A and B both have version 0
                 - A quickly updates the file to version 1 and then 2, deleting versions 0 and 1.
                 - B updates the file and attempts to write version 1 (succeeds, but it is shadowed now) and removes version 0 (and gets a 404).
                 
                 When deleting shadowed old versions, this also means we need to oldest first, not just in any random order as long as they are shadowed, otherwise, we could have:
                 
                 - A and B at zero
                 - A quickly goes to 3 and for whatever reason, we delete old versions in the order 2, 1, 0
                 - A deletes 1
                 - B tries to write 1 (succeeds)
                 - B deletes zero (succeeds)
                 - A deletes 0 (fails and is confused since B was really the conflicting editor)
                 
                 TODO: Maybe all the above does mean we need to move the old version into tmp before attempting to delete it. Say A fails to delete version 0 on its update of 0->1. Then when it updates 1->2 it will attempt to clean up 0 too. We could race on the deletion such that B's delete succeeds and A's fails. This seems like a pretty unlikely thing to happen, but it bears thinking on. I'm loathe to add an extra MOVE on each file update if we don't really need it.
                 */
                
                __block NSError *deleteError;
                ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done) {
                    [connection deleteURL:currentRemoteSnapshotURL withETag:nil completionHandler:^(NSError *errorOrNil) {
                        deleteError = errorOrNil;
                        done();
                    }];
                });
                if (deleteError) {
                    if ([deleteError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND]) {
                        // If we expected vN to be there and some other client has moved us on to vN+1, we just wrote a shadowed version. Need to generate a conflict. This stale version will get cleaned up on a future scan.
                        [containerAgent _fileItemDidDetectUnknownRemoteEdit:self];
                    } else {
                        [deleteError log:@"Error removing original remote snapshot at %@ while uploading new version. Conflict?", currentRemoteSnapshotURL];
                    }
                    
                    cleanup();

                    if (outError)
                        *outError = deleteError;
                    OBChainError(outError);
                    return NO;
                }
            }
            
            // The uploading snapshot is based on our _snapshot when we started the upload. We might have been moved since then! Make sure we don't clobber this in the new snapshot -- we want to start a new upload if this happens. We already do (later on in the commit) check if the file has changed from this state for an edit upload.
            if (OFNOTEQUAL(_snapshot.localRelativePath, uploadingSnapshot.localRelativePath)) {
#ifdef OMNI_ASSERTIONS_ON
                movedWhileUploading = YES;
#endif
                __autoreleasing NSError *markError;
                if (![uploadingSnapshot markAsLocallyMovedToRelativePath:_snapshot.localRelativePath error:&markError]) {
                    [markError log:@"Error marking uploading snapshot as moved to %@", _snapshot.localRelativePath];
                    cleanup();
                    if (outError)
                        *outError = markError;
                    OBChainError(outError);
                    return NO;
                }
            }
            
            OBASSERT(![_snapshot.localSnapshotURL isEqual:uploadingSnapshot.localSnapshotURL]);
            __autoreleasing NSError *replaceError;
            if (![[NSFileManager defaultManager] replaceItemAtURL:_snapshot.localSnapshotURL withItemAtURL:uploadingSnapshot.localSnapshotURL backupItemName:nil options:0 resultingItemURL:NULL error:&replaceError]) {
                [replaceError log:@"Error replacing %@ with %@", _snapshot.localSnapshotURL, uploadingSnapshot.localSnapshotURL];
                if (outError)
                    *outError = replaceError;
                OBChainError(outError);
                cleanup();
                OBFinishPorting; // Not sure how to provoke this case to test it or what could be happening.
                return NO;
            }
        }
        
        // Reload the snapshot as if it were new. We could maybe migrate the info/version plist from the uploading snapshot, but this seems less gross. Also note that we never tell the uploadingSnapshot -didMoveToTargetLocalSnapshotURL: since it is discarded.
        __autoreleasing NSError *error = nil;
        OFXFileSnapshot *uploadedSnapshot = [[OFXFileSnapshot alloc] initWithExistingLocalSnapshotURL:_snapshot.localSnapshotURL error:&error];
        if (!uploadedSnapshot) {
            NSLog(@"Error reloading uploaded snapshot at %@: %@", _snapshot.localSnapshotURL, [error toPropertyList]);
            return NO;
        }
        
#ifdef OMNI_ASSERTIONS_ON
        if (localState.missing) {
            // Rename of non-downloaded file
            OBASSERT(uploadedSnapshot.localState.missing);
        } else if (movedWhileUploading) {
            OBASSERT(uploadedSnapshot.localState.moved);
            OBASSERT(uploadedSnapshot.remoteState.normal);
        } else {
            // Regular ol' upload.
            OBASSERT(uploadedSnapshot.localState.normal);
            OBASSERT(uploadedSnapshot.remoteState.normal);
        }
#endif
        
        DEBUG_TRANSFER(1, @"switching to uploaded snapshot %@", [uploadedSnapshot shortDescription]);
        DEBUG_TRANSFER(2, @"  previously %@", [_snapshot shortDescription]);
        DEBUG_CONTENT(1, @"Commit upload with content \"%@\"", OFXLookupDisplayNameForContentIdentifier(_snapshot.currentContentIdentifier));
        _snapshot = uploadedSnapshot;
        
        return YES;
    };
    
    [transfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
        OBINVARIANT([self _checkInvariants]);
        
        OBASSERT(self.isUploading);
        [self _transferFinished:transfer];

        // TODO: may want to keep _lastError and also put it into updated metadata
        
        // If the transfer was cancelled due to sync being paused, or the commit failed for some reason, we still need to say we aren't uploading.
        if (errorOrNil) {
            if ([errorOrNil causedByUserCancelling]) {
                // OK...
            } else if ([errorOrNil causedByUnreachableHost]) {
                // Guess we'll try again when the network is reachable
            } else if ([errorOrNil hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED]) {
                // Two client editing and we failed to MOVE the new version into place
                [_weak_container _fileItemDidDetectUnknownRemoteEdit:self];

                __autoreleasing NSError *error = errorOrNil;
                OFXError(&error, OFXFileItemDetectedRemoteEdit, nil, nil);
                errorOrNil = error;
            } else {
                OBFinishPortingLater("Is there more we should do to handle unexpected errors when uploading (e.g. quota exceeded)?"); // Tim, any thoughts? -- Ken
                // tjw: Maybe. We don't want to spam the server with upload requests if they are just going to fail. The -_fileItemDidDetectUnknownRemoteEdit: call is going to sync up in another sync happening immediately. It might work to have a notion of a blocking error where -sync: won't try again until something clears that error (net state changes would clear network errors, timer would clear most, user action would clear all).
            }
        }
        return errorOrNil;
    }];

    return transfer;
}

// Downloads the metadata from the remote snapshot (which is expected to have changed), and possibly the contents. If the contents are downloaded, this will unpack it into the proper structure and update the local published document.
- (OFXFileSnapshotTransfer *)prepareDownloadTransferWithConnection:(OFXConnection *)connection filePresenter:(id <NSFilePresenter>)filePresenter;
{
    OBPRECONDITION([self _checkInvariants]);
    OBPRECONDITION(_snapshot); // should at least have a placeholder
    OBPRECONDITION(_currentTransfer == nil, "Shouldn't start a download while still doing another transfer");
    OBINVARIANT([self _checkInvariants]);
    OBPRECONDITION(_snapshot.localState.missing || _snapshot.remoteState.edited || _snapshot.remoteState.moved);
    OBPRECONDITION(filePresenter);
    
    DEBUG_TRANSFER(1, @"Starting download with _contentsRequested %d, localState %@", _contentsRequested, _snapshot.localState);
    
    OFXContainerAgent *container = _weak_container;
    if (!container) {
        OBASSERT_NOT_REACHED("The container should be calling us, so shouldn't have gone away");
        return nil;
    }
    OBASSERT(container.filePresenter == filePresenter); // Maybe don't need to pass this down...
    
    NSURL *targetLocalSnapshotURL = _makeLocalSnapshotURL(container, _identifier);
    
    NSURL *targetRemoteSnapshotURL;
    if (_newestRemoteVersion != OFXFileItemUnknownVersion) {
        OBASSERT(_newestMissingVersion == OFXFileItemUnknownVersion || _newestMissingVersion < _newestRemoteVersion);
        targetRemoteSnapshotURL = _makeRemoteSnapshotURLWithVersion(container, self, _newestRemoteVersion);
    } else {
        OBASSERT(_newestMissingVersion == OFXFileItemUnknownVersion || _newestMissingVersion < _snapshot.version);
        targetRemoteSnapshotURL = _makeRemoteSnapshotURL(container, self, _snapshot);
    }
    
    OBASSERT([_snapshot.localSnapshotURL isEqual:targetLocalSnapshotURL]);
    OBASSERT(_snapshot.version < _newestRemoteVersion || (_snapshot.localState.missing && _contentsRequested && _snapshot.version == _newestRemoteVersion), "Should be downloading a new snapshot, or the contents for our current version (only if we don't have those contents already");
    
    // Pick a contents download location (meaning we will grab the contents instead of just metadata) if someone asked us to or our previous snapshot had contents. If this document is shadowed by another, don't download contents since we'll just throw them away in the commit.
    NSURL *localTemporaryDocumentContentsURL;
    if ((_contentsRequested || (_snapshot.localState.missing == NO)) && !_shadowedByOtherFileItem) {
        __autoreleasing NSError *error;
        localTemporaryDocumentContentsURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:_localDocumentURL allowOriginalDirectory:NO error:&error];
        if (!localTemporaryDocumentContentsURL) {
            // TODO: Bubble up error
            NSLog(@"Error finding temporary URL for downloading %@: %@", [self shortDescription], [error toPropertyList]);
            return nil;
        }
        DEBUG_TRANSFER(1, @"  will download contents to %@", localTemporaryDocumentContentsURL);
    }

    DEBUG_CONTENT(1, @"Starting download with local content \"%@\"", OFXLookupDisplayNameForContentIdentifier(_snapshot.currentContentIdentifier));
    
    OFXFileSnapshotDownloadTransfer *transfer = [[OFXFileSnapshotDownloadTransfer alloc] initWithConnection:connection remoteSnapshotURL:targetRemoteSnapshotURL localTemporaryDocumentContentsURL:localTemporaryDocumentContentsURL currentSnapshot:_snapshot];
    transfer.debugName = self.debugName;

    __weak OFXFileSnapshotDownloadTransfer *weakTransfer = transfer;

    [self _transferStarted:transfer];
    
    transfer.started = ^{
        OFXFileSnapshotDownloadTransfer *strongTransfer = weakTransfer;
        if (strongTransfer.isContentDownload) {
            // Looks like we do need to report a download in our metadata (_makeMetadata avoids doing so until this is YES).
            [self _updatedMetadata];
        }
    };
    transfer.transferProgress = ^{
        [self _updatedMetadata];
    };
    transfer.commit = ^BOOL(NSError **outError){
        OBASSERT(self.hasBeenLocallyDeleted == NO);

        OFXFileSnapshotDownloadTransfer *strongTransfer = weakTransfer;
        if (!strongTransfer) {
            OBASSERT_NOT_REACHED("Shouldn't be invoked after transfer is deallocated");
            return NO;
        }

        // For very quick edits, we might not know that the local file is edited (the file presenter notification might be in flight or our rescan request might still be in flight). So, while we could maybe check our localState here, we can't depend on it and actually need to look at the filesystem state (inside file coordination).
        OBFinishPortingLater("Handle client A moving f1 to f2 and adding a new f1 (but not pushing any changes) and then downloading a conflicting edit to f1"); // We might need to unwind more local edits to get the conflicting goop out of the way. Might need a way to look up the file item with a given original path, or...

        BOOL downloadContents = (localTemporaryDocumentContentsURL != nil);
        OFXFileSnapshot *downloadedSnapshot = strongTransfer.downloadedSnapshot; // The operation clears callbacks, so this retain cycle will be broken.
        OBASSERT((downloadContents && downloadedSnapshot.localState.normal) || (!downloadContents && downloadedSnapshot.localState.missing));

        // Since the download has worked as far as the transfer is concerned, this URL is now ours to cleanup if we fail to commit.
        void (^cleanup)(void) = ^{
            NSURL *downloadedSnapshotURL = downloadedSnapshot.localSnapshotURL;
            __autoreleasing NSError *cleanupError;
            if (![[NSFileManager defaultManager] removeItemAtURL:downloadedSnapshotURL error:&cleanupError]) {
                [cleanupError log:@"Error cleaning up local downloaded snapshot %@", downloadedSnapshot];
            }
        };

        DEBUG_CONTENT(1, @"Commit download with local content \"%@\" and new content \"%@\"", OFXLookupDisplayNameForContentIdentifier(_snapshot.currentContentIdentifier), OFXLookupDisplayNameForContentIdentifier(downloadedSnapshot.currentContentIdentifier));

        // A write with NSFileCoordinatorWritingForMerging implies a read. If we explicitly pass an array of reading URLs that contains an item from writingURLs, filecoordinationd will crash (at least in 10.8.2). I don't have a standalone test case of this, but it is logged as Radar 12993597.
        //NSMutableArray *readingURLs = [NSMutableArray arrayWithObjects:_localDocumentURL, nil];
        NSMutableArray *writingURLs = [NSMutableArray arrayWithObjects:_localDocumentURL, nil];

        // If we have a local rename (possibly as part of name conflict resolution), don't accidentally revert it. This will override the server rename if there is an incoming rename as well.
#ifdef OMNI_ASSERTIONS_ON
        BOOL hadLocalMove = NO;
#endif
        if (_snapshot.localState.moved) {
#ifdef OMNI_ASSERTIONS_ON
            hadLocalMove = YES;
#endif
            __autoreleasing NSError *renameError;
            if (![downloadedSnapshot markAsLocallyMovedToRelativePath:_snapshot.localRelativePath error:&renameError]) {
                cleanup();
                if (outError)
                    *outError = renameError;
                return NO;
            }
        }
        
        // Check if the incoming snapshot has a rename.
        NSURL *updatedLocalDocumentURL = nil;
        BOOL moved = NO;
        if (![_snapshot.localRelativePath isEqualToString:downloadedSnapshot.localRelativePath]) {
            updatedLocalDocumentURL = [container _URLForLocalRelativePath:downloadedSnapshot.localRelativePath isDirectory:downloadedSnapshot.directory];
            [writingURLs addObject:updatedLocalDocumentURL];
            moved = YES;
        } else {
            updatedLocalDocumentURL = _localDocumentURL;
        }

        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:filePresenter];
        __block BOOL success = NO;
        [coordinator prepareForReadingItemsAtURLs:nil options:0 /* provoke save since we are maybe about to write to the file */
                               writingItemsAtURLs:writingURLs options:NSFileCoordinatorWritingForMerging /* there is no "I might not write option" so other presenters are going to get a relinquish no matter what */
                                            error:outError byAccessor:
         ^(void (^completionHandler)(void)){
             success = [self _performDownloadCommitToURL:updatedLocalDocumentURL localTemporaryDocumentContentsURL:localTemporaryDocumentContentsURL targetLocalSnapshotURL:targetLocalSnapshotURL container:container downloadedSnapshot:downloadedSnapshot coordinator:coordinator downloadContents:downloadContents isMove:moved error:outError];

             if (completionHandler)
                 completionHandler();
         }];

        if (!success) {
            cleanup();
            return NO;
        }

        OBASSERT(!hadLocalMove || _snapshot.localState.moved, @"If we had a local move, make sure to preserve that to be uploaded");
        
        return YES;
    };
    
    [transfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
        OBINVARIANT([self _checkInvariants]);
        
        OBASSERT(self.isDownloading == YES);
        [self _transferFinished:transfer];
        OBASSERT(self.isDownloading == NO);

        // TODO: may want to keep _lastError and also put it into updated metadata
        
        // If the transfer was cancelled due to sync being paused, or the commit failed for some reason, we still need to say we aren't downloading.
        if (errorOrNil) {
            // Remote update/delete has clobbered us and we've presumably told the contain to scan. Don't keep attempting the download in the mean time.
            if ([errorOrNil hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND]) {
                _newestMissingVersion = _snapshot.version;
                
                [container _fileItemDidDetectUnknownRemoteEdit:self];
                
                __autoreleasing NSError *error = errorOrNil;
                OFXError(&error, OFXFileItemDetectedRemoteEdit, nil, nil);
                errorOrNil = error;
            }
        }
        return errorOrNil;
    }];
    
    return transfer;
}

- (BOOL)_validateDownloadCommitToURL:(NSURL *)_updatedLocalDocumentURL contentSame:(BOOL)contentSame coordinator:(NSFileCoordinator *)coordinator error:(NSError **)outError;
{
    OBFinishPortingLater("Validate that the updated local document URL is missing too?");
    
    // We pass NSFileCoordinatorWritingForMerging in the 'prepare' in our caller, which should force other presenters to relinquish and save, but experimentally it does not. We have to do an explicit read withChanges:YES here to provoke -[OFXTestSaveFilePresenter savePresentedItemChangesWithCompletionHandler:] in -[OFXConflictTestCase testIncomingCreationVsLocalAutosaveCreation].
    return [coordinator readItemAtURL:_localDocumentURL withChanges:YES error:outError byAccessor:^BOOL(NSURL *newReadingURL, NSError *__autoreleasing *outError) {
        if (self.localState.missing) {
            // If this is the first download of a new file, and something is sleeping in our bed, then we may have created a local document while the download was going on or while we were offline. We cannot publish the content from this download, but we can (and must) accept the metadata so that we know where the file wants to live and so that our container will stop trying to generate downloads for us. We'll return a special error in this case that lets the container know to skip the publishing.
            __autoreleasing NSError *existsError;
            if ([[NSFileManager defaultManager] attributesOfItemAtPath:[newReadingURL path] error:&existsError]) {
                OFXContainerAgent *container = _weak_container;
                OBASSERT(container);
                
                __autoreleasing NSError *conflictError;
                if (![container _relocateFileAtURL:_localDocumentURL toMakeWayForFileItem:self coordinator:coordinator error:&conflictError]) {
                    [conflictError log:@"Error moving %@ out of the way for incoming document %@", _localDocumentURL, [self shortDescription]];
                    if (outError)
                        *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
                    OFXError(outError, OFXFileShadowed, @"Cannot complete download of shadowed file", nil); // wrap this in an error with a little more info, but keep the user-cancelled in there to let callers know this is OK.
                    return NO;
                }
            } else {
                if ([existsError causedByMissingFile]) {
                    // Yay!
                } else {
                    NSLog(@"Error checking if supposedly missing file is really missing at %@: %@", newReadingURL, [existsError toPropertyList]);
                    
                    // Whatever the badness is, try to move it aside... not hopeful.
                    if (![self _generateConflictDocumentFromLocalContentsAndRevertToLocallyMissingWithCoordinator:coordinator error:outError])
                        return NO;
                }
            }
        } else if (self.localState.edited) {
            // If the incoming download is just a name change, we can keep our local edits.
            if (contentSame)
                return YES;
            
            // Known local content edit vs incoming content edit. Move it aside to make way for the incoming download
            if (![self _generateConflictDocumentFromLocalContentsAndRevertToLocallyMissingWithCoordinator:coordinator error:outError])
                return NO;
        } else {
            // Could have a local move, which we preserve in our caller.
            OBASSERT(self.localState.normal || self.localState.moved);
            
            // We *do* want to force autosave on other presenters here since we are trying to do conflict detection.
            __autoreleasing NSError *sameError;
            NSNumber *same = [_snapshot hasSameContentsAsLocalDocumentAtURL:newReadingURL coordinator:coordinator withChanges:YES error:&sameError];
            if (!same) {
                if ([sameError causedByMissingFile]) {
                    // The file has been deleted locally or possibly moved just as we are committing. In the case of deletion, this will act as a resurrection. In the case of a move, we'll end up with a new file.
                    return YES;
                } else {
                    [sameError log:@"Error checking if snapshot %@ and URL %@ have the same contents", [_snapshot shortDescription], newReadingURL];
                    if (outError)
                        *outError = sameError;
                    OBChainError(outError);
                    return NO;
                }
            }
            
            BOOL validateSuccess = NO;
            if (![same boolValue]) {
                // Local edit. Move it aside as a conflict
                validateSuccess = [self _generateConflictDocumentFromLocalContentsAndRevertToLocallyMissingWithCoordinator:coordinator error:outError];
            } else
                validateSuccess = YES; // Nothing changed... yay!
            if (!validateSuccess) {
                OBChainError(outError);
                return NO;
            }
        }
        
        return YES;
    }];
}

- (BOOL)_performDownloadCommitToURL:(NSURL *)updatedLocalDocumentURL localTemporaryDocumentContentsURL:(NSURL *)localTemporaryDocumentContentsURL targetLocalSnapshotURL:(NSURL *)targetLocalSnapshotURL container:(OFXContainerAgent *)container downloadedSnapshot:(OFXFileSnapshot *)downloadedSnapshot coordinator:(NSFileCoordinator *)coordinator downloadContents:(BOOL)downloadContents isMove:(BOOL)moved error:(NSError **)outError;
{
    OBASSERT(_snapshot.localState.missing || _snapshot.remoteState.edited || _snapshot.remoteState.moved);

    BOOL contentSame = [downloadedSnapshot hasSameContentsAsSnapshot:_snapshot];
    DEBUG_CONTENT(1, @"Commit, has same %d", contentSame);
    if (!contentSame) {
        DEBUG_CONTENT(1, @"downloadedSnapshot %@", downloadedSnapshot.infoDictionary);
        DEBUG_CONTENT(1, @"_snapshot %@", _snapshot.infoDictionary);
    }
    
    __autoreleasing NSError *validateDownloadError;
    if (![self _validateDownloadCommitToURL:updatedLocalDocumentURL contentSame:contentSame coordinator:coordinator error:&validateDownloadError]) {
        if ([validateDownloadError hasUnderlyingErrorDomain:OFXErrorDomain code:OFXFileShadowed]) {
            // This might not be set yet if the local file was created since the last scan.
            //OBASSERT(self.shadowedByOtherFileItem);
            
            DEBUG_CONFLICT(1, @"Accepting only metadata for shadowed download at %@", updatedLocalDocumentURL);
            
            // Accept the metadata, but we can't publish the content since something is already on disk at this URL.
            OBASSERT(self.localState.missing, @"We only generate this erorr for the local missing case; make sure to consider other impliciations if this can occur with local published content that becomes shadowed (oxymoronic currently).");
            downloadContents = NO;
            
            // Mark the downloaded snapshot as not having any contents so that we *stay* in the missing state when we adopt it.
            __autoreleasing NSError *error;
            if (![downloadedSnapshot didGiveUpLocalContents:&error]) {
                OBChainError(&error);
                [error log:@"Unable to mark downloaded shadowed snapshot has having no content."];
                if (outError)
                    *outError = error;
                return NO;
            }
        } else {
            if (outError)
                *outError = validateDownloadError;
            OBChainError(outError);
            return NO;
        }
    }

    // Check if the incoming snapshot has a rename and perform it (if we have a local document downloaded).
    if (moved && !self.localState.missing) {
        __autoreleasing NSError *moveError;
        if (![self _performDownloadCommitMoveToURL:updatedLocalDocumentURL coordinator:coordinator error:&moveError]) {
            if (outError)
                *outError = moveError;
            [moveError log:@"Error moving %@ to %@ during commit of download.", _localDocumentURL, updatedLocalDocumentURL];
            return NO;
        }
        
        OFXNoteContentMoved(self, _localDocumentURL, updatedLocalDocumentURL);
        // We don't poke the container here. It will do it in its 'done' block. This method tries to verify invariants but invariants will be broken briefly while we have our new relative path, but the container doesn't know about it yet.
        //[container fileAtURL:_localDocumentURL movedToURL:updatedLocalDocumentURL byUser:NO];
    }
    
    if (downloadContents) {
        BOOL takeExistingContent = NO;
        
        if (_snapshot.localState.normal && contentSame)
            // No need to rewrite the file wrapper (and cause file presenters to reload the contents), but we do need to update the downloaded snapshot to know that it has the same contents (which records inodes and timestamps).
            takeExistingContent = YES;
        else if (_snapshot.localState.edited && contentSame)
            // We have local edits and the incoming change didn't have a content change (probably just a move). Keep the local edits rather than reverting.
            takeExistingContent = YES;
        
        if (takeExistingContent) {
            DEBUG_TRANSFER(1, @"Downloaded snapshot %@ taking over previously published contents from %@", [downloadedSnapshot shortDescription], [_snapshot shortDescription]);
            
            if (![downloadedSnapshot didTakePublishedContentsFromSnapshot:_snapshot error:outError]) {
                OBChainError(outError);
                return NO;
            }
            
            // Not going to use whatever content we downloaded (we only do this on success, since our caller does it on failure).
            __autoreleasing NSError *cleanupError;
            if (![[NSFileManager defaultManager] removeItemAtURL:localTemporaryDocumentContentsURL error:&cleanupError])
                [cleanupError log:@"Error cleaning up temporary download document at %@ (after taking over contents from another version).", localTemporaryDocumentContentsURL];
        } else {
            if (![self _publishContentsFromTemporaryDocumentURL:localTemporaryDocumentContentsURL toLocalDocumentURL:updatedLocalDocumentURL snapshot:downloadedSnapshot coordinator:coordinator error:outError]) {
                OBChainError(outError);
                return NO;
            }
        }
    }
    
    // Move the downloading snapshot into place
    if (![[NSFileManager defaultManager] replaceItemAtURL:targetLocalSnapshotURL withItemAtURL:downloadedSnapshot.localSnapshotURL backupItemName:nil options:0 resultingItemURL:NULL error:outError]) {
        // This can happen if you delete an account while it's still syncing
        OBChainError(outError);
        return NO;
    }
    
    // Let the downloading snapshot know it has moved, and finally signal that we are done downloading!
    [downloadedSnapshot didMoveToTargetLocalSnapshotURL:targetLocalSnapshotURL];
    
    if (moved) {
        DEBUG_TRANSFER(2, @"File item moved, download moved to %@ / %@", downloadedSnapshot.localRelativePath, updatedLocalDocumentURL);
        _localRelativePath = [downloadedSnapshot.localRelativePath copy];
        _localDocumentURL = [updatedLocalDocumentURL copy];
    }
    
    _snapshot = downloadedSnapshot;

    DEBUG_TRANSFER(1, @"switched to downloaded snapshot %@", [_snapshot shortDescription]);
    DEBUG_CONTENT(1, @"Commit download with content \"%@\"", OFXLookupDisplayNameForContentIdentifier(_snapshot.currentContentIdentifier));
    
    return YES;
}

- (BOOL)_performDownloadCommitMoveToURL:(NSURL *)updatedLocalDocumentURL coordinator:(NSFileCoordinator *)coordinator error:(NSError **)outError;
{
    DEBUG_TRANSFER(1, @"performing download commit of move from %@ to %@", self.localRelativePath, updatedLocalDocumentURL);
                   
    __autoreleasing NSError *moveError;
    if ([coordinator moveItemAtURL:_localDocumentURL toURL:updatedLocalDocumentURL createIntermediateDirectories:YES error:&moveError])
        return YES;
    
    // If something is in our way, evict it.
    if (![moveError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EEXIST]) {
        if (outError)
            *outError = moveError;
        return NO;
    }
    
    OFXContainerAgent *container = _weak_container;
    OBASSERT(container);
    
    __autoreleasing NSError *conflictError;
    if (![container _relocateFileAtURL:updatedLocalDocumentURL toMakeWayForFileItem:self coordinator:coordinator error:&conflictError]) {
        [conflictError log:@"Error relocating file at %@ to make way for downloaded move of document %@", updatedLocalDocumentURL, [self shortDescription]];
    } else {
        // Try the move again.
        moveError = nil;
        if ([coordinator moveItemAtURL:_localDocumentURL toURL:updatedLocalDocumentURL createIntermediateDirectories:YES error:&moveError])
            return YES;
    }

    if (outError)
        *outError = moveError;
    OBChainError(outError);
    return NO;
}

- (OFXFileSnapshotTransfer *)prepareDeleteTransferWithConnection:(OFXConnection *)connection filePresenter:(id <NSFilePresenter>)filePresenter;
{
    OBPRECONDITION([self _checkInvariants]);
    OBPRECONDITION(_snapshot);
    OBPRECONDITION(_snapshot.localState.deleted);
    OBPRECONDITION(_currentTransfer == nil, "Shouldn't start a delete while still doing another transfer");
    OBINVARIANT([self _checkInvariants]);
    OBPRECONDITION(filePresenter);
    
    DEBUG_TRANSFER(1, @"Starting delete of %@", [self shortDescription]);

    OFXContainerAgent *container = _weak_container;
    if (!container) {
        OBASSERT_NOT_REACHED("The container should be calling us, so shouldn't have gone away");
        return nil;
    }
    OBASSERT(container.filePresenter == filePresenter); // Maybe don't need to pass this down...
    
    OFXFileSnapshotDeleteTransfer *transfer = [[OFXFileSnapshotDeleteTransfer alloc] initWithConnection:connection fileIdentifier:_identifier snapshot:_snapshot remoteContainerURL:container.remoteContainerDirectory remoteTemporaryDirectoryURL:container.remoteTemporaryDirectory];
    transfer.debugName = self.debugName;
    
    __weak OFXFileSnapshotDeleteTransfer *weakTransfer = transfer;
    
    [self _transferStarted:transfer];
    
    BOOL (^removeSnapshot)(NSError **outError) = [^BOOL(NSError **outError){
        // Remove the local snapshot. If this fails, we'll be doomed to do the delete again and again... Hopefully the move portion of the atomic delete happens so that we don't see the snapshot on the next run.
        __autoreleasing NSError *removeError = nil;
        if (![[NSFileManager defaultManager] atomicallyRemoveItemAtURL:_snapshot.localSnapshotURL error:&removeError]) {
            OBASSERT_NOT_REACHED("Someone poked our snapshot?");
            
            NSLog(@"Error removing local snapshot at %@: %@", _snapshot.localSnapshotURL, [removeError toPropertyList]);
            if (outError)
                *outError = removeError;
            
            return NO; // ... we could maybe let this slide if the removeError as NSPOSIXErrorDomain/ENOENT, but since we shouldn't get here, lets just fail.
        }
        
        TRACE_SIGNAL(OFXFileItem.delete_transfer.commit.removed_local_snapshot);
        return YES;
    } copy];
    
    transfer.commit = ^BOOL(NSError **outError){
        OBASSERT(self.hasBeenLocallyDeleted == YES, @"Cannot resurrect now that the delete has happened on the server"); //
        
        OFXFileSnapshotDeleteTransfer *strongTransfer = weakTransfer;
        if (!strongTransfer) {
            OBASSERT_NOT_REACHED("Shouldn't be invoked after transfer is deallocated");
            return NO;
        }
        
        [_snapshot markAsRemotelyDeleted:outError];
        return removeSnapshot(outError);
    };
    
    [transfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
        OBASSERT(self.isDeleting);
        [self _transferFinished:transfer];
        
        if (errorOrNil) {
            OBINVARIANT([self _checkInvariants]);
            
            if ([errorOrNil hasUnderlyingErrorDomain:OFXErrorDomain code:OFXFileUpdatedWhileDeleting]) {
                // In this case, we also go ahead and remove our local snapshot. The container will clean up after us and on the next sync we'll download the fresh copy. This is easier than trying to resurrect ourselves here (especially since our metadata is out of date and the remote file might have been renamed).
                removeSnapshot(NULL);
            } else {
                OBASSERT([errorOrNil underlyingErrorWithDomain:NSURLErrorDomain]);
                // Maybe offline? We have a delete note, so we'll just try later.
                [errorOrNil log:@"Error deleting snapshot with identifier %@", _identifier];
            }
        } else {
            // We no longer meet our invariants since _snapshot's localSnapshotURL doesn't exist on disk. We are should get discarded by our container now, though.
            //OBINVARIANT([self _checkInvariants]);
        }
        return errorOrNil;
    }];
    
    return transfer;
}

// We've noticed a delete from the server and need to remove our published document
- (BOOL)handleIncomingDeleteWithFilePresenter:(id <NSFilePresenter>)filePresenter error:(NSError **)outError;
{
    // We might have a pending transfer. If we get here, it should end up failing due to the incoming delete (the validateCommit blocks on those transfers check for deletion and bail).
    //OBPRECONDITION(self.isDownloading == NO);
    //OBPRECONDITION(self.isUploading == NO);
    OBPRECONDITION(self.hasBeenLocallyDeleted == NO);
    
    OBINVARIANT([self _checkInvariants]);
    
    if (![self markAsRemotelyDeleted:outError])
        return NO;
    
    // If we die between marking the snapshot as remotely deleted and performing the delete locally, we'll currently re-upload the file to the server on the next run. This isn't terrible, but we could re-process the incoming delete on the next launch by first verifying that the local document reports @YES from -hasSameContentsAsSnapshot: for the deleted snapshot.
    
    OFXContainerAgent *container = _weak_container;
    if (!container) {
        OBASSERT_NOT_REACHED("Invalidated but the container didn't forget about us?");
        return NO;
    }
    
    if (self.localState.missing) {
        // We've never downloaded the file and someone else has removed it now.
    } else {
        __autoreleasing NSError *error;
        
        // If there is a local edit, we should leave the local document but remove the snapshot (which is gone on the server). The local document will then look like a new document. This means that if we ever add history/versioning that we'll lose the link between these versions of the files, but that's probably OK and this is easier than thinking about resurrecting the deleted snapshot. Another side effect (rare) is that if you have three clients with the same file open, A deletes, B edits and C is just viewing, then C will have to close its document rather than reloading the resurrected contents.
        __block BOOL hasLocalEdit = self.localState.edited; // We might know about the edit already...

        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:filePresenter];
        
        // Can only use one writing option at a time, so first we specify a write-with-merge to provoke a save, see if anything happened, and if not, delete.
        BOOL success = [coordinator writeItemAtURL:_localDocumentURL withChanges:YES error:&error byAccessor:^BOOL(NSURL *newURL, NSError **outError) {
            __autoreleasing NSError *sameError;
            NSNumber *same = [_snapshot hasSameContentsAsLocalDocumentAtURL:newURL coordinator:coordinator withChanges:NO/*should already be saved*/ error:&sameError];
            if (same == nil) {
                [sameError log:@"Error checking whether incoming delete for %@ has local conflicting changes", _localDocumentURL];
                hasLocalEdit = YES;
            } else {
                // Maybe there was a local edit away from the original state and then back, but this seems unlikely since we check inodes and mtimes in -hasSameContentsAsLocalDocumentAtURL:... At any rate, don't reset hasLocalEdit here.
                hasLocalEdit |= ![same boolValue];
            }
            if (hasLocalEdit)
                return NO;
            return [coordinator removeItemAtURL:newURL error:outError byAccessor:^BOOL(NSURL *newURL2, NSError **outError) {
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
                // On iOS, we have to handle our own trash
                if (![ODSScope trashItemAtURL:newURL2 resultingItemURL:NULL error:outError])
                    return NO;
#else
                // On Mac, we can use the system trash
                if (![[NSFileManager defaultManager] trashItemAtURL:newURL2 resultingItemURL:NULL error:outError])
                    return NO;
#endif
                TRACE_SIGNAL(OFXFileItem.incoming_delete.removed_local_document);
                OFXNoteContentDeleted(self, newURL2);
                return YES;
            }];
        }];
        if (!success) {
            if (hasLocalEdit) {
                DEBUG_TRANSFER(1, @"Local edit conflicts with incoming delete -- will resurrect document under the same name");
            } else {
                NSLog(@"Error handling incoming delete. Cannot delete %@: %@", _localDocumentURL, [error toPropertyList]);
                if (outError)
                    *outError = error;
                return NO;
            }
        }
    }
    
    // Then remove our snapshot (even on a conflict -- it is gone on the server). If there were conflicting local edits, we'll have left the document alone.
    {
        __autoreleasing NSError *removeError = nil;
        if (![[NSFileManager defaultManager] atomicallyRemoveItemAtURL:_snapshot.localSnapshotURL error:&removeError]) {
            OBASSERT_NOT_REACHED("Someone poked our snapshot?");
            
            NSLog(@"Error removing local snapshot at %@: %@", _snapshot.localSnapshotURL, [removeError toPropertyList]);
            if (outError)
                *outError = removeError;
            
            return NO; // ... we could maybe let this slide if the removeError as NSPOSIXErrorDomain/ENOENT, but since we shouldn't get here, lets just fail.
        }
    }
    
    TRACE_SIGNAL(OFXFileItem.incoming_delete.removed_local_snapshot);
    
    // We don't remove our metadata here; we expect our container to call -invalidate next.
    return YES;
}

static NSString *ClientComputerName(void)
{
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    NSString *fullHostname = OFHostName();
    NSRange dotRange = [fullHostname rangeOfString:@"."];
    if (dotRange.length == 0)
        return fullHostname;
    else
        return [fullHostname substringToIndex:dotRange.location];
#else
    return [[UIDevice currentDevice] name];
#endif
}

- (NSURL *)fileURLForConflictVersion;
{
    OFCreateRegularExpression(ConflictRegularExpression, NSLocalizedStringFromTableInBundle(@"^(.*) \\(conflict( [0-9+])? from .*\\)$", @"OmniFileExchange", OMNI_BUNDLE, @"Conflict file regular expression"));

    NSURL *folderURL = [_localDocumentURL URLByDeletingLastPathComponent];
    NSString *lastComponent = [_localDocumentURL lastPathComponent];
    NSString *baseName = [lastComponent stringByDeletingPathExtension];
    NSString *pathExtension = [lastComponent pathExtension];
    
    // We include the host name, so conflicts in our conflict names shouldn't happen except when two hosts have the same name.
    NSString *hostname = ClientComputerName();
    NSString *debugName = self.debugName; // Avoid spurious extra conflicts due to having the same host name in unit tests
    if (![NSString isEmptyString:debugName])
        hostname = [hostname stringByAppendingFormat:@"-%@", debugName];

    NSUInteger conflictIndex;

    OFRegularExpressionMatch *conflictMatch = [ConflictRegularExpression of_firstMatchInString:baseName];
    if (conflictMatch != nil) {
        NSString *conflictBaseName = [conflictMatch captureGroupAtIndex:0];
        NSString *conflictIndexString = [conflictMatch captureGroupAtIndex:1];
        conflictIndex = [conflictIndexString unsignedIntValue];
#ifdef DEBUG_kc
        NSLog(@"DEBUG: Parsing conflict filename: baseName=[%@], conflictBaseName=[%@], conflictIndexString=[%@], conflictIndex=%lu", baseName, conflictBaseName, conflictIndexString, conflictIndex);
#endif
        baseName = conflictBaseName;
    } else {
        conflictIndex = 0;
    }

    NSURL *candidateURL = nil;
    do {
        conflictIndex++;
        NSString *conflictBaseName;
        if (conflictIndex == 1)
            conflictBaseName = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ (conflict from %@)", @"OmniFileExchange", OMNI_BUNDLE, @"Conflict file format"), baseName, hostname];
        else
            conflictBaseName = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ (conflict %lu from %@)", @"OmniFileExchange", OMNI_BUNDLE, @"Conflict file format"), baseName, conflictIndex, hostname];
        candidateURL = [folderURL URLByAppendingPathComponent:[conflictBaseName stringByAppendingPathExtension:pathExtension]];
    } while ([[self container] publishedFileItemWithURL:candidateURL]);

    // The original URL might not exist, so we can't get this via attribute lookups.
    BOOL isDirectory = [[_localDocumentURL absoluteString] hasSuffix:@"/"];
    
    return [NSURL fileURLWithPath:[candidateURL path] isDirectory:isDirectory];
}

- (NSString *)currentContentIdentifier;
{
    return _snapshot.currentContentIdentifier;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return self; // So we can be a dictionary key
}

#pragma mark - Internal

- (BOOL)isValidToUpload;
{
    // Either needs to be the first upload or an edit of a fully downloaded file (not a new remote file that isn't locally present at all).
    return !self.presentOnServer || self.isDownloaded;
}

- (BOOL)isDownloaded;
{
    return !_snapshot.localState.missing;
}

- (BOOL)presentOnServer;
{
    OFXFileState *remoteState = _snapshot.remoteState;
    
    if (remoteState.deleted) {
        // We are in the middle of processing an incoming delete (we've made the note, but haven't cleaned up the snapshot/file item yet).
        return NO;
    }
    if (remoteState.missing) {
        // Never uploaded
        return NO;
    }
    
    return YES;
}

- (BOOL)hasCurrentTransferBeenCancelled;
{
    return _currentTransfer.cancelled;
}

- (NSString *)publishedFileVersion;
{
    // Used by the container and account agents to publish a Bonjour service with state about what files are on the server.
    return _makeRemoteSnapshotDirectoryName(self, _snapshot);
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@ %@ %@ %@/%@>", NSStringFromClass([self class]), self, self.debugName, _identifier, _localRelativePath, self.localState, self.remoteState];
}

- (NSString *)debugName;
{
    OFXContainerAgent *container = _weak_container;
    OBASSERT(container);
    return container.debugName;
}

#pragma mark - Private

- (OFXFileMetadata *)_makeMetadata;
{
    OBINVARIANT([self _checkInvariants]);

    // TODO: We could maybe cache this until we get poked file NSFilePresenter or find new info on the server, or whatnot.
    OFXFileMetadata *metadata = [[OFXFileMetadata alloc] init];
    OFXFileSnapshot *snapshot = _snapshot;
    
    OFXFileState *localState = snapshot.localState;
    OFXFileState *remoteState = snapshot.remoteState;
    
    OBASSERT(_localDocumentURL);
    
    DEBUG_METADATA(1, @"Making metadata for %@ with snapshot %@", _localDocumentURL, [_snapshot debugDescription]);
    
    metadata.fileIdentifier = _identifier;
    metadata.fileURL = (localState.deleted ? nil : _localDocumentURL); // TODO: Needs synchronize with NSFilePresenter messages
    metadata.directory = _snapshot.directory;
    
    DEBUG_METADATA(1, @"  Local state %@", localState);
    DEBUG_METADATA(1, @"  Remote state %@", remoteState);

    metadata.totalSize = _snapshot.totalSize;
    
    if (remoteState.missing || localState.edited || (localState.moved && !localState.missing)) {
        metadata.uploaded = NO;
        metadata.percentUploaded = 0;
    } else if (localState.normal || localState.missing) {
        metadata.uploaded = YES;
        metadata.percentUploaded = 1;
    } else if (localState.deleted) {
        // Might get deleted while uploading. This file item should disappear soon.
        metadata.uploaded = NO;
        metadata.percentUploaded = 0;
        metadata.deleting = YES;
    } else {
        OBASSERT_NOT_REACHED("Unexpected local state hit");
    }
    
    if (localState.missing || remoteState.edited || remoteState.moved) {
        metadata.downloaded = NO;
        metadata.percentDownloaded = 0;
    } else if (remoteState.normal || remoteState.missing) {
        metadata.downloaded = YES;
        metadata.percentDownloaded = 1;
    } else if (remoteState.deleted) {
        // This can happen if we notice a deletion while we are in the middle of downloading a file.
        metadata.downloaded = NO;
        metadata.percentDownloaded = 0;
        metadata.deleting = YES;
    } else {
        // We might actuall hit this now temporary when we have a conflict
        OBASSERT_NOT_REACHED("Unexpected remote state hit");
    }

    // Override some stuff based on whether we have a transfer going. In particular, don't say we are up/downloaded while we still have a transfer
    if (self.isUploadingContents) {
        metadata.uploaded = NO;
        metadata.uploading = YES;
        metadata.percentUploaded = _currentTransfer.percentCompleted;
        DEBUG_METADATA(1, @"  is uploading content (%f%%)", metadata.percentUploaded * 100);
    } else if (self.isUploading) {
        OBASSERT(self.isUploadingRename, @"Should be a rename");

        DEBUG_METADATA(1, @"  is uploading metadata");
        metadata.uploaded = YES;
        metadata.uploading = YES;
        metadata.percentUploaded = 1;
    }
    
    if (self.isDownloadingContent) { // Don't report downloads that are just metadata updates
        metadata.downloaded = NO;
        metadata.downloading = YES;
        metadata.percentDownloaded = _currentTransfer.percentCompleted;
        DEBUG_METADATA(1, @"  is downloading content (%f%%)", metadata.percentDownloaded * 100);
    } else if (self.isDownloading) {
        DEBUG_METADATA(1, @"  is downloading metadata");
        
        // Just a metadata download... we don't know for sure whether there will be content coming or not.
        // If this is a metadata download of a new file, we should report it as a download. Otherwise, we should report it as normal until we start downloading content.
        BOOL uploaded = !self.remoteState.missing;
        BOOL downloaded = !self.localState.missing;
        
        metadata.uploaded = uploaded;
        metadata.downloaded = downloaded;
        metadata.percentUploaded = uploaded ? 1.0 : 0.0;
        metadata.percentDownloaded = downloaded ? 1.0 : 0.0;
    }
    
    metadata.fileSize = snapshot.totalSize;
    metadata.creationDate = snapshot.userCreationDate;
    metadata.modificationDate = snapshot.userModificationDate;

    // TODO: Make editIdentifier just be an id instead of NSString? Or maybe NSUInteger.
    metadata.editIdentifier = [NSString stringWithFormat:@"%lu", snapshot.version];
    
    return metadata;
}

- (void)_updatedMetadata;
{
    // We check -hasBeenLocallyDeleted here for convenience in the local-delete vs. local-download race case. We could also predicate our calls in the download transferProgress() block, but this seems like a nice global solution that might catch other cases.
    if (_shadowedByOtherFileItem)
        [_metadataRegistrationTable removeObjectForKey:_identifier];
    else if (self.localState.deleted && (self.remoteState.missing || self.remoteState.deleted)) {
        // This was never uploaded, or has been deleted remotely too, so the "delete" transfer isn't going to actually do any network work (which is why we delay clearing the metadata -- so we can show the number of delete operations that need to be performed). Also, if we generate metadata here, we'll hit assertions.
        [_metadataRegistrationTable removeObjectForKey:_identifier];
    } else
        _metadataRegistrationTable[_identifier] = [self _makeMetadata];
}

- (void)_transferStarted:(OFXFileSnapshotTransfer *)transfer;
{
    OBPRECONDITION(_currentTransfer == nil, @"Starting another transfer with out the previous one finishing?");
    OBPRECONDITION(transfer);
    
    _currentTransfer = transfer;
    [self _updatedMetadata];
}

- (void)_transferFinished:(OFXFileSnapshotTransfer *)transfer;
{
    // The caller does a read of a __weak local to pass as our argument
    if (!transfer) {
        OBASSERT_NOT_REACHED("Shouldn't be invoked after transfer is deallocated");
        return;
    }
    if (_currentTransfer == transfer) {
        _currentTransfer = nil;
        [self _updatedMetadata];
    } else {
        OBASSERT_NOT_REACHED("Started another transfer before a previous transfer finished?");
    }
}

// Assumes the passed in coordinator has a proper file presenter and has been prepared or otherwise is ready to write to the localDocumentURL (nested write).
- (BOOL)_publishContentsFromTemporaryDocumentURL:(NSURL *)temporaryDocumentURL toLocalDocumentURL:(NSURL *)localDocumentURL snapshot:(OFXFileSnapshot *)snapshot coordinator:(NSFileCoordinator *)coordinator error:(NSError **)outError;
{
    OBPRECONDITION(temporaryDocumentURL);
    OBPRECONDITION([temporaryDocumentURL checkResourceIsReachableAndReturnError:NULL]);
    OBPRECONDITION(localDocumentURL);
    OBPRECONDITION(snapshot);
    OBPRECONDITION(snapshot.localState.deleted == NO);
    OBPRECONDITION(coordinator);
    OBPRECONDITION(_shadowedByOtherFileItem == NO); // Don't overwrite the published contents of the winner in a name conflict!
    
    DEBUG_TRANSFER(1, @"Publishing contents from %@ to %@", [snapshot shortDescription], localDocumentURL);
    
    static BOOL isRunningUnitTests = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isRunningUnitTests = (getenv("OFXTestsRunning") != NULL);
    });
    
    if (_shadowedByOtherFileItem) {
        // Maybe started a download before we knew we were shadowed.
        // TODO: We'll be resolving this pretty quickly. It would be nice to keep the contents we *would* have published somewhere indexed by editIdentifier and grab them back rather than re-downloading. But, hopefully this should be rare enough to not be worth the extra complexity.
        OFXError(outError, OFXFileShadowed, @"Cannot publish document contents", ([NSString stringWithFormat:@"The file URL %@ has multiple documents that would like to use it, and this file item lost.", localDocumentURL]));
        return NO;;
    }
    
    // We should be able to pass withChanges=NO here since our 'prepare' already did NSFileCoordinatorWritingForMerging and we don't want to force save again. But, experimentally this doesn't work. We have to pass withChanges:YES to provoke -[OFXTestSaveFilePresenter savePresentedItemChangesWithCompletionHandler:] in -[OFXConflictTestCase testIncomingCreationVsLocalAutosaveCreation].
    return [coordinator writeItemAtURL:localDocumentURL withChanges:YES error:outError byAccessor:^BOOL(NSURL *newWriteURL, NSError **outError) {
        
        /*
         HACK HACK HACK: Radar 13167947: Coordinated write to flat file will sometimes not reload NSDocument
         
         If we are too fast here, NSDocument will receive:
         
         relinquish to writer
         reacquire from writer
         did change
         
         Which it seems to ignore (at least for flat files) <bug:///85578> (Apps with open, flat-file documents do not update to synced changes)
         
         If we delay here, they'll get the 'did change' w/in the writer block. The amount of time we wait is obviously fragile. Hopefully this bug will get fixed in the OS or we'll find a better workaround.
         */
        
        BOOL writeURLIsFlatFile;
        __autoreleasing NSNumber *writeURLIsDirectoryNumber = nil;
        __autoreleasing NSError *resourceError = nil;
        if (![newWriteURL getResourceValue:&writeURLIsDirectoryNumber forKey:NSURLIsDirectoryKey error:&resourceError]) {
            writeURLIsFlatFile = YES; // That is, we don't need the workaround
            if (![resourceError causedByMissingFile])
                NSLog(@"Unable to determine if %@ is a directory: %@", newWriteURL, [resourceError toPropertyList]);
        } else
            writeURLIsFlatFile = ![writeURLIsDirectoryNumber boolValue];
        
        if ((!snapshot.directory || writeURLIsFlatFile) && !isRunningUnitTests) {
            sleep(1);
        }
        
        // Create the folder for this item, which might be the first thing in the folder that has been downloaded
        OBFinishPortingLater("We need a version of this that will refuse to create the *entire* path. We do *NOT* want to create the account documents directory. There is something terrible going on if that is missing, and if we create it, that could be interpreted as deleting all the other documents in the account");
        if (![[NSFileManager defaultManager] createDirectoryAtURL:[newWriteURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:outError]) {
            OBChainError(outError);
            return NO;
        }
        
        BOOL (^tryReplace)(NSError **outError) = ^BOOL(NSError **outError){
            if ([[NSFileManager defaultManager] replaceItemAtURL:newWriteURL withItemAtURL:temporaryDocumentURL backupItemName:nil options:0 resultingItemURL:NULL error:outError])
                return YES;
            OBChainError(outError);
            return NO;
        };
        
        __autoreleasing NSError *replaceError;
        BOOL replaced = tryReplace(&replaceError);
        if (!replaced) {
            if ([replaceError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EACCES]) {
                // Some joker (probably me), may have marked a file read-only to see if it works. We don't sync permissions, so if we have an incoming edit of a file that is locally read-only, mark it and its parent directory as read-write.
                [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@(0700)} ofItemAtPath:[[newWriteURL URLByDeletingLastPathComponent] path] error:NULL]; // Make the folder writable
                
                NSNumber *filePermissions = _snapshot.isDirectory ? @(0700) : @(0600);
                [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:filePermissions} ofItemAtPath:[newWriteURL path] error:NULL]; // Make the file itself writable (and executable if it is a folder)
                
                replaceError = nil;
                replaced = tryReplace(&replaceError);
            }
        }
        if (!replaced) {
            if (outError)
                *outError = replaceError;
            OBChainError(outError);
            return NO;
        }
        
        OFXNoteContentChanged(self, newWriteURL);
        
        if (![snapshot didPublishContentsToLocalDocumentURL:newWriteURL error:outError]) {
            OBChainError(outError);
            return NO;
        }
        
        return YES;
    }];
}

// The passed in coordinator should have the container's filePresenter as its presenter (since this isn't a user edit and we don't want to publish change notifications) and should be prepared for writing to the local document URL.
- (BOOL)_generateConflictDocumentFromLocalContentsAndRevertToLocallyMissingWithCoordinator:(NSFileCoordinator *)coordinator error:(NSError **)outError;
{
    OBPRECONDITION(coordinator);
    OBPRECONDITION(self.localState.missing == NO);
    
    /*
     The server has newer contents for the document with our identifier, but we have local edits to push.
     
     Our strategy is that the server copy wins. We also want the user to have some indication that their edits ended up in a conflict version, so we need to:
     
     * Move our local path to a new local path that doesn't exist, using file coordination so that open NSDocument/UIDocument observers know that they should be editing the new conflict copy.
     * Take care that our container agent doesn't queue up a move command to send to the server!
     * Change our identifier(!)
     * Inform our container agent that our identifier has changed
     * Revert the local-edit state in our current snapshot before abandoning it and re-publish the pristine contents
     */
    
    OFXContainerAgent *container = _weak_container;
    if (!container) {
        OBASSERT_NOT_REACHED("The container should be calling us here");
        return NO;
    }
    

    OBFinishPortingLater("Our passed in file coordinator doesn't know about this URL and hasn't done the 'prepare' for it. This *shouldn't* deadlock since we don't have a presenter for it, but this makes me uncomfortable (but so does generating a conflict URL for every possible commit of a download).");
    NSURL *conflictURL = [self fileURLForConflictVersion];
    
    DEBUG_CONFLICT(1, @"Reverting to server state and preserving local contents as content conflict at %@", conflictURL);
    
    // It might be good to just 'prepare' for the conflictURL here and then check if it already exists inside the coordinator (and not actually declare our write). But, really, if we are racing against someone else creating a conflict with the same name, something goofy is going on.
    __block BOOL success = NO;
    __block NSError *conflictError = nil;
    
    [coordinator coordinateWritingItemAtURL:_localDocumentURL options:NSFileCoordinatorWritingForMoving writingItemAtURL:conflictURL options:NSFileCoordinatorWritingForReplacing error:outError byAccessor:^(NSURL *newURL1, NSURL *newURL2) {
        
        __autoreleasing NSError *error;
        BOOL moveSuccess = [[NSFileManager defaultManager] moveItemAtURL:newURL1 toURL:newURL2 error:&error];
        if (!moveSuccess) {
            [error log:@"Error moving %@ to %@ -- will try a guaranteed unique URL", newURL1, newURL2];
            
            // This will be an ugly file name, and won't be perfect for file coordination, but will let the user continue.
            // Sadly, we've never hit this case ourselves, or we might have a better fix.
            NSString *pathExtension = [conflictURL pathExtension];
            NSString *baseName = [[[conflictURL lastPathComponent] stringByDeletingPathExtension] stringByAppendingFormat:@" %@", OFXMLCreateID()];
            
            newURL2 = [[conflictURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:pathExtension]];
            error = nil;
            moveSuccess = [[NSFileManager defaultManager] moveItemAtURL:newURL1 toURL:newURL2 error:&error];
        }
        
        if (moveSuccess) {
            OFXNoteContentMoved(self, newURL1, newURL2);
            [coordinator itemAtURL:newURL1 didMoveToURL:newURL2];
        } else {
            // Hit in http://rt.omnigroup.com/Ticket/Display.html?id=887601
            [error log:@"Error moving %@ to %@", newURL1, newURL2];
            conflictError = error; // strong-ify
            return;
        }

        // Now that we've moved our published file aside, any other observers will pick it up as a new document and a new file item will be created (with a new identifier and no remote contents). One problem, though, is that we told NSFileCoordinator to not send changes to our container for this move (since we don't want to push a move to the server). So, we need to tell the container that something has happened so it will scan.
        // NOTE: This means that ODSFileItem CANNOT keep a pointer to an OFXFileItem (since the the URL of the file item isn't changing here).
        [container _fileItemDidGenerateConflict:self];
        
        // Mark our snapshot as being locally missing and re-publish a stub file.
        error = nil;
        if (![_snapshot didGiveUpLocalContents:&error]) {
            conflictError = error;
            return;
        }
        
        // Some checks to make sure we've fully gone back to being not-downloaded
        OBASSERT(self.presentOnServer == YES);
        OBASSERT(_snapshot.localState.missing);
        OBASSERT(self.isValidToUpload == NO);
        
        // Re-publish our old contents (doing this outside the original coordinator
        OBFinishPortingLater("Deal with local moves -- might need to get the old URL from the snapshot");
        success = YES;
    }];
    
    if (!success) {
        OBASSERT(conflictError);
        if (outError)
            *outError = conflictError;
    }
    
    return success;
}

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
{
    OFXContainerAgent *containerAgent = _weak_container;
    if (!containerAgent) {
        return YES; // We are on the way out, so...
    }
    
    OBINVARIANT(![NSString isEmptyString:_identifier]);
    
    OBINVARIANT(_snapshot, "Should always have a snapshot");
    OBINVARIANT(_snapshot.localState, "Snapshot should have a valid local state");
    OBINVARIANT(_snapshot.remoteState, "Snapshot should have a valid remote state");
    OBINVARIANT(OFURLIsStandardized(_snapshot.localSnapshotURL));

    NSURL *targetLocalSnapshotURL = _makeLocalSnapshotURL(containerAgent, _identifier);
    OBINVARIANT(OFURLIsStandardized(targetLocalSnapshotURL));
    OBINVARIANT([_snapshot.localSnapshotURL isEqual:targetLocalSnapshotURL], "the current snapshot should be ours");

    OBINVARIANT([_localDocumentURL isFileURL]);
    OBINVARIANT(![_localDocumentURL isFileReferenceURL]); // Do not want craziness like file:///.file/id=6571367.27967404/
    
    return YES;
}
#endif

@end

