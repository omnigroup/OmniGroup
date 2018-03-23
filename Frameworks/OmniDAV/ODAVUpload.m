// Copyright 2008-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDAV/ODAVUpload.h>

#import <OmniDAV/ODAVOperation.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/NSArray-OFExtensions.h>

RCS_ID("$Id$");

@implementation ODAVUpload
{
    NSURL *_baseURL;
    BOOL _createParentCollections;
    ODAVConnection *_connection;
    ODAVConnectionURLCompletionHandler _completionHandler;
    
    NSOperationQueue *_operationQueue;
    
    NSMutableArray *_uploadOperations;
    ODAVURLResult *_baseURLResult;
    off_t _totalDataLength;
    off_t _totalUploadedBytes;
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- _initWithFileWrapper:(NSFileWrapper *)fileWrapper toURL:(NSURL *)toURL createParentCollections:(BOOL)createParentCollections connection:(ODAVConnection *)connection completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
{
    OBPRECONDITION(fileWrapper);
    OBPRECONDITION(toURL);
    OBPRECONDITION(connection);
    
    if (!(self = [super init]))
        return nil;

    // Make sure that we can compare _baseURL/targetURL while creating collections
    if ([fileWrapper isDirectory]) {
        toURL = OFURLWithTrailingSlash(toURL);
    }

    _baseURL = [toURL copy];
    _createParentCollections = createParentCollections;
    _connection = connection;
    _completionHandler = [completionHandler copy];
    
    
    _totalDataLength = 0;
    _uploadOperations = [[NSMutableArray alloc] init];
    
    _operationQueue = [[NSOperationQueue alloc] init];
    _operationQueue.name = @"com.omnigroup.OmniDAV.Upload";
    _operationQueue.maxConcurrentOperationCount = 1;
    
    // Keep ourselves alive until we are finished
    OBStrongRetain(self);
    
    [_operationQueue addOperationWithBlock:^{
        __autoreleasing NSError *error = nil;
        
        if (![self _queueUploadFileWrapper:fileWrapper toURL:_baseURL error:&error]) {
            OBASSERT(error != nil);
            [self _finishedWithResult:nil error:error];
            return;
        }
        
        for (ODAVOperation *uploadOperation in [NSArray arrayWithArray:_uploadOperations]) {
            [uploadOperation startWithCallbackQueue:_operationQueue];
        }
    }];
    
    return self;
}

+ (void)uploadFileWrapper:(NSFileWrapper *)fileWrapper toURL:(NSURL *)toURL createParentCollections:(BOOL)createParentCollections connection:(ODAVConnection *)connection completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
{
    ODAVUpload *upload = [[ODAVUpload alloc] _initWithFileWrapper:fileWrapper toURL:toURL createParentCollections:createParentCollections connection:connection completionHandler:completionHandler];
    [upload self];
}

#pragma mark - Async operation handlers

- (void)_operation:(ODAVOperation *)operation didSendBytes:(long long)processedBytes;
{
    OBPRECONDITION(_uploadOperations == nil || [_uploadOperations containsObjectIdenticalTo:operation]);

    if (_uploadOperations == nil)
        return; // We've cancelled these uploads
    
    // TODO: Report progress via NSProgress or KVO on the main queue
    _totalUploadedBytes += processedBytes;
}

- (void)_operationDidFinish:(ODAVOperation *)operation withError:(NSError *)error;
{
    // Some operation that we cancelled due to a failure in an operation before it in the queue? See <bug:///72669> (Exporting files which time out leaves you in a weird state)
    if ([_uploadOperations containsObjectIdenticalTo:operation] == NO)
        return;
    
    if (error) {
        [self _finishedWithResult:nil error:error];
        return;
    }
    
    // An upload finished
    OBASSERT([_uploadOperations containsObjectIdenticalTo:operation]);
    [_uploadOperations removeObjectIdenticalTo:operation];
    if ([_uploadOperations count] > 0)
        return; // Still waiting for more uploads

    // We don't do a final move-into-place for atomic uploads, assuming that our caller will do that.
    OBASSERT(_baseURLResult);
    [self _finishedWithResult:_baseURLResult error:nil];
}

#pragma mark - Private

- (BOOL)_queueUploadFileWrapper:(NSFileWrapper *)fileWrapper toURL:(NSURL *)targetURL error:(NSError **)outError;
{
    if ([fileWrapper isDirectory]) {
        targetURL = OFURLWithTrailingSlash(targetURL); // RFC 2518 section 5.2 says: In general clients SHOULD use the "/" form of collection names.

        __autoreleasing NSError *error = nil;
        __block ODAVURLResult *targetResult = [_connection synchronousMakeCollectionAtURL:targetURL error:&error];
        
        // Might need to create the container if requested to do so.
        if (!targetResult) {
            if (targetURL == _baseURL && _createParentCollections) {
                __block ODAVURLResult *strongResult;
                __block NSError *strongError;
                
                ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done){
                    [_connection makeCollectionAtURLIfMissing:targetURL baseURL:nil completionHandler:^(ODAVURLResult *createResult, NSError *createError) {
                        strongResult = createResult;
                        strongError = createError;
                        done();
                    }];
                });
                
                if (!strongResult) {
                    if (outError)
                        *outError = strongError;
                    return NO;
                } else {
                    targetResult = strongResult;
                }
            } else {
                // We didn't have a targetResult and were not able/allowed to create one, so propagate the error out.
                return NO;
            }
        }
        
        if (targetURL == _baseURL) {
            _baseURLResult = targetResult;
        }
        
        NSDictionary *childWrappers = [fileWrapper fileWrappers];
        for (NSString *childName in childWrappers) {
            NSFileWrapper *childWrapper = [childWrappers objectForKey:childName];
            NSURL *childURL = OFFileURLRelativeToDirectoryURL(targetResult.URL, childName);
            if (![self _queueUploadFileWrapper:childWrapper toURL:childURL error:outError])
                return NO;
        }
    } else if ([fileWrapper isRegularFile]) {
        NSData *data = [fileWrapper regularFileContents];
        _totalDataLength += [data length];
        
        __weak ODAVUpload *weakSelf = self;
        
        ODAVOperation *uploadOperation = [_connection asynchronousPutData:data toURL:targetURL];
        uploadOperation.didSendBytes = ^(ODAVOperation *op, long long byteCount){
            ODAVUpload *strongSelf = weakSelf;
            OBASSERT(strongSelf, "Deallocated w/o cancelling operation?");
            [strongSelf _operation:op didSendBytes:byteCount];
        };
        uploadOperation.didFinish = ^(ODAVOperation *op, NSError *error){
            ODAVUpload *strongSelf = weakSelf;
            OBASSERT(strongSelf, "Deallocated w/o cancelling operation?");
            [strongSelf _operationDidFinish:op withError:error];
        };
        
        [_uploadOperations addObject:uploadOperation];
    } else {
        OBASSERT_NOT_REACHED("We only know how to upload files and directories; we skip symlinks and other file types");
    }
    return YES;
}

- (void)_finishedWithResult:(ODAVURLResult *)result error:(NSError *)error;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);
    
    for (ODAVOperation *uploadOperation in _uploadOperations)
        [uploadOperation cancel];
    [_uploadOperations removeAllObjects];

    if (_completionHandler) {
        ODAVConnectionURLCompletionHandler completionHandler = _completionHandler;
        _completionHandler = nil;
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            completionHandler(result, error);
            OBAutorelease(self); // Matching extra retain when starting
        }];
    } else {
        OBAutorelease(self); // Matching extra retain when starting
    }
}


@end
