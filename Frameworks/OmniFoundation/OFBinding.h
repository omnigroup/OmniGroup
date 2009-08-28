// Copyright 2004-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniBase/macros.h>

@class NSSet, NSMutableSet, NSMutableArray;

typedef struct {
    id object;
    NSString *keyPath;
} OFBindingPoint;

static inline OFBindingPoint OFBindingPointMake(id object, NSString *keyPath)
{
    OFBindingPoint p;
    p.object = object;
    p.keyPath = keyPath;
    return p;
}

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

- initWithSourcePoint:(OFBindingPoint)sourcePoint destinationPoint:(OFBindingPoint)destinationPoint;

- (void)invalidate;

- (BOOL)isEnabled;
- (void)enable;
- (void)disable;

- (void)reset;

- (id)sourceObject;
- (NSString *)sourceKeyPath;

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
#ifdef OMNI_ASSERTIONS_ON
OBDEPRECATED_METHODS(OFBindingSourceObject)
- (NSString *)humanReadableDescriptionForKey:(NSString *)key; // Use the key path variant
- (NSString *)shortHumanReadableDescriptionForKey:(NSString *)key;
@end
#endif

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

extern void OFSetMutableSet(id self, NSString *key, NSMutableSet **ivar, NSSet *set);
extern void OFSetMutableSetByProxy(id self, NSString *key, NSSet *ivar, NSSet *set);
