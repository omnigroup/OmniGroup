// Copyright 2008-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODAVConnection_URLConnection.h"

#import <OmniFoundation/OFCredentials.h>

#import "ODAVOperation-Internal.h"
#import "ODAVConnection-Subclass.h"

RCS_ID("$Id$")

@interface ODAVConnection_URLConnection () <ODAVConnectionSubclass>
@end

@implementation ODAVConnection_URLConnection
{
    ODAVConnectionConfiguration *_configuration;
    
    // Accessed both on the delegate queue and on calling queues that are making new requests, so access to this needs to be serialized.
    NSMapTable *_locked_runningOperationByConnection;
    
    NSOperationQueue *_delegateQueue;
}

- initWithSessionConfiguration:(ODAVConnectionConfiguration *)configuration baseURL:(NSURL *)baseURL;
{
    if (!(self = [super initWithSessionConfiguration:configuration baseURL:baseURL]))
        return nil;
        
    _locked_runningOperationByConnection = [NSMapTable strongToStrongObjectsMapTable];
    DEBUG_TASK(1, @"Starting connection");
    
    _delegateQueue = [[NSOperationQueue alloc] init];
    _delegateQueue.maxConcurrentOperationCount = 1;
    _delegateQueue.name = [NSString stringWithFormat:@"com.omnigroup.OmniDAV.connection_delegate for %p", self];
    
    return self;
}

- (void)dealloc;
{
    [_delegateQueue waitUntilAllOperationsAreFinished];
}

- (ODAVOperation *)_operationForConnection:(NSURLConnection *)connection;
{
    return [self _operationForConnection:connection andRemove:NO];
}

- (ODAVOperation *)_operationForConnection:(NSURLConnection *)connection andRemove:(BOOL)removeOperation;
{
    ODAVOperation *operation;
    @synchronized(self) {
        operation = [_locked_runningOperationByConnection objectForKey:connection];
        DEBUG_TASK(2, @"Found operation %@ for connection %@", operation, connection);
        
        if (removeOperation) {
            [_locked_runningOperationByConnection removeObjectForKey:connection];
        }
    }
    OBASSERT(operation);
    return operation;
}

- (ODAVOperation *)_makeOperationForRequest:(NSURLRequest *)request;
{
    // This whole class is unused by default now, in favor of the NSURLSession-based peer
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [connection setDelegateQueue:_delegateQueue];
#pragma clang diagnostic pop

    ODAVOperation *operation = [[ODAVOperation alloc] initWithRequest:request
                                                                start:^{
                                                                    DEBUG_TASK(1, @"starting connection %@", connection);
                                                                    [connection start]; // We do NOT call -setDelegateQueue: here since the ODAVConnection does this with its internal queue. The queue passed here is for our callbacks.
                                                                }
                                                               cancel:^{
                                                                   DEBUG_TASK(1, @"cancelling connection %@", connection);
                                                                   [connection cancel];
                                                               }];
    
    @synchronized(self) {
        [_locked_runningOperationByConnection setObject:operation forKey:connection];
        DEBUG_TASK(1, @"Added operation %@ for connection %@", operation, connection);
    }
    
    return operation;
}

#pragma mark - NSURLConnectionDelegate

#define MaximumRetries (5)

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
{
    ODAVOperation *op = [self _operationForConnection:connection andRemove:YES];
    
    DEBUG_DAV(3, @"did fail with error %@", error);
    
    if ([error hasUnderlyingErrorDomain:(NSString *)kCFErrorDomainCFNetwork code:kCFURLErrorNetworkConnectionLost]) {
        if (!op.retryable || op.didReceiveBytes || op.didReceiveData || op.didSendBytes) {
            // Retry will need to be handled at a higher level since we might have sent/gotten some bytes and these blocks might have reported some progress already. But if we only have a 'did finish', we can just start over (assuming this is a repeatable operation like a GET/PROPFIND). If this is a PUT/POST or other mutating command, we can't know here whether the operation actually happened on the server.
        } else  if (op.retryIndex < MaximumRetries) {
            // Try again -- server shut down the remote side of a HTTP 1.1 connection, maybe?
            ODAVOperation *retry = [self _makeOperationForRequest:op.request];
            
            retry.didFinish = op.didFinish;
            retry.retryIndex = op.retryIndex + 1;
            
            DEBUG_DAV(2, @"connection lost; retrying with new op: %@", OBShortObjectDescription(retry));
            
            [retry startWithCallbackQueue:op.callbackQueue];
            return;
        }
    }
    
    [op _didCompleteWithError:error];
}

#if 0 // As far as I can tell, this never gets called (maybe since we implement -connection:willSendRequestForAuthenticationChallenge:.
- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection *)connection;
{
    OFSFileManager *fileManager = _weak_fileManager;
    OBASSERT(fileManager, "File manager deallocated before operations finished");
    
    id <OFSFileManagerDelegate> delegate = fileManager.delegate;
    if ([delegate respondsToSelector:@selector(fileManagerShouldUseCredentialStorage:)])
        return [delegate fileManagerShouldUseCredentialStorage:fileManager];
    else
        return YES;
}
#endif

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    OBASSERT([challenge sender], "NSURLConnection-based challenged need the old 'sender' calls.");
    
    [self _handleChallenge:challenge operation:[self _operationForConnection:connection] completionHandler:^(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential) {
        switch (disposition) {
            case NSURLSessionAuthChallengeUseCredential:
                if (credential)
                    [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
                else {
                    [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
                }
                break;
            default:
                DEBUG_DAV(0, "Unhandled auth challenge disposition %ld", disposition);
                break;
        }
    }];
}

#pragma mark - NSURLConnectionDataDelegate

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse;
{
    return [[self _operationForConnection:connection] _willSendRequest:request redirectResponse:redirectResponse];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
{
    [[self _operationForConnection:connection] _didReceiveResponse:response];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
{
    [[self _operationForConnection:connection] _didReceiveData:data];
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite;
{
    [[self _operationForConnection:connection] _didSendBodyData:bytesWritten totalBytesSent:totalBytesWritten totalBytesExpectedToSend:totalBytesExpectedToWrite];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
{
    [[self _operationForConnection:connection andRemove:YES] _didCompleteWithError:nil];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse;
{
    DEBUG_DAV(2, @"will cache response %@", cachedResponse);
    return nil; // Don't cache DAV stuff if asked to.
}

@end
