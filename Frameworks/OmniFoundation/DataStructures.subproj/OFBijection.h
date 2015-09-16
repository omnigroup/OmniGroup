// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <Foundation/NSEnumerator.h>

@interface OFBijection : NSObject <NSFastEnumeration>

+ (instancetype)bijection;
+ (instancetype)bijectionWithObject:(id)anObject forKey:(id)aKey;
+ (instancetype)bijectionWithObjects:(NSArray *)objects forKeys:(NSArray *)keys;
+ (instancetype)bijectionWithObjectsAndKeys:(id)anObject, ... NS_REQUIRES_NIL_TERMINATION;
+ (instancetype)bijectionWithDictionary:(NSDictionary *)dictionary;

- (id)init;
- (id)initWithObject:(id)anObject forKey:(id)aKey;
- (id)initWithObjects:(NSArray *)objects forKeys:(NSArray *)keys; // designated initializer
- (id)initWithObjectsAndKeys:(id)anObject, ... NS_REQUIRES_NIL_TERMINATION;
- (id)initWithDictionary:(NSDictionary *)dictionary;

- (NSUInteger)count;
- (id)objectForKey:(id)aKey;
- (id)keyForObject:(id)anObject;

- (id)objectForKeyedSubscript:(id)aKey;

- (NSArray *)allKeys;
- (NSArray *)allObjects;

- (BOOL)isEqualToBijection:(OFBijection *)bijection;

- (OFBijection *)invertedBijection;

@end
