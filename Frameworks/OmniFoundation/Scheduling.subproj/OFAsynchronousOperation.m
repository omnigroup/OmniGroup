// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFAsynchronousOperation.h>

#import <OmniBase/OmniBase.h>
#import <stdatomic.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

@implementation OFAsynchronousOperation
{
@protected
    enum operationState : uint_fast8_t {
        operationState_unstarted = 0, // Must be 0 so that object initialization automatically gives us the correct initial state
        operationState_running,
        operationState_finished
    };
    
    _Atomic(enum operationState) _state;
    
    BOOL observingCancellation;
}



+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)theKey
{
    /* It doesn't seem like we should be called with these values, since the property is named w/o the "is"... but we are. Apparently NSOperationQueue observes the key "isExecuting", not "executing". */
    if ([theKey isEqualToString:OFOperationIsExecutingKey] || [theKey isEqualToString:OFOperationIsFinishedKey])
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
    [self willChangeValueForKey:OFOperationIsExecutingKey];
    enum operationState st = operationState_unstarted;
    bool did_start_ok = atomic_compare_exchange_strong(&_state, &st, operationState_running);
    [self didChangeValueForKey:OFOperationIsExecutingKey];
    
    if (!did_start_ok) {
        OBRejectInvalidCall(self, _cmd, @"Operation already started");
    }
}

- (void)finish;
{
    [self observeCancellation:NO];
    
    [self willChangeValueForKey:OFOperationIsExecutingKey];
    [self willChangeValueForKey:OFOperationIsFinishedKey];
    enum operationState st = operationState_running;
    bool did_finish_ok = atomic_compare_exchange_strong(&_state, &st, operationState_finished);
    [self didChangeValueForKey:OFOperationIsFinishedKey];
    [self didChangeValueForKey:OFOperationIsExecutingKey];
    
    if (!did_finish_ok) {
        OBRejectInvalidCall(self, _cmd, @"Operation not currently running");
    }
}

/* Cancel handling help */

static char observationCookie;

- (void)observeCancellation:(BOOL)yn;
{
    @synchronized (self) {
        if (yn && !observingCancellation) {
            [self addObserver:(id)[OFAsynchronousOperation class] forKeyPath:OFOperationIsCancelledKey options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionInitial context:&observationCookie];
        } else if (!yn && observingCancellation) {
            [self removeObserver:(id)[OFAsynchronousOperation class] forKeyPath:OFOperationIsCancelledKey context:&observationCookie];
        }
    }
}

+ (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context;
{
    if (context != &observationCookie) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
    
    OBASSERT([keyPath isEqualToString:OFOperationIsCancelledKey]);
    NSNumber *value = [change objectForKey:NSKeyValueChangeNewKey];
    OBASSERT(value != nil);
    
    if ([value boolValue]) {
        [(OFAsynchronousOperation *)object handleCancellation];
    }
}

- (void)handleCancellation;
{
    OBRequestConcreteImplementation(self, _cmd);
}

@end

