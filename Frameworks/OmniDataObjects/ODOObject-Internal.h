// Copyright 2008-2010, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOProperty.h>
#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODOEditingContext.h>

#import <Foundation/NSUndoManager.h>

#import "ODOEntity-Internal.h"

@interface ODOObject (Internal)
- (id)initWithEditingContext:(ODOEditingContext *)context objectID:(ODOObjectID *)objectID isFault:(BOOL)isFault;
- (id)initWithEditingContext:(ODOEditingContext *)context objectID:(ODOObjectID *)objectID snapshot:(CFArrayRef)snapshot;
- (void)_setIsFault:(BOOL)isFault;
- (void)_turnIntoFault:(BOOL)deleting;
- (void)_invalidate;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_odo_checkInvariants;
#endif

@end

__private_extern__ NSArray *_ODOObjectCreatePropertySnapshot(ODOObject *self);

// Make it more clear what we mean when we compare to nil.
#define ODO_OBJECT_LAZY_TO_MANY_FAULT_MARKER (nil)
static inline BOOL ODOObjectValueIsLazyToManyFault(id value)
{
    return (value == ODO_OBJECT_LAZY_TO_MANY_FAULT_MARKER);
}

#ifdef OMNI_ASSERTIONS_ON
__private_extern__ BOOL _ODOAssertSnapshotIsValidForObject(ODOObject *self, CFArrayRef snapshot);
#endif

static inline void _ODOObjectCreateNullValues(ODOObject *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(!self->_flags.invalid);
    OBPRECONDITION(self->_editingContext);
    OBPRECONDITION(self->_objectID);
    OBPRECONDITION(![self isInserted]);
    OBPRECONDITION(![self isUpdated]);
    OBPRECONDITION(![self isDeleted]);
    
    NSUInteger snapshotPropertyCount = [[[self->_objectID entity] snapshotProperties] count];
    OBASSERT(snapshotPropertyCount > 0);
    
    self->_valueStorage = (id *)calloc(sizeof(id), snapshotPropertyCount);
}

static inline void _ODOObjectCreateValuesFromSnapshot(ODOObject *self, CFArrayRef snapshot)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(self->_objectID); // Must be at least this initialized
    OBPRECONDITION(self->_valueStorage == NULL); // but not already envalued
    OBPRECONDITION(_ODOAssertSnapshotIsValidForObject(self, snapshot));

    NSUInteger snapshotPropertyCount = [[[self->_objectID entity] snapshotProperties] count];
    OBASSERT((CFIndex)snapshotPropertyCount == CFArrayGetCount(snapshot));
    
    // Not clearing the array via calloc; will fill it w/o releasing the old values here.
    self->_valueStorage = (id *)malloc(sizeof(id) * snapshotPropertyCount);
    
    // Extract the snapshot into the value storage; this doesn't retain or copy the values!
    CFArrayGetValues(snapshot, CFRangeMake(0, snapshotPropertyCount), (const void **)self->_valueStorage);
    
    // Now, retain them all.  We expect that the values in the snapshot are already immutable copies.  Otherwise we'd have to do "x = copy(x)" for each slot (which'd be slightly slower).
    NSUInteger propertyIndex = snapshotPropertyCount;
    while (propertyIndex--)
        [self->_valueStorage[propertyIndex] retain];
}

static inline BOOL _ODOObjectHasValues(ODOObject *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    return self->_valueStorage != NULL;
}

static inline void _ODOObjectReleaseValues(ODOObject *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    
    // We don't know the count since this isn't an array any longer.
    NSUInteger valueIndex = [[[self->_objectID entity] snapshotProperties] count];
    while (valueIndex--)
        [self->_valueStorage[valueIndex] release]; // Not clearing the slot since we are about to...

    free(self->_valueStorage);
    self->_valueStorage = NULL;
}

static inline void _ODOObjectReleaseValuesIfPresent(ODOObject *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);

    if (!_ODOObjectHasValues(self))
        return;
    _ODOObjectReleaseValues(self);
}

static inline void _ODOObjectSetValuesToNull(ODOObject *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    
    id *valueStorage = self->_valueStorage;
    if (valueStorage) {
        NSUInteger valueIndex = [[[self->_objectID entity] snapshotProperties] count];
        while (valueIndex--) {
            [valueStorage[valueIndex] release];
            valueStorage[valueIndex] = nil; // could remember the count and memset after the loop
        }
    }
}

static inline id _ODOObjectValueAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(snapshotIndex < [[[self->_objectID entity] snapshotProperties] count]);
    OBPRECONDITION(self->_valueStorage != NULL); // This is the case if the object is invalidated either due to deletion or the editing context being reset.  In CoreData, messaging an dead object will sometimes get an exception, sometimes get a crash or sometimes (if you are in the middle of invalidation) get you a stale value.  In ODO, it gets you dead.  Hopefully we won't have to relax this since it makes tracking down these (very real) problems easier.

    return self->_valueStorage[snapshotIndex];
}

static inline void _ODOObjectSetValueAtIndex(ODOObject *self, NSUInteger snapshotIndex, id value)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(snapshotIndex < [[[self->_objectID entity] snapshotProperties] count]);
    
    if (value == self->_valueStorage[snapshotIndex])
        return;
    
    // Not doing -copy since this might be a mutable to-many set.  Higher level code should copy attribute values?  Maybe we should have a setter that passes in a retained value.
    [self->_valueStorage[snapshotIndex] release];
    self->_valueStorage[snapshotIndex] = [value retain];
}

static inline BOOL _ODOObjectIsUndeletable(ODOObject *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    return self->_flags.undeletable;
}

@class ODORelationship;

__private_extern__ void ODOObjectClearValues(ODOObject *self, BOOL deleting);

__private_extern__ void ODOObjectPrepareForAwakeFromFetch(ODOObject *self);
__private_extern__ void ODOObjectPerformAwakeFromFetchWithoutRegisteringEdits(ODOObject *self);
__private_extern__ void ODOObjectFinalizeAwakeFromFetch(ODOObject *self);

__private_extern__ void ODOObjectAwakeSingleObjectFromFetch(ODOObject *object);
__private_extern__ void ODOObjectAwakeObjectsFromFetch(NSArray *objects);

__private_extern__ BOOL ODOObjectToManyRelationshipIsFault(ODOObject *self, ODORelationship *rel);
__private_extern__ NSMutableSet *ODOObjectToManyRelationshipIfNotFault(ODOObject *self, ODORelationship *rel);

__private_extern__ void ODOObjectSetChangeProcessingEnabled(ODOObject *self, BOOL enabled);
__private_extern__ BOOL ODOObjectChangeProcessingEnabled(ODOObject *self);

__private_extern__ CFArrayRef ODOObjectCreateDifferenceRecordFromSnapshot(ODOObject *self, CFArrayRef snapshot);
__private_extern__ void ODOObjectApplyDifferenceRecord(ODOObject *self, CFArrayRef diff);
