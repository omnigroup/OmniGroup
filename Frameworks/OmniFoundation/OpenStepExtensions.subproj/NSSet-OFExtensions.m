// Copyright 2005-2008, 2010-2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$");

@implementation NSSet (OFExtensions)

+ (BOOL)isEmptySet:(NSSet *)set;
{
    return set == nil || set.count == 0;
}

struct performAndAddContext {
    SEL sel;
    id singleObject;
    NSMutableSet *result;
};

static void performAndAdd(const void *anObject, void *_context)
{
    struct performAndAddContext *context = _context;
    id addend = [(id <NSObject>)anObject performSelector:context->sel];
    if (addend) {
        if (context->singleObject == addend) {
            /* ok */
        } else if (context->result != nil) {
            [context->result addObject:addend];
        } else if (context->singleObject == nil) {
            context->singleObject = addend;
        } else {
            NSMutableSet *newSet = [NSMutableSet set];
            [newSet addObject:context->singleObject];
            [newSet addObject:addend];
            context->singleObject = nil;
            context->result = newSet;
        }
    }
}

- (NSSet *)setByPerformingSelector:(SEL)aSelector;
{
    struct performAndAddContext ctxt = {
        .result = nil,
        .singleObject = nil,
        .sel = aSelector
    };
    
    CFSetApplyFunction((CFSetRef)self, performAndAdd, &ctxt);
    
    if (ctxt.result)
        return ctxt.result;
    else if (ctxt.singleObject)
        return [NSSet setWithObject:ctxt.singleObject];
    else
        return [NSSet set];
}

- (NSSet *)setByPerformingBlock:(OFObjectToObjectBlock)block;
{
    NSMutableSet *resultSet = nil;
    id singleResult = nil;
    
    for (id object in self) {
        id result = block(object);
        if (!result)
            continue;
        
        if (resultSet)
            [resultSet addObject:result];
        else if (singleResult)
            resultSet = [NSMutableSet setWithObjects:singleResult, result, nil];
        else
            singleResult = result;
    }
    
    if (resultSet)
        return resultSet;
    return [NSSet setWithObjects:singleResult, nil];
}

- (NSSet *)setByRemovingObject:(id)anObject;
{
    return [self filteredSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return ![evaluatedObject isEqual:anObject];
    }]];
}

struct insertionSortContext {
    SEL sel;
    NSMutableArray *into;
};

static void insertionSort(const void *anObject, void *_context)
{
    struct insertionSortContext *context = _context;
    [context->into insertObject:(id)anObject inArraySortedUsingSelector:context->sel];
}

- (NSArray *)sortedArrayUsingSelector:(SEL)comparator;
{
    struct insertionSortContext ctxt;
    
    ctxt.sel = comparator;
    ctxt.into = [NSMutableArray arrayWithCapacity:[self count]];
    
    CFSetApplyFunction((CFSetRef)self, insertionSort, &ctxt);
    
    return ctxt.into;
}

struct comparatorInsertionSortContext {
    NSComparator comparator;
    NSMutableArray *into;
};

static void comparatorInsertionSort(const void *anObject, void *_context)
{
    struct comparatorInsertionSortContext *context = _context;
    [context->into insertObject:(id)anObject inArraySortedUsingComparator:context->comparator];
}

- (NSArray *)sortedArrayUsingComparator:(NSComparator)comparator;
{
    struct comparatorInsertionSortContext ctxt;
    
    ctxt.comparator = comparator;
    ctxt.into = [NSMutableArray arrayWithCapacity:[self count]];
    
    CFSetApplyFunction((CFSetRef)self, comparatorInsertionSort, &ctxt);
    
    return ctxt.into;
}

// This is just nice so that you don't have to check for a NULL set.
- (void)applyFunction:(CFSetApplierFunction)applier context:(void *)context;
{
    CFSetApplyFunction((CFSetRef)self, applier, context);
}

- (id)any:(OFPredicateBlock)predicate;
{
    for (id obj in self) {
        if (predicate(obj))
            return obj;
    }
    return nil;
}

- (BOOL)all:(OFPredicateBlock)predicate;
{
    for (id obj in self) {
        if (!predicate(obj))
            return NO;
    }
    return YES;
}

- (id)min:(NSComparator)comparator;
{
    id minimumValue = nil;
    for (id value in self) {
        if (!minimumValue || comparator(minimumValue, value) == NSOrderedDescending)
            minimumValue = value;
    }
    return minimumValue;
}

- (id)max:(NSComparator)comparator;
{
    id maximumValue = nil;
    for (id value in self) {
        if (!maximumValue || comparator(maximumValue, value) == NSOrderedAscending)
            maximumValue = value;
    }
    return maximumValue;
}

- (id)minValueForKey:(NSString *)key comparator:(NSComparator)comparator;
{
    id minimumValue = nil;
    for (id object in self) {
        id value = [object valueForKey:key];
        if (!minimumValue || (value && comparator(minimumValue, value) == NSOrderedDescending))
            minimumValue = value;
    }
    return minimumValue;
}

- (id)maxValueForKey:(NSString *)key comparator:(NSComparator)comparator;
{
    id maximumValue = nil;
    for (id object in self) {
        id value = [object valueForKey:key];
        if (!maximumValue || (value && comparator(maximumValue, value) == NSOrderedAscending))
            maximumValue = value;
    }
    return maximumValue;
}

- (NSSet *)select:(OFPredicateBlock)predicate;
{
    NSMutableSet *matches = [NSMutableSet set];
    for (id obj in self)
        if (predicate(obj))
            [matches addObject:obj];
    return matches;
}


@end
