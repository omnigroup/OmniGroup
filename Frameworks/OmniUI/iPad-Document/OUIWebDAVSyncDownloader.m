// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIWebDAVSyncDownloader.h"


#import <MobileCoreServices/MobileCoreServices.h>
#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVOperation.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSUtilities.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFUTI.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$");

@implementation OUIWebDAVSyncDownloader
{
    ODAVConnection *_connection;
    ODAVOperation *_downloadOperation;
    NSOutputStream *_downloadStream;
    NSMutableArray *_uploadOperations;
    
    ODAVFileInfo *_file;
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

- initWithConnection:(ODAVConnection *)connection;
{
    OBPRECONDITION(connection);
    
    if (!(self = [super init]))
        return nil;
    
    _connection = connection;
    
    return self;
}

#pragma mark - OUIConcreteSyncDownloader

- (void)download:(ODAVFileInfo *)aFile;
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
        for (ODAVFileInfo *nextFile in _fileQueue)
            _totalDataLength += nextFile.size;
        
        ODAVFileInfo *firstFile = [_fileQueue lastObject];
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
        [_downloadOperation cancel];
    } else if (_uploadOperations != nil) {
        for (ODAVOperation *uploadOperation in _uploadOperations)
            [uploadOperation cancel];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUISyncDownloadCanceledNotification object:self];
}

- (void)uploadFileWrapper:(NSFileWrapper *)fileWrapper toURL:(NSURL *)targetURL;
{
    OBPRECONDITION(_connection);
    
    _totalDataLength = 0;
    _uploadOperations = [[NSMutableArray alloc] init];
    __autoreleasing NSError *error = nil;
    OBASSERT (_baseURL == nil);
    _baseURL = targetURL;
    if (![self _queueUploadFileWrapper:fileWrapper atomically:YES toURL:targetURL connection:_connection error:&error]) {
        OBASSERT(error != nil);
        OUI_PRESENT_ERROR(error);
        [self _cleanupWithSuccess:NO];
        return;
    }
    for (ODAVOperation *uploadOperation in [NSArray arrayWithArray:_uploadOperations]) {
        [uploadOperation startWithCallbackQueue:[NSOperationQueue mainQueue]];
    }
}

#pragma mark - Async operation handlers

- (void)_operation:(ODAVOperation *)operation didReceiveData:(NSData *)data;
{    
    OBPRECONDITION(operation == _downloadOperation);
    
    self.progressView.progress = (double)operation.processedLength/(double)_totalDataLength;
    
    if ([_downloadStream write:[data bytes] maxLength:[data length]] == -1) {
        OUI_PRESENT_ERROR([_downloadStream streamError]);
        [self _cleanupWithSuccess:NO];
        return;
    }
}

- (void)_operation:(ODAVOperation *)operation didSendBytes:(long long)processedBytes;
{    
    OBPRECONDITION(_uploadOperations == nil || [_uploadOperations containsObjectIdenticalTo:operation]);
    if (_uploadOperations == nil)
        return; // We've cancelled these uploads
    
    _totalUploadedBytes += processedBytes;
    self.progressView.progress = (double)_totalUploadedBytes/(double)_totalDataLength;
}

- (void)_operationDidFinish:(ODAVOperation *)operation withError:(NSError *)error;
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
            ODAVFileInfo *firstFile = [_fileQueue lastObject];
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
        } else if (ODSIsZipFileType(fileUTI)) {
            __autoreleasing NSError *unarchiveError = nil;
            localFile = [self unarchiveFileAtPath:localFile error:&unarchiveError];
            if (!localFile || unarchiveError)
                OUI_PRESENT_ERROR(unarchiveError);
        }
        
        if (localFile) {
            [self.cancelButton setTitle:NSLocalizedStringFromTableInBundle(@"Finished", @"OmniUIDocument", OMNI_BUNDLE, @"finished") forState:UIControlStateNormal];
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
            [_connection synchronousDeleteURL:_uploadFinalURL withETag:nil error:NULL]; // Ignore delete errors
            
            // we might be replacing a file with a directory, check the verison with and without a slash.
            NSString *url = [_uploadFinalURL absoluteString];
            if ([url hasSuffix:@"/"]) {
                url = [url substringToIndex:[url length] - 1]; // if it's got a trailing slash, trim it.
                [_connection synchronousDeleteURL:[NSURL URLWithString:url] withETag:nil error:NULL];
            }
            __autoreleasing NSError *moveError = nil;
            if (![_connection synchronousMoveURL:_uploadTemporaryURL toMissingURL:_uploadFinalURL error:&moveError]) {
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

- (void)_downloadFile:(ODAVFileInfo *)aFile;
{    
    _file = aFile;
        
    NSString *localFilePath = [self _downloadLocation];
    NSString *localFileDirectory = [localFilePath stringByDeletingLastPathComponent];
    
    __autoreleasing NSError *createDirectoryError;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:localFileDirectory withIntermediateDirectories:YES attributes:nil error:&createDirectoryError]) {
        OUI_PRESENT_ALERT(createDirectoryError);
        [self cancelDownload:nil];
        return;
    }
    
    _downloadStream = [[NSOutputStream alloc] initToFileAtPath:localFilePath append:NO];
    [_downloadStream open];
    
    OBASSERT(_downloadOperation == nil);
    _downloadOperation = [_connection asynchronousGetContentsOfURL:aFile.originalURL];
    
    __weak OUIWebDAVSyncDownloader *weakSelf = self;
    _downloadOperation.didReceiveData = ^(ODAVOperation *op, NSData *data){
        OUIWebDAVSyncDownloader *strongSelf = weakSelf;
        OBASSERT(strongSelf, "Deallocated w/o cancelling operation?");
        [strongSelf _operation:op didReceiveData:data];
    };
    _downloadOperation.didFinish = ^(ODAVOperation *op, NSError *error){
        OUIWebDAVSyncDownloader *strongSelf = weakSelf;
        OBASSERT(strongSelf, "Deallocated w/o cancelling operation?");
        [strongSelf _operationDidFinish:op withError:error];
    };
    [_downloadOperation startWithCallbackQueue:[NSOperationQueue mainQueue]];
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

- (void)_readAndQueueContentsOfDirectory:(ODAVFileInfo *)rootDirectory;
{
    __autoreleasing NSError *error = nil;
    
    NSMutableArray *directoryFileInfos = [NSMutableArray arrayWithObject:rootDirectory];
    NSMutableArray *fileQueue = [[NSMutableArray alloc] init];
    
    while ([directoryFileInfos count] > 0) {
        ODAVFileInfo *directory = [directoryFileInfos lastObject];
        
        ODAVMultipleFileInfoResult *result = [_connection synchronousDirectoryContentsAtURL:directory.originalURL withETag:nil error:&error];
        if (!result) {
            OUI_PRESENT_ALERT(error);
            [self cancelDownload:nil];
            return;
        }
        [directoryFileInfos removeLastObject];

        for (ODAVFileInfo *fileInfo in result.fileInfos) {
            if (fileInfo.isDirectory)
                [directoryFileInfos addObject:fileInfo];
            else
                [fileQueue addObject:fileInfo];
        }
    }
    
    _fileQueue = fileQueue;
}

- (BOOL)_queueUploadFileWrapper:(NSFileWrapper *)fileWrapper atomically:(BOOL)atomically toURL:(NSURL *)targetURL connection:(ODAVConnection *)connection error:(NSError **)outError;
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
            targetURL = OFURLWithTrailingSlash(OFURLWithNameAffix(targetURL, temporaryNameSuffix, NO, YES));
        }
        
        NSURL *parentURL = [connection synchronousMakeCollectionAtURL:targetURL error:&error].URL;
        if (atomically) {
            _uploadTemporaryURL = parentURL;
            if (parentURL != nil && !OFURLEqualsURL(parentURL, targetURL)) {
                NSString *rewrittenFinalURLString = OFURLAnalogousRewrite(targetURL, [_uploadFinalURL absoluteString], parentURL);
                if (rewrittenFinalURLString)
                    _uploadFinalURL = [NSURL URLWithString:rewrittenFinalURLString];
            }
        }

        NSDictionary *childWrappers = [fileWrapper fileWrappers];
        for (NSString *childName in childWrappers) {
            NSFileWrapper *childWrapper = [childWrappers objectForKey:childName];
            NSURL *childURL = OFFileURLRelativeToDirectoryURL(parentURL, childName);
            if (![self _queueUploadFileWrapper:childWrapper atomically:NO toURL:childURL connection:connection error:outError])
                return NO;
        }
    } else if ([fileWrapper isRegularFile]) {
        NSData *data = [fileWrapper regularFileContents];
        _totalDataLength += [data length];
        
        if ([[targetURL absoluteString] hasSuffix:@"/"]) {// we're replacing a package w/ a flat file
            OBASSERT(_uploadTemporaryURL == nil); // Otherwise we'd need a stack of things to rename rather than just one
            OBASSERT(_uploadFinalURL == nil);
            
            NSString *temporaryNameSuffix = [@"-write-in-progress-" stringByAppendingString:OFXMLCreateID()];
            _uploadFinalURL = targetURL;
            targetURL = OFURLWithNameAffix(targetURL, temporaryNameSuffix, NO, YES);
            _uploadTemporaryURL = targetURL;
        }
        __weak OUIWebDAVSyncDownloader *weakSelf = self;

        ODAVOperation *uploadOperation = [connection asynchronousPutData:data toURL:targetURL];
        uploadOperation.didSendBytes = ^(ODAVOperation *op, long long byteCount){
            OUIWebDAVSyncDownloader *strongSelf = weakSelf;
            OBASSERT(strongSelf, "Deallocated w/o cancelling operation?");
            [strongSelf _operation:op didSendBytes:byteCount];
        };
        uploadOperation.didFinish = ^(ODAVOperation *op, NSError *error){
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
