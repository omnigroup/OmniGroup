// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileItem-Internal.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFileExchange/OFXRegistrationTable.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/OFXMLIdentifier.h>

#import <OmniFileExchange/OFXAccountClientParameters.h>
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
static OFPreference *OFXFileItemRecentErrorExpirationTimeInterval;

@implementation OFXFileItem
{
    OFXFileSnapshot *_snapshot;
    OFXFileSnapshotTransfer *_currentTransfer;

    // If we get a 404, record the version here and refuse to try to fetch that version again until the next scan tells us what our new version is. Set to OFXFileItemUnknownVersion if we know of no missing version.
    NSUInteger _newestMissingVersion;
    
    // During a remote scan, our container will tell us our latest version number. Set to OFXFileItemUnknownVersion if we don't know of any newer version than _snapshot.version
    NSUInteger _newestRemoteVersion;
    
    // Used to record recurring errors (which we might not otherwise log) so that we can throttle/pause operations if there are too many.
    NSMutableArray <OFXRecentError *> *_recentErrors;
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
    if (OFNOTEQUAL(string, [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]))
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
    OBASSERT([[identifier stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]] isEqual:identifier], @"Should not require URL encoding");
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
        return nil;
    }
    
    if (outVersion)
        *outVersion = [versionString unsignedLongValue];
    
    return fileIdentifier;
}

NSArray <ODAVFileInfo *> *OFXFetchDocumentFileInfos(ODAVConnection *connection, NSURL *containerURL, NSString *identifier, NSError **outError)
{
    __autoreleasing NSError *error;
    ODAVMultipleFileInfoResult *result = OFXFetchFileInfosEnsuringDirectoryExists(connection, containerURL, &error);
    if (!result) {
        if (outError)
            *outError = error;
        OBChainError(outError);
        return nil;
    }
    
    // Don't require full parsing of the id~version.
    NSString *identifierPrefix;
    if (identifier) {
        identifierPrefix = [NSString stringWithFormat:@"%@" OFXRemoteFileIdentifierToVersionSeparator, identifier];
    }
    
    // Winnow down our list to what we expect to find
    NSArray <ODAVFileInfo *> *fileInfos = [result.fileInfos select:^BOOL(ODAVFileInfo *fileInfo) {
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

static NSURL *_remoteContainerDirectory(OFXContainerAgent *containerAgent, ODAVConnection *connection)
{
    OBPRECONDITION(containerAgent);
    OBPRECONDITION(connection);
    
    NSURL *remoteContainerDirectory = containerAgent.remoteContainerDirectory;
    if (!connection) {
        OBASSERT_NOT_REACHED("How can we get here?");
        return remoteContainerDirectory;
    }
    return [connection suggestRedirectedURLForURL:remoteContainerDirectory];
}

static NSURL *_makeRemoteSnapshotURLWithVersion(OFXContainerAgent *containerAgent, ODAVConnection *connection, OFXFileItem *fileItem, NSUInteger fileVersion)
{
    OBPRECONDITION(containerAgent);
    OBPRECONDITION(fileVersion != OFXFileItemUnknownVersion);
    
    NSString *directoryName = _makeRemoteSnapshotDirectoryNameWithVersion(fileItem, fileVersion);
    
    return [_remoteContainerDirectory(containerAgent, connection) URLByAppendingPathComponent:directoryName isDirectory:YES];
}

static NSURL *_makeRemoteSnapshotURL(OFXContainerAgent *containerAgent, ODAVConnection *connection, OFXFileItem *fileItem, OFXFileSnapshot *snapshot)
{
    OBPRECONDITION(containerAgent);

    NSString *directoryName = _makeRemoteSnapshotDirectoryName(fileItem, snapshot);
    if (!directoryName)
        return nil;
    
    return [_remoteContainerDirectory(containerAgent, connection) URLByAppendingPathComponent:directoryName isDirectory:YES];
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OFXFileItemRecentErrorExpirationTimeInterval = [OFPreference preferenceForKey:@"OFXFileItemRecentErrorExpirationTimeInterval"];
}

- _initWithIdentifier:(NSString *)identifier snapshot:(OFXFileSnapshot *)snapshot localDocumentURL:(NSURL *)localDocumentURL intendedLocalRelativePath:(NSString *)intendedLocalRelativePath container:(OFXContainerAgent *)container error:(NSError **)outError;
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
    
    _identifier = [identifier copy];
    _snapshot = snapshot;
    _newestMissingVersion = OFXFileItemUnknownVersion;
    _newestRemoteVersion = OFXFileItemUnknownVersion;
    
    NSString *localRelativePath = [container _localRelativePathForFileURL:localDocumentURL];
    OBASSERT(intendedLocalRelativePath == nil || ![localRelativePath isEqualToString:intendedLocalRelativePath], @"Should be nil or a different path");
    OBASSERT(intendedLocalRelativePath == nil || [[localRelativePath pathExtension] isEqualToString:[intendedLocalRelativePath pathExtension]]);

    _localRelativePath = [localRelativePath copy];
    OBASSERT([_localRelativePath isEqual:snapshot.localRelativePath]);
    
    // The current URL of the document we represent. This might not yet exist if the download got killed off before we could make the stub.
    _localDocumentURL = [container _URLForLocalRelativePath:_localRelativePath isDirectory:snapshot.directory];

    // Start out with the right content greediness.
    _contentsRequested = container.automaticallyDownloadFileContents;

    DEBUG_SYNC(1, @"starting with snapshot %@", [snapshot shortDescription]);
    
    return self;
}

// Used when the container agent has detected a new local file. The returned instance will have a local snapshot, but nothing will exist on the server.
- (id)initWithNewLocalDocumentURL:(NSURL *)localDocumentURL container:(OFXContainerAgent *)container error:(NSError **)outError;
{
    return [self initWithNewLocalDocumentURL:localDocumentURL asConflictGeneratedFromFileItem:nil coordinator:nil container:container error:outError];
}

- (id)initWithNewLocalDocumentURL:(NSURL *)localDocumentURL asConflictGeneratedFromFileItem:(OFXFileItem *)originalItem coordinator:(NSFileCoordinator *)coordinator container:(OFXContainerAgent *)container error:(NSError **)outError;
{
    OBPRECONDITION(!originalItem || coordinator, "If an original item is specified, we must also get a file coordinator that is already reading it"); // We get passed down a file coordinator that was involved in reading the (now moved) localDocumentURL or the original item and reuse it here to avoid deadlock.
    
    NSString *identifier = OFXMLCreateID();
    NSURL *localSnapshotURL = _makeLocalSnapshotURL(container, identifier);
    NSString *localRelativePath = [container _localRelativePathForFileURL:localDocumentURL];
    
    // Immediately create our snapshot so that we can check if further edits should provoke another upload.
    OFXFileSnapshot *snapshot = [[OFXFileSnapshot alloc] initWithTargetLocalSnapshotURL:localSnapshotURL forNewLocalDocumentAtURL:localDocumentURL localRelativePath:localRelativePath intendedLocalRelativePath:originalItem.intendedLocalRelativePath coordinator:coordinator error:outError];
    if (!snapshot)
        return nil;
    OBASSERT(snapshot.remoteState.missing);
    
    // Move it from its temporary location to the real location immediately.
    OBASSERT(OFNOTEQUAL(snapshot.localSnapshotURL, localSnapshotURL));
    if (![[NSFileManager defaultManager] moveItemAtURL:snapshot.localSnapshotURL toURL:localSnapshotURL error:outError])
        return nil;
    
    [snapshot didMoveToTargetLocalSnapshotURL:localSnapshotURL];
    
    if (!(self = [self _initWithIdentifier:identifier snapshot:snapshot localDocumentURL:localDocumentURL intendedLocalRelativePath:originalItem.intendedLocalRelativePath container:container error:outError]))
        return nil;
    
    OBPOSTCONDITION([self _checkInvariants]);
    return self;
}

// Used when a new item has appeared in the remote container
- (id)initWithNewRemoteSnapshotAtURL:(NSURL *)remoteSnapshotURL container:(OFXContainerAgent *)container filePresenter:(id <NSFilePresenter>)filePresenter connection:(ODAVConnection *)connection error:(NSError **)outError;
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
    
    if (!(self = [self _initWithIdentifier:fileIdentifier snapshot:snapshot localDocumentURL:localDocumentURL intendedLocalRelativePath: nil container:container error:outError]))
        return nil;
    
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

    if (!(self = [self _initWithIdentifier:[localSnapshotURL lastPathComponent] snapshot:snapshot localDocumentURL:localDocumentURL intendedLocalRelativePath: nil container:container error:outError]))
        return nil;
        
    OBPOSTCONDITION([self _checkInvariants]);
    return self;
}

@synthesize container = _weak_container;

- (NSUInteger)version;
{
    OBPRECONDITION(_snapshot);
    
    return _snapshot.version;
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

- (NSString *)intendedLocalRelativePath;
{
    return _snapshot.intendedLocalRelativePath;
}

- (NSString *)requestedLocalRelativePath;
{
    OBPRECONDITION(_localRelativePath);
    return _localRelativePath;
}

- (OFXRecentError *)mostRecentTransferError;
{
    return [_recentErrors lastObject];
}

- (void)addRecentTransferErrorsByLocalRelativePath:(NSMutableDictionary <NSString *, NSArray <OFXRecentError *> *> *)recentErrorsByLocalRelativePath;
{
    if ([_recentErrors count] == 0)
        return;
        
    // Remove any stale errors
    NSDate *keepErrorsAfterDate = [NSDate dateWithTimeIntervalSinceNow:-[OFXFileItemRecentErrorExpirationTimeInterval doubleValue]];
    OFXRecentError *recentError;
    while ((recentError = [_recentErrors firstObject])) {
        if ([recentError.date isAfterDate:keepErrorsAfterDate])
            break;
        [_recentErrors removeObjectAtIndex:0];
    }
    
    if ([_recentErrors count] == 0) {
        _recentErrors = nil;
    } else {
        [recentErrorsByLocalRelativePath setObject:[_recentErrors copy] forKey:_localRelativePath];
    }
}

- (void)clearRecentTransferErrors;
{
    _recentErrors = nil;
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

// If this a user-indented move, we expect that our container will ask us to upload a snapshot after this.
- (void)markAsMovedToURL:(NSURL *)localDocumentURL source:(OFXFileItemMoveSource)source;
{
    OBPRECONDITION([localDocumentURL isFileURL]);
    OBPRECONDITION(![localDocumentURL isFileReferenceURL]);
    OBPRECONDITION(OFNOTEQUAL(_localDocumentURL, localDocumentURL) || (source == OFXFileItemMoveSourceLocalUser && self.localState.autoMoved)); // Might be finalizing a conflict name via -_finalizeConflictNamesForFilesIntendingToBeAtRelativePaths:
    OBPRECONDITION(self.localState.missing || OFURLIsStandardizedOrMissing(localDocumentURL)); // Allow for missing URLs since it might get moved again quickly or deleted
    
    OFXContainerAgent *container = _weak_container;
    if (!container) {
        OBASSERT_NOT_REACHED("Move notification not processed before invalidation?");
        return;
    }
    
    _localRelativePath = [[container _localRelativePathForFileURL:localDocumentURL] copy];
    _localDocumentURL = [localDocumentURL copy];
    DEBUG_SYNC(2, @"File item moved, -didMoveToURL: %@ / %@", _localRelativePath, _localDocumentURL);

    // Record the updated relative path in the snapshot's Version.plist so that, if we exit, we can still associate this file item's snapshot with the proper filesystem object the next time we run.
    __autoreleasing NSError *error;
    if (![_snapshot markAsLocallyMovedToRelativePath:_localRelativePath isAutomaticMove:(source == OFXFileItemMoveSourceAutomatic) error:&error]) {
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
- (OFXFileSnapshotTransfer *)prepareUploadTransferWithConnection:(ODAVConnection *)connection error:(NSError **)outPrepareUploadError;
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
    OBASSERT(remoteState.missing || localState.edited || localState.userMoved, @"Why are we uploading, otherwise?");

    NSURL *currentRemoteSnapshotURL = _makeRemoteSnapshotURL(containerAgent, connection, self, _snapshot);
    
    DEBUG_CONTENT(1, @"Starting upload with content \"%@\"", OFXLookupDisplayNameForContentIdentifier(_snapshot.currentContentIdentifier));
    
    OFXFileSnapshotUploadTransfer *uploadTransfer;
    if (localState.missing && localState.userMoved)
        // Doing a rename of a file that hasn't been downloaded. In this case, we don't have a local copy of the document to use as the basis for an upload (and there is no chance of its contents having been changed).
        uploadTransfer = [[OFXFileSnapshotUploadRenameTransfer alloc] initWithConnection:connection currentSnapshot:_snapshot remoteTemporaryDirectory:containerAgent.remoteTemporaryDirectory currentRemoteSnapshotURL:currentRemoteSnapshotURL error:outPrepareUploadError];
    else
        uploadTransfer = [[OFXFileSnapshotUploadContentsTransfer alloc] initWithConnection:connection currentSnapshot:_snapshot forUploadingVersionOfDocumentAtURL:_localDocumentURL localRelativePath:_localRelativePath remoteTemporaryDirectory:containerAgent.remoteTemporaryDirectory error:outPrepareUploadError];
    if (!uploadTransfer)
        return nil;
    uploadTransfer.debugName = self.debugName;

    __weak OFXFileSnapshotUploadTransfer *weakTransfer = uploadTransfer;
    
    [self _transferStarted:uploadTransfer];

    uploadTransfer.transferProgress = ^{
        [self _updatedMetadata];
    };
    uploadTransfer.commit = ^BOOL(NSError **outCommitError){
#ifdef OMNI_ASSERTIONS_ON
        BOOL movedWhileUploading = NO;
        BOOL moveWhileUploadingIsAutomatic = NO;
#endif
        
        // Commit the upload remotely and locally.
        {
            OFXFileSnapshotUploadTransfer *strongTransfer = weakTransfer;
            if (!strongTransfer) {
                OBASSERT_NOT_REACHED("Shouldn't be invoked after transfer is deallocated");
                if (outCommitError)
                    *outCommitError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
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
            NSURL *targetRemoteSnapshotURL = _makeRemoteSnapshotURL(containerAgent, connection, self, uploadingSnapshot);
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
                
                if (outCommitError)
                    *outCommitError = moveError;
                OBChainError(outCommitError);
                return NO;
            }
            
            if (currentRemoteSnapshotURL) {
                /*
                 
                 Delete the old version on the server. Don't need to first move it into the tmp directory since even if the delete is only partially successful, the newer version will supercede the old one. We do need to signal conflict if this delete fails, though, since it means that another client has moved the version forward on us (or deleted the file).
                
                 Consider:
                 - client A and B both have version 0
                 - A quickly updates the file to version 1 and then 2, deleting versions 0 and 1.
                 - B updates the file and attempts to write version 1 (succeeds, but it is superceded now) and removes version 0 (and gets a 404).
                 
                 When deleting superceded old versions, this also means we need to oldest first, not just in any random order as long as they are superceded, otherwise, we could have:
                 
                 - A and B at zero
                 - A quickly goes to 3 and for whatever reason, we delete old versions in the order 2, 1, 0
                 - A deletes 1
                 - B tries to write 1 (succeeds)
                 - B deletes zero (succeeds)
                 - A deletes 0 (fails and is confused since B was really the conflicting editor)
                 
                 TODO: Maybe all the above does mean we need to move the old version into tmp before attempting to delete it. Say A fails to delete version 0 on its update of 0->1. Then when it updates 1->2 it will attempt to clean up 0 too. We could race on the deletion such that B's delete succeeds and A's fails. This seems like a pretty unlikely thing to happen, but it bears thinking on. I'm loathe to add an extra MOVE on each file update if we don't really need it.
                 */
                
                __block NSError *deleteError;
                
                if (containerAgent.clientParameters.deletePreviousFileVersionAfterNewVersionUploaded) {
                    ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done) {
                        [connection deleteURL:currentRemoteSnapshotURL withETag:nil completionHandler:^(NSError *errorOrNil) {
                            deleteError = errorOrNil;
                            done();
                        }];
                    });
                }
                
                if (deleteError) {
                    if ([deleteError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND]) {
                        // If we expected vN to be there and some other client has moved us on to vN+1, we just wrote a superceded version. Need to generate a conflict. This stale version will get cleaned up on a future scan.
                        [containerAgent _fileItemDidDetectUnknownRemoteEdit:self];
                    } else {
                        // We might have lost a network connection (Yosemite seems particularly prone to this). At any rate, by this point we've successfully written the new version so this isn't a hard error. Let's try scanning again, but don't make this a self conflict by having written a new snapshot to the server and then *not* recording that here. <bug:///109269> (Unassigned: Please don't interpret network loss as a conflict error [distance, ssl])
                        // This stale version will get cleaned up on a future scan.
                        [deleteError log:@"Error removing original remote snapshot at %@ while uploading new version. Network trouble?", currentRemoteSnapshotURL];
                        deleteError = nil;
                    }
                }
                if (deleteError) {
                    cleanup();

                    if (outCommitError)
                        *outCommitError = deleteError;
                    OBChainError(outCommitError);
                    return NO;
                }
            }
            
            // The uploading snapshot is based on our _snapshot when we started the upload. We might have been moved since then! Make sure we don't clobber this in the new snapshot -- we want to start a new upload if this happens. We already do (later on in the commit) check if the file has changed from this state for an edit upload.
            // We check !autoMoved here so that we don't mess up on -[OFXRenameTestCase testRenameOfNewLocalFileWhileUploading]. In this case, when the move happens, our current snapshot still has remoteState of missing. In this case, we don't mark the local snapshot as having been moved since there is nothing on the server to update. But once we get here, we know that there is. Instead of checking !autoMoved, we could maybe check userMoved as wel as checking if the snapshot was previously missing on the server.
            if (OFNOTEQUAL(_snapshot.localRelativePath, uploadingSnapshot.localRelativePath) && (_snapshot.localState.autoMoved == NO) /* Not checking userMoved -- see above */) {
#ifdef OMNI_ASSERTIONS_ON
                movedWhileUploading = YES;
                moveWhileUploadingIsAutomatic = NO;
#endif
                __autoreleasing NSError *markError;
                if (![uploadingSnapshot markAsLocallyMovedToRelativePath:_snapshot.localRelativePath isAutomaticMove:NO error:&markError]) {
                    [markError log:@"Error marking uploading snapshot as moved to %@", _snapshot.localRelativePath];
                    cleanup();
                    if (outCommitError)
                        *outCommitError = markError;
                    OBChainError(outCommitError);
                    return NO;
                }
            }
            
            OBASSERT(![_snapshot.localSnapshotURL isEqual:uploadingSnapshot.localSnapshotURL]);
            __autoreleasing NSError *replaceError;
            if (![[NSFileManager defaultManager] replaceItemAtURL:_snapshot.localSnapshotURL withItemAtURL:uploadingSnapshot.localSnapshotURL backupItemName:nil options:0 resultingItemURL:NULL error:&replaceError]) {
                [replaceError log:@"Error replacing %@ with %@", _snapshot.localSnapshotURL, uploadingSnapshot.localSnapshotURL];
                if (outCommitError)
                    *outCommitError = replaceError;
                OBChainError(outCommitError);
                cleanup();
                OBFinishPortingWithNote("<bug:///147843> (iOS-OmniOutliner Engineering: Figure out how to test file replacement error in -[OXFileItem prepareUploadTransferWithConnection:error:])"); // Not sure how to provoke this case to test it or what could be happening.
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
            if (moveWhileUploadingIsAutomatic)
                OBASSERT(uploadedSnapshot.localState.autoMoved);
            else
                OBASSERT(uploadedSnapshot.localState.userMoved);
            OBASSERT(uploadedSnapshot.remoteState.normal);
        } else {
            // Regular ol' upload, or upload of a new conflict version
            OBASSERT(uploadedSnapshot.localState.normal || uploadedSnapshot.localState.onlyAutoMoved);
            OBASSERT(uploadedSnapshot.remoteState.normal);
        }
#endif
        
        DEBUG_TRANSFER(1, @"switching to uploaded snapshot %@", [uploadedSnapshot shortDescription]);
        DEBUG_TRANSFER(2, @"  previously %@", [_snapshot shortDescription]);
        DEBUG_CONTENT(1, @"Commit upload with content \"%@\"", OFXLookupDisplayNameForContentIdentifier(_snapshot.currentContentIdentifier));
        _snapshot = uploadedSnapshot;
        
        return YES;
    };
    
    [uploadTransfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
        OBINVARIANT([self _checkInvariants]);
        
        OBASSERT(self.isUploading);
        [self _transferFinished:transfer withError:errorOrNil];
        
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
            }
        }
        return errorOrNil;
    }];

    return uploadTransfer;
}

// Downloads the metadata from the remote snapshot (which is expected to have changed), and possibly the contents. If the contents are downloaded, this will unpack it into the proper structure and update the local published document.
- (OFXFileSnapshotTransfer *)prepareDownloadTransferWithConnection:(ODAVConnection *)connection filePresenter:(id <NSFilePresenter>)filePresenter;
{
    OBPRECONDITION([self _checkInvariants]);
    OBPRECONDITION(_snapshot); // should at least have a placeholder
    OBPRECONDITION(_currentTransfer == nil, "Shouldn't start a download while still doing another transfer");
    OBINVARIANT([self _checkInvariants]);
    OBPRECONDITION(_snapshot.localState.missing || _snapshot.remoteState.edited || _snapshot.remoteState.userMoved);
    OBPRECONDITION(filePresenter);
    
    DEBUG_TRANSFER(2, @"Starting download with _contentsRequested %d, localState %@", _contentsRequested, _snapshot.localState);
    
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
        targetRemoteSnapshotURL = _makeRemoteSnapshotURLWithVersion(container, connection, self, _newestRemoteVersion);
    } else {
        OBASSERT(_newestMissingVersion == OFXFileItemUnknownVersion || _newestMissingVersion < _snapshot.version);
        targetRemoteSnapshotURL = _makeRemoteSnapshotURL(container, connection, self, _snapshot);
    }
    
    OBASSERT([_snapshot.localSnapshotURL isEqual:targetLocalSnapshotURL]);
    OBASSERT(_snapshot.version < _newestRemoteVersion || (_snapshot.localState.missing && _contentsRequested && _snapshot.version == _newestRemoteVersion), "Should be downloading a new snapshot, or the contents for our current version (only if we don't have those contents already");
    
    // Pick a contents download location (meaning we will grab the contents instead of just metadata) if someone asked us to or our previous snapshot had contents.
    NSURL *localTemporaryDocumentContentsURL;
    if ((_contentsRequested || (_snapshot.localState.missing == NO))) {
        __autoreleasing NSError *error;
        localTemporaryDocumentContentsURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:_localDocumentURL allowOriginalDirectory:NO error:&error];
        if (!localTemporaryDocumentContentsURL) {
            // TODO: Bubble up error
            NSLog(@"Error finding temporary URL for downloading %@: %@", [self shortDescription], [error toPropertyList]);
            return nil;
        }
        DEBUG_TRANSFER(1, @"  will download contents to %@", localTemporaryDocumentContentsURL);
    }

    DEBUG_CONTENT(2, @"Starting download with local content \"%@\"", OFXLookupDisplayNameForContentIdentifier(_snapshot.currentContentIdentifier));
    
    OFXFileSnapshotDownloadTransfer *downloadTransfer = [[OFXFileSnapshotDownloadTransfer alloc] initWithConnection:connection remoteSnapshotURL:targetRemoteSnapshotURL localTemporaryDocumentContentsURL:localTemporaryDocumentContentsURL currentSnapshot:_snapshot];
    downloadTransfer.debugName = self.debugName;

    __weak OFXFileSnapshotDownloadTransfer *weakTransfer = downloadTransfer;

    [self _transferStarted:downloadTransfer];
    
    downloadTransfer.started = ^{
        OFXFileSnapshotDownloadTransfer *strongTransfer = weakTransfer;
        if (strongTransfer.isContentDownload) {
            // Looks like we do need to report a download in our metadata (_makeMetadata avoids doing so until this is YES).
            [self _updatedMetadata];
        }
    };
    downloadTransfer.transferProgress = ^{
        [self _updatedMetadata];
    };
    downloadTransfer.commit = ^BOOL(NSError **outError){
        OBASSERT(self.hasBeenLocallyDeleted == NO);

        OFXFileSnapshotDownloadTransfer *strongTransfer = weakTransfer;
        if (!strongTransfer) {
            OBASSERT_NOT_REACHED("Shouldn't be invoked after transfer is deallocated");
            return NO;
        }

        // For very quick edits, we might not know that the local file is edited (the file presenter notification might be in flight or our rescan request might still be in flight). So, while we could maybe check our localState here, we can't depend on it and actually need to look at the filesystem state (inside file coordination).

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
        NSMutableArray <NSURL *> *writingURLs = [NSMutableArray arrayWithObjects:_localDocumentURL, nil];

#ifdef OMNI_ASSERTIONS_ON
        BOOL hadLocalMove = NO;
#endif
        // If we have a local rename initiated by the user, don't accidentally revert it. We'll push it to the server soon, presumably.
        // If we have a local automove and the incoming snapshot isn't a move, keep that too (just a content edit of some conflict version). But if the relative path is changing, the user may have resolved a conflict between files on another client and we are downloading that resolution.
        if (_snapshot.localState.userMoved || (_snapshot.localState.autoMoved && [downloadedSnapshot.localRelativePath isEqualToString:_snapshot.intendedLocalRelativePath])) {
#ifdef OMNI_ASSERTIONS_ON
            hadLocalMove = YES;
#endif
            __autoreleasing NSError *renameError;
            if (![downloadedSnapshot markAsLocallyMovedToRelativePath:_snapshot.localRelativePath isAutomaticMove:_snapshot.localState.autoMoved error:&renameError]) {
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
        __block NSError *strongError = nil;

        [coordinator prepareForReadingItemsAtURLs:@[] options:0 /* provoke save since we are maybe about to write to the file */
                               writingItemsAtURLs:writingURLs options:NSFileCoordinatorWritingForMerging /* there is no "I might not write option" so other presenters are going to get a relinquish no matter what */
                                            error:outError byAccessor:
         ^(void (^completionHandler)(void)){
             __autoreleasing NSError *error = nil;
             success = [self _performDownloadCommitToURL:updatedLocalDocumentURL localTemporaryDocumentContentsURL:localTemporaryDocumentContentsURL targetLocalSnapshotURL:targetLocalSnapshotURL container:container downloadedSnapshot:downloadedSnapshot coordinator:coordinator downloadContents:downloadContents isMove:moved error:&error];
             if (!success) {
                 strongError = error;
             }

             if (completionHandler)
                 completionHandler();
         }];

        if (!success) {
            if (outError) {
                *outError = strongError;
            }
            cleanup();
            return NO;
        }

        OBASSERT(!hadLocalMove || _snapshot.localState.userMoved || _snapshot.localState.autoMoved, @"If we had a local move, make sure to preserve that to be uploaded");
        
        return YES;
    };
    
    [downloadTransfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
        OBINVARIANT([self _checkInvariants]);
        
        OBASSERT(self.isDownloading == YES);
        [self _transferFinished:transfer withError:errorOrNil];
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
    
    return downloadTransfer;
}

- (BOOL)_validateDownloadCommitToURL:(NSURL *)_updatedLocalDocumentURL contentSame:(BOOL)contentSame coordinator:(NSFileCoordinator *)coordinator error:(NSError **)outValidateError;
{
    // TODO: Validate that the updated local document URL is missing too?
    
    // We pass NSFileCoordinatorWritingForMerging in the 'prepare' in our caller, which should force other presenters to relinquish and save, but experimentally it does not. We have to do an explicit read withChanges:YES here to provoke -[OFXTestSaveFilePresenter savePresentedItemChangesWithCompletionHandler:] in -[OFXConflictTestCase testIncomingCreationVsLocalAutosaveCreation].
    return [coordinator readItemAtURL:_localDocumentURL withChanges:YES error:outValidateError byAccessor:^BOOL(NSURL *newReadingURL, NSError *__autoreleasing *outError) {
        if (self.localState.missing) {
            // If this is the first download of a new file, and something is sleeping in our bed, then we may have created a local document while the download was going on or while we were offline. Or perhaps two files on the server have specified they want the same location and the user san't resolved the conflict yet. We cannot publish the content from this download to the original URL, but we can publish it to a automatically chosen conflict URL.
            __autoreleasing NSError *existsError;
            if ([[NSFileManager defaultManager] attributesOfItemAtPath:[newReadingURL path] error:&existsError]) {
                OFXContainerAgent *container = _weak_container;
                OBASSERT(container);
                
                __autoreleasing NSError *conflictError;
                if (![container _relocateFileAtURL:_localDocumentURL toMakeWayForFileItem:self coordinator:coordinator error:&conflictError]) {
                    [conflictError log:@"Error moving %@ out of the way for incoming document %@", _localDocumentURL, [self shortDescription]];
                    if (outError)
                        *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
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
            OBASSERT(self.localState.normal || self.localState.userMoved || self.localState.autoMoved);
            
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
    OBASSERT(_snapshot.localState.missing || _snapshot.remoteState.edited || _snapshot.remoteState.userMoved);

    BOOL contentSame = [downloadedSnapshot hasSameContentsAsSnapshot:_snapshot];
    DEBUG_CONTENT(1, @"Commit, has same %d", contentSame);
    if (!contentSame) {
        DEBUG_CONTENT(1, @"downloadedSnapshot %@", downloadedSnapshot.infoDictionary);
        DEBUG_CONTENT(1, @"_snapshot %@", _snapshot.infoDictionary);
    }
    
    __autoreleasing NSError *validateDownloadError;
    if (![self _validateDownloadCommitToURL:updatedLocalDocumentURL contentSame:contentSame coordinator:coordinator error:&validateDownloadError]) {
        if (outError)
            *outError = validateDownloadError;
        OBChainError(outError);
        return NO;
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

- (OFXFileSnapshotTransfer *)prepareDeleteTransferWithConnection:(ODAVConnection *)connection filePresenter:(id <NSFilePresenter>)filePresenter;
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
    
    OFXFileSnapshotDeleteTransfer *deleteTransfer = [[OFXFileSnapshotDeleteTransfer alloc] initWithConnection:connection fileIdentifier:_identifier snapshot:_snapshot remoteContainerURL:container.remoteContainerDirectory remoteTemporaryDirectoryURL:container.remoteTemporaryDirectory];
    deleteTransfer.debugName = self.debugName;
    
    __weak OFXFileSnapshotDeleteTransfer *weakTransfer = deleteTransfer;
    
    [self _transferStarted:deleteTransfer];
    
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
    
    deleteTransfer.commit = ^BOOL(NSError **outError){
        OBASSERT(self.hasBeenLocallyDeleted == YES, @"Cannot resurrect now that the delete has happened on the server"); //
        
        OFXFileSnapshotDeleteTransfer *strongTransfer = weakTransfer;
        if (!strongTransfer) {
            OBASSERT_NOT_REACHED("Shouldn't be invoked after transfer is deallocated");
            return NO;
        }
        
        [_snapshot markAsRemotelyDeleted:outError];
        return removeSnapshot(outError);
    };
    
    [deleteTransfer addDone:^NSError *(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil){
        OBASSERT(self.isDeleting);
        [self _transferFinished:transfer withError:errorOrNil];
        
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
    
    return deleteTransfer;
}

// We've noticed a delete from the server and need to remove our published document
- (BOOL)handleIncomingDeleteWithFilePresenter:(id <NSFilePresenter>)filePresenter error:(NSError **)outIncomingDeleteError;
{
    // We might have a pending transfer. If we get here, it should end up failing due to the incoming delete (the validateCommit blocks on those transfers check for deletion and bail).
    //OBPRECONDITION(self.isDownloading == NO);
    //OBPRECONDITION(self.isUploading == NO);
    OBPRECONDITION(self.hasBeenLocallyDeleted == NO);
    
    OBINVARIANT([self _checkInvariants]);
    
    if (![self markAsRemotelyDeleted:outIncomingDeleteError])
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
        BOOL success = [coordinator writeItemAtURL:_localDocumentURL withChanges:YES error:&error byAccessor:^BOOL(NSURL *newURL, NSError **outWriteItemError) {
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
            return [coordinator removeItemAtURL:newURL error:outWriteItemError byAccessor:^BOOL(NSURL *newURL2, NSError **outError) {
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
                if (outIncomingDeleteError)
                    *outIncomingDeleteError = error;
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
            if (outIncomingDeleteError)
                *outIncomingDeleteError = removeError;
            
            return NO; // ... we could maybe let this slide if the removeError as NSPOSIXErrorDomain/ENOENT, but since we shouldn't get here, lets just fail.
        }
    }
    
    TRACE_SIGNAL(OFXFileItem.incoming_delete.removed_local_snapshot);
    
    // We don't remove our metadata here; we expect our container to call -invalidate next.
    return YES;
}

- (NSURL *)fileURLForConflictVersion;
{
    OFCreateRegularExpression(ConflictRegularExpression, NSLocalizedStringFromTableInBundle(@"^(.*) \\(conflict( [0-9+])? from .*\\)$", @"OmniFileExchange", OMNI_BUNDLE, @"Conflict file regular expression"));

    NSURL *folderURL = [_localDocumentURL URLByDeletingLastPathComponent];
    NSString *lastComponent = [_localDocumentURL lastPathComponent];
    NSString *baseName = [lastComponent stringByDeletingPathExtension];
    NSString *pathExtension = [lastComponent pathExtension];

    // Since we make conflict names locally and independently on each host now, don't use our local computer name, but instead the computer that last edited the file.
    NSString *userName = _snapshot.lastEditedUser;
    NSString *hostName = _snapshot.lastEditedHost;
    
    NSString *editName;
    if (userName && hostName)
        editName = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ on %@", @"OmniFileExchange", OMNI_BUNDLE, @"Conflict last edit file format"), userName, hostName];
    else if (userName)
        editName = userName;
    else
        editName = hostName;
    OBASSERT(![NSString isEmptyString:editName]);
    
    NSString *debugName = self.debugName; // Avoid spurious extra conflicts due to having the same host name in unit tests
    if (![NSString isEmptyString:debugName])
        editName = [editName stringByAppendingFormat:@"-%@", debugName];

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
            conflictBaseName = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ (conflict from %@)", @"OmniFileExchange", OMNI_BUNDLE, @"Conflict file format"), baseName, editName];
        else
            conflictBaseName = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ (conflict %lu from %@)", @"OmniFileExchange", OMNI_BUNDLE, @"Conflict file format"), baseName, conflictIndex, editName];
        candidateURL = [folderURL URLByAppendingPathComponent:[conflictBaseName stringByAppendingPathExtension:pathExtension]];
    } while ([[self container] fileItemWithURL:candidateURL]);

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
    
    if (localState.deleted == NO) {
        metadata.fileURL = _localDocumentURL; // TODO: Needs synchronize with NSFilePresenter messages
        
        if (self.localState.autoMoved) {
            // Our _localRelativePath is the automatically chosen location.
            NSURL *intendedFileURL = _localDocumentURL;
            
            for (NSString *component in [_localRelativePath pathComponents]) {
                (void)component;
                intendedFileURL = [intendedFileURL URLByDeletingLastPathComponent];
            }
            intendedFileURL = [intendedFileURL URLByAppendingPathComponent:_snapshot.intendedLocalRelativePath isDirectory:_snapshot.isDirectory];
            metadata.intendedFileURL = intendedFileURL;
        } else
            metadata.intendedFileURL = _localDocumentURL;
    }
    metadata.directory = _snapshot.directory;
    
    
    DEBUG_METADATA(1, @"  Local state %@", localState);
    DEBUG_METADATA(1, @"  Remote state %@", remoteState);
    
    metadata.totalSize = _snapshot.totalSize;
    
    if (remoteState.missing || localState.edited || (localState.userMoved && !localState.missing)) { // auto-moves don't need to be uploaded
        metadata.uploaded = NO;
        metadata.percentUploaded = 0;
    } else if (localState.normal || localState.missing || localState.autoMoved) {
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
    
    OBASSERT(remoteState.autoMoved == NO, "The server only has user intended moves");
    if (localState.missing || remoteState.edited || remoteState.userMoved) {
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
    
    metadata.fileModificationDate = snapshot.fileModificationDate;
    metadata.inode = snapshot.inode;
    
    return metadata;
}

- (NSURL *)_intendedLocalDocumentURL;
{
    OFXContainerAgent *container = _weak_container;
    OBASSERT(container);
    return [container _URLForLocalRelativePath:self.intendedLocalRelativePath isDirectory:_snapshot.directory];
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

- (void)_updatedMetadata;
{
    OFXContainerAgent *container = _weak_container;
    if (!container) {
        // This can happen when a transfer is scheduled to start and then we stop the agent.
        return;
    }
    [container _fileItemNeedsMetadataUpdated:self];
}

- (void)_transferStarted:(OFXFileSnapshotTransfer *)transfer;
{
    OBPRECONDITION(_currentTransfer == nil, @"Starting another transfer with out the previous one finishing?");
    OBPRECONDITION(transfer);
    
    _currentTransfer = transfer;
    [self _updatedMetadata];
}

- (void)_transferFinished:(OFXFileSnapshotTransfer *)transfer withError:(NSError *)errorOrNil;
{
    // The caller does a read of a __weak local to pass as our argument
    if (!transfer) {
        OBASSERT_NOT_REACHED("Shouldn't be invoked after transfer is deallocated");
        return;
    }
    if (_currentTransfer == transfer) {
        _currentTransfer = nil;
        
        // Not currently clearing errors on success, though that might be reasonable (unclear if we could have upload specific errors that would get spuriously cleared by a successful download).
        if (errorOrNil) {
            if (!_recentErrors)
                _recentErrors = [[NSMutableArray alloc] init];
            [_recentErrors addObject:[OFXRecentError recentError:errorOrNil withDate:[NSDate date]]];
        }
        
        [self _updatedMetadata];
    } else {
        OBASSERT_NOT_REACHED("Started another transfer before a previous transfer finished?");
    }
}

// Assumes the passed in coordinator has a proper file presenter and has been prepared or otherwise is ready to write to the localDocumentURL (nested write).
- (BOOL)_publishContentsFromTemporaryDocumentURL:(NSURL *)temporaryDocumentURL toLocalDocumentURL:(NSURL *)localDocumentURL snapshot:(OFXFileSnapshot *)snapshot coordinator:(NSFileCoordinator *)coordinator error:(NSError **)outPublishContentsError;
{
    OBPRECONDITION(temporaryDocumentURL);
    OBPRECONDITION([temporaryDocumentURL checkResourceIsReachableAndReturnError:NULL]);
    OBPRECONDITION(localDocumentURL);
    OBPRECONDITION(snapshot);
    OBPRECONDITION(snapshot.localState.deleted == NO);
    OBPRECONDITION(coordinator);
    
    DEBUG_TRANSFER(1, @"Publishing contents from %@ to %@", [snapshot shortDescription], localDocumentURL);
    
    static BOOL isRunningUnitTests = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isRunningUnitTests = (getenv("OFXTestsRunning") != NULL);
    });
    
    // We should be able to pass withChanges=NO here since our 'prepare' already did NSFileCoordinatorWritingForMerging and we don't want to force save again. But, experimentally this doesn't work. We have to pass withChanges:YES to provoke -[OFXTestSaveFilePresenter savePresentedItemChangesWithCompletionHandler:] in -[OFXConflictTestCase testIncomingCreationVsLocalAutosaveCreation].
    return [coordinator writeItemAtURL:localDocumentURL withChanges:YES error:outPublishContentsError byAccessor:^BOOL(NSURL *newWriteURL, NSError **outWriteItemError) {
        
        /*
         HACK HACK HACK: Radar 13167947: Coordinated write to flat file will sometimes not reload NSDocument
         
         If we are too fast here, NSDocument will receive:
         
         relinquish to writer
         reacquire from writer
         did change
         
         Which it seems to ignore (at least for flat files) <bug:///85578> (Apps with open, flat-file documents do not update to synced changes)
         
         If we delay here, they'll get the 'did change' w/in the writer block. The amount of time we wait is obviously fragile. Hopefully this bug will get fixed in the OS or we'll find a better workaround.
         */
        
        DEBUG_TRANSFER(2, @"  newWriteURL %@", newWriteURL);

        BOOL writeURLIsFlatFile;
        __autoreleasing NSNumber *writeURLIsDirectoryNumber = nil;
        __autoreleasing NSError *resourceError = nil;
        if (![newWriteURL getResourceValue:&writeURLIsDirectoryNumber forKey:NSURLIsDirectoryKey error:&resourceError]) {
            writeURLIsFlatFile = YES; // That is, we don't need the workaround
            if (![resourceError causedByMissingFile])
                NSLog(@"Unable to determine if %@ is a directory: %@", newWriteURL, [resourceError toPropertyList]);
        } else
            writeURLIsFlatFile = ![writeURLIsDirectoryNumber boolValue];
        DEBUG_TRANSFER(2, @"  writeURLIsFlatFile %d, snapshot.directory %d", writeURLIsFlatFile, snapshot.directory);
        
        if ((!snapshot.directory || writeURLIsFlatFile) && !isRunningUnitTests) {
            sleep(1);
        }
        
        // Create the folder for this item, which might be the first thing in the folder that has been downloaded
        // It would be nice to have a version of this that will refuse to create the *entire* path. We do *NOT* want to create the account documents directory. There is something terrible going on if that is missing, and if we create it, that could be interpreted as deleting all the other documents in the account.
        if (![[NSFileManager defaultManager] createDirectoryAtURL:[newWriteURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:outWriteItemError]) {
            OBChainError(outWriteItemError);
            return NO;
        }
        
        BOOL (^tryReplace)(NSError **outTryReplaceError) = ^BOOL(NSError **outTryReplaceError){
            DEBUG_TRANSFER(2, @"  replace %@ with %@", newWriteURL, temporaryDocumentURL);
            if ([[NSFileManager defaultManager] replaceItemAtURL:newWriteURL withItemAtURL:temporaryDocumentURL backupItemName:nil options:0 resultingItemURL:NULL error:outTryReplaceError])
                return YES;
            OBChainError(outTryReplaceError);
            return NO;
        };
        
        __autoreleasing NSError *replaceError;
        BOOL replaced = tryReplace(&replaceError);
        if (!replaced) {
            if ([replaceError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EACCES]) {
                DEBUG_TRANSFER(2, @"  fixing permissions");

                // Some joker (probably me), may have marked a file read-only to see if it works. We don't sync permissions, so if we have an incoming edit of a file that is locally read-only, mark it and its parent directory as read-write.
                [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@(0700)} ofItemAtPath:[[newWriteURL URLByDeletingLastPathComponent] path] error:NULL]; // Make the folder writable
                
                NSNumber *filePermissions = _snapshot.isDirectory ? @(0700) : @(0600);
                [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:filePermissions} ofItemAtPath:[newWriteURL path] error:NULL]; // Make the file itself writable (and executable if it is a folder)
                
                replaceError = nil;
                replaced = tryReplace(&replaceError);
            }
        }
        if (!replaced) {
            if (outWriteItemError)
                *outWriteItemError = replaceError;
            OBChainError(outWriteItemError);
            return NO;
        }
        
        OFXNoteContentChanged(self, newWriteURL);
        
        DEBUG_TRANSFER(2, @"  did publish to %@", newWriteURL);
        if (![snapshot didPublishContentsToLocalDocumentURL:newWriteURL error:outWriteItemError]) {
            OBChainError(outWriteItemError);
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
     
     Our strategy is that the server copy wins the edit of the exiting file identifier (since its contents are on the server already). We also want the user to have some indication that their edits ended up in a conflict version, so we need to:
     
     * Make a new file with the user's existing edits, with a new file identifier, the same desired URL, but an automatically chosen conflict name. Do this by moving our local path to the new conflict name, using file coordination so that open NSDocument/UIDocument observers know that they should be editing the new conflict copy.
     * Take care that our container agent doesn't queue up a move command to send to the server!
     * Change our identifier(!)
     * Inform our container agent that our identifier has changed
     * Become locally missing
     * Return success (and then later we should notice that the document index has multiple claims on a file and so the newly published file should also get renamed to have a conflict marker).
     */
    
    OFXContainerAgent *container = _weak_container;
    if (!container) {
        OBASSERT_NOT_REACHED("The container should be calling us here");
        return NO;
    }
    

    // Our passed in file coordinator doesn't know about this URL and hasn't done the 'prepare' for it. This *shouldn't* deadlock since we don't have a presenter for it, but this makes me uncomfortable (but so does generating a conflict URL for every possible commit of a download).
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
        [container _fileItem:self didGenerateConflictAtURL:conflictURL coordinator:coordinator];
        
        // Mark our snapshot as being locally missing
        error = nil;
        if (![_snapshot didGiveUpLocalContents:&error]) {
            conflictError = error;
            return;
        }
        
        // Some checks to make sure we've fully gone back to being not-downloaded
        OBASSERT(self.presentOnServer == YES);
        OBASSERT(_snapshot.localState.missing);
        OBASSERT(self.isValidToUpload == NO);
        
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
    
    // If we were downloading while there is an incoming delete, our local snapshot will be missing (and trying to check if the URL is standardized will fail).
    if (_snapshot.localState.missing && _snapshot.remoteState.deleted) {
        __autoreleasing NSError *error;
        OBINVARIANT([_snapshot.localSnapshotURL checkResourceIsReachableAndReturnError:&error] == NO && [error causedByMissingFile]);
    } else {
        OBINVARIANT(OFURLIsStandardized(_snapshot.localSnapshotURL));
    }

    NSURL *targetLocalSnapshotURL = _makeLocalSnapshotURL(containerAgent, _identifier);
    OBINVARIANT([_snapshot.localSnapshotURL isEqual:targetLocalSnapshotURL], "the current snapshot should be ours");

    OBINVARIANT([_localDocumentURL isFileURL]);
    OBINVARIANT(![_localDocumentURL isFileReferenceURL]); // Do not want craziness like file:///.file/id=6571367.27967404/
    
    return YES;
}
#endif

@end

