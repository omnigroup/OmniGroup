// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSURL, NSOperationQueue;
@class NSHTTPURLResponse;

// NSCopying should be implemented to just return self, so that operations can be used as dictionary keys.
@protocol ODAVAsynchronousOperation <NSObject, NSCopying>

// If set and an error response is returned, this can decide whether to retry the operation by returning a *new* operation.
// If a new block is returned, the original block's didFinish will *not* be called.
@property(nonatomic,copy,nonnull) id <ODAVAsynchronousOperation> __nullable (^shouldRetry)(id <ODAVAsynchronousOperation> __nonnull op, NSHTTPURLResponse * _Null_unspecified response);

// If set, this is called when a retry is going to take over for an operation. This is called both for operations returned from `shouldRetry` and possibly internally generated retry operations on network loss. By default, the didFinish from the original operation will have already been assigned to the new operation when `willRetry` is called.
@property(nonatomic,copy,nonnull) void (^willRetry)(id <ODAVAsynchronousOperation> __nonnull original, id <ODAVAsynchronousOperation> __nonnull retry);

@property(nonatomic,copy,nonnull) void (^didFinish)(id <ODAVAsynchronousOperation> __nonnull op, NSError * __nullable errorOrNil);
@property(nonatomic,copy,nullable) void (^didReceiveBytes)(id <ODAVAsynchronousOperation> __nonnull op, long long byteCount);
@property(nonatomic,copy,nullable) void (^didReceiveData)(id <ODAVAsynchronousOperation> __nonnull op, NSData * __nonnull data);
@property(nonatomic,copy,nullable) void (^didSendBytes)(id <ODAVAsynchronousOperation> __nonnull op, long long byteCount);

@property(readonly,nonatomic) NSURL * _Null_unspecified url;

@property(readonly,nonatomic) long long processedLength;
@property(readonly,nonatomic) long long expectedLength;
@property(nonatomic,readonly,nullable) NSData *resultData; // Only set if didReceiveData is nil, otherwise that block is expected to accumulate data however the caller wants

/*
 The callback queue specifies what queue the didFinish, etc. callbacks will be fired. If nil is passed, the current queue is used.
 */
- (void)startWithCallbackQueue:(NSOperationQueue * __nullable)queue;
- (void)cancel;

@end
