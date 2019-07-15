// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class ODAVConnection;
@class OFXFileSnapshotTransfer;

// Done blocks are called in the order they are added. If committed==NO, then errorOrNil will be set. If the block wants to signal that it handled the error, it can return a different error. Returning nil is equivalent to returning the passed in errorOrNil.
typedef NSError * (^OFXFileSnapshotTransferDone)(OFXFileSnapshotTransfer *transfer, NSError *errorOrNil);

/*
 Transfers are intended to get variable duration upload/download operations off the account agent's operation queue so that it can respond to other bookkeeping needs. But, this means that they may become irrelevant or wrong by the time they finish. So, transfers should never *commit* their results (they should always transfer data to a temporary location), leaving committing of the transfer to the container (still possibly a network operation, but not variable based on the size of the transfer).
 
 Note, this is not a subclass of NSOperation since it needs to be event driven via NSURLConnection. We don't want to run the runloop waiting for a transfer to finish, but rather to get callbacks when it is finished. We *could* make a subclass of NSOperation (OFSURLRequestOperation) that overrode -start, -isExecuting, and -isFinished. This would allow us to build dependency graphs, but NSOperationQueue doesn't have a notion of failed operations doing implicit cancellation of downstream operations (a MKCOL that fails should kill off PUT operations that depend on it).
 */
@interface OFXFileSnapshotTransfer : NSObject

- initWithConnection:(ODAVConnection *)connection;

- (void)invalidate;

@property(nonatomic,readonly) ODAVConnection *connection;
@property(nonatomic,readonly) NSOperationQueue *operationQueue; // The serial queue this instance was created on and on which it should expect to be operated on.
@property(nonatomic,readonly) NSOperationQueue *transferOperationQueue; // A serial queue for async DAV operations. Needs to be different from operationQueue to avoid deadlocks when transitioning from an async ODAVOperation to a synchronous one (at least until we go all async).

// Should be read in transferProgress blocks. Probably doesn't need to be atomic, but it will be changed on one queue and read on another, so for good form...
@property(atomic,readonly) float percentCompleted;

// Called by subclasses to provoke transferProgress invocations
- (void)updatePercentCompleted:(float)percentCompleted;
- (void)finished:(NSError *)errorOrNil;
- (void)cancelForShutdown:(BOOL)isShuttingDown;

// Callbacks are currently invoked on the NSOperationQueue that -initWithFileManager: was called on.
@property(nonatomic,copy) void (^transferProgress)(void);
@property(nonatomic,copy) NSError *(^validateCommit)(void);
@property(nonatomic,copy) BOOL (^commit)(NSError **outError);
- (void)addDone:(OFXFileSnapshotTransferDone)done;
@property(nonatomic,readonly) BOOL cancelled;

// Required subclass methods
- (void)start;
- (void)performCancel;

// Debugging
@property(nonatomic,copy) NSString *debugName;

@end

// Convenience for subclasses
#define OFXFileSnapshotTransferReturnWithError(e) do { \
    OBChainError(&e); \
    [self finished:e]; \
    return; \
} while(0)
