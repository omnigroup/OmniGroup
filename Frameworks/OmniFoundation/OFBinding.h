// Copyright 2004-2007, 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniBase/macros.h>
#import <OmniFoundation/OFBindingPoint.h>

@class NSSet, NSMutableSet, NSMutableArray;

// Reifies a dependency between a source field and a destination field. Changes to the source are detected via KVO and propagated to the destination by KVC. This much is similar to dependent keys in stock KVO. Additional features here are that the binding is reified as an object for which propagation of changes can be disable, reenabled, or forced (for example if we are disabled but want to force an update).
@interface OFBinding : NSObject
{
@protected
    unsigned int _enabledCount;
    BOOL _registered;
    id        _sourceObject;
    NSString *_sourceKeyPath;
    id        _nonretained_destinationObject; // We assume the destantion owns us
    NSString *_destinationKeyPath;
}

- initWithSourceObject:(id)sourceObject sourceKeyPath:(NSString *)sourceKeyPath
     destinationObject:(id)destinationObject destinationKeyPath:(NSString *)destinationKeyPath; // designated initializer for now...

- initWithSourcePoint:(OFBindingPoint *)sourcePoint destinationPoint:(OFBindingPoint *)destinationPoint;

- (void)invalidate;

- (BOOL)isEnabled;
- (void)enable;
- (void)disable;

- (void)reset;

- (OFBindingPoint *)sourcePoint;
- (id)sourceObject;
- (NSString *)sourceKeyPath;

- (OFBindingPoint *)destinationPoint;
- (id)destinationObject;
- (NSString *)destinationKeyPath;

- (id)currentValue;
- (void)propagateCurrentValue;

- (NSString *)humanReadableDescription;
- (NSString *)shortHumanReadableDescription;

- (BOOL)isEqualConsideringSourceAndKeyPath:(OFBinding *)otherBinding;

@end


@interface NSObject (OFBindingSourceObject)
- (void)bindingWillInvalidate:(OFBinding *)binding;
- (NSString *)humanReadableDescriptionForKeyPath:(NSString *)keyPath;
- (NSString *)shortHumanReadableDescriptionForKeyPath:(NSString *)keyPath;
@end

// For plain attributes and to-one relationships.  If you bind this for a to-many, it won't do insert/remove/replace calls.
// This is the default if you create an ODBinding
@interface OFObjectBinding : OFBinding
@end

// Ordered to-many properties
@interface OFArrayBinding : OFBinding
- (NSMutableArray *)mutableValue;
@end

// Unordered to-many properties
@interface OFSetBinding : OFBinding
- (NSMutableSet *)mutableValue;
@end

extern NSString *OFKeyPathForKeys(NSString *firstKey, ...) NS_REQUIRES_NIL_TERMINATION;
extern NSArray *OFKeysForKeyPath(NSString *keyPath);

extern void OFSetMutableSet(id self, NSString *key, OB_STRONG NSMutableSet **ivar, NSSet *set);
extern void OFSetMutableSetByProxy(id self, NSString *key, NSSet *ivar, NSSet *set);

#define OFSetSetProperty(self, key, set) OFSetMutableSet(self, (NO && self.key ? @#key : @#key), &_##key, set)
