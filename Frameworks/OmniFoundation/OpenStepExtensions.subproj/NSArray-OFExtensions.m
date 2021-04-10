// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
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

+ (NSArray *)arrayWithCount:(NSUInteger)count valueAtIndex:(id (^)(NSUInteger))valueAtIndex;
{
#if OB_ARC
#error Need to make this array __strong and initialized to zeros, or otherwise hold onto the objects that are returned from the block, since if *it* is ARC, the objects could get deallocated immediately
#endif
    if (count == 0)
        return [NSArray array]; // See header for why we don't use `self`

    id *objects = malloc(sizeof(*objects) * count);
    for (NSUInteger valueIndex = 0; valueIndex < count; valueIndex++) {
        objects[valueIndex] = valueAtIndex(valueIndex);
    }

    // See header for why we don't use `self`
    NSArray *result = [[[NSArray alloc] initWithObjects:objects count:count] autorelease];

#if OB_ARC
#error Need to store nils to each element to release them, or otherwise arrange to lose the reference we added above.
#endif
    free(objects);

    return result;
}

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

typedef NSComparisonResult (*comparisonMethodIMPType)(id rcvr, SEL _cmd, id other);

- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingSelector:(SEL)selector;
{
    OBPRECONDITION([anObject respondsToSelector:selector]);
    
    comparisonMethodIMPType implementation = (comparisonMethodIMPType)[anObject methodForSelector:selector];
    
    return [self indexWhereObjectWouldBelong:anObject inArraySortedUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        OBASSERT(obj1 == anObject, "This is the implementation we cached");
        return implementation(obj1, selector, obj2);
    }];
}

- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingComparator:(NSComparator)comparator;
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
	NSComparisonResult result = (NSComparisonResult)comparator(anObject, compareWith);
	if (result > 0) /* NSOrderedDescending */
            low = test+1;
    }
    return low;
}

- (NSUInteger)indexWhereObjectWouldBelong:(id)anObject inArraySortedUsingSortDescriptors:(NSArray *)sortDescriptors;
{
    // optimization: check for count == 1 here and have a different callback for a single descriptor vs. multiple.
    return [self indexWhereObjectWouldBelong:anObject inArraySortedUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        for (NSSortDescriptor *sortDescriptor in sortDescriptors) {
            NSComparisonResult result = [sortDescriptor compareObject:obj1 toObject:obj2];
            if (result != NSOrderedSame)
                return result;
        }
        
        return NSOrderedSame;
    }];
}

- (NSUInteger)indexOfObject:(id)anObject identical:(BOOL)requireIdentity inArraySortedUsingComparator:(NSComparator)comparator;
{
    NSUInteger objectIndex = [self indexWhereObjectWouldBelong:anObject inArraySortedUsingComparator:comparator];
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
            if (comparator(anObject, compareWith) != NSOrderedSame)
                break;
        } while (objectIndex--);
        
        objectIndex = startingAtIndex;
        while (++objectIndex < count) {
            compareWith = (id)CFArrayGetValueAtIndex((CFArrayRef)self, objectIndex);
            if (compareWith == anObject)
                return objectIndex;
            if (comparator(anObject, compareWith) != NSOrderedSame)
                break;
        }
    } else {
        compareWith = (id)CFArrayGetValueAtIndex((CFArrayRef)self, objectIndex);
        if (comparator(anObject, compareWith) == NSOrderedSame)
            return objectIndex;
    }
    return NSNotFound;
}

static NSComparisonResult compareWithSelector(id obj1, id obj2, void *context)
{
    return ( (NSComparisonResult(*)(id, SEL, id))objc_msgSend )(obj1, (SEL)context, obj2);
}

- (NSUInteger)indexOfObject:(id)anObject inArraySortedUsingSelector:(SEL)selector;
{
    comparisonMethodIMPType implementation = (comparisonMethodIMPType)[anObject methodForSelector:selector];
    
    return [self indexOfObject:anObject identical:NO inArraySortedUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        OBASSERT(obj1 == anObject, "This is the implementation we cached");
        return implementation(obj1, selector, obj2);
    }];
}

- (NSUInteger)indexOfObjectIdenticalTo:(id)anObject inArraySortedUsingSelector:(SEL)selector;
{
    comparisonMethodIMPType implementation = (comparisonMethodIMPType)[anObject methodForSelector:selector];
    
    return [self indexOfObject:anObject identical:YES inArraySortedUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        OBASSERT(obj1 == anObject, "This is the implementation we cached");
        return implementation(obj1, selector, obj2);
    }];
}

- (BOOL)isSortedUsingComparator:(NSComparator)comparator;
{
    return OFCFArrayIsSortedAscendingUsingComparator((CFArrayRef)self, comparator);
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
        ( (void(*)(id, SEL, id, id))objc_msgSend )(object, selector, arg1, arg2);
}

- (void)makeObjectsPerformSelector:(SEL)aSelector withBool:(BOOL)aBool;
{
    for (id object in self)
        ( (void(*)(id, SEL, BOOL))objc_msgSend )(object, aSelector, aBool);
}

- (NSArray *)numberedArrayDescribedBySelector:(SEL)aSelector;
{
    NSUInteger arrayIndex, arrayCount = [self count];
    if (arrayCount == 0)
        return [NSArray array];
    
    NSMutableArray *result = [NSMutableArray array];
    for (arrayIndex = 0; arrayIndex < arrayCount; arrayIndex++) {
        id value = [self objectAtIndex:arrayIndex];
        NSString *valueDescription = ( (id(*)(id, SEL))objc_msgSend )(value, aSelector);
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

- (NSArray *)arrayByInsertingObjectsFromArray:(NSArray *)objects atIndex:(NSUInteger)index;
{
    if ([objects count] == 0)
        return [[self copy] autorelease];
    
    NSMutableArray *result = [[self mutableCopy] autorelease];
    [result replaceObjectsInRange:NSMakeRange(index, 0) withObjectsFromArray:objects];
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

- (NSArray *)arrayByRemovingObjectAtIndex:(NSUInteger)index;
{
    NSMutableArray *updated = [[self mutableCopy] autorelease];
    [updated removeObjectAtIndex:index];
    return updated;
}

- (NSArray *)arrayByReplacingObjectAtIndex:(NSUInteger)index withObject:(id)anObject;
{
    NSMutableArray *updatedArray = [NSMutableArray arrayWithArray:self];
    updatedArray[index] = anObject;
    return [NSArray arrayWithArray:updatedArray];
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
        if ((key = OBSendObjectReturnMessageWithObject(object, aSelector, argument)))
            [dict setObject:object forKey:key];
    }

    NSDictionary *result = [NSDictionary dictionaryWithDictionary:dict];
    [dict release];
    return result;
}

- (NSDictionary *)indexByBlock:(NS_NOESCAPE OFObjectToObjectBlock)blk;
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithCapacity:[self count]];
    
    for (id object in self) {
        id key;
        if ((key = blk(object)) != nil) {
            OBASSERT(dict[key] == nil, "We may want a non-unique index variant later, but this is probably an error");
            [dict setObject:object forKey:key];
        }
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
        id selectorResult = OBSendObjectReturnMessageWithObject(singleObject, aSelector, anObject);
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
        id selectorResult = OBSendObjectReturnMessage(singleObject, aSelector);
        
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

- (NSArray *)arrayByPerformingBlock:(NS_NOESCAPE OFObjectToObjectBlock)blk;
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[self count]];
    
    for (id singleObject in self) {
        id selectorResult = blk(singleObject);
        if (selectorResult)
            [result addObject:selectorResult];
    }
        
    return result;
}

- (NSArray *)flattenedArrayByPerformingBlock:(NS_NOESCAPE OFObjectToObjectBlock)blk;
{
    NSMutableArray *result = [[NSMutableArray new] autorelease];
    for (id singleObject in self) {
        id selectorResult = blk(singleObject);
        if (selectorResult == nil) {
            continue;
        }
        
        if ([selectorResult isKindOfClass:[NSArray class]]) {
            [result addObjectsFromArray:selectorResult];
        } else {
            [result addObject:selectorResult];
        }
    }
    
    return result;
}

- (NSSet *)setByPerformingBlock:(NS_NOESCAPE OFObjectToObjectBlock)blk;
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

- (id)min:(NS_NOESCAPE NSComparator)comparator;
{
    id minimumValue = nil;
    for (id value in self) {
        if (!minimumValue || comparator(minimumValue, value) == NSOrderedDescending)
            minimumValue = value;
    }
    return minimumValue;
}

- (id)max:(NS_NOESCAPE NSComparator)comparator;
{
    id maximumValue = nil;
    for (id value in self) {
        if (!maximumValue || comparator(maximumValue, value) == NSOrderedAscending)
            maximumValue = value;
    }
    return maximumValue;
}

- (NSArray *)select:(NS_NOESCAPE OFPredicateBlock)predicate;
{
    NSMutableArray *result = [NSMutableArray array];
    
    for (id element in self)
        if (predicate(element))
            [result addObject:element];
    
    return result;
}

- (NSArray *)reject:(NS_NOESCAPE OFPredicateBlock)predicate;
{
    NSMutableArray *result = [NSMutableArray array];
    
    for (id element in self)
        if (!predicate(element))
            [result addObject:element];
    
    return result;
}

- (id)first:(NS_NOESCAPE OFPredicateBlock)predicate;
{
    for (id object in self)
        if (predicate(object))
            return object;
    return nil;
}

- (id)firstInRange:(NSRange)range that:(NS_NOESCAPE OFPredicateBlock)predicate;
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

- (id)last:(NS_NOESCAPE OFPredicateBlock)predicate;
{
    // If performance ever matters, could try using the NSFastEnumeration protocol, or even just doing getObjects:range: for batches.
    for (id object in [self reverseObjectEnumerator])
        if (predicate(object))
            return object;
    return nil;
}

- (id)lastInRange:(NSRange)range that:(NS_NOESCAPE OFPredicateBlock)predicate;
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

- (BOOL)any:(NS_NOESCAPE OFPredicateBlock)predicate;
{
    for (id object in self) {
        if (predicate(object)) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)all:(NS_NOESCAPE OFPredicateBlock)predicate;
{
    for (id object in self)
        if (!predicate(object))
            return NO;
    return YES;
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

- (BOOL)anyObjectSatisfiesPredicate:(NS_NOESCAPE OFPredicateBlock)pred;
{
    for (id element in self) {
        if (pred(element))
            return YES;
    }
    return NO;
}

- (BOOL)allObjectsSatisfyPredicate:(NS_NOESCAPE OFPredicateBlock)pred;
{
    for (id element in self) {
        if (!pred(element))
            return NO;
    }
    return YES;
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
        return self.count == 0; // Return YES when otherArray is nil and self has 0 members.
    }

    if (self.count != otherArray.count) {
        return NO;
    }

    NSUInteger objectIndex = 0;
    for (id oneObject in self) {
        if (oneObject != otherArray[objectIndex]) {
            return NO;
        }
        objectIndex++;
    }
    return YES;
}

- (BOOL)hasIdenticalSubarray:(NSArray *)otherArray atIndex:(NSUInteger)startingIndex;
{
    NSUInteger length = CFArrayGetCount((CFArrayRef)self);
    NSUInteger otherLength = CFArrayGetCount((CFArrayRef)otherArray);

    if (startingIndex + otherLength > length)
        return NO; // Not enoufh objects past the starting index to match up
    
    for (NSUInteger testIndex = 0; testIndex < otherLength; testIndex++) {
        if (CFArrayGetValueAtIndex((CFArrayRef)self, startingIndex + testIndex) != CFArrayGetValueAtIndex((CFArrayRef)otherArray, testIndex))
            return NO;
    }
    
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
