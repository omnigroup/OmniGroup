// Copyright 2005-2008, 2010-2011, 2013 Omni Development, Inc. All rights reserved.
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

- (NSSet *)select:(OFPredicateBlock)predicate;
{
    NSMutableSet *matches = [NSMutableSet set];
    for (id obj in self)
        if (predicate(obj))
            [matches addObject:obj];
    return matches;
}

@end
