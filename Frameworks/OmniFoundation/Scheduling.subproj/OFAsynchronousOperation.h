// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSOperation.h>

/*!
 @summary OFErrorableOperation is a convenience abstract superclass for use with asynchronous code.
 
 */
@interface OFAsynchronousOperation: NSOperation

/* Subclasses must override -start as described in the NSOperation subclassing notes, and should call [super start] which will put the operation into the "running" state. Subclasses are responsible for cancellation handling (both checking for cancellation after calling [super start], and checking the .cancelled property and/or observing it to cancel a running operation.) */

#if 0 /* Not yet implemented */
/* Subclasses may call -observeCancellation to cause -handleCancellation to be called. -handleCancellation may be called before this method returns (if the operation is already canceled or if it is canceled right then). Because of asynchrony, it may also be called after the subclass calls -finish (though not after -finish returns). */
- (void)observeCancellation;

/* Override point. Subclasses should not call super. Subclasses are still responsible for calling -finish whether or not this method is invoked. */
- (void)handleCancellation;
#endif

/* This method is for use by concrete subclasses: -finish must be called exactly once after -start returns. The operation will transition to the finished, non-executing state. Concrete subclasses will presumably add a property holding their result; they must set that property before finishing. */
- (void)finish;

@end

