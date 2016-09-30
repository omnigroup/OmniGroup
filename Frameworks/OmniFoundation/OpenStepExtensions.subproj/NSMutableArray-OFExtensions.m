// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSMutableArray-OFExtensions.h>

#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>
#import <OmniBase/OBUtilities.h>

#include <Foundation/Foundation.h>

RCS_ID("$Id$")

@implementation NSMutableArray (OFExtensions)

- (void)insertObjectsFromArray:(NSArray *)anArray atIndex:(NSUInteger)anIndex
{
    [self replaceObjectsInRange:NSMakeRange(anIndex, 0) withObjectsFromArray:anArray];
}

- (void)removeIdenticalObjectsFromArray:(NSArray *)removeArray;
{
    NSEnumerator               *removeEnumerator;
    id				removeObject;

    if (!removeArray)
	return;
    removeEnumerator = [removeArray objectEnumerator];
    while ((removeObject = [removeEnumerator nextObject]))
	[self removeObjectIdenticalTo:removeObject];
}

- (void)addObjects:(id)firstObject, ...;
{
    if (firstObject == nil)
        return;
    
    [self addObject:firstObject];
    
    id next;
    va_list argList;

    va_start(argList, firstObject);
    while ((next = va_arg(argList, id)) != nil)
        [self addObject:next];
    va_end(argList);
}

- (void)addObjectsFromSet:(NSSet *)aSet;
{
    for (id object in aSet)
        [self addObject:object];
}

- (void)addObjectIgnoringNil:(id)object; // adds the object if it is not nil, ignoring otherwise.
{
    if (object != nil) {
        [self addObject:object];
    }
}

- (void)removeObjectsInSet:(NSSet *)aSet;
{
    NSUInteger objectIndex = [self count];
    while (objectIndex--) {
        if ([aSet member:[self objectAtIndex:objectIndex]])
            [self removeObjectAtIndex:objectIndex];
    }
}

- (void)removeObjectsSatisfyingPredicate:(BOOL (^)(id))predicate;
{
    // Index based iteration since we'll be altering the array (and fast enumeration / block based enumeration will assert in that case).
    NSUInteger objectIndex = [self count];
    while (objectIndex--) {
        if (predicate(self[objectIndex])) {
            [self removeObjectAtIndex:objectIndex];
        }
    }
}


- (BOOL)addObjectIfAbsent:(id)anObject;
{
    if (![self containsObject:anObject]) {
        [self addObject:anObject];
        return YES;
    } else {
        return NO;
    }
}

- (void)replaceObjectsInRange:(NSRange)replacementRange byApplyingSelector:(SEL)selector
{
    NSMutableArray *replacements = [[NSMutableArray alloc] initWithCapacity:replacementRange.length];

    for (NSUInteger objectIndex = 0; objectIndex < replacementRange.length; objectIndex ++) {
        id sourceObject = self[replacementRange.location + objectIndex];
        id replacementObject = OBSendObjectReturnMessage(sourceObject, selector);
        if (replacementObject == nil)
            OBRejectInvalidCall(self, _cmd,
                                @"Object at index %lu returned nil from %@",
                                (unsigned long)(replacementRange.location + objectIndex),
                                NSStringFromSelector(selector));
        [replacements addObject:replacementObject];
    }

    [self replaceObjectsInRange:replacementRange withObjectsFromArray:replacements];

    [replacements release];
}

- (void)reverse
{
    NSUInteger count, objectIndex;

    count = [self count];
    if (count < 2)
        return;
    for(objectIndex = 0; objectIndex < count/2; objectIndex ++) {
        NSUInteger otherIndex = count - objectIndex - 1;
        [self exchangeObjectAtIndex:objectIndex withObjectAtIndex:otherIndex];
    }
}

/* If these are not true, the routines which store integer values in CFDictionaries here and elsewhere clobber memory */
_Static_assert(sizeof(NSUInteger) == sizeof(uintptr_t), "");
_Static_assert(sizeof(void *) == sizeof(NSUInteger), "");

- (void)sortBasedOnOrderInArray:(NSArray *)ordering identical:(BOOL)usePointerEquality unknownAtFront:(BOOL)putUnknownObjectsAtFront;
{
    NSUInteger orderingCount = [ordering count];
    
    CFMutableDictionaryRef sortOrdering = CFDictionaryCreateMutable(kCFAllocatorDefault, orderingCount,
                                                                    usePointerEquality? &OFNonOwnedPointerDictionaryKeyCallbacks : &OFNSObjectDictionaryKeyCallbacks,
                                                                    &OFIntegerDictionaryValueCallbacks);
    for (NSUInteger orderingIndex = 0; orderingIndex < orderingCount; orderingIndex++)
        OFCFDictionaryAddUIntegerValue(sortOrdering, ordering[orderingIndex], orderingIndex);
    
    [self sortUsingComparator:^NSComparisonResult(id object1, id object2) {
        if (object1 == object2)
            return NSOrderedSame;
        
        NSUInteger obj1Index = 0, obj2Index = 0;
        Boolean obj1Known = OFCFDictionaryGetUIntegerValueIfPresent(sortOrdering, (__bridge void *)object1, &obj1Index);
        Boolean obj2Known = OFCFDictionaryGetUIntegerValueIfPresent(sortOrdering, (__bridge void *)object2, &obj2Index);
        
        if (obj1Known) {
            if (obj2Known) {
                if (obj1Index < obj2Index)
                    return NSOrderedAscending;
                else {
                    OBASSERT(obj1Index != obj2Index);
                    return NSOrderedDescending;
                }
            } else
                return putUnknownObjectsAtFront ? NSOrderedDescending : NSOrderedAscending;
        } else {
            if (obj2Known)
                return putUnknownObjectsAtFront ? NSOrderedAscending : NSOrderedDescending;
            else
                return NSOrderedSame;
        }
    }];
    
    CFRelease(sortOrdering);
}


/* Assumes the array is already sorted to insert the object quickly in the right place */
- (void)insertObject:anObject inArraySortedUsingSelector:(SEL)selector;
{
    NSUInteger objectIndex = [self indexWhereObjectWouldBelong:anObject inArraySortedUsingSelector:selector];
    [self insertObject:anObject atIndex:objectIndex];
}    

- (void)insertObject:(id)anObject inArraySortedUsingComparator:(NSComparator)comparator;
{
    NSUInteger objectIndex = [self indexWhereObjectWouldBelong:anObject inArraySortedUsingComparator:comparator];
    [self insertObject:anObject atIndex:objectIndex];
}

/* Assumes the array is already sorted to find the object quickly and remove it */
- (void)removeObjectIdenticalTo: (id)anObject fromArraySortedUsingSelector:(SEL)selector
{
    NSUInteger objectIndex = [self indexOfObjectIdenticalTo:anObject inArraySortedUsingSelector:selector];
    if (objectIndex != NSNotFound)
        [self removeObjectAtIndex: objectIndex];
}

- (void)removeObjectIdenticalTo:(id)anObject fromArraySortedUsingComparator:(NSComparator)comparator;
{
    NSUInteger objectIndex = [self indexOfObject:anObject identical:YES inArraySortedUsingComparator:comparator];
    if (objectIndex != NSNotFound)
        [self removeObjectAtIndex:objectIndex];
}

struct sortOnAttributeContext {
    SEL getAttribute;
    SEL compareAttributes;
};

static NSComparisonResult doCompareOnAttribute(id a, id b, void *ctxt)
{
    SEL getAttribute = ((struct sortOnAttributeContext *)ctxt)->getAttribute;
    SEL compareAttributes = ((struct sortOnAttributeContext *)ctxt)->compareAttributes;

    id attributeA = OBSendObjectReturnMessage(a, getAttribute);
    id attributeB = OBSendObjectReturnMessage(b, getAttribute);

    NSComparisonResult (*cmp)(id, SEL, id) = (typeof(cmp))objc_msgSend;
    
    return (NSComparisonResult)cmp(attributeA, compareAttributes, attributeB);
}
    
- (void)sortOnAttribute:(SEL)fetchAttributeSelector usingSelector:(SEL)comparisonSelector
{
    struct sortOnAttributeContext sortContext;

    sortContext.getAttribute = fetchAttributeSelector;
    sortContext.compareAttributes = comparisonSelector;

    [self sortUsingFunction:doCompareOnAttribute context:&sortContext];
}

@end
