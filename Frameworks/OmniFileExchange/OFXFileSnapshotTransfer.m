// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshotTransfer.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>

RCS_ID("$Id$")

@implementation OFXFileSnapshotTransfer
{
    NSMutableArray *_doneBlocks;
    BOOL _cancelled;
    BOOL _finished;
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithConnection:(ODAVConnection *)connection;
{
    OBPRECONDITION(connection);
//    OBPRECONDITION(connection.validateCertificateForChallenge); // We aren't going to fill in these details -- we expect the caller to have done so
    OBPRECONDITION(connection.findCredentialsForChallenge);
    
    if (!(self = [super init]))
        return nil;
    
    _connection = connection;
    
    _operationQueue = [NSOperationQueue currentQueue];
    OBASSERT(_operationQueue.maxConcurrentOperationCount == 1);
    
    _transferOperationQueue = [[NSOperationQueue alloc] init];
    _transferOperationQueue.maxConcurrentOperationCount = 1;
    _transferOperationQueue.name = [NSString stringWithFormat:@"Transfer queue for %@", [self shortDescription]];
    
    return self;
}

- (void)dealloc;
{
    OBASSERT(_commit == nil, @"Should have either been cancelled or finished");
}

- (void)invalidate;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);
    
    // Clear all our block pointers once we are done running so we don't have to deal with retain cycles in the blocks themselves.
    // As a side-effect, this means that calling -finished: twice will do nothing. We should attempt to not do this anyway, but this could help if we screw up.
    _transferProgress = nil;
    _validateCommit = nil;
    _commit = nil;
    _doneBlocks = nil;
}

- (void)updatePercentCompleted:(float)percentCompleted;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);
    
    BOOL changed = (_percentCompleted != percentCompleted);
    if (!changed)
        return;
    
    _percentCompleted = percentCompleted;
    
    if (_transferProgress)
        // TODO: Throttle the number of times we'll fire this. At least don't queue one up if we have one already queued
        _transferProgress();
}

static BOOL _shouldLogError(NSError *error)
{
    OBPRECONDITION(error);
    
    if ([error causedByUserCancelling])
        return NO;
    
    // -causedByUserCancelling doesn't check this case since it might be non-user action.
    if ([error hasUnderlyingErrorDomain:NSURLErrorDomain code:NSURLErrorCancelled])
        return (OFXSyncDebug > 0);
    if ([error hasUnderlyingErrorDomain:NSURLErrorDomain code:NSURLErrorUserCancelledAuthentication])
        return (OFXSyncDebug > 0);

    if ([error hasUnderlyingErrorDomain:OFXErrorDomain code:OFXFileUpdatedWhileDeleting])
        // Delete vs. edit conflict will deal with this. Log them if the debug level is elevated, but not as a normal matter of course.
        return (OFXSyncDebug > 0);
    
    if ([error hasUnderlyingErrorDomain:OFXErrorDomain code:OFXFileDeletedWhileDownloading])
        // We were downloading a file, but before it finished, we deleted it locally.
        return (OFXSyncDebug > 0);

    if ([error hasUnderlyingErrorDomain:OFXErrorDomain code:OFXFileItemDetectedRemoteEdit])
        // Tried to delete an old version that has gone missing, maybe or other case where we got a precondition or file missing failure that looks like we have a remote edit (and we'll rescan and retry, so don't complain loudly).
        return (OFXSyncDebug > 0);
    
    if ([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED])
        // Edit vs. edit conflict where the MOVE failed to put the new snapshot into place since there was one there already
        return (OFXSyncDebug > 0);
    
    return YES;
}

// Called by subclasses when they are done
- (void)finished:(NSError *)errorOrNil;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue);
    OBPRECONDITION(_finished == NO, "Don't call -finished: multiple times");

    _finished = YES;
    
    if (errorOrNil) {
        if ([errorOrNil causedByUserCancelling])
            DEBUG_TRANSFER(1, @"Cancelled");
        else
            DEBUG_TRANSFER(1, @"Finished with error %@", [errorOrNil toPropertyList]);
    } else
        DEBUG_TRANSFER(1, @"Finished successfully");

    // We might get called twice if we get cancelled with shutdown=NO.
    // OBASSERT(_doneBlocks, @"Don't call -finish: multiple times"); // Though -invalidate should prevent us from doing anything on the extra calls.
    
    if (errorOrNil == nil) {
        if (_validateCommit)
            errorOrNil = _validateCommit();
        
        if (errorOrNil == nil) {
            if (_commit) {
                __autoreleasing NSError *commitError;
                if (!_commit(&commitError)) {
                    OBASSERT(commitError);
                    errorOrNil = commitError;
                }
            }
        }
    }
 
    // The error may or may not be a usual circumstance. So, we take the result of each done block and pass it to the next. These are called in the order they are added (file item first and then container). Each item can optionally wrap the error in another error. By the time we get back *here*, the error may have been wrapped in something that signals it has been handled. For example, remote edits will cause s 404 due to our versioning scheme and file items will eat those.
    OBStrongRetain(self); // In-flight messages don't retain the receiver and this could end up removing all our references
    for (OFXFileSnapshotTransferDone done in _doneBlocks) {
        NSError *doneError = done(self, errorOrNil);
        if (doneError)
            errorOrNil = doneError;
    }
    
    if (errorOrNil && _shouldLogError(errorOrNil)) {
        NSString *description = [self shortDescription];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [errorOrNil log:@"Error performing transfer %@", description];
        }];
    }
    
    [self invalidate];
    OBStrongRelease(self);
}

- (void)cancelForShutdown:(BOOL)isShuttingDown;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == _operationQueue, "Cancellation should come from our originator.");

    if (_cancelled)
        return;
    
    _cancelled = YES;
    
    OBStrongRetain(self); // After the calls to cleanup, we could be deallocated if we don't exercise care here. We want to call our -performCancel first.
    if (isShuttingDown) {
        // Try to prevent further callbacks since the originator doesn't want them. But, it might get some anyway and needs to remember that it cancelled us.
        [self invalidate];
    } else {
        // In this case, we are just pausing syncing and we want the owning file item to get told that the transfer is done (so it won't think it is still uploading/downloading).
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
        [self finished:error];
    }
    
    // Now, actually kill off the NSURLConnection if we can. We will have already cleared our blocks by this point, so while we don't expect the NSURLConnection to send any more delegate methods, if it already had some queued, they'll get ignored silently.
    [self performCancel];
    OBStrongRelease(self);
}

// Make sure that each block is only set once -- different parts of the code base may use subsets of these
#define _setBlock(b) do { \
    OBPRECONDITION(_ ## b == nil); \
    _ ## b = [b copy]; \
} while (0)

- (void)setValidateCommit:(NSError * (^)(void))validateCommit;
{
    _setBlock(validateCommit);
}
- (void)setCommit:(BOOL (^)(NSError **))commit;
{
    _setBlock(commit);
}
- (void)addDone:(OFXFileSnapshotTransferDone)done;
{
    if (!_doneBlocks)
        _doneBlocks = [NSMutableArray new];
    [_doneBlocks addObject:[done copy]];
}

#pragma mark - Subclass responsibility

- (void)start;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)performCancel;
{
    OBRequestConcreteImplementation(self, _cmd);
}

@end
