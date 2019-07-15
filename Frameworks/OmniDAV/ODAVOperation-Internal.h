// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDAV/ODAVOperation.h>

@class ODAVConnection;

@interface ODAVOperation ()

- initWithRequest:(NSURLRequest *)request
            start:(void (^)(void))start
           cancel:(void (^)(void))cancel;

@property(nonatomic,readonly) NSURLRequest *request;
@property(nonatomic,readonly) NSOperationQueue *callbackQueue;

- (void)_credentialsNotFoundForChallenge:(NSURLAuthenticationChallenge *)challenge disposition:(NSURLSessionAuthChallengeDisposition)disposition;
- (void)_didCompleteWithError:(NSError *)error connection:(ODAVConnection *)connection;
- (void)_didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
- (void)_didReceiveResponse:(NSURLResponse *)response;
- (void)_didReceiveData:(NSData *)data;
- (NSURLRequest *)_willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse;

@end
