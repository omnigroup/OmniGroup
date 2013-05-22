// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshotDownloadTransfer.h"

#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmnifileStore/OFSAsynchronousOperation.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>

#import "OFXDownloadFileSnapshot.h"
#import "OFXFileState.h"
#import "OFXFileSnapshotRemoteEncoding.h"

RCS_ID("$Id$")

@implementation OFXFileSnapshotDownloadTransfer
{
    NSURL *_remoteSnapshotURL;
    NSURL *_localTemporaryDocumentContentsURL;
    OFXFileSnapshot *_currentSnapshot;
    
    OFXDownloadFileSnapshot *_downloadingSnapshot;
    NSMutableDictionary *_readOperationToLocalFileURL;
    id <OFSAsynchronousOperation> _runningOperation;
    NSMutableData *_resultData; // Would need a separate map for op->results if we run more than one at a time.
    
    BOOL _cancelled;
    
    long long _totalBytesToRead;
    long long _totalBytesRead;
}

- initWithFileManager:(OFSDAVFileManager *)fileManager remoteSnapshotURL:(NSURL *)remoteSnapshotURL localTemporaryDocumentContentsURL:(NSURL *)localTemporaryDocumentContentsURL currentSnapshot:(OFXFileSnapshot *)currentSnapshot;
{
    OBPRECONDITION(currentSnapshot, "should at least be a metadata stub");
    OBPRECONDITION(remoteSnapshotURL);
    
    if (!(self = [super initWithFileManager:fileManager]))
        return nil;
    
    _currentSnapshot = currentSnapshot;
    _localTemporaryDocumentContentsURL = [localTemporaryDocumentContentsURL copy];
    _remoteSnapshotURL = [remoteSnapshotURL copy];
    _readOperationToLocalFileURL = [NSMutableDictionary new];

    return self;
}

- (void)start;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);

    OFSDAVFileManager *fileManager = self.fileManager;
    
    __autoreleasing NSError *error;
    
    DEBUG_TRANSFER(1, @"Performing download of %@", _remoteSnapshotURL);
    if (_localTemporaryDocumentContentsURL)
        DEBUG_TRANSFER(1, @"  to local document contents %@", _localTemporaryDocumentContentsURL);
    DEBUG_TRANSFER(2, @"  Local version %lu", _currentSnapshot.version);

    NSURL *temporaryLocalSnapshotURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:_currentSnapshot.localSnapshotURL allowOriginalDirectory:NO error:&error];
    OBASSERT([[temporaryLocalSnapshotURL absoluteString] hasSuffix:@"/"]); // should have intuited isDirectory:YES
    if (!temporaryLocalSnapshotURL)
        OFXFileSnapshotTransferReturnWithError(error);
    
    if (![OFXDownloadFileSnapshot writeSnapshotToTemporaryURL:temporaryLocalSnapshotURL byFetchingMetadataOfRemoteSnapshotAtURL:_remoteSnapshotURL fileIdentifier:NULL fileManager:fileManager error:&error])
        OFXFileSnapshotTransferReturnWithError(error);
    
    _downloadingSnapshot = [[OFXDownloadFileSnapshot alloc] initWithExistingLocalSnapshotURL:temporaryLocalSnapshotURL error:&error];
    if (!_downloadingSnapshot) {
        [[NSFileManager defaultManager] removeItemAtURL:temporaryLocalSnapshotURL error:NULL];
        OFXFileSnapshotTransferReturnWithError(error);
    }
    
    // If our content is the same as our old snapshot, this is probably just a rename. We compute this so that higher level code can disavow download status if our "download" is just metadata.
    OBFinishPortingLater("Is it safe to look at the snapshot localState on this queue? The bookkeeping queue might be futzing with the status if the user makes a local edit while we are doing this download (and presumably about to hit a conflict if there really is content download needed");
    _isContentDownload = !(_currentSnapshot.localState.normal && [_downloadingSnapshot hasSameContentsAsSnapshot:_currentSnapshot]);
    if (_started) {
        typeof(_started) started = [_started copy]; // Don't crash if we are racing with cancellation
        [self.operationQueue addOperationWithBlock:^{
            started();
        }];
    }
    
    // This temporary snapshot is always undownloaded and thus totally devoid of contents
    OBASSERT(_downloadingSnapshot.localState.missing);

    if (_localTemporaryDocumentContentsURL) {
        DEBUG_TRANSFER(1, @"  Downloading %@ to %@", _remoteSnapshotURL, _localTemporaryDocumentContentsURL);

        if (![_downloadingSnapshot makeDownloadStructureAt:_localTemporaryDocumentContentsURL error:&error withFileApplier:^(NSURL *fileURL, long long fileSize, NSString *hash){
            // TODO: Avoid redownloading data we've already downloaded. This is not terribly likely, but we could have a document with the same image attached multiple times.

            NSURL *remoteFileURL = [_remoteSnapshotURL URLByAppendingPathComponent:hash];
            
            DEBUG_TRANSFER(2, @"  Reading %@ -> %@", remoteFileURL, fileURL);
            
            // No need to use an ETag here since the data is SHA-1 indexed.
            id <OFSAsynchronousOperation> readOperation = [fileManager asynchronousReadContentsOfURL:remoteFileURL];
            
            __weak OFXFileSnapshotDownloadTransfer *weakSelf = self;
            readOperation.didFinish = ^(id <OFSAsynchronousOperation> op, NSError *errorOrNil){
                OFXFileSnapshotDownloadTransfer *strongSelf = weakSelf;
                if (!strongSelf)
                    return; // Operation cancelled.
                [strongSelf.operationQueue addOperationWithBlock:^{
                    [strongSelf _readOperation:op finishedWithError:errorOrNil];
                }];
            };
            
            readOperation.didReceiveData = ^(id <OFSAsynchronousOperation> op, NSData *data){
                OFXFileSnapshotDownloadTransfer *strongSelf = weakSelf;
                if (!strongSelf)
                    return; // Operation cancelled.
                [strongSelf.operationQueue addOperationWithBlock:^{
                    [strongSelf _readOperation:op didReceiveData:data];
                }];
            };
            _readOperationToLocalFileURL[readOperation] = fileURL;
            
            _totalBytesToRead += fileSize;
        }]) {
            // It might have been partially created... clean up after ourselves.
            [[NSFileManager defaultManager] removeItemAtURL:_localTemporaryDocumentContentsURL error:NULL];
            
            DEBUG_TRANSFER(1, @"  download failed %@", [error toPropertyList]);
            OFXFileSnapshotTransferReturnWithError(error);
            return;
        }
        
        _didMakeLocalTemporaryDocumentContentsURL = YES;
    }

    [self _startReadOperation];
}

- (void)finished:(NSError *)errorOrNil;
{
    if (errorOrNil)
        [self _cleanupDownloadingSnapshot];

    [super finished:errorOrNil];
}

- (void)performCancel;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);
    
    // We *might* get more delegate messages, or we might not. In particular we might get -fileManager:operationDidFinish:withError:, which could call -finished:...
    _cancelled = YES;
    [self _cleanupDownloadingSnapshot];
    [_runningOperation stopOperation];
}

- (void)invalidate;
{
    _started = nil;
    [super invalidate];
}

#pragma mark - Private

- (void)_cleanupDownloadingSnapshot;
{
    if (_downloadingSnapshot) {
        // Clean up the temporary snapshot (since our caller can't claim it on error). We do *not* cleanup the temporary document location since that was passed into us rather than us creating it. Our caller cleans that up.
        __autoreleasing NSError *cleanupError;
        NSURL *temporarySnapshotURL = _downloadingSnapshot.localSnapshotURL;
        if (![[NSFileManager defaultManager] removeItemAtURL:temporarySnapshotURL error:&cleanupError])
            [cleanupError log:@"Error cleaning up temporary download snapshot at %@", temporarySnapshotURL];
        _downloadingSnapshot = nil;
        
        _didMakeLocalTemporaryDocumentContentsURL = NO;
    }
}

- (void)_readOperation:(id <OFSAsynchronousOperation>)operation didReceiveData:(NSData *)data;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);
    OBPRECONDITION(operation == _runningOperation);
    OBPRECONDITION([_readOperationToLocalFileURL objectForKey:operation] != nil);
    OBPRECONDITION(_resultData);
    
    [_resultData appendData:data];
    _totalBytesRead += [data length];
    
    double percentComplete = (double)_totalBytesRead/(double)_totalBytesToRead;
    OBASSERT(percentComplete > 0); // we just wrote some...
    OBASSERT(percentComplete <= 1.0);
    
    [self updatePercentCompleted:CLAMP(percentComplete, 0.0, 1.0)];
}

- (void)_readOperation:(id <OFSAsynchronousOperation>)operation finishedWithError:(NSError *)errorOrNil;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);
    OBPRECONDITION(operation == _runningOperation);
    OBPRECONDITION([_readOperationToLocalFileURL objectForKey:operation] != nil);
    
    if (errorOrNil) {
        [self finished:errorOrNil];
        return;
    }
    if (_cancelled)
        return;
    
    NSURL *fileURL = _readOperationToLocalFileURL[operation];
    
    OBFinishPortingLater("One downside to always using Info.plist is that we lose this check for the main plist. Random bit corruption on disk would have a relatively low chance of clobbering XML structure. If we gzip the plist, this'll be more likely to be noticed");
    // Validate the hash.
    // TODO: Queue this so that the hash validation can run concurrently with the next file download.
    NSString *expectedHash = OFXHashFileNameForData(_resultData);
    if (![expectedHash isEqualToString:[operation.url lastPathComponent]]) {
        __autoreleasing NSError *corruptionError = nil;
        OFXError(&corruptionError, OFXSnapshotCorrupt, @"Possible document corruption", ([NSString stringWithFormat:@"Expected hash (%@) does not match the last path component of \"%@\"", expectedHash, operation.url]));
        [self finished:corruptionError];
        return;
    }
    
    // We expect to be writing to a temporary location, so no 'atomic' flag needed.
    __autoreleasing NSError *writeError;
    if (![_resultData writeToURL:fileURL options:0 error:&writeError])
        OFXFileSnapshotTransferReturnWithError(writeError);
    
    [_readOperationToLocalFileURL removeObjectForKey:operation];
    _runningOperation = nil;
    _resultData = nil;
    [self _startReadOperation];
}

- (void)_startReadOperation;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == self.operationQueue);

    if (_cancelled)
        return;
    
    _runningOperation = [[_readOperationToLocalFileURL allKeys] lastObject];
    if (_runningOperation) {
        _resultData = [NSMutableData new];
        [_runningOperation startOperationOnQueue:self.transferOperationQueue];
        return;
    }
    
    __autoreleasing NSError *error;

    if (_localTemporaryDocumentContentsURL) {
        if (![_downloadingSnapshot finishedDownloadingToURL:_localTemporaryDocumentContentsURL error:&error])
            OFXFileSnapshotTransferReturnWithError(error);
        
        DEBUG_TRANSFER(1, @"  downloaded contents into %@", [_downloadingSnapshot shortDescription]);
    }
    
    // Reload the downloaded snapshot as a regular snapshot so the caller can use it.
    _downloadedSnapshot = [[OFXDownloadFileSnapshot alloc] initWithExistingLocalSnapshotURL:_downloadingSnapshot.localSnapshotURL error:&error];
    if (!_downloadedSnapshot)
        OFXFileSnapshotTransferReturnWithError(error);
    DEBUG_TRANSFER(1, @"  reloaded downloaded snapshot %@", [_downloadedSnapshot shortDescription]);
    
    [self finished:nil];
}

@end
