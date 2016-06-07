// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFAsynchronousOperation.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

@implementation OFAsynchronousOperation
{
@protected
    enum operationState : sig_atomic_t {
        operationState_unstarted = 0, // Must be 0 so that object initialization automatically gives us the correct initial state
        operationState_running,
        operationState_finished
    } _state;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)theKey
{
    /* It doesn't seem like we should be called with these values, since the property is named w/o the "is"... but we are. Apparently NSOperationQueue observes the key "isExecuting", not "executing". */
    if ([theKey isEqualToString:@"isExecuting"] || [theKey isEqualToString:@"isFinished"])
        return NO;
    
    return [super automaticallyNotifiesObserversForKey:theKey];
}

- (BOOL)isAsynchronous
{
    return YES;
}

- (BOOL)isExecuting
{
    return ( _state == operationState_running );
}

- (BOOL)isFinished
{
    return ( _state == operationState_finished );
}

- (void)start;
{
    switch(_state) {
        case operationState_unstarted:
            [self willChangeValueForKey:@"isExecuting"];
            _state = operationState_running;
            [self didChangeValueForKey:@"isExecuting"];
            break;
        default:
            OBRejectInvalidCall(self, _cmd, @"Operation already started");
    }
}

- (void)finish;
{
    if (_state != operationState_running)
        OBRejectInvalidCall(self, _cmd, @"Operation not currently running");
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    _state = operationState_finished;
    [self didChangeValueForKey:@"isFinished"];
    [self didChangeValueForKey:@"isExecuting"];
}

#if 0 /* Not implemented yet */
/* Cancel handling help */

- (void)handleCancellation;
{
    OBRequestConcreteImplementation(self, _cmd);
}
#endif

@end

