// Copyright 1997-2005, 2007-2008, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSArray.h>
#import <Foundation/NSObjCRuntime.h> // for NSComparator

@class NSSet;

@interface NSMutableArray (OFExtensions)

- (void)insertObjectsFromArray:(NSArray *)anArray atIndex:(NSUInteger)anIndex;
- (void)removeIdenticalObjectsFromArray:(NSArray *)removeArray;

- (void)addObjects:(id)firstObject, ... NS_REQUIRES_NIL_TERMINATION;
- (void)addObjectsFromSet:(NSSet *)aSet;
- (void)removeObjectsInSet:(NSSet *)aSet;
- (void)addObjectIgnoringNil:(id)object; // adds the object if it is not nil, ignoring otherwise.

// Returns YES if the object was absent (and was added), returns NO if object was already in array. Uses -isEqual:.
- (BOOL)addObjectIfAbsent:(id)anObject;

- (void)replaceObjectsInRange:(NSRange)replacementRange byApplyingSelector:(SEL)selector;

- (void)reverse;

- (void)sortBasedOnOrderInArray:(NSArray *)ordering identical:(BOOL)usePointerEquality unknownAtFront:(BOOL)putUnknownObjectsAtFront;

// Maintaining sorted arrays
- (void)insertObject:(id)anObject inArraySortedUsingSelector:(SEL)selector;
- (void)insertObject:(id)anObject inArraySortedUsingComparator:(NSComparator)comparator;
- (void)removeObjectIdenticalTo:(id)anObject fromArraySortedUsingSelector:(SEL)selector;
- (void)removeObjectIdenticalTo:(id)anObject fromArraySortedUsingComparator:(NSComparator)comparator;

// Sorting on an object's attribute
- (void)sortOnAttribute:(SEL)fetchAttributeSelector usingSelector:(SEL)comparisonSelector;

@end
