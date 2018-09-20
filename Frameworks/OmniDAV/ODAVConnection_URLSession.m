// Copyright 2008-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODAVConnection_URLSession.h"

#import <OmniFoundation/OFCredentials.h>
#import <OmniDAV/ODAVOperation.h>
#import "ODAVOperation-Internal.h"
#import "ODAVConnection-Subclass.h"

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

// NSURLSession retains its delegate until it is invalidated. Break this up...
@interface ODAVConnectionDelegate_URLSession : NSObject <NSURLSessionDataDelegate>
- initWithConnection:(ODAVConnection_URLSession *)connection;
@end


@interface ODAVConnection_URLSession () <ODAVConnectionSubclass>
@end

@implementation ODAVConnection_URLSession
{
    NSURLSession *_session;
    NSOperationQueue *_delegateQueue;
    
    // Accessed both on the delegate queue and on calling queues that are making new requests, so access to this needs to be serialized.
    NSMutableDictionary<NSURLSessionTask *, ODAVOperation *> *_locked_runningOperationByTask;
}

- initWithSessionConfiguration:(ODAVConnectionConfiguration *)configuration baseURL:(NSURL *)baseURL;
{
    if (!(self = [super initWithSessionConfiguration:configuration baseURL:baseURL]))
        return nil;
    
    NSURLSessionConfiguration *_configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    // Controlled by Settings.app on iOS.
    _configuration.allowsCellularAccess = YES;
    
    // HTTP pipelining defaults to off with NSURLSession and did with NSURLConnection as well it seems? At least NSURLRequest has it off by default.
    _configuration.HTTPShouldUsePipelining = configuration.HTTPShouldUsePipelining;

    // configuration.identifier -- set this for background operations

    // Default to not caching any DAV operations (as we did in ODAVConnection_URLConnection). Individual requests can override.
    _configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

    //configuration.timeoutIntervalForRequest = 300;
    
    //configuration = ...
    //configuration.URLCredentialStorage = ...
    
    _configuration.URLCache = nil;
    
    /*
     We create a private serial queue for the NSURLSession delegate callbacks. ODAVOperations will receive their internal updates on that queue and then when they fire *their* callbacks, they do it on the queue the initial operation was requested on, or on an explicit queue if -startWithCallbackQueue: was used.
     
     A better scheme might be to have each operation have a serial queue for its notifications and then we can have a concurrent queue for incoming messages, but that would assume that NSURLSession ensures that task-based delegate callbacks are invoked in order. Hopefully none of our delegate callbacks take long enough that it will matter.
     */
    
    _locked_runningOperationByTask = [[NSMutableDictionary alloc] init];
    
    _delegateQueue = [[NSOperationQueue alloc] init];
    _delegateQueue.maxConcurrentOperationCount = 1;
    _delegateQueue.name = [NSString stringWithFormat:@"com.omnigroup.OmniDAV.connection_session_delegate for %p", self];

    ODAVConnectionDelegate_URLSession *delegate = [[ODAVConnectionDelegate_URLSession alloc] initWithConnection:self];

    _session = [NSURLSession sessionWithConfiguration:_configuration delegate:delegate delegateQueue:_delegateQueue];
    DEBUG_DAV(1, @"Created session %@ with interposing delegate %@ and queue %@", _session, delegate, _delegateQueue);
    
    return self;
}

- (void)dealloc;
{
    DEBUG_DAV(1, "Destroying connection");

    OBFinishPortingLater("<bug:///147931> (iOS-OmniOutliner Engineering: Should we let tasks finish or cancel them -- maybe make our caller specify which - in -[ODAVConnection_URLSession dealloc])");
    [_session finishTasksAndInvalidate];
    [_delegateQueue waitUntilAllOperationsAreFinished];
}

- (ODAVOperation *)_operationForTask:(NSURLSessionTask *)task;
{
    return [self _operationForTask:task isCompleting:NO];
}

- (ODAVOperation *)_operationForTask:(NSURLSessionTask *)task isCompleting:(BOOL)isCompleting;
{
    ODAVOperation *operation;
    @synchronized(self) {
        operation = _locked_runningOperationByTask[task];
        DEBUG_TASK(2, @"Found operation %@ for task %@", operation, task);
    }
    OBASSERT(isCompleting || operation); // Allow the operation to not be found if we are completing. See note about Radar 14557123.
    return operation;
}

- (ODAVOperation *)_makeOperationForRequest:(NSURLRequest *)request;
{
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request];
    ODAVOperation *operation = [[ODAVOperation alloc] initWithRequest:request start:^{
        DEBUG_TASK(1, @"starting task %@", task);
        DEBUG_TASK(2, @"headers %@", task.originalRequest.allHTTPHeaderFields);
        [task resume];
    }
                                                               cancel:^{
                                                                   DEBUG_TASK(1, @"cancelling task %@", task);
                                                                   [task cancel];
                                                               }];
    
    @synchronized(self) {
        _locked_runningOperationByTask[task] = operation;
        DEBUG_TASK(1, @"Added operation %@ for task %@", operation, task);
    }

    return operation;
}

- (void)_taskCompleted:(NSURLSessionTask *)task error:(nullable NSError *)error;
{
    /*
     Radar 14557123: NSURLSession can send -URLSession:task:didCompleteWithError: twice for a task.
     Cancelling a task and its normal completion can race and we can end up with two completion notifications.
     */

    ODAVOperation *op = [self _operationForTask:task isCompleting:YES];

    [op _didCompleteWithError:error connection:self];

    @synchronized(self) {
        DEBUG_TASK(1, @"Removing operation %@ for task %@", op, task);
        [_locked_runningOperationByTask removeObjectForKey:task];
    }
}

@end

@implementation ODAVConnectionDelegate_URLSession
{
    __weak ODAVConnection_URLSession *_weak_connection;
}

- initWithConnection:(ODAVConnection_URLSession *)connection;
{
    self = [super init];
    _weak_connection = connection;
    return self;
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error;
{
    DEBUG_DAV(1, "didBecomeInvalidWithError:%@", error);
    
    // Called with error == nil if you call -invalidateAndCancel
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler;
{
    DEBUG_DAV(1, "didReceiveChallenge:%@", challenge);

    ODAVConnection_URLSession *connection = _weak_connection;
    if (!connection) {
        if (completionHandler) {
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        }
        return;
    }
    
    // This is called for challenges that aren't related to a specific request, such as proxy authentication, TLS setup, Kerberos negotiation, etc.

    [connection _handleChallenge:challenge operation:nil completionHandler:completionHandler];
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler;
{
    DEBUG_DAV(1, "task:%@ willPerformHTTPRedirection:%@ newRequest:%@", task, response, request);
    
    ODAVConnection_URLSession *connection = _weak_connection;
    if (!connection) {
        if (completionHandler) {
            completionHandler(request);
        }
        return;
    }

    ODAVOperation *op = [connection _operationForTask:task];
    NSURLRequest *continuation = [op _willSendRequest:request redirectResponse:response];
    if (completionHandler)
        completionHandler(continuation);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler;
{
    DEBUG_DAV(1, "task:%@ didReceiveChallenge:%@", task, challenge);
    
    ODAVConnection_URLSession *connection = _weak_connection;
    if (!connection) {
        if (completionHandler) {
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        }
        return;
    }

    // We seem to get the server trust challenge directed to the per-session method -URLSession:didReceiveChallenge:completionHandler:, but then the actual login credentials come through here. For now, we direct them to the same method.
    
    ODAVOperation *operation = [connection _operationForTask:task];
    [connection _handleChallenge:challenge operation:operation completionHandler:completionHandler];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error;
{
    DEBUG_DAV(1, "task:%@ didCompleteWithError:%@", task, error);
    
    ODAVConnection_URLSession *connection = _weak_connection;
    if (!connection) {
        return;
    }

    [connection _taskCompleted:task error:error];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
{
    DEBUG_DAV(1, "task:%@ didSendBodyData:%qd totalBytesSent:%qd totalBytesExpectedToSend:%qd", task, bytesSent, totalBytesSent, totalBytesExpectedToSend);
    
    ODAVConnection_URLSession *connection = _weak_connection;
    if (!connection) {
        return;
    }

    [[connection _operationForTask:task] _didSendBodyData:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesExpectedToSend];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler;
{
    DEBUG_DAV(1, "task:%@ didReceiveResponse:%@", dataTask, response);
    
    ODAVConnection_URLSession *connection = _weak_connection;
    if (!connection) {
        if (completionHandler) {
            completionHandler(NSURLSessionResponseAllow);
        }
        return;
    }

    [[connection _operationForTask:dataTask] _didReceiveResponse:response];
    
    OBFinishPortingLater("<bug:///147932> (iOS-OmniOutliner Bug: OmniDAV should have a means to do file member GETs as downloads to temporary files (NSURLSessionResponseBecomeDownload))");
    if (completionHandler)
        completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data;
{
    DEBUG_DAV(1, "dataTask:%@ didReceiveData:<%@ length=%ld>", dataTask, [data class], [data length]);
    
    ODAVConnection_URLSession *connection = _weak_connection;
    if (!connection) {
        return;
    }

    [[connection _operationForTask:dataTask] _didReceiveData:data];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse * _Nullable cachedResponse))completionHandler;
{
    DEBUG_DAV(1, @"dataTask:%@ willCacheResponse:%@", dataTask, proposedResponse);

    if (completionHandler)
        completionHandler(nil); // Don't cache DAV stuff if asked to.
}

@end

NS_ASSUME_NONNULL_END
