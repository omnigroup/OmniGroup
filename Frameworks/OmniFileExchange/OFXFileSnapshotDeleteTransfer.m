// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshotDeleteTransfer.h"

#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFileStore/Errors.h>

#import "OFXFileState.h"
#import "OFXFileSnapshot.h"
#import "OFXFileSnapshotRemoteEncoding.h"

RCS_ID("$Id$")

@implementation OFXFileSnapshotDeleteTransfer
{
    NSString *_fileIdentifier;
    OFXFileState *_currentSnapshotRemoteState;
    NSUInteger _currentSnapshotVersion;
    NSURL *_remoteContainerURL;
    NSURL *_remoteTemporaryDirectoryURL;
}

- (id)initWithFileManager:(OFSDAVFileManager *)fileManager fileIdentifier:(NSString *)fileIdentifier snapshot:(OFXFileSnapshot *)currentSnapshot remoteContainerURL:(NSURL *)remoteContainerURL remoteTemporaryDirectoryURL:(NSURL *)remoteTemporaryDirectoryURL;
{
    OBPRECONDITION(![NSString isEmptyString:fileIdentifier]);
    OBPRECONDITION(currentSnapshot);
    OBPRECONDITION(remoteContainerURL);
    OBPRECONDITION(remoteTemporaryDirectoryURL);
    OBPRECONDITION(!OFURLEqualsURL(remoteContainerURL, remoteTemporaryDirectoryURL));
    
    if (!(self = [super initWithFileManager:fileManager]))
        return nil;
    
    _fileIdentifier = [fileIdentifier copy];
    _remoteContainerURL = [remoteContainerURL copy];
    _remoteTemporaryDirectoryURL = [remoteTemporaryDirectoryURL copy];
    
    // Remember the original remote state (which could change once we get off this queue if this operation and a container's PROPFIND are racing).
    _currentSnapshotRemoteState = currentSnapshot.remoteState;
    
    // Also remember the newest version we know for the file. If we see a newer version while deleting, we'll signal a conflict.
    _currentSnapshotVersion = currentSnapshot.version;
    
    return self;
}

- (void)start;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);
    
    if (_currentSnapshotRemoteState.missing) {
        // This is a delete that is just cleaning up a local snapshot. The document never got fully uploaded to the server.
    } else {
        TRACE_SIGNAL(OFXFileSnapshotDeleteTransfer.remote_delete_attempted);
        OFSDAVFileManager *fileManager = self.fileManager;
        __autoreleasing NSError *error;

        if (_fileIdentifier == nil) {
            NSCAssert(_fileIdentifier, @"If _fileIdentifier is nil, we could delete all files in the container"); // should throw
            abort(); // ... but just in case
        }
        
        OBFinishPortingLater("Need to write tests that actually generate multiple versions to delete");
        NSArray *fileInfos = OFXFetchDocumentFileInfos(fileManager, _remoteContainerURL, _fileIdentifier, &error);
        if ([fileInfos count] > 1) {
            OBASSERT_NOT_REACHED("We don't have any way of hitting this in normal operations, so this code is untested and needs to be.");
            fileInfos = [fileInfos sortedArrayUsingComparator:^NSComparisonResult(OFSFileInfo *fileInfo1, OFSFileInfo *fileInfo2) {
                return OFXCompareFileInfoByVersion(fileInfo1, fileInfo2);
            }];
        }
        
        for (OFSFileInfo *fileVersionInfo in fileInfos) {
            // Delete oldest to newest so that if we die partway through, other clients won't see an old version resurrected.
            // Move into tmp and delete, in case the deletion is non-atomic. If we want to avoid this, we'd need to ensure that other client seeing a partially deleted snapshot would either ignore it or clean it up themselves.
            
            // If this file is newer than we knew about, bail with a conflict
            NSUInteger fileVersion;
            if (!OFXFileItemIdentifierFromRemoteSnapshotURL(fileVersionInfo.originalURL, &fileVersion, &error)) {
                OBASSERT_NOT_REACHED("We should have parsed this already");
                fileVersion = NSUIntegerMax;
            }
            if (fileVersion > _currentSnapshotVersion) {
                NSString *reason = [NSString stringWithFormat:@"New version of file (%lu) was discovered while deleting up to version %lu", fileVersion, _currentSnapshotVersion];
                OFXError(&error, OFXFileUpdatedWhileDeleting, @"File has been edited on another device.", reason);
                [self finished:error];
                return;
            }
            
            NSURL *temporaryURL = [_remoteTemporaryDirectoryURL URLByAppendingPathComponent:OFXMLCreateID() isDirectory:YES];
            temporaryURL = [fileManager moveURL:fileVersionInfo.originalURL toMissingURL:temporaryURL error:&error];
            if (!temporaryURL) {
                if ([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_NOT_FOUND]) {
                    // Delete/delete conflict? Guess it is gone either way!
                    [self finished:nil];
                    return;
                } else {
                    OBChainError(&error);
                    [self finished:error];
                    return;
                }
            }
            
            if (![fileManager deleteURL:temporaryURL error:&error]) {
                if ([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_NOT_FOUND]) {
                    // Seems very  unlikely, but maybe we are racing against another client cleaning out trash from the temporary directory?
                } else {
                    [self finished:error];
                    return;
                }
            }
        }
    }

    [self finished:nil];
}

- (void)finished:(NSError *)errorOrNil;
{
    [super finished:errorOrNil];
    TRACE_SIGNAL(OFXFileSnapshotDeleteTransfer.finished);
}

@end
