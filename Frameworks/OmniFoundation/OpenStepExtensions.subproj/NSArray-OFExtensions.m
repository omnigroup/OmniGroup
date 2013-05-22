// Copyright 1997-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSArray-OFExtensions.h>

#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/OFNull.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

#import <Foundation/Foundation.h>

RCS_ID("$Id$")

@implementation NSArray (OFExtensions)

- (id)anyObject;
{
    return [self count] > 0 ? [self objectAtIndex:0] : nil;
}

- (NSIndexSet *)copyIndexesOfObjectsInSet:(NSSet *)objects;
{
    NSMutableIndexSet *indexes = nil;
    
    NSUInteger objectIndex = [self count];
    while (objectIndex--) {
        if ([objects member:[self objectAtIndex:objectIndex]]) {
            if (!indexes)
                indexes = [[NSMutableIndexSet alloc] init];
            [indexes addIndex:objectIndex];
        }
    }
    
    return indexes;
}

- (NSUInteger)indexOfString:(NSString *)aString;
{
    return [self indexOfString:aString options:0 range:NSMakeRange(0, [aString length])];
}

- (NSUInteger)indexOfString:(NSString *)aString options:(unsigned)someOptions;
{
    return [self indexOfString:aString options:someOptions range:NSMakeRange(0, [aString length])];
}

- (NSUInteger)indexOfString:(NSString *)aString options:(unsigned)someOptions range:(NSRange)aRange;
{
    Class stringClass = [NSString class];
    NSUInteger objectCount = [self count];
    for (NSUInteger objectIndex = 0; objectIndex < objectCount; objectIndex++) {
	NSObject *anObject = [self objectAtIndex:objectIndex];
	if ([anObject isKindOfClass:stringClass] && [aString compare:(NSString *)anObject options:someOptions range:aRange] == NSOrderedSame)
	    return objectIndex;
    }
    
    return NSNotFound;
}

- (NSString *)componentsJoinedByComma;
{
    return [self componentsJoinedByString:@", "];
}

- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;
{
    NSUInteger low = 0;
    NSUInteger range = 1;
    NSUInteger count = [self count];
    
    while (count >= range) /* range is the lowest power of 2 > count */
        range <<= 1;

    while (range) {
        NSUInteger test = low + (range >>= 1);
        if (test >= count)
            continue;
	id compareWith = (id)CFArrayGetValueAtIndex((CFArrayRef)self, test);
	if (compareWith == anObject) 
            return test;
	NSComparisonResult result = (NSComparisonResult)comparator(anObject, compareWith, context);
	if (result > 0) /* NSOrderedDescending */
            low = test+1;
	else if (result == NSOrderedSame) 
            return test;
    }
    return low;
}

typedef NSComparisonResult (*comparisonMethodIMPType)(id rcvr, SEL _cmd, id other);
struct selectorAndIMP {
    SEL selector;
    comparisonMethodIMPType implementation;
};

static NSComparisonResult compareWithSelectorAndIMP(id obj1, id obj2, void *context)
{
    return (((struct selectorAndIMP *)context) -> implementation)(obj1, (((struct selectorAndIMP *)context) -> selector), obj2);
}

- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingSelector:(SEL)selector;
{
    struct selectorAndIMP selAndImp;
    
    OBASSERT([anObject respondsToSelector:selector]);
    
    selAndImp.selector = selector;
    selAndImp.implementation = (comparisonMethodIMPType)[anObject methodForSelector:selector];
    
    return [self indexWhereObjectWouldBelong:anObject inArraySortedUsingFunction:compareWithSelectorAndIMP context:&selAndImp];
}

static NSComparisonResult compareWithSortDescriptors(id obj1, id obj2, void *context)
{
    NSArray *sortDescriptors = (NSArray *)context;

    for (NSSortDescriptor *sortDescriptor in sortDescriptors) {
	NSComparisonResult result = [sortDescriptor compareObject:obj1 toObject:obj2];
	if (result != NSOrderedSame)
	    return result;
    }
    
    return NSOrderedSame;
}

- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingSortDescriptors:(NSArray *)sortDescriptors;
{
    // optimization: check for count == 1 here and have a different callback for a single descriptor vs. multiple.
    return [self indexWhereObjectWouldBelong:anObject inArraySortedUsingFunction:compareWithSortDescriptors context:sortDescriptors];
}

- (NSUInteger)indexOfObject:(id)anObject identical:(BOOL)requireIdentity inArraySortedUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;
{
    NSUInteger objectIndex = [self indexWhereObjectWouldBelong:anObject inArraySortedUsingFunction:comparator context:context];
    NSUInteger count = [self count];
    id compareWith;
    
    if (objectIndex == count)
        return NSNotFound;

    if (requireIdentity) {            
        NSUInteger startingAtIndex = objectIndex;
        do {
            compareWith = (id)CFArrayGetValueAtIndex((CFArrayRef)self, objectIndex);
            if (compareWith == anObject) 
                return objectIndex;
            if (comparator(anObject, compareWith, context) != NSOrderedSame)
                break;
        } while (objectIndex--);
        
        objectIndex = startingAtIndex;
        while (++objectIndex < count) {
            compareWith = (id)CFArrayGetValueAtIndex((CFArrayRef)self, objectIndex);
            if (compareWith == anObject)
                return objectIndex;
            if (comparator(anObject, compareWith, context) != NSOrderedSame)
                break;
        }
    } else {
        compareWith = (id)CFArrayGetValueAtIndex((CFArrayRef)self, objectIndex);
        if ((NSComparisonResult)comparator(anObject, compareWith, context) == NSOrderedSame)
            return objectIndex;
    }
    return NSNotFound;
}

static NSComparisonResult compareWithSelector(id obj1, id obj2, void *context)
{
    return (NSComparisonResult)objc_msgSend(obj1, (SEL)context, obj2);
}

- (NSUInteger)indexOfObject:(id)anObject inArraySortedUsingSelector:(SEL)selector;
{
    struct selectorAndIMP selAndImp;
    
    selAndImp.selector = selector;
    selAndImp.implementation = (comparisonMethodIMPType)[anObject methodForSelector:selector];
    
    return [self indexOfObject:anObject identical:NO inArraySortedUsingFunction:compareWithSelectorAndIMP context:&selAndImp];
}

- (NSUInteger)indexOfObjectIdenticalTo:(id)anObject inArraySortedUsingSelector:(SEL)selector;
{
    struct selectorAndIMP selAndImp;
    
    selAndImp.selector = selector;
    selAndImp.implementation = (comparisonMethodIMPType)[anObject methodForSelector:selector];
    
    return [self indexOfObject:anObject identical:YES inArraySortedUsingFunction:compareWithSelectorAndIMP context:&selAndImp];
}

- (BOOL)isSortedUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;
{
    return OFCFArrayIsSortedAscendingUsingFunction((CFArrayRef)self, (CFComparatorFunction)comparator, context);
}

- (BOOL)isSortedUsingSelector:(SEL)selector;
{
    return [self isSortedUsingFunction:compareWithSelector context:selector];
}

- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)arg1 withObject:(id)arg2;
{
    for (id object in self)
        objc_msgSend(object, selector, arg1, arg2);
}

- (void)makeObjectsPerformSelector:(SEL)aSelector withBool:(BOOL)aBool;
{
    for (id object in self)
        objc_msgSend(object, aSelector, aBool);
}

- (NSArray *)numberedArrayDescribedBySelector:(SEL)aSelector;
{
    NSUInteger arrayIndex, arrayCount = [self count];
    if (arrayCount == 0)
        return [NSArray array];
    
    NSMutableArray *result = [NSMutableArray array];
    for (arrayIndex = 0; arrayIndex < arrayCount; arrayIndex++) {
        id value = [self objectAtIndex:arrayIndex];
        NSString *valueDescription = objc_msgSend(value, aSelector);
        [result addObject:[NSString stringWithFormat:@"%lu. %@", arrayIndex, valueDescription]];
    }

    return result;
}

- (NSArray *)arrayByInsertingObject:(id)anObject atIndex:(NSUInteger)index;
{
    if (index > self.count)
        return nil;
    
    NSMutableArray *result = [[self mutableCopy] autorelease];
    [result insertObject:anObject atIndex:index];
    
    return result;
}

- (NSArray *)arrayByRemovingObject:(id)anObject;
{    
    if (![self containsObject:anObject])
        return [NSArray arrayWithArray:self];

    NSMutableArray *filteredArray = [NSMutableArray arrayWithArray:self];
    [filteredArray removeObject:anObject];

    return [NSArray arrayWithArray:filteredArray];
}

- (NSArray *)arrayByRemovingObjectIdenticalTo:(id)anObject;
{
    if (![self containsObject:anObject])
        return [NSArray arrayWithArray:self];

    NSMutableArray *filteredArray = [NSMutableArray arrayWithArray:self];
    [filteredArray removeObjectIdenticalTo:anObject];

    return [NSArray arrayWithArray:filteredArray];
}

- (NSDictionary *)indexBySelector:(SEL)aSelector;
{
    return [self indexBySelector:aSelector withObject:nil];
}

- (NSDictionary *)indexBySelector:(SEL)aSelector withObject:(id)argument;
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithCapacity:[self count]];

    for (id object in self) {
        id key;
        if ((key = [object performSelector:aSelector withObject:argument]))
            [dict setObject:object forKey:key];
    }

    NSDictionary *result = [NSDictionary dictionaryWithDictionary:dict];
    [dict release];
    return result;
}

- (NSDictionary *)indexByBlock:(OFObjectToObjectBlock)blk;
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithCapacity:[self count]];
    
    for (id object in self) {
        id key;
        if ((key = blk(object)) != nil)
            [dict setObject:object forKey:key];
    }
    
    NSDictionary *result = [NSDictionary dictionaryWithDictionary:dict];
    [dict release];
    return result;
}

- (NSArray *)arrayByPerformingSelector:(SEL)aSelector;
{
    // objc_msgSend won't bother passing the nil argument to the method implementation because of the selector signature.
    return [self arrayByPerformingSelector:aSelector withObject:nil];
}

- (NSArray *)arrayByPerformingSelector:(SEL)aSelector withObject:(id)anObject;
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[self count]];
    
    for (id singleObject in self) {
        id selectorResult = [singleObject performSelector:aSelector withObject:anObject];
        if (selectorResult)
            [result addObject:selectorResult];
    }

    return result;
}

- (NSSet *)setByPerformingSelector:(SEL)aSelector;
{
    id singleResult = nil;
    NSMutableSet *result = nil;
    for (id singleObject in self) {
        id selectorResult = [singleObject performSelector:aSelector /* withObject:anObject */ ];
        
        if (selectorResult) {
            if (singleResult == selectorResult) {
                /* ok */
            } else if (result != nil) {
                [result addObject:selectorResult];
            } else if (singleResult == nil) {
                singleResult = selectorResult;
            } else {
                result = [NSMutableSet set];
                [result addObject:singleResult];
                [result addObject:selectorResult];
                singleResult = nil;
            }
        }
    }
    
    if (result)
        return result;
    else if (singleResult)
        return [NSSet setWithObject:singleResult];
    else
        return [NSSet set];
}

- (NSArray *)arrayByPerformingBlock:(OFObjectToObjectBlock)blk;
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[self count]];
    
    for (id singleObject in self) {
        id selectorResult = blk(singleObject);
        if (selectorResult)
            [result addObject:selectorResult];
    }
        
    return result;
}

- (NSSet *)setByPerformingBlock:(OFObjectToObjectBlock)blk;
{
    id singleResult = nil;
    NSMutableSet *result = nil;
    for (id singleObject in self) {
        id selectorResult = blk(singleObject);
        
        if (selectorResult) {
            if (singleResult == selectorResult) {
                /* ok */
            } else if (result != nil) {
                [result addObject:selectorResult];
            } else if (singleResult == nil) {
                singleResult = selectorResult;
            } else {
                result = [NSMutableSet set];
                [result addObject:singleResult];
                [result addObject:selectorResult];
                singleResult = nil;
            }
        }
    }
    
    if (result)
        return result;
    else if (singleResult)
        return [NSSet setWithObject:singleResult];
    else
        return [NSSet set];
}

- (NSArray *)flattenedArray;
{
    NSMutableArray *result = [NSMutableArray array];
    
    for (id anObj in self) {
        if ([anObj isKindOfClass:[NSArray class]]) {
            [result addObjectsFromArray:[anObj flattenedArray]];
        } else {
            [result addObject:anObj];
        }
    }
    
    return result;
}

- (NSArray *)select:(OFPredicateBlock)predicate;
{
    NSMutableArray *result = [NSMutableArray array];
    
    for (id element in self)
        if (predicate(element))
            [result addObject:element];
    
    return result;
}

- (NSArray *)reject:(OFPredicateBlock)predicate;
{
    NSMutableArray *result = [NSMutableArray array];
    
    for (id element in self)
        if (!predicate(element))
            [result addObject:element];
    
    return result;
}

- (id)first:(OFPredicateBlock)predicate;
{
    for (id object in self)
        if (predicate(object))
            return object;
    return nil;
}

- (id)firstInRange:(NSRange)range that:(OFPredicateBlock)predicate;
{
    // If performance ever matters, could try using the NSFastEnumeration protocol, or even just doing getObjects:range: for batches.
    NSUInteger objectIndex;
    for (objectIndex = range.location; objectIndex < NSMaxRange(range); objectIndex++) {
        id object = (id)CFArrayGetValueAtIndex((CFArrayRef)self, objectIndex);
        if (predicate(object))
            return object;
    }
    return nil;
}

- (id)last:(OFPredicateBlock)predicate;
{
    // If performance ever matters, could try using the NSFastEnumeration protocol, or even just doing getObjects:range: for batches.
    for (id object in [self reverseObjectEnumerator])
        if (predicate(object))
            return object;
    return nil;
}

- (id)lastInRange:(NSRange)range that:(OFPredicateBlock)predicate;
{
    // If performance ever matters, could try using the NSFastEnumeration protocol, or even just doing getObjects:range: for batches.
    if (range.length > 0) {
        NSUInteger objectIndex = NSMaxRange(range);
        do {
            objectIndex--;
            id object = (id)CFArrayGetValueAtIndex((CFArrayRef)self, objectIndex);
            if (predicate(object))
                return object;
        } while (objectIndex > range.location);
    }
    return nil;
}

- (NSArray *)objectsSatisfyingCondition:(SEL)aSelector;
{
    // objc_msgSend won't bother passing the nil argument to the method implementation because of the selector signature.
    return [self objectsSatisfyingCondition:aSelector withObject:nil];
}

- (NSArray *)objectsSatisfyingCondition:(SEL)aSelector withObject:(id)anObject;
{
    NSMutableArray *result = [NSMutableArray array];
    
    for (id element in self) {
        if ([element satisfiesCondition:aSelector withObject:anObject])
            [result addObject:element];
    }

    return result;
}

- (BOOL)anyObjectSatisfiesCondition:(SEL)sel;
{
    return [self anyObjectSatisfiesCondition:sel withObject:nil];
}

- (BOOL)anyObjectSatisfiesCondition:(SEL)sel withObject:(id)anObject;
{
    for (id element in self) {
        if ([element satisfiesCondition:sel withObject:anObject])
            return YES;
    }
    
    return NO;
}

- (BOOL)anyObjectSatisfiesPredicate:(OFPredicateBlock)pred;
{
    for (id element in self) {
        if (pred(element))
            return YES;
    }
    return NO;
}

- (NSMutableArray *)deepMutableCopy;
{
    NSMutableArray *newArray = [[NSMutableArray alloc] init];
    for (id anObject in self) {
        if ([anObject respondsToSelector:@selector(deepMutableCopy)]) {
            anObject = [anObject deepMutableCopy];
            [newArray addObject:anObject];
            [anObject release];
        } else if ([anObject conformsToProtocol:@protocol(NSMutableCopying)]) {
            anObject = [anObject mutableCopy];
            [newArray addObject:anObject];
            [anObject release];
        } else {
            [newArray addObject:anObject];
        }
    }

    return newArray;
}

- (NSArray *)reversedArray;
{
    NSUInteger objectIndex, objectCount = [self count];
    if (objectCount < 2)
        return [[self copy] autorelease];
    
    NSMutableArray *result = [[self mutableCopy] autorelease];
    for (objectIndex = 0; objectIndex < objectCount / 2; objectIndex++)
        CFArrayExchangeValuesAtIndices((CFMutableArrayRef)result, objectIndex, objectCount - objectIndex - 1);
    return result;
}

// Returns YES if the two arrays contain exactly the same pointers in the same order.  That is, this doesn't use -isEqual: on the components
- (BOOL)isIdenticalToArray:(NSArray *)otherArray;
{
    if (!otherArray) {
        OBASSERT([self count] > 0); // Older versions of this method would compare empty to nil as YES.  Do we want that still?
        return NO;
    }

    CFIndex objectIndex = CFArrayGetCount((CFArrayRef)self);
    if (objectIndex != CFArrayGetCount((CFArrayRef)otherArray))
        return NO;
    
    while (objectIndex--)
        if (CFArrayGetValueAtIndex((CFArrayRef)self, objectIndex) != CFArrayGetValueAtIndex((CFArrayRef)otherArray, objectIndex))
            return NO;
    return YES;
}

// -containsObjectsInOrder: moved from TPTrending 6Dec2001 wiml
- (BOOL)containsObjectsInOrder:(NSArray *)orderedObjects
{
    id testItem = nil;
    
    NSUInteger myCount = [self count];
    NSUInteger objCount = [orderedObjects count];
    
    NSUInteger myIndex = 0, objIndex = 0;
    while (objIndex < objCount) {
        id item;
        
        // Not enough objects left in self to correspond to objects left in orderedObjects
        if ((objCount - objIndex) > (myCount - myIndex))
            return NO;
        
        item = [self objectAtIndex:myIndex];
        if (!testItem)
            testItem = [orderedObjects objectAtIndex:objIndex];
        if (item == testItem) {
            testItem = nil;
            objIndex ++;
        }
        myIndex ++;
    }
    
    return YES;
}

- (BOOL)containsObjectIdenticalTo:anObject;
{
    return [self indexOfObjectIdenticalTo:anObject] != NSNotFound;
}

- (NSUInteger)indexOfFirstObjectWithValueForKey:(NSString *)key equalTo:(id)searchValue;
{
    NSUInteger objectIndex, objectCount = [self count];
    
    for (objectIndex = 0; objectIndex < objectCount; objectIndex++) {
        id object = [self objectAtIndex:objectIndex];
        id objectValue = [object valueForKey:key];
        if (OFISEQUAL(objectValue, searchValue))
            return objectIndex;
    }
    
    return NSNotFound;
}

- (id)firstObjectWithValueForKey:(NSString *)key equalTo:(id)searchValue;
{
    NSUInteger objectIndex = [self indexOfFirstObjectWithValueForKey:key equalTo:searchValue];
    return (objectIndex == NSNotFound) ? nil : [self objectAtIndex:objectIndex];
}

// A convenience method so that you don't have to check for a NULL array or build the range
- (void)applyFunction:(CFArrayApplierFunction)applier context:(void *)context;
{
    CFArrayApplyFunction((CFArrayRef)self, CFRangeMake(0, CFArrayGetCount((CFArrayRef)self)), applier, context);
}

@end
