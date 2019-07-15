// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSArray.h>
#import <Foundation/NSObjCRuntime.h> // for NSComparator

@class NSSet;

@interface NSMutableArray<ObjectType> (OFExtensions)

- (void)insertObjectsFromArray:(NSArray<ObjectType> *)anArray atIndex:(NSUInteger)anIndex;
- (void)removeIdenticalObjectsFromArray:(NSArray<ObjectType> *)removeArray;

- (void)addObjects:(ObjectType)firstObject, ... NS_REQUIRES_NIL_TERMINATION;
- (void)addObjectsFromSet:(NSSet<ObjectType> *)aSet;

- (void)removeObjectsInSet:(NSSet<ObjectType> *)aSet;
- (void)removeObjectsSatisfyingPredicate:(BOOL (^)(ObjectType))predicate;
- (void)removeLastObjectSatisfyingPredicate:(BOOL (^)(id))predicate;

- (void)addObjectIgnoringNil:(ObjectType)object; // adds the object if it is not nil, ignoring otherwise.

// Returns YES if the object was absent (and was added), returns NO if object was already in array. Uses -isEqual:.
- (BOOL)addObjectIfAbsent:(ObjectType)anObject;

- (void)replaceObjectsInRange:(NSRange)replacementRange byApplyingSelector:(SEL)selector;

- (void)reverse;

- (void)sortBasedOnOrderInArray:(NSArray *)ordering identical:(BOOL)usePointerEquality unknownAtFront:(BOOL)putUnknownObjectsAtFront;

// Maintaining sorted arrays
- (void)insertObject:(ObjectType)anObject inArraySortedUsingSelector:(SEL)selector;
- (void)insertObject:(ObjectType)anObject inArraySortedUsingComparator:(NSComparator)comparator;
- (void)removeObjectIdenticalTo:(ObjectType)anObject fromArraySortedUsingSelector:(SEL)selector;
- (void)removeObjectIdenticalTo:(ObjectType)anObject fromArraySortedUsingComparator:(NSComparator)comparator;

// Sorting on an object's attribute
- (void)sortOnAttribute:(SEL)fetchAttributeSelector usingSelector:(SEL)comparisonSelector;

@end
