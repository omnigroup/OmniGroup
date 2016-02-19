// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSURL, NSOperationQueue;

// NSCopying should be implemented to just return self, so that operations can be used as dictionary keys.
@protocol ODAVAsynchronousOperation <NSObject, NSCopying>

@property(nonatomic,copy) void (^didFinish)(id <ODAVAsynchronousOperation> op, NSError *errorOrNil);
@property(nonatomic,copy) void (^didReceiveBytes)(id <ODAVAsynchronousOperation> op, long long byteCount);
@property(nonatomic,copy) void (^didReceiveData)(id <ODAVAsynchronousOperation> op, NSData *data);
@property(nonatomic,copy) void (^didSendBytes)(id <ODAVAsynchronousOperation> op, long long byteCount);

@property(readonly,nonatomic) NSURL *url;

@property(readonly,nonatomic) long long processedLength;
@property(readonly,nonatomic) long long expectedLength;
@property(nonatomic,readonly) NSData *resultData; // Only set if didReceiveData is nil, otherwise that block is expected to accumulate data however the caller wants

/*
 The callback queue specifies what queue the didFinish, etc. callbacks will be fired. If nil is passed, the current queue is used.
 */
- (void)startWithCallbackQueue:(NSOperationQueue *)queue;
- (void)cancel;

@end
