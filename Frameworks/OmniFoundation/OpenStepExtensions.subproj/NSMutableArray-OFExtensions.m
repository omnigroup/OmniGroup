// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSMutableArray-OFExtensions.h>

#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/CFDictionary-OFExtensions.h>

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

static void addObjectToArray(const void *value, void *context)
{
    [(NSMutableArray *)context addObject:(id)value];
}

- (void)addObjectsFromSet:(NSSet *)aSet;
{
    if (aSet == nil || [aSet count] == 0)
        return;

    /* We use this instead of an NSSet method in order to avoid autoreleases */
    CFSetApplyFunction((CFSetRef)aSet, addObjectToArray, (void *)self);
}

- (void)removeObjectsInSet:(NSSet *)aSet;
{
    NSUInteger objectIndex = [self count];
    while (objectIndex--) {
        if ([aSet member:[self objectAtIndex:objectIndex]])
            [self removeObjectAtIndex:objectIndex];
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
    NSUInteger objectIndex;

    NS_DURING;
    
    for(objectIndex = 0; objectIndex < replacementRange.length; objectIndex ++) {
        id sourceObject, replacementObject;

        sourceObject = [self objectAtIndex:(replacementRange.location + objectIndex)];
        replacementObject = [sourceObject performSelector:selector];
        if (replacementObject == nil)
            OBRejectInvalidCall(self, _cmd,
                                @"Object at index %lu returned nil from %@",
                                (unsigned long)(replacementRange.location + objectIndex),
                                NSStringFromSelector(selector));
        [replacements addObject:replacementObject];
    }

    [self replaceObjectsInRange:replacementRange withObjectsFromArray:replacements];

    NS_HANDLER {
        [replacements release];
        [localException raise];
    } NS_ENDHANDLER;

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

#ifdef OMNI_ASSERTIONS_ON
static void  __attribute__((constructor)) check_sizes(void)
{
    /* If these are not true, the routines which store integer values in CFDictionaries here and elsewhere clobber memory */
    assert(sizeof(NSUInteger) == sizeof(uintptr_t));
    assert(sizeof(void *) == sizeof(NSUInteger));
}
#endif

struct sortOrderingContext {
    CFMutableDictionaryRef sortOrdering;
    BOOL putUnknownObjectsAtFront;
};

static NSComparisonResult orderObjectsBySavedIndex(id object1, id object2, void *_context)
{
    const struct sortOrderingContext context = *(struct sortOrderingContext *)_context;
    Boolean obj1Known, obj2Known;
    NSUInteger obj1Index, obj2Index;
    
    if (object1 == object2)
        return NSOrderedSame;
    
    obj1Index = obj2Index = 0;
    obj1Known = OFCFDictionaryGetUIntegerValueIfPresent(context.sortOrdering, object1, &obj1Index);
    obj2Known = OFCFDictionaryGetUIntegerValueIfPresent(context.sortOrdering, object2, &obj2Index);

    if (obj1Known) {
        if (obj2Known) {
            if (obj1Index < obj2Index)
                return NSOrderedAscending;
            else {
                OBASSERT(obj1Index != obj2Index);
                return NSOrderedDescending;
            }
        } else
            return context.putUnknownObjectsAtFront ? NSOrderedDescending : NSOrderedAscending;
    } else {
        if (obj2Known)
            return context.putUnknownObjectsAtFront ? NSOrderedAscending : NSOrderedDescending;
        else
            return NSOrderedSame;
    }
}

- (void)sortBasedOnOrderInArray:(NSArray *)ordering identical:(BOOL)usePointerEquality unknownAtFront:(BOOL)putUnknownObjectsAtFront;
{
    struct sortOrderingContext context;
    NSUInteger orderingCount = [ordering count];
    NSUInteger orderingIndex;
    
    context.putUnknownObjectsAtFront = putUnknownObjectsAtFront;
    context.sortOrdering = CFDictionaryCreateMutable(kCFAllocatorDefault, orderingCount,
                                                     usePointerEquality? &OFNonOwnedPointerDictionaryKeyCallbacks : &OFNSObjectDictionaryKeyCallbacks,
                                                     &OFIntegerDictionaryValueCallbacks);
    for(orderingIndex = 0; orderingIndex < orderingCount; orderingIndex++)
        OFCFDictionaryAddUIntegerValue(context.sortOrdering, [ordering objectAtIndex:orderingIndex], orderingIndex);
    [self sortUsingFunction:&orderObjectsBySavedIndex context:&context];
    CFRelease(context.sortOrdering);
}


/* Assumes the array is already sorted to insert the object quickly in the right place */
- (void)insertObject:anObject inArraySortedUsingSelector:(SEL)selector;
{
    NSUInteger objectIndex = [self indexWhereObjectWouldBelong:anObject inArraySortedUsingSelector:selector];
    [self insertObject:anObject atIndex:objectIndex];
}    

- (void)insertObject:(id)anObject inArraySortedUsingFunction:(NSComparisonResult (*)(id, id, void *))compare context:(void *)context;
{
    NSUInteger objectIndex = [self indexWhereObjectWouldBelong:anObject inArraySortedUsingFunction:compare context:context];
    [self insertObject:anObject atIndex:objectIndex];
}

/* Assumes the array is already sorted to find the object quickly and remove it */
- (void)removeObjectIdenticalTo: (id)anObject fromArraySortedUsingSelector:(SEL)selector
{
    NSUInteger objectIndex = [self indexOfObjectIdenticalTo:anObject inArraySortedUsingSelector:selector];
    if (objectIndex != NSNotFound)
        [self removeObjectAtIndex: objectIndex];
}

- (void)removeObjectIdenticalTo:(id)anObject fromArraySortedUsingFunction:(NSComparisonResult (*)(id, id, void *))compare context:(void *)context;
{
    NSUInteger objectIndex = [self indexOfObject:anObject identical:YES inArraySortedUsingFunction:compare context:context];
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
    id attributeA, attributeB;

    attributeA = [a performSelector:getAttribute];
    attributeB = [b performSelector:getAttribute];

    return (NSComparisonResult)[attributeA performSelector:compareAttributes withObject:attributeB];
}
    
- (void)sortOnAttribute:(SEL)fetchAttributeSelector usingSelector:(SEL)comparisonSelector
{
    struct sortOnAttributeContext sortContext;

    sortContext.getAttribute = fetchAttributeSelector;
    sortContext.compareAttributes = comparisonSelector;

    [self sortUsingFunction:doCompareOnAttribute context:&sortContext];
}

@end
