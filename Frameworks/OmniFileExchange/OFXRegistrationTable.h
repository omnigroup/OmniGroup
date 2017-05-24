// Copyright 2013-2014,2017 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@interface OFXRegistrationTable <__covariant ValueType> : NSObject

- initWithName:(NSString *)name;

@property(nonatomic,readonly) NSSet <ValueType> *values; // KVO compliant -- will only fire on the main queue

// Mutations are deferred and possibly coalesced. Changes for individual keys are expected to be serialized by the caller -- that is, if you have two callers fighting over a key entry, the order of operations will be undefined (though still "safe").
- (ValueType)objectForKeyedSubscript:(NSString *)key;
- (void)setObject:(ValueType)obj forKeyedSubscript:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;

// Bulk update support -- maybe this should be the only option...
- (void)removeObjectsWithKeys:(NSArray <NSString *> *)removeKeys setObjectsWithDictionary:(NSDictionary <NSString *, ValueType> *)setObjects;

@end
