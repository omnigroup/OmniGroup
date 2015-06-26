// Copyright 2008-2015 Omni Development, Inc. All rights reserved.
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

@interface ODAVConnection_URLSession () <NSURLSessionDataDelegate, ODAVConnectionSubclass>
@end

@implementation ODAVConnection_URLSession
{
    NSURLSession *_session;
    NSOperationQueue *_delegateQueue;
    
    // Accessed both on the delegate queue and on calling queues that are making new requests, so access to this needs to be serialized.
    NSMutableDictionary *_locked_runningOperationByTask;
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
    
    // The request we are given will already have values -- would these override, or are these just for the convenience methods that make requests?
    //configuration.requestCachePolicy = NSURLRequestUseProtocolCachePolicy;
    //configuration.timeoutIntervalForRequest = 300;
    
    //configuration = ...
    //configuration.URLCredentialStorage = ...
    //configuration.URLCache = ...
    
    /*
     We create a private serial queue for the NSURLSession delegate callbacks. ODAVOperations will receive their internal updates on that queue and then when they fire *their* callbacks, they do it on the queue the initial operation was requested on, or on an explicit queue if -startWithCallbackQueue: was used.
     
     A better scheme might be to have each operation have a serial queue for its notifications and then we can have a concurrent queue for incoming messages, but that would assume that NSURLSession ensures that task-based delegate callbacks are invoked in order. Hopefully none of our delegate callbacks take long enough that it will matter.
     */
    
    _locked_runningOperationByTask = [[NSMutableDictionary alloc] init];
    
    _delegateQueue = [[NSOperationQueue alloc] init];
    _delegateQueue.maxConcurrentOperationCount = 1;
    _delegateQueue.name = [NSString stringWithFormat:@"com.omnigroup.OmniDAV.connection_session_delegate for %p", self];
    
    _session = [NSURLSession sessionWithConfiguration:_configuration delegate:self delegateQueue:_delegateQueue];
    DEBUG_TASK(1, @"Created session %@ with delegate queue %@", _session, _delegateQueue);
    
    return self;
}

- (void)dealloc;
{
    OBFinishPortingLater("Should we let tasks finish or cancel them -- maybe make our caller specify which");
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

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error;
{
    DEBUG_DAV(1, "didBecomeInvalidWithError:%@", error);
    
    // Called with error == nil if you call -invalidateAndCancel
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler;
{
    DEBUG_DAV(1, "didReceiveChallenge:%@", challenge);
    
    [self _handleChallenge:challenge operation:nil completionHandler:completionHandler];
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler;
{
    DEBUG_DAV(1, "task:%@ willPerformHTTPRedirection:%@ newRequest:%@", task, response, request);
    
    ODAVOperation *op = [self _operationForTask:task];
    NSURLRequest *continuation = [op _willSendRequest:request redirectResponse:response];
    if (completionHandler)
        completionHandler(continuation);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler;
{
    DEBUG_DAV(1, "task:%@ didReceiveChallenge:%@", task, challenge);
    
    // We seem to get the server trust challenge directed to the per-session method -URLSession:didReceiveChallenge:completionHandler:, but then the actual login credentials come through here. For now, we direct them to the same method.
    
    ODAVOperation *operation = [self _operationForTask:task];
    [self _handleChallenge:challenge operation:operation completionHandler:completionHandler];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error;
{
    DEBUG_DAV(1, "task:%@ didCompleteWithError:%@", task, error);
    
    /*
     Radar 14557123: NSURLSession can send -URLSession:task:didCompleteWithError: twice for a task.
     Cancelling a task and its normal completion can race and we can end up with two completion notifications.
     */
    
    ODAVOperation *op = [self _operationForTask:task isCompleting:YES];
    [op _didCompleteWithError:error];
    
    @synchronized(self) {
        DEBUG_TASK(1, @"Removing operation %@ for task %@", op, task);
        [_locked_runningOperationByTask removeObjectForKey:task];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
{
    DEBUG_DAV(1, "task:%@ didSendBodyData:%qd totalBytesSent:%qd totalBytesExpectedToSend:%qd", task, bytesSent, totalBytesSent, totalBytesExpectedToSend);
    
    [[self _operationForTask:task] _didSendBodyData:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesSent];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler;
{
    DEBUG_DAV(1, "task:%@ didReceiveResponse:%@", dataTask, response);
    
    [[self _operationForTask:dataTask] _didReceiveResponse:response];
    
    OBFinishPortingLater("OmniDAV should have a means to do file member GETs as downloads to temporary files (NSURLSessionResponseBecomeDownload)");
    if (completionHandler)
        completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data;
{
    DEBUG_DAV(1, "dataTask:%@ didReceiveData:<%@ length=%ld>", dataTask, [data class], [data length]);
    
    [[self _operationForTask:dataTask] _didReceiveData:data];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler;
{
    DEBUG_DAV(1, @"dataTask:%@ willCacheResponse:%@", dataTask, proposedResponse);
    
    if (completionHandler)
        completionHandler(nil); // Don't cache DAV stuff if asked to.
}

@end
