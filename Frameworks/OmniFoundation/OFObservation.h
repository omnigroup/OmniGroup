// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#import <Foundation/NSKeyValueObserving.h>

NS_ASSUME_NONNULL_BEGIN

@interface OFObservationChange<ObserverType, ObservedObjectType> : NSObject

@property(nonatomic,readonly,strong) ObserverType observer;
@property(nonatomic,readonly,strong) ObservedObjectType observedObject;
@property(nonatomic,readonly) BOOL isPrior;
@property(nonatomic,readonly) NSString *keyPath;
@property(nullable,nonatomic,readonly) id oldValue;
@property(nullable,nonatomic,readonly) id newValue;

@end

/// Higher level interface to KVO that automatically unsubscribes when the OFObservation instance is deallocated.
@interface OFObservation<ObserverType, ObservedObjectType> : NSObject

/*
 If `observedObject` is nil, then a nil result will be returned. This simplifies setters so that they don't need to nil out OFObservation ivars from previous state:
 
 - (void)setFoo:(Foo *)foo;
 {
     _foo = foo;
     _fooObservation = [OFObservation makeObserver:self ...]; // returns nil and lets the old observation be deallocated in the case that the incoming `foo` is nil.
 }
 */
+ (nullable instancetype)makeObserver:(ObserverType)observer withKeyPath:(NSString *)keyPath ofObject:(nullable ObservedObjectType)observedObject options:(NSKeyValueObservingOptions)options withAction:(void (^)(OFObservationChange<ObserverType, ObservedObjectType> *change))action;
+ (nullable instancetype)makeObserver:(ObserverType)observer withKeyPath:(NSString *)keyPath ofObject:(nullable ObservedObjectType)observedObject withAction:(void (^)(OFObservationChange<ObserverType, ObservedObjectType> *change))action;

@property(nonatomic,readonly,weak) ObserverType observer;
@property(nonatomic,readonly,strong,nullable) ObservedObjectType observedObject; // nil once -invalidate has been sent, but not otherwise
@property(nonatomic,readonly) NSKeyValueObservingOptions options;
@property(nonatomic,readonly,copy) NSString *keyPath;

- (void)invalidate;

/*
 
 Helper macro which avoids most of the boilerplate. This always has `self` as the observer, which should be the 99% case, and which makes it obvious which of the two objects involved is the observed one. The key path should be passed in *without* @"..." since it gets passed through OFValidateKeyPath() to ensure that it is an actual property on the observed object, and since it is used to infer the type of the value at the end of the keyPath.
 
 The bits of the action '^(OFObservationChange *)' should be left off the action and will be concatenated on with this macro with the right generic type. This gives static type checking when referencing the observer (which is `self`).
 
 A typical call will look like:
 
 _object = object
 _fooObservation = OFObserve(_object, foo, options, {
     [change.observer doSomething];
 });
 
 As noted above, this handles the case of `object` being nil by clearing out _fooObservation.
 
 */

#define OFObserve(observedObject, keyPath, options_, blockBody) \
    [OFObservation makeObserver:self withKeyPath:OFValidateKeyPath(observedObject, keyPath) ofObject:observedObject options:(options_) withAction:^(OFObservationChange<typeof(self), typeof(observedObject)> *change)blockBody]

@end

NS_ASSUME_NONNULL_END
