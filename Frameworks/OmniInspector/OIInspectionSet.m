// Copyright 2003-2008, 2010, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspectionSet.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

@interface OIInspectionSetMatchesForPredicate : NSObject

@property(nonatomic,readonly) OFPredicateBlock predicate;
@property(nonatomic,readonly) NSArray *results; // Returns an array sorted by pointer so that we can easily do an 'is identical' comparison

@end

@implementation OIInspectionSetMatchesForPredicate
{
    NSMutableArray *_results;
}

- initWithPredicate:(OFPredicateBlock)predicate;
{
    if (!(self = [super init]))
        return nil;
    
    _predicate = [predicate copy];
    
    return self;
}

@synthesize results = _results;

- (void)addObjectIfMatchesPredicate:(id)object;
{
    if (_predicate && !_predicate(object))
        return;
    if (!_results)
        _results = [[NSMutableArray alloc] init];
    [_results insertObject:object inArraySortedUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        if (obj1 > obj2)
            return NSOrderedDescending;
        else if (obj1 < obj2)
            return NSOrderedAscending;
        return NSOrderedSame;
    }];
}

@end

@implementation OIInspectionSet
{
    CFMutableDictionaryRef objects;
    NSUInteger insertionSequence;
}

// Init and dealloc

- init;
{
    if (!(self = [super init]))
        return nil;

    // We want pointer equality, not content equality (particularly for OSStyle)
    objects = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                        &OFPointerEqualObjectDictionaryKeyCallbacks,
                                        &OFIntegerDictionaryValueCallbacks);
    insertionSequence = 0;
    
    return self;
}

- (void)dealloc;
{
    CFRelease(objects);
}

//
// API
//

- (void)addObject:(id)object;
{
    OBASSERT(object != nil);
    OFCFDictionaryAddUIntegerValue(objects, (OB_BRIDGE void *)object, ++insertionSequence);
}

- (void)addObjectsFromArray:(NSArray *)someObjects;
{
    OFForEachInArray(someObjects, id, anObject, OFCFDictionaryAddUIntegerValue(objects, (OB_BRIDGE void *)anObject, ++insertionSequence));
}

- (void)removeObject:(id)object;
{
    CFDictionaryRemoveValue(objects, (const void *)object);
    if (CFDictionaryGetCount(objects) == 0)
        insertionSequence = 0;
}

- (BOOL)containsObject:(id)object;
{
    return CFDictionaryContainsKey(objects, (OB_BRIDGE void *)object)? YES : NO;
}

- (NSArray *)allObjects;
{
    return [(OB_BRIDGE NSDictionary *)objects allKeys];
}

- (NSUInteger)count;
{
    return CFDictionaryGetCount(objects);
}

static void _addIfMatchesPredicate(const void *value, const void *sequence, void *context)
{
    OIInspectionSetMatchesForPredicate *ctx = (OB_BRIDGE OIInspectionSetMatchesForPredicate *)context;
    id object = (OB_BRIDGE id)value;
    [ctx addObjectIfMatchesPredicate:object];
}

- (NSArray *)copyObjectsSatisfyingPredicateBlock:(OFPredicateBlock)predicate;
{
    OBPRECONDITION(predicate);
    
    OIInspectionSetMatchesForPredicate *ctx = [[OIInspectionSetMatchesForPredicate alloc] initWithPredicate:predicate];
    CFDictionaryApplyFunction(objects, _addIfMatchesPredicate, (OB_BRIDGE void *)ctx);
    
    NSArray *results = [ctx.results copy];
    
    return results;
}

- (NSArray *)copyObjectsSatisfyingPredicate:(NSPredicate *)predicate;
{
    return [self copyObjectsSatisfyingPredicateBlock:^BOOL(id object){
        return [predicate evaluateWithObject:object];
    }];
}

- (void)removeObjectsSatisfyingPredicate:(NSPredicate *)predicate;
{
    // Can't modify a set we are enumerating, so collect objects to remove up front.
    NSArray *toRemove = [self copyObjectsSatisfyingPredicate:predicate];
    [self removeObjectsInArray:toRemove];
}

- (void)removeObjectsInArray:(NSArray *)toRemove;
{
    NSUInteger objectIndex = [toRemove count];
    while (objectIndex--)
        [self removeObject:[toRemove objectAtIndex:objectIndex]];
}

- (void)removeAllObjects;
{
    [self removeObjectsInArray:[self allObjects]];
}

static NSComparisonResult compareSequence(id obj1, id obj2, void *context)
{
    Boolean exists1, exists2;
    NSUInteger seq1, seq2;
    
    seq1 = seq2 = 0;
    exists1 = OFCFDictionaryGetUIntegerValueIfPresent((CFDictionaryRef)context, (OB_BRIDGE void *)obj1, &seq1);
    exists2 = OFCFDictionaryGetUIntegerValueIfPresent((CFDictionaryRef)context, (OB_BRIDGE void *)obj2, &seq2);
    
    if (exists1 && exists2) {
        if (seq1 > seq2)
            return NSOrderedDescending;
        else if (seq1 < seq2)
            return NSOrderedAscending;
        return NSOrderedSame;
    }
    
    // Objects not in the sequence at all get sorted to the end, in no particular order.
    if (exists1 && !exists2)
        return NSOrderedAscending;
    if (exists2 && !exists1)
        return NSOrderedDescending;
    return NSOrderedSame;
}

- (NSArray *)objectsSortedByInsertionOrder:(NSArray *)someObjects;
{
    return [someObjects sortedArrayUsingFunction:compareSequence context:(void *)objects];
}

- (NSUInteger)insertionOrderForObject:(id)object;
{
    return OFCFDictionaryGetUIntegerValueWithDefault(objects, (OB_BRIDGE void *)object, NSNotFound);
}

//
// Debugging
//
static void describeEnt(const void *k, const void *v, void *d)
{
    uintptr_t ix = (uintptr_t)v;
    [(OB_BRIDGE NSMutableDictionary *)d setObject:[NSNumber numberWithUnsignedInteger:ix] forKey:OBShortObjectDescription((OB_BRIDGE id)k)];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];

    CFDictionaryApplyFunction(objects, describeEnt, (OB_BRIDGE void *)dict);
    [dict setIntegerValue:insertionSequence forKey:@"insertionSequence"];
    
    return dict;
}

@end
