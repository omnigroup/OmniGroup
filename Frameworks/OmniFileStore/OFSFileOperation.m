// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSFileOperation.h"

#import <OmniFileStore/OFSFileManager.h>

RCS_ID("$Id$");

@implementation OFSFileOperation

- initWithFileManager:(OFSFileManager *)fileManager readingURL:(NSURL *)url target:(id <OFSFileManagerAsynchronousOperationTarget>)target;
{
    if (!(self = [super init]))
        return nil;
    
    _nonretained_fileManager = fileManager;
    _url = [url copy];
    _read = YES;
    _data = nil;
    _target = [target retain];
    
    return self;
}

- initWithFileManager:(OFSFileManager *)fileManager writingData:(NSData *)data atomically:(BOOL)atomically toURL:(NSURL *)url target:(id <OFSFileManagerAsynchronousOperationTarget>)target;
{
    if (!(self = [super init]))
        return nil;
    
    _nonretained_fileManager = fileManager;
    _url = [url copy];
    _read = NO;
    _atomically = atomically;
    _data = [data copy];
    _target = [target retain];
    
    return self;
}

- (void)dealloc;
{
    [_url release];
    [_data release];
    [_target release];
    [super dealloc];
}

#pragma mark -
#pragma mark OFSAsynchronousOperation

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

- (void)startOperation;
{
    OBPRECONDITION(_processedLength == 0); // Don't call more than once.
    
    // We do all operations synchronously by default right now.
    if (_read) {
        NSError *error = nil;
        NSData *data = [_nonretained_fileManager dataWithContentsOfURL:_url error:&error];
        if (data == nil) {
            [_target fileManager:_nonretained_fileManager operationDidFinish:self withError:error];
        } else {
            _processedLength = [data length];
            if ([_target respondsToSelector:@selector(fileManager:operation:didReceiveData:)])
                [_target fileManager:_nonretained_fileManager operation:self didReceiveData:data];
            else
                [_target fileManager:_nonretained_fileManager operation:self didProcessBytes:_processedLength];
            [_target fileManager:_nonretained_fileManager operationDidFinish:self withError:nil];
        }
    } else {
        NSError *error = nil;
        if (![_nonretained_fileManager writeData:_data toURL:_url atomically:_atomically error:&error]) {
            [_target fileManager:_nonretained_fileManager operationDidFinish:self withError:error];
        } else {
            _processedLength = [_data length];
            [_target fileManager:_nonretained_fileManager operation:self didProcessBytes:_processedLength];
            [_target fileManager:_nonretained_fileManager operationDidFinish:self withError:nil];
        }
    }
}

- (void)stopOperation;
{
    // no-op: synchronous operation-only
}

@end
