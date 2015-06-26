// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshotUploadRenameTransfer.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>

#import "OFXFileSnapshotRemoteEncoding.h"
#import "OFXFileState.h"
#import "OFXUploadRenameFileSnapshot.h"

RCS_ID("$Id$")

@implementation OFXFileSnapshotUploadRenameTransfer
{
    NSURL *_currentRemoteSnapshotURL;
    NSUInteger _currentRemoteSnapshotVersion;
    OFXUploadRenameFileSnapshot *_uploadingSnapshot;
}

- (id)initWithConnection:(ODAVConnection *)connection currentSnapshot:(OFXFileSnapshot *)currentSnapshot remoteTemporaryDirectory:(NSURL *)remoteTemporaryDirectory;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (id)initWithConnection:(ODAVConnection *)connection currentSnapshot:(OFXFileSnapshot *)currentSnapshot remoteTemporaryDirectory:(NSURL *)remoteTemporaryDirectory currentRemoteSnapshotURL:(NSURL *)currentRemoteSnapshotURL error:(NSError **)outError;
{
    OBPRECONDITION(currentSnapshot.localState.missing, "Should use the 'contents' upload transfer instead");
    OBPRECONDITION(currentSnapshot.localState.userMoved, "Only for renames");
    OBPRECONDITION(currentRemoteSnapshotURL);

    if (!(self = [super initWithConnection:connection currentSnapshot:currentSnapshot remoteTemporaryDirectory:remoteTemporaryDirectory]))
        return nil;
    
    // Make a copy of the original snapshot as our uploading snapshot.
    NSURL *temporarySnapshotURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:currentSnapshot.localSnapshotURL allowOriginalDirectory:NO error:outError];
    if (!temporarySnapshotURL)
        return nil;
    if (![[NSFileManager defaultManager] copyItemAtURL:currentSnapshot.localSnapshotURL toURL:temporarySnapshotURL error:outError])
        return nil;
    
    _currentRemoteSnapshotVersion = currentSnapshot.version;
    _currentRemoteSnapshotURL = [currentRemoteSnapshotURL copy];
    _uploadingSnapshot = [[OFXUploadRenameFileSnapshot alloc] initWithExistingLocalSnapshotURL:temporarySnapshotURL error:outError];
    if (!_uploadingSnapshot)
        return nil;

    if (![_uploadingSnapshot prepareToUploadRename:outError])
        return nil;
    
    return self;
}

- (OFXUploadRenameFileSnapshot *)uploadingSnapshot;
{
    return _uploadingSnapshot;
}

- (void)start;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);
    
    DEBUG_TRANSFER(1, @"Preparing remote rename by doing COPY of %@ -> %@", _currentRemoteSnapshotURL, self.temporaryRemoteSnapshotURL);

    ODAVConnection *connection = self.connection;

    __block NSError *error;
    __block NSURL *temporaryRemoteSnapshotURL = [connection suggestRedirectedURLForURL:self.temporaryRemoteSnapshotURL];
    
    ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done) {
        // Copy the server-side snapshot
        [connection copyURL:_currentRemoteSnapshotURL toURL:temporaryRemoteSnapshotURL withSourceETag:nil overwrite:NO completionHandler:^(ODAVURLResult *temporaryRemoteSnapshotResult, NSError *copyError) {
            if (!temporaryRemoteSnapshotResult) {
                error = OBChainedError(copyError);
                done();
                return;
            }
            
            // Remove the previous Info.plist
            NSURL *oldInfoURL = [temporaryRemoteSnapshotURL URLByAppendingPathComponent:kOFXRemoteInfoFilename isDirectory:NO];
            [connection deleteURL:oldInfoURL withETag:nil completionHandler:^(NSError *deleteError) {
                if (deleteError) {
                    error = OBChainedError(deleteError);
                    done();
                    return;
                }
                
                // Write the updated Info.plist
                __autoreleasing NSError *plistError;
                NSData *infoData = [NSPropertyListSerialization dataWithPropertyList:_uploadingSnapshot.infoDictionary format:NSPropertyListXMLFormat_v1_0 options:0 error:&plistError];
                if (!infoData) {
                    error = OBChainedError(plistError);
                    done();
                    return;
                }
                
                NSURL *infoURL = [temporaryRemoteSnapshotURL URLByAppendingPathComponent:kOFXRemoteInfoFilename isDirectory:NO];
                [connection putData:infoData toURL:infoURL completionHandler:^(ODAVURLResult *writtenResult, NSError *writeError) {
                    if (!writtenResult) {
                        error = OBChainedError(writeError);
                        done();
                        return;
                    }
                    done();
                }];
            }];
        }];
    });

    if (!error) {
        OBASSERT(_uploadingSnapshot.version == _currentRemoteSnapshotVersion + 1);
        
        __autoreleasing NSError *finishError;
        if (![_uploadingSnapshot finishedUploadingWithError:&finishError])
            error = OBChainedError(finishError);
        else {
            DEBUG_TRANSFER(1, @"Uploaded %@", temporaryRemoteSnapshotURL);
            TRACE_SIGNAL(OFXFileSnapshotUploadRenameTransfer.remote_metadata_rename);
        }
    }
    
    // Allow commit() callback to get the redirected URL.
    self.temporaryRemoteSnapshotURL = temporaryRemoteSnapshotURL;
    
    // Success!
    [self finished:error];
}

@end
