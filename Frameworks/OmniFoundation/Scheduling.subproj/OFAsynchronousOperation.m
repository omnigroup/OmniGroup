// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFAsynchronousOperation.h>

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <stdatomic.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

@implementation OFAsynchronousOperation
{
@private
    void (^_preCompletionBlock)(OFAsynchronousOperation * __nonnull);

@protected
    enum operationState : uint_fast8_t {
        operationState_unstarted = 0, // Must be 0 so that object initialization automatically gives us the correct initial state
        operationState_running,
        operationState_finished
    };
    
    _Atomic(enum operationState) _state;
    
    // The following are all protected by @synchronized(self); they're touched less often.
    BOOL observingCancellation;
    BOOL subclassHandlingCancellation;
}

@synthesize preCompletionBlock = _preCompletionBlock;

static void _locked_updateObservation(OFAsynchronousOperation *self, BOOL shouldObserve);

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
    
    if (_preCompletionBlock) {
        void (^blk)(OFAsynchronousOperation * __nonnull) = _preCompletionBlock;
        _preCompletionBlock = nil;
        blk(self);
    }
    
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
        subclassHandlingCancellation = yn;
        _locked_updateObservation(self, yn);
    }
}

static void _locked_updateObservation(OFAsynchronousOperation *self, BOOL shouldObserve)
{
    /* We can't easily use atomic ops to handle this case, because we need to make sure that the add/remove observer calls are invoked in the same order as their threads' corresponding access to observingCancellation (otherwise the eventual state of the object won't match observingCancellation). */
    /* One downside here is that during the "initial" observation, which can call our subclass's -handleCancellation, we're still holding the @synchronized lock. This doesn't seem likely to be a problem very often but could potentially lead to a deadlock if a subclass's -handleCancellation can block on something that blocks on us. */
    BOOL amObserving = self->observingCancellation;
    
    if (shouldObserve && !amObserving) {
        self->observingCancellation = YES;
        [self addObserver:(id)[OFAsynchronousOperation class] forKeyPath:OFOperationIsCancelledKey options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionInitial context:&observationCookie];
    } else if (!shouldObserve && amObserving) {
        self->observingCancellation = NO;
        [self removeObserver:(id)[OFAsynchronousOperation class] forKeyPath:OFOperationIsCancelledKey context:&observationCookie];
    }
}

+ (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context;
{
    if (context != &observationCookie) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    
    OBASSERT([keyPath isEqualToString:OFOperationIsCancelledKey]);
    NSNumber *value = [change objectForKey:NSKeyValueChangeNewKey];
    OBASSERT(value != nil);
    
    if ([value boolValue]) {
        // Presumably, the cancelled value can only go from false to true once.
        [(OFAsynchronousOperation *)object handleCancellation];
    }
}

- (void)handleCancellation;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSMutableDictionary *)debugDictionary
{
    NSMutableDictionary *d = [super debugDictionary];
    
    enum operationState st = _state;
    NSString *stateName;
    switch(st) {
        case operationState_unstarted:
            stateName = @"unstarted";
            break;
            
        case operationState_running:
            stateName = @"running";
            break;
            
        case operationState_finished:
            stateName = @"finished";
            break;
            
        default:
            stateName = @"???";
            break;
    }
    
    [d setObject:stateName forKey:@"state"];
    [d setBoolValue:self.isCancelled forKey:OFOperationIsCancelledKey defaultValue:NO];
    
    return d;
}

@end

