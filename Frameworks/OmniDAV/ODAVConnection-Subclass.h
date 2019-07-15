// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObjCRuntime.h> // For NS_ASSUME_NONNULL_BEGIN, END
#import <OmniDAV/ODAVConnection.h>

NS_ASSUME_NONNULL_BEGIN

@class ODAVOperation;
@class NSURLRequest;

@protocol ODAVConnectionSubclass
- (ODAVOperation *)_makeOperationForRequest:(NSURLRequest *)request;
@end

// For subclasses to call
@interface ODAVConnection ()
- (void)_handleChallenge:(NSURLAuthenticationChallenge *)challenge
               operation:(nullable ODAVOperation *)operation
       completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler;
@end

NS_ASSUME_NONNULL_END
