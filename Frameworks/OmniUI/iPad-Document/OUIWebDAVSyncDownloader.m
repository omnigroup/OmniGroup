// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIWebDAVSyncDownloader.h"

#import <MobileCoreServices/MobileCoreServices.h>
#import <OmniFileStore/OFSAsynchronousOperation.h>
#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$");

@interface OUIWebDAVSyncDownloader () <OFSFileManagerDelegate>
@end


@implementation OUIWebDAVSyncDownloader
{
    OFSFileManager *_fileManager;
    id <OFSAsynchronousOperation> _downloadOperation;
    NSOutputStream *_downloadStream;
    NSMutableArray *_uploadOperations;
    
    OFSFileInfo *_file;
    NSURL *_baseURL;
    NSMutableArray *_fileQueue;
    NSString *_downloadTimestamp; // for uniqueing
    NSString *_downloadPath; // for cleaning up after download is complete
    
    off_t _totalDataLength;
    off_t _totalUploadedBytes;
    
    NSURL *_uploadTemporaryURL, *_uploadFinalURL;
}

- (id)init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- initWithFileManager:(OFSFileManager *)fileManager;
{
    OBPRECONDITION(fileManager);
    
    if (!(self = [super init]))
        return nil;
    
    _fileManager = fileManager;
    
    return self;
}

@synthesize fileManager = _fileManager;

#pragma mark - OUIConcreteSyncDownloader

- (void)download:(OFSFileInfo *)aFile;
{
    _baseURL = nil;
    _fileQueue = nil;
    
    _baseURL = [aFile originalURL];
    // the new uniqued location of our downloaded file.
     // should have been cleared at conclusion of last download, but just in case...
    _downloadTimestamp = nil;
    NSString *tempPath = [self _downloadLocation];
    
    _downloadPath = tempPath;

    if ([aFile isDirectory]) {
        [self _readAndQueueContentsOfDirectory:aFile];
        
        OBASSERT([_fileQueue count]);
        for (OFSFileInfo *nextFile in _fileQueue)
            _totalDataLength += nextFile.size;
        
        OFSFileInfo *firstFile = [_fileQueue lastObject];
        [self _downloadFile:firstFile];
        [_fileQueue removeObjectIdenticalTo:firstFile];
    } else {
        _totalDataLength = [aFile size];
        [self _downloadFile:aFile];
    } 
}

- (IBAction)cancelDownload:(id)sender;
{
    if (_downloadOperation != nil) {
        [_downloadStream close];
        [_downloadOperation stopOperation];
    } else if (_uploadOperations != nil) {
        for (id <OFSAsynchronousOperation> uploadOperation in _uploadOperations)
            [uploadOperation stopOperation];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUISyncDownloadCanceledNotification object:self];
}

- (void)uploadFileWrapper:(NSFileWrapper *)fileWrapper toURL:(NSURL *)targetURL;
{
    OBPRECONDITION(_fileManager);
    
    _totalDataLength = 0;
    _uploadOperations = [[NSMutableArray alloc] init];
    __autoreleasing NSError *error = nil;
    OBASSERT (_baseURL == nil);
    _baseURL = targetURL;
    if (![self _queueUploadFileWrapper:fileWrapper atomically:YES toURL:targetURL usingFileManager:_fileManager error:&error]) {
        OBASSERT(error != nil);
        OUI_PRESENT_ERROR(error);
        [self _cleanupWithSuccess:NO];
        return;
    }
    for (id <OFSAsynchronousOperation> uploadOperation in [NSArray arrayWithArray:_uploadOperations]) {
        [uploadOperation startOperationOnQueue:nil];
    }
}

#pragma mark - Async operation handlers

- (void)_operation:(id <OFSAsynchronousOperation>)operation didReceiveData:(NSData *)data;
{    
    OBPRECONDITION(operation == _downloadOperation);
    
    self.progressView.progress = (double)operation.processedLength/(double)_totalDataLength;
    
    if ([_downloadStream write:[data bytes] maxLength:[data length]] == -1) {
        OUI_PRESENT_ERROR([_downloadStream streamError]);
        [self _cleanupWithSuccess:NO];
        return;
    }
}

- (void)_operation:(id <OFSAsynchronousOperation>)operation didSendBytes:(long long)processedBytes;
{    
    OBPRECONDITION(_uploadOperations == nil || [_uploadOperations containsObjectIdenticalTo:operation]);
    if (_uploadOperations == nil)
        return; // We've cancelled these uploads
    
    _totalUploadedBytes += processedBytes;
    self.progressView.progress = (double)_totalUploadedBytes/(double)_totalDataLength;
}

- (void)_operationDidFinish:(id <OFSAsynchronousOperation>)operation withError:(NSError *)error;
{
    // Some operation that we cancelled due to a failure in an operation before it in the queue? See <bug:///72669> (Exporting files which time out leaves you in a weird state)
    if (operation != _downloadOperation && [_uploadOperations containsObjectIdenticalTo:operation] == NO)
        return;

    if (error) {
        OUI_PRESENT_ERROR(error);
        
        [self _cleanupWithSuccess:NO];
        return;
    }
    
    BOOL success = YES;
    NSDictionary *userInfo = nil;
    
    if (operation == _downloadOperation) {
        // Our current download finished
        [_downloadStream close];
        
        if ([_fileQueue count] != 0) {
             _downloadOperation = nil;
            OFSFileInfo *firstFile = [_fileQueue lastObject];
            [self _downloadFile:firstFile];
            [_fileQueue removeObjectIdenticalTo:firstFile];
            return; // On to the next download
        }
        
        // all downloads are done, lets do our final cleanup
        NSString *localFile = _downloadPath;
        NSURL *localFileURL = [NSURL fileURLWithPath:localFile];
        __autoreleasing NSError *utiError;
        NSString *fileUTI = OFUTIForFileURLPreferringNative(localFileURL, &utiError);
        if (!fileUTI) {
            localFile = nil;
            OUI_PRESENT_ERROR(utiError);
        } else if (OFSIsZipFileType(fileUTI)) {
            __autoreleasing NSError *unarchiveError = nil;
            localFile = [self unarchiveFileAtPath:localFile error:&unarchiveError];
            if (!localFile || unarchiveError)
                OUI_PRESENT_ERROR(unarchiveError);
        }
        
        if (localFile) {
            [self.cancelButton setTitle:NSLocalizedStringFromTableInBundle(@"Finished", @"OmniUIDocument", OMNI_BUNDLE, @"finished") forState:UIControlStateNormal];
            UIImage *backgroundImage = [[UIImage imageNamed:@"OUIExportFinishedBadge.png"] stretchableImageWithLeftCapWidth:6 topCapHeight:0];
            [self.cancelButton setBackgroundImage:backgroundImage forState:UIControlStateNormal];
            userInfo = [NSDictionary dictionaryWithObject:[NSURL fileURLWithPath:localFile] forKey:OUISyncDownloadURL];
        }
        
        success = localFile != nil;

    } else {
        // An upload finished
        OBASSERT([_uploadOperations containsObjectIdenticalTo:operation]);
        [_uploadOperations removeObjectIdenticalTo:operation];
        if ([_uploadOperations count] != 0)
            return; // Still waiting for more uploads
        
        // All uploads are done if we get to here, final cleanup time!
        // For atomic directory wrapper uploads, move our temporary URL to our final URL

        if (_uploadTemporaryURL != nil) {
            [_fileManager deleteURL:_uploadFinalURL error:NULL]; // Ignore delete errors
            // we might be replacing a file with a directory, check the verison with and without a slash.
            NSString *url = [_uploadFinalURL absoluteString];
            if ([url hasSuffix:@"/"]) {
                url = [url substringToIndex:[url length] - 1]; // if it's got a trailing slash, trim it.
                [_fileManager deleteURL:[NSURL URLWithString:url] error:NULL];
            }
            __autoreleasing NSError *moveError = nil;
            if (![_fileManager moveURL:_uploadTemporaryURL toURL:_uploadFinalURL error:&moveError]) {
                OUI_PRESENT_ERROR(moveError);
                success = NO;
            }
            
            _uploadTemporaryURL = nil;
            _uploadFinalURL = nil;
        }
        
        userInfo = [NSDictionary dictionaryWithObject:_baseURL forKey:OUISyncDownloadURL];
        
        OBASSERT(_uploadTemporaryURL == nil);
        OBASSERT(_uploadFinalURL == nil);
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUISyncDownloadFinishedNotification object:self userInfo:userInfo];
    [self _cleanupWithSuccess:success];
}

#pragma mark -
#pragma mark Debugging

- (NSString *)shortDescription;
{
    NSMutableDictionary *properties = [[NSMutableDictionary alloc] init];
    [properties setObject:_file forKey:@"_file" defaultObject:nil];
    [properties setObject:_baseURL forKey:@"_baseURL" defaultObject:nil];
    [properties setObject:_downloadTimestamp forKey:@"_downloadTimestamp" defaultObject:nil];
    [properties setObject:_downloadPath forKey:@"_downloadPath" defaultObject:nil];
    [properties setObject:_fileQueue forKey:@"_fileQueue" defaultObject:nil];
    return [NSString stringWithFormat:@"<%@:%p> %@", NSStringFromClass([self class]), self, properties];
}


#pragma mark -
#pragma mark Private

- (void)_downloadFile:(OFSFileInfo *)aFile;
{    
    _file = aFile;
        
    __autoreleasing NSError *error;
    NSString *localFilePath = [self _downloadLocation];
    NSString *localFileDirectory = [localFilePath stringByDeletingLastPathComponent];
    
    if (![[NSFileManager defaultManager] createDirectoryAtPath:localFileDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
        OUI_PRESENT_ALERT(error);
        [self cancelDownload:nil];
        return;
    }
    
    _downloadStream = [[NSOutputStream alloc] initToFileAtPath:localFilePath append:NO];
    [_downloadStream open];
    
    OBASSERT(_downloadOperation == nil);
    _downloadOperation = [_fileManager asynchronousReadContentsOfURL:[aFile originalURL]];
    
    __weak OUIWebDAVSyncDownloader *weakSelf = self;
    _downloadOperation.didReceiveData = ^(id <OFSAsynchronousOperation> op, NSData *data){
        OUIWebDAVSyncDownloader *strongSelf = weakSelf;
        OBASSERT(strongSelf, "Deallocated w/o cancelling operation?");
        [strongSelf _operation:op didReceiveData:data];
    };
    _downloadOperation.didFinish = ^(id <OFSAsynchronousOperation> op, NSError *error){
        OUIWebDAVSyncDownloader *strongSelf = weakSelf;
        OBASSERT(strongSelf, "Deallocated w/o cancelling operation?");
        [strongSelf _operationDidFinish:op withError:error];
    };
    [_downloadOperation startOperationOnQueue:nil];
    
}

- (void)_cleanupWithSuccess:(BOOL)success;
{
    if (!success)
        [[NSNotificationCenter defaultCenter] postNotificationName:OUISyncDownloadCanceledNotification object:self];
    else if (_downloadOperation != nil || [_uploadOperations count] != 0)
        [self cancelDownload:nil];
    
    _file = nil;
    _baseURL = nil;
    _fileQueue = nil;
    _downloadTimestamp = nil;
    _downloadPath = nil;
}

- (NSString *)_downloadLocation;
{
    if (!_downloadTimestamp)
        _downloadTimestamp = [[NSDate date] description];
    
    NSString *fileLocalRelativePath = nil;
    if (_baseURL) {
        NSURL *fileURL = [_file originalURL];
        fileLocalRelativePath = [[fileURL path] stringByRemovingString:[_baseURL path]]; 
        
        NSString *localBase = [NSTemporaryDirectory() stringByAppendingPathComponent:_downloadTimestamp];
        localBase = [localBase stringByAppendingPathComponent:[[_baseURL path] lastPathComponent]];
        return [localBase stringByAppendingPathComponent:fileLocalRelativePath];
    } else {
        NSString *localBase = [NSTemporaryDirectory() stringByAppendingPathComponent:_downloadTimestamp];
        return [localBase stringByAppendingPathComponent:[_file name]];
    }
}

- (void)_readAndQueueContentsOfDirectory:(OFSFileInfo *)aDirectory;
{
    __autoreleasing NSError *outError = nil;
    
    NSArray *fileInfos = [_fileManager directoryContentsAtURL:[aDirectory originalURL] havingExtension:nil options:OFSDirectoryEnumerationForceRecursiveDirectoryRead error:&outError];
    if (outError) {
        OUI_PRESENT_ALERT(outError);
        [self cancelDownload:nil];
        return;
    }
    
    _fileQueue = [[NSMutableArray alloc] init];
    for (OFSFileInfo *fileInfo in fileInfos)
        if (![fileInfo isDirectory])
            [_fileQueue addObject:fileInfo];
}

- (BOOL)_queueUploadFileWrapper:(NSFileWrapper *)fileWrapper atomically:(BOOL)atomically toURL:(NSURL *)targetURL usingFileManager:(OFSFileManager *)fileManager error:(NSError **)outError;
{
#ifdef DEBUG_kc
    NSLog(@"DEBUG: Queueing upload to %@", [targetURL absoluteString]);
#endif
    if ([fileWrapper isDirectory]) {
        targetURL = OFURLWithTrailingSlash(targetURL); // RFC 2518 section 5.2 says: In general clients SHOULD use the "/" form of collection names.
        __autoreleasing NSError *error = nil;
        if (atomically) {
            OBASSERT(_uploadTemporaryURL == nil); // Otherwise we'd need a stack of things to rename rather than just one
            OBASSERT(_uploadFinalURL == nil);
            
            NSString *temporaryNameSuffix = [@"-write-in-progress-" stringByAppendingString:OFXMLCreateID()];
            _uploadFinalURL = targetURL;
            targetURL = OFURLWithTrailingSlash(OFSURLWithNameAffix(targetURL, temporaryNameSuffix, NO, YES));
        }
        NSURL *parentURL = [fileManager createDirectoryAtURL:targetURL attributes:nil error:&error];
        if (atomically) {
            _uploadTemporaryURL = parentURL;
            if (parentURL != nil && !OFURLEqualsURL(parentURL, targetURL)) {
                NSString *rewrittenFinalURLString = OFSURLAnalogousRewrite(targetURL, [_uploadFinalURL absoluteString], parentURL);
                if (rewrittenFinalURLString)
                    _uploadFinalURL = [NSURL URLWithString:rewrittenFinalURLString];
            }
        }

        NSDictionary *childWrappers = [fileWrapper fileWrappers];
        for (NSString *childName in childWrappers) {
            NSFileWrapper *childWrapper = [childWrappers objectForKey:childName];
            NSURL *childURL = OFSFileURLRelativeToDirectoryURL(parentURL, childName);;
            if (![self _queueUploadFileWrapper:childWrapper atomically:NO toURL:childURL usingFileManager:fileManager error:outError])
                return NO;
        }
    } else if ([fileWrapper isRegularFile]) {
        NSData *data = [fileWrapper regularFileContents];
        _totalDataLength += [data length];
        
        __weak OUIWebDAVSyncDownloader *weakSelf = self;

        id <OFSAsynchronousOperation> uploadOperation = [fileManager asynchronousWriteData:data toURL:targetURL atomically:NO];
        uploadOperation.didSendBytes = ^(id <OFSAsynchronousOperation> op, long long byteCount){
            OUIWebDAVSyncDownloader *strongSelf = weakSelf;
            OBASSERT(strongSelf, "Deallocated w/o cancelling operation?");
            [strongSelf _operation:op didSendBytes:byteCount];
        };
        uploadOperation.didFinish = ^(id <OFSAsynchronousOperation> op, NSError *error){
            OUIWebDAVSyncDownloader *strongSelf = weakSelf;
            OBASSERT(strongSelf, "Deallocated w/o cancelling operation?");
            [strongSelf _operationDidFinish:op withError:error];
        };
        
        [_uploadOperations addObject:uploadOperation];
    } else {
        OBASSERT_NOT_REACHED("We only know how to upload files and directories; we skip symlinks and other file types");
    }
    return YES;
}

@end
