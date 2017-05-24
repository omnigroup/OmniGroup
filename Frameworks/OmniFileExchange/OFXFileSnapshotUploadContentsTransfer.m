// Copyright 2013-2015,2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshotUploadContentsTransfer.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDAV/ODAVOperation.h>

#import "OFXUploadContentsFileSnapshot.h"
#import "OFXFileSnapshotRemoteEncoding.h"
#import "OFXFileState.h"

RCS_ID("$Id$")

/*
 Uploads a snapshot to a temporary location on the remote server. This is explicitly a *temporary* location; after the completion of this operation, the completion handler will be used to commit the operation by moving the upload to its final location (or abandoning/deleting it).
 */

@implementation OFXFileSnapshotUploadContentsTransfer
{
    OFXUploadContentsFileSnapshot *_uploadingSnapshot;
    
    NSMutableArray <ODAVOperation *> *_writeOperations;
    id <ODAVAsynchronousOperation> _runningOperation;
    BOOL _cancelled;
    
    long long _totalBytesToWrite;
    long long _totalBytesWritten;
}

- (id)initWithConnection:(ODAVConnection *)connection currentSnapshot:(OFXFileSnapshot *)currentSnapshot forUploadingVersionOfDocumentAtURL:(NSURL *)localDocumentURL localRelativePath:(NSString *)localRelativePath remoteTemporaryDirectory:(NSURL *)remoteTemporaryDirectory error:(NSError **)outError;
{    
    if (!(self = [super initWithConnection:connection currentSnapshot:currentSnapshot remoteTemporaryDirectory:remoteTemporaryDirectory]))
        return nil;
    
    _writeOperations = [NSMutableArray new];
    
    // This does a coordinated read of the document and captures a copy of the current document contents as well as local filesystem state (so we can tell if the local document changes later).
    _uploadingSnapshot = [[OFXUploadContentsFileSnapshot alloc] initWithTargetLocalSnapshotURL:currentSnapshot.localSnapshotURL forUploadingVersionOfDocumentAtURL:localDocumentURL localRelativePath:localRelativePath previousSnapshot:currentSnapshot error:outError];
    if (!_uploadingSnapshot)
        return nil;
    
    OBASSERT_IF(currentSnapshot.remoteState.missing, _uploadingSnapshot.version == 0);
    OBASSERT_IF(!currentSnapshot.remoteState.missing, _uploadingSnapshot.version == currentSnapshot.version + 1);
    
    _uploadingSnapshot.debugName = self.debugName;
    
    return self;
}

- (void)start;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);
    
    DEBUG_TRANSFER(1, @"Uploading snapshot to %@", self.remoteTemporaryDirectoryURL);
        
    __autoreleasing NSError *error;
    
    NSURL *temporaryRemoteSnapshotURL = [self _makeTemporaryRemoteSnapshotURL:&error];
    if (!temporaryRemoteSnapshotURL)
        OFXFileSnapshotTransferReturnWithError(error);

    // Collect async write operations        
    BOOL success = [_uploadingSnapshot iterateFiles:&error withApplier:^BOOL(NSURL *fileURL, NSString *hash, NSError **applierError){
        NSURL *remoteFileURL = [temporaryRemoteSnapshotURL URLByAppendingPathComponent:hash];
        
        DEBUG_TRANSFER(2, @"  Writing %@ -> %@", fileURL, remoteFileURL);
        
        // Require that we file map since we pre-read these. OmniFileExchange directories should always be on local filesystems (so file coordination works) and we should always be reading from a private snapshot here (so there should be no editors).
        NSData *fileData = [[NSData alloc] initWithContentsOfURL:fileURL options:NSDataReadingMappedAlways|NSDataReadingUncached error:applierError];
        if (!fileData) {
            OBChainError(applierError);
            return NO;
        }
        
        _totalBytesToWrite += [fileData length];
        
        ODAVOperation *writeOperation = [self.connection asynchronousPutData:fileData toURL:remoteFileURL];
        [_writeOperations addObject:writeOperation];
        
        return YES;
    }];
    if (!success)
        OFXFileSnapshotTransferReturnWithError(error);
    
    // Add a write operation for the manifest. Doesn't matter what order these happen in since we are writing to a temporary spot.
    {
        // Write the manifest
        NSData *infoData = [NSPropertyListSerialization dataWithPropertyList:_uploadingSnapshot.infoDictionary format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        if (!infoData)
            OFXFileSnapshotTransferReturnWithError(error);
        
        NSURL *infoURL = [temporaryRemoteSnapshotURL URLByAppendingPathComponent:kOFXRemoteInfoFilename];
        
        _totalBytesToWrite += [infoData length];

        ODAVOperation *writeOperation = [self.connection asynchronousPutData:infoData toURL:infoURL];
        [_writeOperations addObject:writeOperation];
    }
    
    [self _startWriteOperation];
}

- (void)performCancel;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);

    // We *might* get more delegate messages, or we might not. In particular we might get -fileManager:operationDidFinish:withError:, which could call -finished:...
    _cancelled = YES;
    
    [_uploadingSnapshot removeTemporaryCopyOfDocument];
    [_runningOperation cancel];
}

- (void)finished:(NSError *)errorOrNil;
{
    [_uploadingSnapshot removeTemporaryCopyOfDocument];
    
    if (errorOrNil) {
        __autoreleasing NSError *cleanupError;
        if (![[NSFileManager defaultManager] removeItemAtURL:_uploadingSnapshot.localSnapshotURL error:&cleanupError])
            [cleanupError log:@"Error removing temporary snapshot created for uploading at %@", _uploadingSnapshot.localSnapshotURL];
    }
    
    [super finished:errorOrNil];
}

#pragma mark - OFXFileSnapshotUploadTransfer subclass

- (OFXFileSnapshot *)uploadingSnapshot;
{
    return _uploadingSnapshot;
}

#pragma mark - Internal

- (NSURL *)_makeTemporaryRemoteSnapshotURL:(NSError **)outError;
{
    // Try to avoid redundant PROPFINDs in the common case -- assume remoteTemporaryDirectoryURL exists and fall back to a slower path if there is an error here.
    
    __block ODAVURLResult *result;
    __block NSError *resultError;
    
    ODAVConnection *connection = self.connection;
    NSURL *temporaryRemoteSnapshotURL = self.temporaryRemoteSnapshotURL;
    
    ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done){
        [connection makeCollectionAtURL:temporaryRemoteSnapshotURL completionHandler:^(ODAVURLResult *singleCreateResult, NSError *singleCreateError) {
            if (singleCreateResult) {
                result = singleCreateResult; // Yay!
                done();
                return;
            }
            
            // Try creating the whole directory path.
            [connection makeCollectionAtURLIfMissing:temporaryRemoteSnapshotURL baseURL:connection.baseURL completionHandler:^(ODAVURLResult *fullCreateResult, NSError *fullCreateError) {
                if (fullCreateResult)
                    result = fullCreateResult; // Yay!
                else
                    resultError = fullCreateError;
                done();
            }];
        }];
    });
    
    // Remember the redirects we see in this initial MKCOL so that we don't get a redirect on our final MOVE.
    if ([result.redirects count] > 0) {
        [connection updateBaseURLWithRedirects:result.redirects];
    }
    
    // Remember the redirected URL
    self.temporaryRemoteSnapshotURL = result.URL;
    if (!result && outError)
        *outError = resultError;
    return result.URL;
}

- (void)_startWriteOperation;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);

    if (_cancelled)
        return;

    _runningOperation = [_writeOperations lastObject];
    if (_runningOperation) {
        __weak OFXFileSnapshotUploadContentsTransfer *weakSelf = self;
        _runningOperation.didFinish = ^(ODAVOperation *op, NSError *errorOrNil){
            OFXFileSnapshotUploadContentsTransfer *strongSelf = weakSelf;
            if (!strongSelf)
                return; // Cancelled, presumably
            OBASSERT([NSOperationQueue currentQueue] == strongSelf.transferOperationQueue);
            [strongSelf.operationQueue addOperationWithBlock:^{
                [strongSelf _writeOperation:op didFinish:errorOrNil];
            }];
        };
        _runningOperation.didSendBytes = ^(ODAVOperation *op, long long byteCount){
            OFXFileSnapshotUploadContentsTransfer *strongSelf = weakSelf;
            if (!strongSelf)
                return; // Cancelled, presumably
            OBASSERT([NSOperationQueue currentQueue] == strongSelf.transferOperationQueue);
            [strongSelf.operationQueue addOperationWithBlock:^{
                [strongSelf _writeOperation:op didSendBytes:byteCount];
            }];
        };
        [_runningOperation startWithCallbackQueue:self.transferOperationQueue];
        return;
    }
    
    __autoreleasing NSError *error;
    if (![_uploadingSnapshot finishedUploadingWithError:&error])
        OFXFileSnapshotTransferReturnWithError(error);
    
    DEBUG_TRANSFER(1, @"Uploaded %@", self.temporaryRemoteSnapshotURL);
    
    // Our superclass wants this called on the transfer queue...
    [self finished:nil];
}

- (void)_writeOperation:(ODAVOperation *)operation didFinish:(NSError *)error;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);
    OBPRECONDITION(operation == _runningOperation);
    OBPRECONDITION([_writeOperations indexOfObject:operation] != NSNotFound);
    
    if (error) {
        [self finished:error];
        return;
    }
    if (_cancelled)
        return;
    
    [_writeOperations removeObject:operation];
    _runningOperation = nil;
    
    [self _startWriteOperation];
}

- (void)_writeOperation:(ODAVOperation *)operation didSendBytes:(long long)processedBytes;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);
    
    _totalBytesWritten += processedBytes;
    
    double percentComplete = (double)_totalBytesWritten/(double)_totalBytesToWrite;
    OBASSERT(percentComplete > 0); // we just wrote some...
    OBASSERT(percentComplete <= 1.0);
    
    [self updatePercentCompleted:CLAMP(percentComplete, 0.0, 1.0)];
}

@end
