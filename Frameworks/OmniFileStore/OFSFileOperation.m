// Copyright 2008-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSFileOperation.h"

#import <OmniFileStore/OFSFileManager.h>

RCS_ID("$Id$");

@implementation OFSFileOperation
{
    __weak OFSFileManager *_weak_fileManager;
    NSOperationQueue *_callbackQueue;
    NSData *_data;
    enum {
        OFSFileOperationRead,
        OFSFileOperationWrite,
        OFSFileOperationDelete
    } _op;
    BOOL _atomically; // for writing
    NSURL *_url;

    long long _processedLength;
}

- initWithFileManager:(OFSFileManager *)fileManager readingURL:(NSURL *)url;
{
    if (!(self = [super init]))
        return nil;
    
    _weak_fileManager = fileManager;
    _url = [url copy];
    _op = OFSFileOperationRead;
    _data = nil;
    
    return self;
}

- initWithFileManager:(OFSFileManager *)fileManager writingData:(NSData *)data atomically:(BOOL)atomically toURL:(NSURL *)url;
{
    if (!(self = [super init]))
        return nil;
    
    _weak_fileManager = fileManager;
    _url = [url copy];
    _op = OFSFileOperationWrite;
    _atomically = atomically;
    _data = [data copy];
    
    return self;
}

- initWithFileManager:(OFSFileManager *)fileManager deletingURL:(NSURL *)url;
{
    if (!(self = [super init]))
        return nil;
    
    _weak_fileManager = fileManager;
    _url = [url copy];
    _op = OFSFileOperationDelete;
    _data = nil;
    
    return self;
}

#pragma mark - ODAVAsynchronousOperation

// These callbacks should all be called with this macro
#define PERFORM_CALLBACK(callback, ...) do { \
    typeof(callback) _cb = (callback); \
    if (_cb) { \
        [_callbackQueue addOperationWithBlock:^{ \
            _cb(__VA_ARGS__); \
        }]; \
    } \
} while(0)

@synthesize shouldRetry = _shouldRetry;
@synthesize willRetry = _willRetry;
@synthesize didFinish = _didFinish;
@synthesize didReceiveData = _didReceiveData;
@synthesize didReceiveBytes = _didReceiveBytes;
@synthesize didSendBytes = _didSendBytes;

- (NSURL *)url;
{
    return _url;
}

- (long long)processedLength;
{
    return _processedLength;
}

- (long long)expectedLength;
{
    return [_data length];
}

- (NSData *)resultData;
{
    if (_op != OFSFileOperationRead)
        OBRejectInvalidCall(self, _cmd, @"Not a read operation (_op = %d)", _op);
    
    return _data;
}

- (void)startWithCallbackQueue:(NSOperationQueue *)queue;
{
    OBPRECONDITION(_didFinish); // What is the purpose of an async operation that we don't track the end of?
    OBPRECONDITION(_processedLength == 0); // Don't call more than once.
    
    if (queue)
        _callbackQueue = queue;
    else
        _callbackQueue = [NSOperationQueue currentQueue];

    OFSFileManager *fileManager = _weak_fileManager;
    if (!fileManager) {
        OBASSERT_NOT_REACHED("File manager released with unfinished operations");
        return;
    }
    
    // We do all operations synchronously by default right now.
    __autoreleasing NSError *error = nil;
    switch(_op) {
      case OFSFileOperationRead:
      {
        NSData *data = [fileManager dataWithContentsOfURL:_url error:&error];
        if (data == nil) {
            NSError *strongError = error;
            PERFORM_CALLBACK(_didFinish, self, strongError);
        } else {
            _processedLength = [data length];
            if (_didReceiveData) {
                PERFORM_CALLBACK(_didReceiveData, self, data);
            } else if (_didReceiveBytes) {
                PERFORM_CALLBACK(_didReceiveBytes, self, _processedLength);
            }
            if (!_didReceiveData)
                _data = data;
            PERFORM_CALLBACK(_didFinish, self, nil);
        }
        break;
      }
      case OFSFileOperationWrite:
      {
        if (![fileManager writeData:_data toURL:_url atomically:_atomically error:&error]) {
            NSError *strongError = error;
            PERFORM_CALLBACK(_didFinish, self, strongError);
        } else {
            _processedLength = [_data length];
            PERFORM_CALLBACK(_didSendBytes, self, _processedLength);
            PERFORM_CALLBACK(_didFinish, self, nil);
        }
        break;
      }
      case OFSFileOperationDelete:
      {
        if (![fileManager deleteURL:_url error:&error]) {
            NSError *strongError = error;
            PERFORM_CALLBACK(_didFinish, self, strongError);
        } else {
            PERFORM_CALLBACK(_didFinish, self, nil);
        }
        break;
      }
    }
}

- (void)cancel;
{
    // no-op: synchronous operation-only
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

@end
