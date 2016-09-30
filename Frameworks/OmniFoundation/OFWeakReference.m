// Copyright 2012-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFWeakReference.h>

#import <OmniFoundation/NSMutableArray-OFExtensions.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

// Stuff from the old OFWeakRetain protocol
OBDEPRECATED_METHOD(-invalidateWeakRetains);
OBDEPRECATED_METHOD(-incrementWeakRetainCount);
OBDEPRECATED_METHOD(-decrementWeakRetainCount);
OBDEPRECATED_METHOD(-strongRetain);

// Helper from OFWeakRetainConcreteImplementation.h
OBDEPRECATED_METHOD(-_releaseFromWeakRetainHelper);

#if !OB_ARC
#error This file must be built with ARC enabled to support auto-zeroing weak references
#endif

@implementation OFWeakReference
{
    __weak id _weakObject;
    void *_nonretainedObjectPointer;
    BOOL _isDeallocating;
}

@synthesize object = _weakObject;

- (instancetype)initWithObject:(id)object;
{
    if (!(self = [super init]))
        return nil;
    
    _weakObject = object;
    _nonretainedObjectPointer = (__bridge void *)object;
    
    return self;
}

- (instancetype)initWithDeallocatingObject:(id)object;
{
    if (!(self = [super init]))
        return nil;
    
    _nonretainedObjectPointer = (__bridge void *)object;
    _isDeallocating = YES;
    
    return self;
}

- (BOOL)referencesObject:(void *)objectPointer;
{
    if (_nonretainedObjectPointer != objectPointer) {
        return NO;
    }
    return _weakObject != nil; // In case it got deallocated and a new object created at the same address.
}

/// Adds a new OFWeakReference to object. It is an error to add the same object more than once. This will also remove any references to objects that have been deallocated.
+ (void)add:(id)object toReferences:(NSMutableArray <OFWeakReference *> *)references;
{
    OBPRECONDITION(references != nil);

#ifdef OMNI_ASSERTIONS_ON
    for (OFWeakReference *reference in references) {
        OBASSERT([reference referencesObject:(__bridge void *)object] == NO);
    }
#endif
    [self _pruneReferences:references];

    OFWeakReference *reference = [[OFWeakReference alloc] initWithObject:object];
    [references addObject:reference];
}

/// Removes a reference to an existing object. It is an error to attempt to remove an object that was not previously added. This will also remove any references to objects that have been deallocated.
+ (void)remove:(id)object fromReferences:(NSMutableArray <OFWeakReference *> *)references;
{
    OBPRECONDITION(references != nil);

#ifdef OMNI_ASSERTIONS_ON
    __block BOOL found = NO;
#endif

    [references removeObjectsSatisfyingPredicate:^BOOL(OFWeakReference *reference){
        _Nullable id existing = reference.object;

#ifdef OMNI_ASSERTIONS_ON
        found |= (existing == object) || (existing == nil && reference->_nonretainedObjectPointer == (__bridge void *)(object));
#endif
        return (existing == object) || (existing == nil); // Clean up any deallocated references at the same time.
    }];

    // **NOTE** If you are hitting this, make sure you aren't trying to remove a reference to an object that is in the middle of its -dealloc. In that case, its wrapping OFWeakReference will return nil from -object and it will have been pruned automatically.
    OBASSERT(found, "Attempted to remove an observer that is not registered.");
}

/// Calls the given block once for each still-valid object in the reference array. Any invalid references will be removed.
+ (void)forEachReference:(NSMutableArray <OFWeakReference *> *)references perform:(void (^)(id))action;
{
    // Copying in case the action makes further modifications. Any newly added references will not be considered, and any removed references will still be acted on this time around.
    NSArray <OFWeakReference *> *copy = [references copy];

    for (OFWeakReference *reference in copy) {
        id object = reference.object;
        if (object == nil) {
            // Don't assume that the reference array is unmodified. We *could* probe the original index first if this N^2 approach ever shows up on a profile. Also, something else might have removed it (like a reentrant call to add/remove another reference).
            NSUInteger referenceIndex = [references indexOfObjectIdenticalTo:reference];
            if (referenceIndex != NSNotFound) {
                [references removeObject:object];
            }
        } else {
            action(object);
        }
    }
}

+ (void)_pruneReferences:(NSMutableArray <OFWeakReference *> *)references;
{
    [references removeObjectsSatisfyingPredicate:^BOOL(OFWeakReference *reference){
        return (reference.object == nil);
    }];
}

+ (BOOL)referencesEmpty:(NSArray *)references;
{
    for (OFWeakReference *ref in references) {
        if (ref.object != nil)
            return NO;
    }
    return YES;
}

+ (NSUInteger)countReferences:(NSArray *)references;
{
    __block NSUInteger count = 0;

    for (OFWeakReference *ref in references) {
        if (ref.object != nil) {
            count++;
        }
    }

    return count;
}

#pragma mark - NSObject protocol

- (BOOL)isEqual:(id)otherObject;
{
    if (self == otherObject)
        return YES;

    if (![otherObject isKindOfClass:[self class]])
        return NO;

    OFWeakReference *otherReference = (OFWeakReference *)otherObject;
    return otherReference->_nonretainedObjectPointer == _nonretainedObjectPointer && (otherReference->_weakObject == _weakObject || _isDeallocating || otherReference->_isDeallocating);
}

- (NSUInteger)hash;
{
    return (NSUInteger)_nonretainedObjectPointer;
}

#pragma mark - Debugging

- (NSString *)debugDescription;
{
    return [NSString stringWithFormat:@"<%@: %p -- %@>", NSStringFromClass([self class]), self, OBShortObjectDescription(self.object)];
}

@end

NS_ASSUME_NONNULL_END
