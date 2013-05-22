// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshotUploadRenameTransfer.h"

#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFileStore/OFSFileInfo.h>

#import "OFXUploadRenameFileSnapshot.h"
#import "OFXFileState.h"
#import "OFXFileSnapshotRemoteEncoding.h"

RCS_ID("$Id$")

@implementation OFXFileSnapshotUploadRenameTransfer
{
    NSURL *_currentRemoteSnapshotURL;
    NSUInteger _currentRemoteSnapshotVersion;
    OFXUploadRenameFileSnapshot *_uploadingSnapshot;
}

- (id)initWithFileManager:(OFSDAVFileManager *)fileManager currentSnapshot:(OFXFileSnapshot *)currentSnapshot remoteTemporaryDirectory:(NSURL *)remoteTemporaryDirectory;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (id)initWithFileManager:(OFSDAVFileManager *)fileManager currentSnapshot:(OFXFileSnapshot *)currentSnapshot remoteTemporaryDirectory:(NSURL *)remoteTemporaryDirectory currentRemoteSnapshotURL:(NSURL *)currentRemoteSnapshotURL error:(NSError **)outError;
{
    OBPRECONDITION(currentSnapshot.localState.missing, "Should use the 'contents' upload transfer instead");
    OBPRECONDITION(currentSnapshot.localState.moved, "Only for renames");
    OBPRECONDITION(currentRemoteSnapshotURL);

    if (!(self = [super initWithFileManager:fileManager currentSnapshot:currentSnapshot remoteTemporaryDirectory:remoteTemporaryDirectory]))
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
    
    __autoreleasing NSError *error;

    // Copy the server-side snapshot
    OFSDAVFileManager *fileManager = self.fileManager;
    NSURL *temporaryRemoteSnapshotURL = [fileManager copyURL:_currentRemoteSnapshotURL toURL:self.temporaryRemoteSnapshotURL withSourceETag:nil overwrite:NO error:&error];
    if (!temporaryRemoteSnapshotURL)
        OFXFileSnapshotTransferReturnWithError(error);
    
    // Remember the redirected URL, for what it's worth.
    self.temporaryRemoteSnapshotURL = temporaryRemoteSnapshotURL;
    
    // Remove the previous Info.plist
    NSURL *oldInfoURL = [temporaryRemoteSnapshotURL URLByAppendingPathComponent:kOFXRemoteInfoFilename isDirectory:NO];
    if (![fileManager deleteURL:oldInfoURL withETag:nil error:&error])
        OFXFileSnapshotTransferReturnWithError(error);

    // Write the updated Info.plist
    NSData *infoData = [NSPropertyListSerialization dataWithPropertyList:_uploadingSnapshot.infoDictionary format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!infoData)
        OFXFileSnapshotTransferReturnWithError(error);

    NSURL *infoURL = [temporaryRemoteSnapshotURL URLByAppendingPathComponent:kOFXRemoteInfoFilename isDirectory:NO];

    if (![fileManager writeData:infoData toURL:infoURL atomically:NO error:&error])
        OFXFileSnapshotTransferReturnWithError(error);
    
    OBASSERT(_uploadingSnapshot.version == _currentRemoteSnapshotVersion + 1);
    if (![_uploadingSnapshot finishedUploadingWithError:&error])
        OFXFileSnapshotTransferReturnWithError(error);
    
    DEBUG_TRANSFER(1, @"Uploaded %@", temporaryRemoteSnapshotURL);

    // Success!
    [self finished:nil];
}

@end
