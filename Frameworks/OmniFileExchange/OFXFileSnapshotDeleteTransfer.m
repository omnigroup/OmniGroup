// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshotDeleteTransfer.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>

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

- (id)initWithConnection:(ODAVConnection *)connection fileIdentifier:(NSString *)fileIdentifier snapshot:(OFXFileSnapshot *)currentSnapshot remoteContainerURL:(NSURL *)remoteContainerURL remoteTemporaryDirectoryURL:(NSURL *)remoteTemporaryDirectoryURL;
{
    OBPRECONDITION(![NSString isEmptyString:fileIdentifier]);
    OBPRECONDITION(currentSnapshot);
    OBPRECONDITION(remoteContainerURL);
    OBPRECONDITION(remoteTemporaryDirectoryURL);
    OBPRECONDITION(!OFURLEqualsURL(remoteContainerURL, remoteTemporaryDirectoryURL));
    
    if (!(self = [super initWithConnection:connection]))
        return nil;
    
    _fileIdentifier = [fileIdentifier copy];
    _remoteContainerURL = [[connection suggestRedirectedURLForURL:remoteContainerURL] copy];
    _remoteTemporaryDirectoryURL = [[connection suggestRedirectedURLForURL:remoteTemporaryDirectoryURL] copy];
    
    // Remember the original remote state (which could change once we get off this queue if this operation and a container's PROPFIND are racing).
    _currentSnapshotRemoteState = currentSnapshot.remoteState;
    
    // Also remember the newest version we know for the file. If we see a newer version while deleting, we'll signal a conflict.
    _currentSnapshotVersion = currentSnapshot.version;
    
    return self;
}

- (void)start;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);
    
    if (_currentSnapshotRemoteState.missing || _currentSnapshotRemoteState.deleted) {
        // This is a delete that is just cleaning up a local snapshot. The document never got fully uploaded to the server or was remotely deleted too.
    } else {
        TRACE_SIGNAL(OFXFileSnapshotDeleteTransfer.remote_delete_attempted);
        ODAVConnection *connection = self.connection;
        __autoreleasing NSError *error;

        if (_fileIdentifier == nil) {
            NSCAssert(_fileIdentifier, @"If _fileIdentifier is nil, we could delete all files in the container"); // should throw
            abort(); // ... but just in case
        }

        // Tests of deleting multiple document versions have to manufature situations where we actually *have* multiple versions to delete.
        NSArray <ODAVFileInfo *> *fileInfos = OFXFetchDocumentFileInfos(connection, _remoteContainerURL, _fileIdentifier, &error);
        if ([fileInfos count] > 1) {
            fileInfos = [fileInfos sortedArrayUsingComparator:^NSComparisonResult(ODAVFileInfo *fileInfo1, ODAVFileInfo *fileInfo2) {
                return OFXCompareFileInfoByVersion(fileInfo1, fileInfo2);
            }];
        }
        
        for (ODAVFileInfo *fileVersionInfo in fileInfos) {
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

            // Use any redirect discovered during our PROPFIND.
            temporaryURL = [connection suggestRedirectedURLForURL:temporaryURL];
            
            __block NSError *resultError;
            
            ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done) {
                [connection moveURL:fileVersionInfo.originalURL toMissingURL:temporaryURL completionHandler:^(ODAVURLResult *moveResult, NSError *moveError) {
                    if (!moveResult) {
                        if ([moveError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND]) {
                            // Delete/delete conflict? Guess it is gone either way!
                        } else
                            resultError = OBChainedError(moveError);
                        done();
                        return;
                    }
                    
                    [connection deleteURL:moveResult.URL withETag:nil completionHandler:^(NSError *deleteError) {
                        if (deleteError) {
                            if ([deleteError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND]) {
                                // Seems very  unlikely, but maybe we are racing against another client cleaning out trash from the temporary directory?
                            } else
                                resultError = OBChainedError(deleteError);
                        }
                        done();
                    }];
                }];
            });
            
            if (resultError) {
                [self finished:resultError];
                return;
            }
            
            TRACE_APPEND(OFXFileSnapshotDeleteTransfer.deleted_urls, fileVersionInfo.originalURL);
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
