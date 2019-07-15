// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSOperation.h>

/*!
 @summary OFAsynchronousOperation is a convenience abstract superclass for use with asynchronous code.
 
 */

// The key paths for observing operation state.
#define OFOperationIsFinishedKey   @"isFinished"
#define OFOperationIsExecutingKey  @"isExecuting"
#define OFOperationIsCancelledKey  @"isCancelled"

@interface OFAsynchronousOperation: NSOperation

/* An additional utility hook on NSOperation. This block, if set, is called during -finish right *before* the operation's -isFinished property becomes true; this can be used to do additional bookkeeping before any dependent operations start. (In contrast, NSOperation's completionBlock is called *after* -finished becomes true.) */
@property (nullable,copy) void (^preCompletionBlock)(OFAsynchronousOperation * __nonnull);

/* Subclasses must override -start as described in the NSOperation subclassing notes, and should call [super start] which will put the operation into the "running" state. Subclasses are responsible for cancellation handling (both checking for cancellation after calling [super start], and checking the .cancelled property and/or observing it to cancel a running operation.) */

/* Subclasses may call -observeCancellation to cause -handleCancellation to be called. -handleCancellation may be called before this method returns (if the operation is already canceled or if it is canceled right then). Because of asynchrony, it may also be called after the subclass calls -finish (though presumably not after -finish returns). */
- (void)observeCancellation:(BOOL)yn;

/* Override point. Subclasses should not call super. Subclasses are still responsible for calling -finish whether or not this method is invoked. This method may be called on any thread, regardless of which thread the operation is queued or running on. */
- (void)handleCancellation;

/* This method is for use by concrete subclasses: -finish must be called exactly once after -start returns. The operation will transition to the finished, non-executing state. Concrete subclasses will presumably add a property holding their result; they must set that property before finishing. */
- (void)finish;

@end

/* A protocol that is useful to compose with NSOperation subclasses. */
@protocol OFErrorable

/** Returns the error state of the operation: if non-nil, the operation has failed with an error. Note that cancellation is not an error; you must check both the isCancelled and the error properties of an OFErrorable operation to determine whether it produced its desired result. */
@property (readonly,nullable) NSError *error;

@end
