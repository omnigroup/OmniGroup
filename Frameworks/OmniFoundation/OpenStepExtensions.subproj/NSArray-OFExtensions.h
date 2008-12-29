// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSArray-OFExtensions.h 102833 2008-07-15 00:56:16Z bungi $

#import <Foundation/NSArray.h>

#import <OmniFoundation/OFDictionaryInitialization.h>
#import <CoreFoundation/CFSet.h>

@class NSDecimalNumber, NSSet;
@class OFMultiValueDictionary;

@interface NSArray (OFExtensions)

- (id)anyObject;
    // Returns any object from the array.

- (NSArray *)elementsAsInstancesOfClass:(Class)aClass withContext:(id)context;

- (NSIndexSet *)copyIndexesOfObjectsInSet:(NSSet *)objects;

// These are safe to use on mixed-content arrays.
// The first two call -indexOfString:options:range: with default values.
- (NSUInteger)indexOfString:(NSString *)aString;
- (NSUInteger)indexOfString:(NSString *)aString options:(unsigned int)someOptions;
- (NSUInteger)indexOfString:(NSString *)aString options:(unsigned int)someOptions 	range:(NSRange)aRange;
- (NSString *)componentsJoinedByComma;
- (NSString *)componentsJoinedByCommaAndAnd;
    // (x) -> "x"; (x, y) -> "x and y";  (x, y, z) -> "x, y, and z", and so on

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

- (NSDecimalNumber *)decimalNumberSumForSelector:(SEL)aSelector;
- (NSArray *)numberedArrayDescribedBySelector:(SEL)aSelector;
- (NSArray *)objectsDescribedByIndexesString:(NSString *)indexesString;
- (NSArray *)arrayByRemovingObject:(id)anObject;
- (NSArray *)arrayByRemovingObjectIdenticalTo:(id)anObject;
- (NSDictionary *)indexBySelector:(SEL)aSelector;
- (NSDictionary *)indexBySelector:(SEL)aSelector withObject:(id)argument;
- (NSArray *)arrayByPerformingSelector:(SEL)aSelector;
- (NSArray *)arrayByPerformingSelector:(SEL)aSelector withObject:(id)anObject;
- (NSSet *)setByPerformingSelector:(SEL)aSelector;

- (NSArray *)objectsSatisfyingCondition:(SEL)aSelector;
- (NSArray *)objectsSatisfyingCondition:(SEL)aSelector withObject:(id)anObject;
// Returns an array of objects that return true when tested by aSelector.

- (BOOL)anyObjectSatisfiesCondition:(SEL)sel;
- (BOOL)anyObjectSatisfiesCondition:(SEL)sel withObject:(id)object;

- (NSMutableArray *)deepMutableCopy;

- (NSArray *)reversedArray;

- (NSArray *)deepCopyWithReplacementFunction:(id (*)(id, void *))funct context:(void *)context;

- (BOOL)isIdenticalToArray:(NSArray *)otherArray;

- (BOOL)containsObjectsInOrder:(NSArray *)orderedObjects;
- (BOOL)containsObjectIdenticalTo:anObject;

- (NSUInteger)indexOfFirstObjectWithValueForKey:(NSString *)key equalTo:(id)searchValue;
- (id)firstObjectWithValueForKey:(NSString *)key equalTo:(id)searchValue;

- (void)applyFunction:(CFSetApplierFunction)applier context:(void *)context;

@end
