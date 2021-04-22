// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFPointerStack.h>

#import <Foundation/NSPointerArray.h>

OB_REQUIRE_ARC

NS_ASSUME_NONNULL_BEGIN

@interface OFPointerStack<T> ()

@property (nonatomic, strong) NSPointerArray *pointers;
@property (nonatomic, strong) NSMutableArray<BOOL (^)(T)> *compactionConditions;

@end

#pragma mark -

@implementation OFPointerStack

- (instancetype)init
{
    if (self = [super init]) {
        _pointers = [NSPointerArray weakObjectsPointerArray];
    }
    return self;
}

// O(1)
- (void)push:(id)object;
{
    [self push:object uniquing:NO];
}

/*
 If unique is YES, this is O(n). This ensures that the only instance of your object in the stack is the one at the top.
 */

- (void)push:(id)object uniquing:(BOOL)unique;
{
    if (unique) {
        [self remove:object];
    }
    [self.pointers insertPointer:(__bridge void * _Nullable)(object) atIndex:0];
}

/*
 If compactFirst is YES, this is O(n). We prune nil entries, and then perform the operation. If compactFirst is NO, this is O(1), but you might receive a nil object when there are valid objects in the stack
 */
- (nullable id)peekAfterCompacting:(BOOL)compactFirst;
{
    if (self.pointers.count == 0) {
        return nil;
    }
    if (compactFirst) {
        [self _compact];
    }
    
    return [self objectAtIndex:0];
}

- (nullable id)popAfterCompacting:(BOOL)compactFirst;
{
    if (self.pointers.count == 0) {
        return nil;
    }
    if (compactFirst) {
        [self _compact];
    }
    id object = [self objectAtIndex:0];
    [self.pointers removePointerAtIndex:0];
    return object;
}

// O(n)
- (NSInteger)count; // We compact before calculating the count
{
    [self _compact];
    return self.pointers.count;
}

- (BOOL)isEmpty; // Convenience for count == 0
{
    // Thread safety ensured by -count
    return self.count == 0;
}

- (BOOL)contains:(id)object; // Could be made O(1) if we add an additional NSMapTable storage that has weakly held keys that hold the stack members, and has some arbitrary object value. If table[object] is non-nil, it's in the stack. We'd also need to remove keys upon calling the remove: and pop: methods, and upon removing object that satisfy a compaction condition.
{
    return [self firstElementSatisfyingCondition:^BOOL(id anObject) { return object == anObject; }] != nil;
}

- (NSArray *)allObjects;
{
    [self _compact];
    NSMutableArray *array = [NSMutableArray array];
    [self _performBlockOnElements:^void (id object, BOOL *stop) {
        [array addObject:object];
    }];
    return array;
}

- (nullable id)firstElementSatisfyingCondition:(BOOL (^)(id))condition;
{
    [self _compact];
    __block id returnObject = nil;
    [self _performBlockOnElements:^void (id object, BOOL *stop) {
        if (condition(object)) {
            returnObject = object;
            *stop = YES;
        }
    }];
    return returnObject;
}

- (NSArray<id> *)allElementsSatisfyingCondition:(BOOL (^)(id))condition;
{
    [self _compact];
    NSMutableArray *array = [NSMutableArray array];
    [self _performBlockOnElements:^void (id object, BOOL *stop) {
        if (condition(object)) {
            [array addObject:object];
        }
    }];
    return array;
}

- (void)remove:(id)object;
{
    [self _compact];
    NSInteger count = self.pointers.count;
    for (int i = 0; i < count; i++) {
        void *pointer = [self.pointers pointerAtIndex:i];
        OBASSERT(pointer != NULL);
        id anObject = (__bridge id)pointer;
        if (anObject == object) {
            [self.pointers removePointerAtIndex:i];
            i--;
            count--;
        }
    }
}

// API
// Normally, the only compaction condition is that nil objects and NULL pointers are pruned. This happens upon calling each O(n) operation. Your condition block can be called up to N times, so if your condition takes higher than constant time to evaluate (or you introduce N conditions) you could introduce performance issues. Also, be sure to be careful if you use objects that may be in the pointer stack as a basis for comparison in this block, as that will strongly retain the object and sidestep the weak behavior that is expected with this structure.
- (void)addAdditionalCompactionCondition:(BOOL (^)(id))condition;
{
    if (self.compactionConditions == nil) {
        self.compactionConditions = [NSMutableArray array];
    }
    [self.compactionConditions addObject:[condition copy]];
}

// MARK: - Private

- (nullable id)objectAtIndex:(NSInteger)index;
{
    if (index < 0 || index >= self.count) {
        return nil;
    }
    
    void *pointer = [self.pointers pointerAtIndex:index];
    if (pointer == NULL) {
        return nil;
    }
    id object = (__bridge id)(pointer);
    return object;
}

- (void)_performBlockOnElements:(void (^)(id, BOOL *))block;
{
    NSInteger count = self.pointers.count;
    BOOL stop = NO;
    for (int i = 0; i < count; i++) {
        void *pointer = [self.pointers pointerAtIndex:i];
        if (pointer == NULL) {
            continue;
        }
        id object = (__bridge id)(pointer);
        block(object, &stop);
        if (stop) {
            return;
        }
    }
}

- (void)_compact;
{
    NSInteger count = self.pointers.count-1;
    for (NSInteger i = count; i >= 0; i--) {
        void *pointer = [self.pointers pointerAtIndex:i];
        id object = (__bridge id)(pointer);
        // Prune null pointers and deallocated weak pointers
        if (pointer == NULL || [(NSObject *)object self] == nil) {
            [self.pointers removePointerAtIndex:i];
        }
    }
    
    if (self.compactionConditions.count > 0) {
        for (BOOL (^compactionCondition)(id) in self.compactionConditions) {
            count = self.pointers.count-1;
            for (NSInteger i = count; i >= 0; i--) {
                void *pointer = [self.pointers pointerAtIndex:i];
                id object = (__bridge id)(pointer);
                
                // Prune null pointers and deallocated weak pointers. Even though we did this above, it's possible another thread has deallocated our instance since doing this before.
                if (pointer == NULL || [(NSObject *)object self] == nil) {
                    [self.pointers removePointerAtIndex:i];
                    continue;
                }
                
                if (!compactionCondition(object)) {
                    // If the object doesn't satisfy this compaction condition, prune it.
                    [self.pointers removePointerAtIndex:i];
                }
                
            }
        }
    }
}

@end

NS_ASSUME_NONNULL_END
