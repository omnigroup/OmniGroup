// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSDictionary.h>

@interface OFOrderedMutableDictionary : NSMutableDictionary

- (id<NSCopying>)keyAtIndex:(NSUInteger)index;
- (NSUInteger)indexOfKey:(id<NSCopying>)aKey;

- (id)objectAtIndex:(NSUInteger)index;
- (id)objectAtIndexedSubscript:(NSUInteger)index;

- (void)setIndex:(NSUInteger)index forKey:(id<NSCopying>)aKey;
- (void)setObject:(id)anObject index:(NSUInteger)index forKey:(id<NSCopying>)aKey;

- (void)sortUsingComparator:(NSComparator)cmptr;

- (void)enumerateEntriesUsingBlock:(void (^)(NSUInteger index, id<NSCopying> key, id obj, BOOL *stop))blk;

- (void)enumerateEntriesWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(NSUInteger index, id<NSCopying> key, id obj, BOOL *stop))blk;

@end
