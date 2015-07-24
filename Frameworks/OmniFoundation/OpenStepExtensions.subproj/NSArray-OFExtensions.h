// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSArray.h>

#import <CoreFoundation/CFSet.h>
#import <OmniFoundation/OFUtilities.h>

@class NSSet;

@interface NSArray (OFExtensions)

- (id)anyObject;
    // Returns any object from the array.

- (NSIndexSet *)copyIndexesOfObjectsInSet:(NSSet *)objects;

// These are safe to use on mixed-content arrays.
// The first two call -indexOfString:options:range: with default values.
- (NSUInteger)indexOfString:(NSString *)aString;
- (NSUInteger)indexOfString:(NSString *)aString options:(unsigned int)someOptions;
- (NSUInteger)indexOfString:(NSString *)aString options:(unsigned int)someOptions 	range:(NSRange)aRange;
- (NSString *)componentsJoinedByComma;

- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingSelector:(SEL)selector;
- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingComparator:(NSComparator)comparator;
- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingSortDescriptors:(NSArray *)sortDescriptors;

- (NSUInteger)indexOfObject:(id)anObject identical:(BOOL)requireIdentity inArraySortedUsingComparator:(NSComparator)comparator;

- (NSUInteger)indexOfObject: (id) anObject inArraySortedUsingSelector: (SEL) selector;
- (NSUInteger)indexOfObjectIdenticalTo: (id) anObject inArraySortedUsingSelector: (SEL) selector;
- (BOOL)isSortedUsingComparator:(NSComparator)comparator;
- (BOOL) isSortedUsingSelector:(SEL)selector;
- (BOOL) isSortedUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;

- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)arg1 withObject:(id)arg2;
- (void)makeObjectsPerformSelector:(SEL)aSelector withBool:(BOOL)aBool;

- (NSArray *)numberedArrayDescribedBySelector:(SEL)aSelector;
- (NSArray *)arrayByInsertingObject:(id)anObject atIndex:(NSUInteger)index;
- (NSArray *)arrayByInsertingObjectsFromArray:(NSArray *)objects atIndex:(NSUInteger)index;
- (NSArray *)arrayByRemovingObject:(id)anObject;
- (NSArray *)arrayByRemovingObjectIdenticalTo:(id)anObject;
- (NSArray *)arrayByRemovingObjectAtIndex:(NSUInteger)index;
- (NSArray *)arrayByReplacingObjectAtIndex:(NSUInteger)index withObject:(id)anObject;
- (NSDictionary *)indexBySelector:(SEL)aSelector;
- (NSDictionary *)indexBySelector:(SEL)aSelector withObject:(id)argument;
- (NSArray *)arrayByPerformingSelector:(SEL)aSelector;
- (NSArray *)arrayByPerformingSelector:(SEL)aSelector withObject:(id)anObject;
- (NSSet *)setByPerformingSelector:(SEL)aSelector;

- (NSArray *)arrayByPerformingBlock:(OFObjectToObjectBlock)blk;
- (NSSet *)setByPerformingBlock:(OFObjectToObjectBlock)blk;
- (NSDictionary *)indexByBlock:(OFObjectToObjectBlock)blk;

- (NSArray *)flattenedArray;

- (NSArray *)select:(OFPredicateBlock)predicate;
- (NSArray *)reject:(OFPredicateBlock)predicate;

- (id)first:(OFPredicateBlock)predicate;
- (id)firstInRange:(NSRange)range that:(OFPredicateBlock)predicate;

- (id)last:(OFPredicateBlock)predicate;
- (id)lastInRange:(NSRange)range that:(OFPredicateBlock)predicate;

- (BOOL)all:(OFPredicateBlock)predicate;

- (NSArray *)objectsSatisfyingCondition:(SEL)aSelector;
- (NSArray *)objectsSatisfyingCondition:(SEL)aSelector withObject:(id)anObject;
// Returns an array of objects that return true when tested by aSelector.

- (BOOL)anyObjectSatisfiesCondition:(SEL)sel;
- (BOOL)anyObjectSatisfiesCondition:(SEL)sel withObject:(id)object;
- (BOOL)anyObjectSatisfiesPredicate:(OFPredicateBlock)pred;
- (BOOL)allObjectsSatisfyPredicate:(OFPredicateBlock)pred;

- (NSMutableArray *)deepMutableCopy NS_RETURNS_RETAINED;

- (NSArray *)reversedArray;

- (BOOL)isIdenticalToArray:(NSArray *)otherArray;
- (BOOL)hasIdenticalSubarray:(NSArray *)otherArray atIndex:(NSUInteger)startingIndex;

- (BOOL)containsObjectsInOrder:(NSArray *)orderedObjects;
- (BOOL)containsObjectIdenticalTo:anObject;

- (NSUInteger)indexOfFirstObjectWithValueForKey:(NSString *)key equalTo:(id)searchValue;
- (id)firstObjectWithValueForKey:(NSString *)key equalTo:(id)searchValue;

- (void)applyFunction:(CFSetApplierFunction)applier context:(void *)context;

@end

// API exposed in Xcode 5 that was been around for a while
#if !defined(MAC_OS_X_VERSION_10_9) || MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_9
@interface NSArray ()
- (id)firstObject NS_AVAILABLE(10_6, 4_0);
@end
#endif
