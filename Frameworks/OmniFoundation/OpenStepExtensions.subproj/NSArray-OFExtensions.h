// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSArray.h>
#import <Foundation/NSSortDescriptor.h>

#import <CoreFoundation/CFSet.h>
#import <OmniFoundation/OFUtilities.h>

NS_ASSUME_NONNULL_BEGIN

@class NSSet;

@interface NSArray <__covariant ObjectType> (OFExtensions)

#define COMPARE_BLOCK NSComparisonResult(NS_NOESCAPE ^)(ObjectType, ObjectType)
#define PREDICATE_BLOCK BOOL(NS_NOESCAPE ^)(ObjectType)
#define MAP_BLOCK id(NS_NOESCAPE ^)(ObjectType)

/// Builds a new array by calling the valueAtIndex block for 0..<length. Currently always returns an immutable array since we can't do "instancetype<ObjectType>"
+ (NSArray <ObjectType> *)arrayWithCount:(NSUInteger)count valueAtIndex:(ObjectType (^)(NSUInteger))valueAtIndex;

- (nullable ObjectType)anyObject;
    // Returns any object from the array.

- (nullable NSIndexSet *)copyIndexesOfObjectsInSet:(NSSet <ObjectType> *)objects;

// These are safe to use on mixed-content arrays.
// The first two call -indexOfString:options:range: with default values.
- (NSUInteger)indexOfString:(NSString *)aString;
- (NSUInteger)indexOfString:(NSString *)aString options:(unsigned int)someOptions;
- (NSUInteger)indexOfString:(NSString *)aString options:(unsigned int)someOptions range:(NSRange)aRange;
- (NSString *)componentsJoinedByComma;

- (NSUInteger)indexWhereObjectWouldBelong:(ObjectType)anObject inArraySortedUsingSelector:(SEL)selector;
- (NSUInteger)indexWhereObjectWouldBelong:(ObjectType)anObject inArraySortedUsingComparator:(NSComparator)comparator;
- (NSUInteger)indexWhereObjectWouldBelong:(ObjectType)anObject inArraySortedUsingSortDescriptors:(NSArray <NSSortDescriptor *> *)sortDescriptors;

- (NSUInteger)indexOfObject:(ObjectType)anObject identical:(BOOL)requireIdentity inArraySortedUsingComparator:(NSComparator)comparator;

- (NSUInteger)indexOfObject: (ObjectType) anObject inArraySortedUsingSelector: (SEL) selector;
- (NSUInteger)indexOfObjectIdenticalTo: (ObjectType) anObject inArraySortedUsingSelector: (SEL) selector;
- (BOOL)isSortedUsingComparator:(NSComparator)comparator;
- (BOOL) isSortedUsingSelector:(SEL)selector;
- (BOOL) isSortedUsingFunction:(NSComparisonResult (*)(ObjectType, ObjectType, void *))comparator context:(void *)context;

- (void)makeObjectsPerformSelector:(SEL)selector withObject:(nullable id)arg1 withObject:(nullable id)arg2;
- (void)makeObjectsPerformSelector:(SEL)aSelector withBool:(BOOL)aBool;

- (NSArray <NSString *> *)numberedArrayDescribedBySelector:(SEL)aSelector;
- (nullable NSArray <ObjectType> *)arrayByInsertingObject:(ObjectType)anObject atIndex:(NSUInteger)index;
- (NSArray <ObjectType> *)arrayByInsertingObjectsFromArray:(NSArray <ObjectType> *)objects atIndex:(NSUInteger)index;
- (NSArray <ObjectType> *)arrayByRemovingObject:(ObjectType)anObject;
- (NSArray <ObjectType> *)arrayByRemovingObjectIdenticalTo:(ObjectType)anObject;
- (NSArray <ObjectType> *)arrayByRemovingObjectAtIndex:(NSUInteger)index;
- (NSArray <ObjectType> *)arrayByReplacingObjectAtIndex:(NSUInteger)index withObject:(ObjectType)anObject;
- (NSDictionary <id,ObjectType> *)indexBySelector:(SEL)aSelector;
- (NSDictionary <id,ObjectType> *)indexBySelector:(SEL)aSelector withObject:(nullable id)argument;
- (NSArray *)arrayByPerformingSelector:(SEL)aSelector;
- (NSArray *)arrayByPerformingSelector:(SEL)aSelector withObject:(nullable id)anObject;
- (NSSet *)setByPerformingSelector:(SEL)aSelector;

- (NSArray *)arrayByPerformingBlock:(MAP_BLOCK)blk;
- (NSArray *)flattenedArrayByPerformingBlock:(MAP_BLOCK)blk;
- (NSSet *)setByPerformingBlock:(MAP_BLOCK)blk;
- (NSDictionary <id,ObjectType> *)indexByBlock:(MAP_BLOCK)blk;

- (NSArray *)flattenedArray;

- (nullable ObjectType)min:(COMPARE_BLOCK)comparator;
- (nullable ObjectType)max:(COMPARE_BLOCK)comparator;

- (NSArray <ObjectType> *)select:(PREDICATE_BLOCK)predicate;
- (NSArray <ObjectType> *)reject:(PREDICATE_BLOCK)predicate;

- (nullable ObjectType)first:(PREDICATE_BLOCK)predicate;
- (nullable ObjectType)firstInRange:(NSRange)range that:(PREDICATE_BLOCK)predicate;

- (nullable ObjectType)last:(PREDICATE_BLOCK)predicate;
- (nullable ObjectType)lastInRange:(NSRange)range that:(PREDICATE_BLOCK)predicate;

- (BOOL)any:(PREDICATE_BLOCK)predicate;
- (BOOL)all:(PREDICATE_BLOCK)predicate;

- (NSArray <ObjectType> *)objectsSatisfyingCondition:(SEL)aSelector;
- (NSArray <ObjectType> *)objectsSatisfyingCondition:(SEL)aSelector withObject:(nullable id)anObject;
// Returns an array of objects that return true when tested by aSelector.

- (BOOL)anyObjectSatisfiesCondition:(SEL)sel;
- (BOOL)anyObjectSatisfiesCondition:(SEL)sel withObject:(nullable id)object;
- (BOOL)anyObjectSatisfiesPredicate:(PREDICATE_BLOCK)pred;
- (BOOL)allObjectsSatisfyPredicate:(PREDICATE_BLOCK)pred;

- (NSMutableArray <ObjectType> *)deepMutableCopy NS_RETURNS_RETAINED;

- (NSArray <ObjectType> *)reversedArray;

- (BOOL)isIdenticalToArray:(NSArray <ObjectType> *)otherArray;
- (BOOL)hasIdenticalSubarray:(NSArray <ObjectType> *)otherArray atIndex:(NSUInteger)startingIndex;

- (BOOL)containsObjectsInOrder:(NSArray <ObjectType> *)orderedObjects;
- (BOOL)containsObjectIdenticalTo:(id)anObject;

- (NSUInteger)indexOfFirstObjectWithValueForKey:(NSString *)key equalTo:(id)searchValue;
- (nullable ObjectType)firstObjectWithValueForKey:(NSString *)key equalTo:(id)searchValue;

- (void)applyFunction:(CFSetApplierFunction)applier context:(void *)context;

#undef PREDICATE_BLOCK
#undef MAP_BLOCK

@end

NS_ASSUME_NONNULL_END
