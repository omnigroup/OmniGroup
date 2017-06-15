// Copyright 2003-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSelectionSet.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFCFCallbacks.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

NS_ASSUME_NONNULL_BEGIN

/*
 This could potentially use a NSMutableOrderedSet internally (or be replaced by extensions on it...), except that it doesn't seem clear that we can force NSOrderedSet to use pointer equality.
 */

@interface OFSelectionSetMatchesForPredicate : NSObject

@property(nonatomic,readonly) OFPredicateBlock predicate;
@property(nonatomic,readonly) NSArray *results; // Returns an array sorted by pointer so that we can easily do an 'is identical' comparison

@end

@implementation OFSelectionSetMatchesForPredicate
{
    NSMutableArray *_results;
}

- initWithPredicate:(OFPredicateBlock)predicate;
{
    if (!(self = [super init]))
        return nil;
    
    _predicate = [predicate copy];
    _results = [[NSMutableArray alloc] init];

    return self;
}

@synthesize results = _results;

- (void)addObjectIfMatchesPredicate:(id)object;
{
    if (_predicate && !_predicate(object))
        return;
    [_results insertObject:object inArraySortedUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        if (obj1 > obj2)
            return NSOrderedDescending;
        else if (obj1 < obj2)
            return NSOrderedAscending;
        return NSOrderedSame;
    }];
}

@end

@implementation OFSelectionSet
{
    CFMutableDictionaryRef _objectToInsertionSequence;
    NSUInteger _lastInsertionSequence;
}

// Init and dealloc

- init;
{
    if (!(self = [super init]))
        return nil;

    // We want pointer equality, not content equality (particularly for OSStyle)
    _objectToInsertionSequence = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                           &OFPointerEqualObjectDictionaryKeyCallbacks,
                                                           &OFIntegerDictionaryValueCallbacks);
    _lastInsertionSequence = 0;
    
    return self;
}

- (void)dealloc;
{
    if (_objectToInsertionSequence)
        CFRelease(_objectToInsertionSequence);
}

//
// API
//

- (void)addObject:(id)object;
{
    OBASSERT(object != nil);
    OFCFDictionaryAddUIntegerValue(_objectToInsertionSequence, (OB_BRIDGE void *)object, ++_lastInsertionSequence);
}

- (void)addObjectsFromArray:(NSArray *)someObjects;
{
    OFForEachInArray(someObjects, id, anObject, OFCFDictionaryAddUIntegerValue(_objectToInsertionSequence, (OB_BRIDGE void *)anObject, ++_lastInsertionSequence));
}

- (void)removeObject:(id)object;
{
    CFDictionaryRemoveValue(_objectToInsertionSequence, (const void *)object);
    if (CFDictionaryGetCount(_objectToInsertionSequence) == 0)
        _lastInsertionSequence = 0;
}

- (BOOL)containsObject:(id)object;
{
    return CFDictionaryContainsKey(_objectToInsertionSequence, (OB_BRIDGE void *)object)? YES : NO;
}

- (NSArray *)allObjects;
{
    return [(OB_BRIDGE NSDictionary *)_objectToInsertionSequence allKeys];
}

- (NSUInteger)count;
{
    return CFDictionaryGetCount(_objectToInsertionSequence);
}

static void _addIfMatchesPredicate(const void *value, const void *sequence, void *context)
{
    OFSelectionSetMatchesForPredicate *ctx = (OB_BRIDGE OFSelectionSetMatchesForPredicate *)context;
    id object = (OB_BRIDGE id)value;
    [ctx addObjectIfMatchesPredicate:object];
}

- (NSArray *)copyObjectsSatisfyingPredicateBlock:(OFPredicateBlock)predicate;
{
    OBPRECONDITION(predicate);
    
    OFSelectionSetMatchesForPredicate *ctx = [[OFSelectionSetMatchesForPredicate alloc] initWithPredicate:predicate];
    CFDictionaryApplyFunction(_objectToInsertionSequence, _addIfMatchesPredicate, (OB_BRIDGE void *)ctx);
    
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
    return [someObjects sortedArrayUsingFunction:compareSequence context:(void *)_objectToInsertionSequence];
}

- (NSUInteger)insertionOrderForObject:(id)object;
{
    return OFCFDictionaryGetUIntegerValueWithDefault(_objectToInsertionSequence, (OB_BRIDGE void *)object, NSNotFound);
}

- (void)applyInInsertionOrder:(void (^)(id object))action;
{
    NSArray *objects = [self objectsSortedByInsertionOrder:self.allObjects];
    for (id object in objects) {
        action(object);
    }
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

    CFDictionaryApplyFunction(_objectToInsertionSequence, describeEnt, (OB_BRIDGE void *)dict);
    [dict setIntegerValue:_lastInsertionSequence forKey:@"nextInsertionSequence"];
    
    return dict;
}

@end

NS_ASSUME_NONNULL_END
