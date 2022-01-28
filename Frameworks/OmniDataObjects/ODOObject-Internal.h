// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODOObjectSnapshot.h>
#import <OmniDataObjects/ODOProperty.h>
#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODOEditingContext.h>
#import <OmniDataObjects/ODOFloatingDate.h>

#import <Foundation/NSUndoManager.h>

#import "ODOEntity-Internal.h"
#import "ODOProperty-Internal.h"
#import "ODOStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface ODOObject () {

    @package
    union {
        // Our implementation is non-ARC and manages these references manually, but make this header importable by ARC.
        __unsafe_unretained ODOProperty * _Nullable single;
        __unsafe_unretained NSMutableArray <ODOProperty *> * _Nullable multiple;
    } _propertyBeingCalculated;

    struct {
        unsigned int isFault : 1;
        unsigned int changeProcessingDisabled : 1;
        unsigned int invalid : 1;
        unsigned int isAwakingFromInsert : 1;

        unsigned int isScheduledForBatchFetch : 1;
        unsigned int needsAwakeFromFetch : 1;
        unsigned int isAwakingFromFetch : 1;

        unsigned int isAwakingFromReinsertionAfterUndoneDeletion : 1;
        unsigned int isAwakingFromUnarchive : 1;
        unsigned int hasChangedModifyingToManyRelationshipSinceLastSave : 1;
        unsigned int undeletable : 1;
        unsigned int hasStartedDeletion : 1; // -isDeleted is only true while the object is pending deletion
        unsigned int hasFinishedDeletion : 1; // -isDeleted is only true while the object is pending deletion
        unsigned int propertyBeingCalculatedIsMultiple : 1;
    } _flags;

}

// Internal initializers
- (instancetype)initWithEditingContext:(ODOEditingContext *)context objectID:(ODOObjectID *)objectID isFault:(BOOL)isFault NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithEditingContext:(ODOEditingContext *)context objectID:(ODOObjectID *)objectID snapshot:(ODOObjectSnapshot *)snapshot NS_DESIGNATED_INITIALIZER;

@end

@interface ODOObject (Internal)

- (BOOL)_isAwakingFromInsert;
- (void)_setIsAwakingFromInsert:(BOOL)isAwakingFromInsert;
- (void)_setIsAwakingFromReinsertionAfterUndoneDeletion:(BOOL)isAwakingFromReinsertionAfterUndoneDeletion;
- (void)_setIsFault:(BOOL)isFault;
- (void)_turnIntoFault:(ODOFaultEvent)faultEvent;
- (void)_invalidate;

- (BOOL)_isCalculatingValueForProperty:(ODOProperty *)property;
- (void)_setIsCalculatingValueForProperty:(ODOProperty *)property;
- (void)_clearIsCalculatingValueForProperty:(ODOProperty *)property;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_odo_checkInvariants;
#endif

@end

// Faster than isKindOfClass:
@interface NSObject (ODOIsObject)
- (BOOL)_isODOObject;
@end

extern NSSet *_ODOEmptyToManySet OB_HIDDEN;
extern ODOObjectSnapshot *_ODOObjectCreatePropertySnapshot(ODOObject *self) OB_HIDDEN;

// Make it more clear what we mean when we compare to nil.
#define ODO_OBJECT_LAZY_TO_MANY_FAULT_MARKER (nil)
static inline BOOL ODOObjectValueIsLazyToManyFault(id value)
{
    return (value == ODO_OBJECT_LAZY_TO_MANY_FAULT_MARKER);
}

#ifdef OMNI_ASSERTIONS_ON
BOOL _ODOAssertSnapshotIsValidForObject(ODOObject *self, ODOObjectSnapshot *snapshot) OB_HIDDEN;
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
    
    size_t snapshotSize = self->_objectID.entity.snapshotSize;
    OBASSERT(snapshotSize > 0);
    
    self->_valueStorage = calloc(1, snapshotSize);
    _ODOStorageCheckBase(self->_valueStorage);
}

static inline void _ODOObjectCreateValuesFromSnapshot(ODOObject *self, ODOObjectSnapshot *snapshot)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(self->_objectID); // Must be at least this initialized
    OBPRECONDITION(self->_valueStorage == NULL); // but not already envalued
    OBPRECONDITION(_ODOAssertSnapshotIsValidForObject(self, snapshot));

    ODOEntity *entity = self->_objectID.entity;
    size_t storageSize = entity.snapshotSize;

    // Not clearing the array via calloc; will overwrite it with memcpy from the snapshot storage.
    self->_valueStorage = malloc(storageSize);
    _ODOStorageCheckBase(self->_valueStorage);

    ODOStorageCopy(entity, self->_valueStorage, ODOObjectSnapshotGetStorageBase(snapshot), storageSize);
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
    ODOEntity *entity = self->_objectID.entity;
    for (ODOProperty *property in entity.snapshotProperties) {
        ODOStorageKey storageKey = property->_storageKey;
        if (storageKey.type != ODOStorageTypeObject) {
            continue;
        }
        
        ODOStorageReleaseObject(entity, self->_valueStorage, storageKey);
    }

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

static inline id _Nullable _ODOObjectGetObjectValueForProperty(ODOObject *self, ODOProperty *property)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(self.entity == property.entity);
    OBPRECONDITION(!self->_flags.invalid);
    OBPRECONDITION(self->_editingContext);
    OBPRECONDITION(self->_objectID);

    OBPRECONDITION(self->_valueStorage != NULL); // This is the case if the object is invalidated either due to deletion or the editing context being reset.  In CoreData, messaging an dead object will sometimes get an exception, sometimes get a crash or sometimes (if you are in the middle of invalidation) get you a stale value.  In ODO, it gets you dead.  Hopefully we won't have to relax this since it makes tracking down these (very real) problems easier.

    return ODOStorageGetObjectValue(self->_objectID.entity, self->_valueStorage, property->_storageKey);
}


static inline void _ODOObjectSetObjectValueForProperty(ODOObject *self, ODOProperty *property, id _Nullable value)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(self.entity == property.entity);
    OBPRECONDITION(!self->_flags.invalid);
    OBPRECONDITION(self->_editingContext);
    OBPRECONDITION(self->_objectID);

    ODOEntity *entity = self->_objectID.entity;

    ODOStorageSetObjectValue(entity, self->_valueStorage, property->_storageKey, value);
}

static inline BOOL _ODOObjectIsUndeletable(ODOObject *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    return self->_flags.undeletable;
}

static inline BOOL _ODOIsEqual(_Nullable id value1, _Nullable id value2)
{
    if (!OFISEQUAL(value1, value2))
        return NO;

    if (value1 != nil && [value1 isKindOfClass:[NSDate class]]) {
        NSDate *date1 = value1;
        NSDate *date2 = value2;
        return date1.isFloating == date2.isFloating;
    } else {
        return YES;
    }
}

@class ODORelationship;
@class NSMapTable<KeyType, ObjectType>;

void ODOObjectPrepareObjectsForAwakeFromFetch(ODOEntity *entity, NSArray <ODOObject *> *objects,  NSMapTable<ODOEntity *, NSMutableArray <ODOObject *> *> * _Nullable entityToPrefetchObjects) OB_HIDDEN;

void ODOObjectPerformAwakeFromFetchWithoutRegisteringEdits(ODOObject *self) OB_HIDDEN;
void ODOObjectFinalizeAwakeFromFetch(ODOObject *self) OB_HIDDEN;

BOOL ODOObjectToManyRelationshipIsFault(ODOObject *self, ODORelationship *rel) OB_HIDDEN;
NSMutableSet * _Nullable ODOObjectToManyRelationshipIfNotFault(ODOObject *self, ODORelationship *rel) OB_HIDDEN;

void ODOObjectSetChangeProcessingEnabled(ODOObject *self, BOOL enabled) OB_HIDDEN;
BOOL ODOObjectChangeProcessingEnabled(ODOObject *self) OB_HIDDEN;

_Nullable CFArrayRef ODOObjectCreateDifferenceRecordFromSnapshot(ODOObject *self, ODOObjectSnapshot *snapshot) OB_HIDDEN;
void ODOObjectApplyDifferenceRecord(ODOObject *self, CFArrayRef diff) OB_HIDDEN;

extern void ODOObjectWillChangeValueForProperty(ODOObject *object, ODOProperty *property) OB_HIDDEN;
extern void ODOObjectDidChangeValueForProperty(ODOObject *object, ODOProperty *property) OB_HIDDEN;

NS_ASSUME_NONNULL_END
