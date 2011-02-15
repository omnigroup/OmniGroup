// Copyright 1997-2011 Omni Development, Inc.  All rights reserved.
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

@class NSDecimalNumber, NSSet;
@class OFMultiValueDictionary;

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

- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;
- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingSelector:(SEL)selector;
- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingSortDescriptors:(NSArray *)sortDescriptors;

- (NSUInteger)indexOfObject: (id) anObject identical:(BOOL)requireIdentity inArraySortedUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;

- (NSUInteger)indexOfObject: (id) anObject inArraySortedUsingSelector: (SEL) selector;
- (NSUInteger)indexOfObjectIdenticalTo: (id) anObject inArraySortedUsingSelector: (SEL) selector;
- (BOOL) isSortedUsingSelector:(SEL)selector;
- (BOOL) isSortedUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;

- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)arg1 withObject:(id)arg2;
- (void)makeObjectsPerformSelector:(SEL)aSelector withBool:(BOOL)aBool;

- (NSArray *)numberedArrayDescribedBySelector:(SEL)aSelector;
- (NSArray *)arrayByRemovingObject:(id)anObject;
- (NSArray *)arrayByRemovingObjectIdenticalTo:(id)anObject;
- (NSDictionary *)indexBySelector:(SEL)aSelector;
- (NSDictionary *)indexBySelector:(SEL)aSelector withObject:(id)argument;
- (NSArray *)arrayByPerformingSelector:(SEL)aSelector;
- (NSArray *)arrayByPerformingSelector:(SEL)aSelector withObject:(id)anObject;
- (NSSet *)setByPerformingSelector:(SEL)aSelector;

#ifdef NS_BLOCKS_AVAILABLE
- (NSArray *)arrayByPerformingBlock:(OFObjectToObjectBlock)blk;
- (NSSet *)setByPerformingBlock:(OFObjectToObjectBlock)blk;
- (NSDictionary *)indexByBlock:(OFObjectToObjectBlock)blk;
#endif

#ifdef NS_BLOCKS_AVAILABLE
- (NSArray *)select:(OFPredicateBlock)predicate;
- (NSArray *)reject:(OFPredicateBlock)predicate;

- (id)first:(OFPredicateBlock)predicate;
- (id)firstInRange:(NSRange)range that:(OFPredicateBlock)predicate;

- (id)last:(OFPredicateBlock)predicate;
- (id)lastInRange:(NSRange)range that:(OFPredicateBlock)predicate;

#endif

- (NSArray *)objectsSatisfyingCondition:(SEL)aSelector;
- (NSArray *)objectsSatisfyingCondition:(SEL)aSelector withObject:(id)anObject;
// Returns an array of objects that return true when tested by aSelector.

- (BOOL)anyObjectSatisfiesCondition:(SEL)sel;
- (BOOL)anyObjectSatisfiesCondition:(SEL)sel withObject:(id)object;

- (NSMutableArray *)deepMutableCopy NS_RETURNS_RETAINED;

- (NSArray *)reversedArray;

- (BOOL)isIdenticalToArray:(NSArray *)otherArray;

- (BOOL)containsObjectsInOrder:(NSArray *)orderedObjects;
- (BOOL)containsObjectIdenticalTo:anObject;

- (NSUInteger)indexOfFirstObjectWithValueForKey:(NSString *)key equalTo:(id)searchValue;
- (id)firstObjectWithValueForKey:(NSString *)key equalTo:(id)searchValue;

- (void)applyFunction:(CFSetApplierFunction)applier context:(void *)context;

@end
