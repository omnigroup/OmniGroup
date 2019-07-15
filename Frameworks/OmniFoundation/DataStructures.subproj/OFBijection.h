// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <Foundation/NSEnumerator.h>

NS_ASSUME_NONNULL_BEGIN

@interface OFBijection<__covariant KeyType, __covariant ObjectType> : NSObject <NSFastEnumeration>

+ (instancetype)bijection;
+ (instancetype)bijectionWithObject:(id)anObject forKey:(id)aKey;
+ (instancetype)bijectionWithObjects:(NSArray *)objects forKeys:(NSArray *)keys;
+ (instancetype)bijectionWithObjectsAndKeys:(id)anObject, ... NS_REQUIRES_NIL_TERMINATION;
+ (instancetype)bijectionWithDictionary:(NSDictionary<KeyType, ObjectType> *)dictionary;

- (id)init;
- (id)initWithObject:(ObjectType)anObject forKey:(KeyType)aKey;
- (id)initWithObjects:(NSArray<ObjectType> *)objects forKeys:(NSArray<KeyType> *)keys; // designated initializer
- (id)initWithObjectsAndKeys:(id)anObject, ... NS_REQUIRES_NIL_TERMINATION;
- (id)initWithDictionary:(NSDictionary<KeyType, ObjectType> *)dictionary;

- (NSUInteger)count;
- (nullable ObjectType)objectForKey:(KeyType)aKey;
- (nullable KeyType)keyForObject:(ObjectType)anObject;

- (nullable ObjectType)objectForKeyedSubscript:(KeyType)aKey;

- (NSArray<KeyType> *)allKeys;
- (NSArray<ObjectType> *)allObjects;

- (BOOL)isEqualToBijection:(OFBijection *)bijection;

- (OFBijection<ObjectType, KeyType> *)invertedBijection;

@end

NS_ASSUME_NONNULL_END
