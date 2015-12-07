// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObservation.h>

@import OmniBase;

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

OB_REQUIRE_ARC

@interface OFObservationChange ()
- initWithObservation:(OFObservation *)observation change:(NSDictionary<NSString *,id> *)change;
@end

@implementation OFObservationChange
{
    OFObservation *_observation;
    NSDictionary<NSString *,id> *_change;
}

- initWithObservation:(OFObservation *)observation change:(NSDictionary<NSString *,id> *)change;
{
    if (!(self = [super init]))
        return nil;
    
    _observation = observation;
    
    // Strongify the observer for the duration of the change notification
    _observer = observation.observer;
    OBASSERT(_observer, "This should not have been deallocated since we are getting notified.");
    
    // We could -copy this and might want to eventually, but we are ephemeral and will let go of what is (presumably) a special dictionary when we are deallocated.
    _change = change;

    return self;
}

- (id)observedObject;
{
    return _observation.observedObject;
}

- (BOOL)isPrior;
{
    OBPRECONDITION(_observation.options & NSKeyValueObservingOptionPrior, "Will never get a prior notification without the NSKeyValueObservingOptionPrior option specified");
    return [_change[NSKeyValueChangeNotificationIsPriorKey] boolValue];
}

- (nullable id)oldValue;
{
    OBPRECONDITION(_observation.options & NSKeyValueObservingOptionOld, "Asked for the old value without the NSKeyValueObservingOptionOld option specified");
    id oldValue = _change[NSKeyValueChangeOldKey];
    return OFISNULL(oldValue) ? nil : oldValue;
}

- (nullable id)newValue;
{
    OBPRECONDITION(_observation.options & NSKeyValueObservingOptionOld, "Asked for the new value without the NSKeyValueObservingOptionNew option specified");
    id newValue = _change[NSKeyValueChangeNewKey];
    return OFISNULL(newValue) ? nil : newValue;
}

@end

@implementation OFObservation
{
    void (^_action)(OFObservationChange *change);
}

static unsigned OFObservationContext;

// TODO: It may make more sense to split out various configuration options into different subclasses with exploded `change` dictionaris for the action callback. That is, if you want to sign up with NSKeyValueObservingOptionPrior, you'd call a creation method whose name said that and whose block actually took the old and new values.


+ (nullable instancetype)makeObserver:(id)observer withKeyPath:(NSString *)keyPath ofObject:(nullable id)observedObject options:(NSKeyValueObservingOptions)options withAction:(void (^)(OFObservationChange<id,id> *change))action;
{
    if (!observedObject)
        return nil;
    return [[self alloc] initWithObserver:observer keyPath:keyPath ofObject:observedObject options:options withAction:action];
}

+ (nullable instancetype)makeObserver:(id)observer withKeyPath:(NSString *)keyPath ofObject:(nullable id)observedObject withAction:(void (^)(OFObservationChange<id,id> *change))action;
{
    if (!observedObject)
        return nil;
    return [[self alloc] initWithObserver:observer keyPath:keyPath ofObject:observedObject options:0 withAction:action];
}

@synthesize observer = _weak_observer;

- initWithObserver:(id)observer keyPath:(NSString *)keyPath ofObject:(id)observedObject options:(NSKeyValueObservingOptions)options withAction:(void (^)(OFObservationChange<id,id> *change))action;
{
    OBPRECONDITION(observer);
    OBPRECONDITION(![NSString isEmptyString:keyPath]);
    OBPRECONDITION(observedObject);
    OBPRECONDITION(action);
    
    if (!(self = [super init]))
        return nil;
    
    _weak_observer = observer;
    _options = options;
    _observedObject = observedObject;
    _keyPath = [keyPath copy];
    _action = [action copy];

    [observedObject addObserver:self forKeyPath:_keyPath options:options context:&OFObservationContext];
    
    return self;
}

- (void)dealloc;
{
    [self invalidate];
}

- (void)invalidate;
{
    [_observedObject removeObserver:self forKeyPath:_keyPath context:&OFObservationContext];
    _observedObject = nil;
    _action = nil;
}

// The arguments are marked nullable since NSObject(NSKeyValueObserving) inexplicably defines them that way.
- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSString *,id> *) change context:(nullable void *)context;
{
    OBPRECONDITION([keyPath isEqual:_keyPath]);
    OBPRECONDITION(object == _observedObject);
    OBPRECONDITION(context == &OFObservationContext); // Though I guess someone could subclass us...
    
    if (context == &OFObservationContext) {
        id observer = _weak_observer;
        if (!observer) {
            OBASSERT_NOT_REACHED("Observation of %@.%@ left registered after observer has been deallocated!", [_observedObject shortDescription], _keyPath);
            [self invalidate];
        } else {
            OFObservationChange *observationChange = [[OFObservationChange alloc] initWithObservation:self change:change];
            typeof(_action) action = _action; // in case firing this calls -invalidate
            action(observationChange);
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end

NS_ASSUME_NONNULL_END
