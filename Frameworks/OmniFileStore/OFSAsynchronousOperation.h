// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSURL;

// NSCopying should be implemented to just return self, so that operations can be used as dictionary keys.
@protocol OFSAsynchronousOperation <NSObject, NSCopying>

@property(nonatomic,copy) void (^didFinish)(id <OFSAsynchronousOperation> op, NSError *errorOrNil);
@property(nonatomic,copy) void (^didReceiveBytes)(id <OFSAsynchronousOperation> op, long long byteCount);
@property(nonatomic,copy) void (^didReceiveData)(id <OFSAsynchronousOperation> op, NSData *data);
@property(nonatomic,copy) void (^didSendBytes)(id <OFSAsynchronousOperation> op, long long byteCount);

@property(readonly,nonatomic) NSURL *url;

@property(readonly,nonatomic) long long processedLength;
@property(readonly,nonatomic) long long expectedLength;

/*
 In the case of DAV operations, a nil queue means to schedule NSURLConnection on the current thread's runloop.
 In this case, the caller must ensure that the current thread will not exit until the operation is completed or cancelled.
 If the caller is running on a background queue, then the caller will need to run the runloop manually (since the worker thread could exit). In this case, it is better to pass a non-nil queue.
 */
- (void)startOperationOnQueue:(NSOperationQueue *)queue;

- (void)stopOperation;

@end
