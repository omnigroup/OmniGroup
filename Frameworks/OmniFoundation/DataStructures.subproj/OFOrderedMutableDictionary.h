// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSDictionary.h>

NS_ASSUME_NONNULL_BEGIN

@interface OFOrderedMutableDictionary<KeyType, ObjectType> : NSMutableDictionary<KeyType, ObjectType>

- (id)initWithCapacity:(NSUInteger)numItems NS_DESIGNATED_INITIALIZER;

- (KeyType)keyAtIndex:(NSUInteger)index;
- (NSUInteger)indexOfKey:(KeyType)aKey;

- (ObjectType)objectAtIndex:(NSUInteger)index;
- (ObjectType)objectAtIndexedSubscript:(NSUInteger)index;

- (void)setIndex:(NSUInteger)index forKey:(KeyType)aKey;
- (void)setObject:(ObjectType)anObject index:(NSUInteger)index forKey:(KeyType)aKey;

- (void)sortUsingComparator:(NSComparator)cmptr;

- (void)enumerateEntriesUsingBlock:(void (^)(NSUInteger index, KeyType key, ObjectType obj, BOOL *stop))blk;

- (void)enumerateEntriesWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(NSUInteger index, KeyType key, ObjectType obj, BOOL *stop))blk;

@end

NS_ASSUME_NONNULL_END
