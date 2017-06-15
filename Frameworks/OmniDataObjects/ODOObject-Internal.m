// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOObject-Internal.h"

#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/ODOEditingContext.h>
#import <OmniDataObjects/ODOObjectID.h>

#import "ODOObject-Accessors.h"
#import "ODOProperty-Internal.h"
#import "ODOEditingContext-Internal.h"

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation ODOObject (Internal)

#ifdef OMNI_ASSERTIONS_ON
BOOL _ODOAssertSnapshotIsValidForObject(ODOObject *self, CFArrayRef snapshot)
{
    // The snapshot should have no to-manys and all to-ones should be just primary keys.
    // All values shoudl be of the proper class
    NSArray *properties = [[self->_objectID entity] snapshotProperties];
    NSUInteger propertyIndex = [properties count];
    while (propertyIndex--) {
        ODOProperty *property = [properties objectAtIndex:propertyIndex];
        struct _ODOPropertyFlags flags = ODOPropertyFlags(property);
        
        id value = (id)CFArrayGetValueAtIndex(snapshot, propertyIndex);
        if (flags.relationship) {
            ODORelationship *rel = (ODORelationship *)property;
            
            if (flags.toMany) {
                OBASSERT(value == ODO_OBJECT_LAZY_TO_MANY_FAULT_MARKER);
            } else {
                OBASSERT(!value || [value isKindOfClass:[[[rel destinationEntity] primaryKeyAttribute] valueClass]]);
            }
        } else {
            ODOAttribute *attr = (ODOAttribute *)property;
            OBASSERT(!value || [value isKindOfClass:[attr valueClass]]);
        }
    }
    
    return YES;
}
#endif

- (BOOL)_isAwakingFromInsert;
{
    return _flags.isAwakingFromInsert;
}

- (void)_setIsAwakingFromInsert:(BOOL)isAwakingFromInsert;
{
    _flags.isAwakingFromInsert = isAwakingFromInsert;
}

- (void)_setIsAwakingFromReinsertionAfterUndoneDeletion:(BOOL)isAwakingFromReinsertionAfterUndoneDeletion;
{
    _flags.isAwakingFromReinsertionAfterUndoneDeletion = isAwakingFromReinsertionAfterUndoneDeletion;
}

- (void)_setIsFault:(BOOL)isFault;
{
    _flags.isFault = isFault;
}

- (void)_turnIntoFault:(BOOL)deleting;
{
    OBPRECONDITION([_editingContext objectRegisteredForID:_objectID] == self);
    OBPRECONDITION(!_flags.isFault);
    OBPRECONDITION(!_flags.invalid);
    
    if (_flags.isFault) {
        // check at runtime anyway
        return;
    }
    
    OBASSERT(_ODOObjectHasValues(self));
    [self willTurnIntoFault];
    
    _ODOObjectReleaseValues(self);

    _flags.isFault = YES;
    
    [self didTurnIntoFault];
}

- (void)_invalidate;
{
    // First, become a fault
    if (!_flags.isFault) {
        [self _turnIntoFault:NO/*deleting*/];
    }
    
    // Cleared in _turnIntoFault: and we have no way of ever becoming valid again.
    _ODOObjectReleaseValuesIfPresent(self);
    
    // Once we are invalid, we are no longer a fault (we can't be resurrected/fetched)
    _flags.invalid = YES;
    _flags.isFault = NO;
    
    [_editingContext release];
    _editingContext = nil;
    
    // We leave _objectID; notification observers need to be able to get the entity/pk of deleted objects.
}

- (BOOL)_isCalculatingValueForKey:(NSString *)key;
{
    return [_keysForPropertiesBeingCalculated containsObject:key];
}

- (void)_setIsCalculatingValueForKey:(NSString *)key;
{
    if (_keysForPropertiesBeingCalculated == nil) {
        _keysForPropertiesBeingCalculated = [[NSMutableSet alloc] init];
        [_keysForPropertiesBeingCalculated addObject:key];
    }
}

- (void)_clearIsCalculatingValueForKey:(NSString *)key;
{
    [_keysForPropertiesBeingCalculated removeObject:key];
    if (_keysForPropertiesBeingCalculated.count == 0) {
        [_keysForPropertiesBeingCalculated release];
        _keysForPropertiesBeingCalculated = nil;
    }
}

NSArray *_ODOObjectCreatePropertySnapshot(ODOObject *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(self->_editingContext);
    OBPRECONDITION(!self->_flags.invalid);
    OBPRECONDITION(!self->_flags.isFault);
    
    // Can't just copy the array.  In particular, keeping any mutable sets for to-many relationships would be wasted space and any to-one relationships are to actual ODOObjects.  But, these objects might be deleted, so if we use the snapshot to re-insert, we need to use the objectID, not the object itself.  In fact, what we *really* want is just the primary key of the to-one destination.  This is how we represent lazy to-one faults and thus it means that we can just fill in the object with the foreign key without doing any two-phase remapping of pk to object.

    ODOEntity *entity = [self->_objectID entity];
    NSArray *snapshotProperties = [entity snapshotProperties];
    NSUInteger propIndex, propCount = [snapshotProperties count];
    
    // We do store the full array for snapshots, one slot per snapshot property, even though we don't really need the slots for to-manys.  One optimization would be to pack/unpack them as needed.
    CFMutableArrayRef snapshot = CFArrayCreateMutable(kCFAllocatorDefault, propCount, &OFNSObjectArrayCallbacks);
    Class instanceClass = [self class];

    for (propIndex = 0; propIndex < propCount; propIndex++) {
        ODOProperty *prop = [snapshotProperties objectAtIndex:propIndex];
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        
        id value = _ODOObjectValueAtIndex(self, propIndex);
        
        if (flags.relationship) {
            if (flags.toMany) {
                // Don't care what the current value is, but we need to insert a placeholder.  We use the lazy to-many fault representation so that any insertion based on the snapshot will start out with a fault.
                value = ODO_OBJECT_LAZY_TO_MANY_FAULT_MARKER;
            } else {
                // We want the primary key if the relationship has already been faulted.
                if ([value isKindOfClass:[ODOObject class]])
                    value = [[(ODOObject *)value objectID] primaryKey];
            }
        }

        // Classes can opt out of including transient calcuated properties in snapshots.
        // This is necessary in the case that the transient calculated property is holding pointers to ODOObject instances.
        if (flags.calculated && flags.transient && ![instanceClass shouldIncludeSnapshotForTransientCalculatedProperty:prop]) {
            value = nil;
        }

        CFArrayAppendValue(snapshot, value);
    }
    
    OBASSERT(CFArrayGetCount(snapshot) == (CFIndex)propCount);
    OBASSERT(_ODOAssertSnapshotIsValidForObject(self, snapshot));

    return (NSArray *)snapshot;
}

#ifdef OMNI_ASSERTIONS_ON

typedef struct {
    ODOObject *owner;
    ODORelationship *toOne;
} ValidateRelationshipDestination;

static void _validateRelationshipDestination(const void *value, void *context)
{
    ValidateRelationshipDestination *ctx = context;

    // If owner is pointing at a lazy to-one fault, this will be the destination object's primary key.  There may or may not be a fault registered in this direction in this case.
    if (![(id)value isKindOfClass:[ODOObject class]]) {
        id key = (id)value;
        OBASSERT(key);
        OBASSERT([key isKindOfClass:[[[ctx->toOne destinationEntity] primaryKeyAttribute] valueClass]]);
        return;
    }
    
    ODOObject *dest = (ODOObject *)value;

    // Destination should be registered in our editing context
    OBASSERT([dest editingContext] == [ctx->owner editingContext]);
    OBASSERT([[dest editingContext] objectRegisteredForID:[dest objectID]] == dest);
    
    // Should not be deleted, or delete propagation should have at least nullified it.
    OBASSERT(![dest isDeleted]);
                                         
    // This destination object might still be a fault.  In that case, it has no reference back to the owner will be around.
    if ([dest isFault]) {
        return;
    }
    
    // Can't call -primitiveValueForKey: since that would cause lazy fault creation to fire.
    OBASSERT([[[dest entity] snapshotProperties] containsObject:ctx->toOne]);
    struct _ODOPropertyFlags flags = ODOPropertyFlags(ctx->toOne);
    id relationshipValue = _ODOObjectValueAtIndex(dest, flags.snapshotIndex);

    // If this is a lazy to-one fault, it will be the primary key of the owner instead of a pointer to the owner
    if ([relationshipValue isKindOfClass:[ODOObject class]]) {
        OBASSERT(relationshipValue == ctx->owner);
    } else {
        OBASSERT([relationshipValue isEqual:[[ctx->owner objectID] primaryKey]]);
    }
}

- (BOOL)_odo_checkInvariants;
{
    OBASSERT(_objectID); // We don't clear this on invalidation; notification observers need to be able to get the entity/pk of deleted objects.
    
    // These flags shouldn't be left on except inside private API
    OBASSERT(_flags.needsAwakeFromFetch == NO);
    OBASSERT(_flags.changeProcessingDisabled == NO);
    
    if (_flags.invalid) {
        OBASSERT(_editingContext == nil);
        OBASSERT(_flags.isFault == NO); // Can't be fetched, so not a fault
        OBASSERT(_ODOObjectHasValues(self) == NO);
    } else {
        OBASSERT(_editingContext);
        OBASSERT([_editingContext objectRegisteredForID:_objectID] == self);
        
        // Objects can be in only one state and faults can't be edited at all.
        BOOL inserted = [self isInserted];
        BOOL updated = [self isUpdated];
        BOOL deleted = [self isDeleted];
        BOOL fault = [self isFault];

        NSArray *snapshotProperties = [[self entity] snapshotProperties];
        NSUInteger propertyIndex = [snapshotProperties count];
        
        if (fault) {
            OBASSERT(!inserted);
            OBASSERT(!updated);
            OBASSERT(_ODOObjectHasValues(self) == NO); // No point in holding values.
        } else {
            OBASSERT(_ODOObjectHasValues(self) == YES); // Real objects have values!
            OBASSERT(deleted == NO); // deleted objects are turned into faults first
            
            NSUInteger mods = 0;
            if (inserted) {
                mods++;
            }

            if (updated) {
                mods++;
            }

            if (deleted) {
                mods++;
            }
            
            OBASSERT(mods <= 1);
            
            // All our values should be reasonable
            while (propertyIndex--) {
                ODOProperty *prop = [snapshotProperties objectAtIndex:propertyIndex];
                struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
                id value = _ODOObjectValueAtIndex(self, propertyIndex);

                if (flags.relationship) {
                    if (flags.toMany) {
                        if (!ODOObjectValueIsLazyToManyFault(value)) {
                            // All the values in the set should be registered objects.  Moreover, they shouldn't be deleted and their inverse should point back at us.
                            ValidateRelationshipDestination ctx = {
                                .owner = self,
                                .toOne = [(ODORelationship *)prop inverseRelationship],
                            };
                            OBASSERT([ctx.toOne isToMany] == NO); // No many-to-many relationships
                            CFSetApplyFunction((CFSetRef)value, _validateRelationshipDestination, &ctx);
                        }
                    } else {
                        // Verify our relationship to the destination.  This is goofy since our callback is goofy.  If the value is a lazy fault, it won't be a ODOObject
                        if ([value isKindOfClass:[ODOObject class]]) {
                            ValidateRelationshipDestination ctx = {
                                .owner = value,
                                .toOne = (ODORelationship *)prop,
                            };
                            _validateRelationshipDestination(self, &ctx);
                        } else if (value != nil) {
                            // At least do the class check on the lazy fault primary key
                            OBASSERT([value isKindOfClass:[[[(ODORelationship *)prop destinationEntity] primaryKeyAttribute] valueClass]]);
                        }
                    }
                } else {
                    OBASSERT(value == nil || [value isKindOfClass:[(ODOAttribute *)prop valueClass]]); // OK to temporarily violate the nullity, but not the type
                }
            }
        }
    }
    return YES;
}

#endif

void ODOObjectClearValues(ODOObject *self, BOOL deleting)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(!self->_flags.isFault);
    OBPRECONDITION(!self->_flags.invalid);
    OBPRECONDITION(self->_editingContext);
    OBPRECONDITION(self->_objectID);
    OBPRECONDITION(deleting || ![self isInserted]);
    OBPRECONDITION(deleting || ![self isUpdated]);
    // allow deleted objects -- we clear values from objects as soon as they are snapshoted prior to being put in the deleted set.

    if (_ODOObjectHasValues(self))
        _ODOObjectSetValuesToNull(self);
}

// -awakeFromFetch support functions.  When awaking objects, we need to first prepare them, awake them and finally finalize the awake.  The awake function is *also* called in -valueForKey: if _flags.needsAwakeFromFetch is still set.  If a bunch of objects are fetched at the same time (say, all the assignable contexts in OmniFocus) and awoken, one object might try to reference another when it awakes (say, children trying to compute their transient rank path or hierarchical name properties).
void ODOObjectPrepareForAwakeFromFetch(ODOObject *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(self->_flags.changeProcessingDisabled == NO);
    OBPRECONDITION(self->_flags.needsAwakeFromFetch == NO);
    OBPRECONDITION(self->_flags.isFault == NO);
    
    self->_flags.changeProcessingDisabled = YES;
    self->_flags.needsAwakeFromFetch = YES;
}

void ODOObjectPerformAwakeFromFetchWithoutRegisteringEdits(ODOObject *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(self->_flags.changeProcessingDisabled == YES);

    // Allow edits w/o marking the object as edited or making a committed property snapshot, at least to base properties (editing relationships might be a terrible idea ... not sure).
    // This should really only set non-persistent properties (transient properties & local ivar caches of some sort).  So, when this flag is set, -setValue:forKey: will assert if any modeled property is poked.

    if (self->_flags.needsAwakeFromFetch == NO) {
        // Some access from *another* awaking object caused this one to wake up already
        return;
    }
    
    self->_flags.needsAwakeFromFetch = NO;

    OBASSERT(!self->_flags.isAwakingFromFetch);
    self->_flags.isAwakingFromFetch = YES;
    @try {
        // Could possibly raise
        [self awakeFromFetch];
    } @finally {
        self->_flags.isAwakingFromFetch = NO;
    }
}

void ODOObjectFinalizeAwakeFromFetch(ODOObject *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(self->_flags.needsAwakeFromFetch == NO);
    OBPRECONDITION(self->_flags.changeProcessingDisabled == YES);
    
    self->_flags.changeProcessingDisabled = NO;
    
    [self didAwakeFromFetch];
}

void ODOObjectAwakeSingleObjectFromFetch(ODOObject *object)
{
    ODOObjectPrepareForAwakeFromFetch(object);
    ODOObjectPerformAwakeFromFetchWithoutRegisteringEdits(object);
    ODOObjectFinalizeAwakeFromFetch(object);
}

void ODOObjectAwakeObjectsFromFetch(NSArray *objects)
{
    NSUInteger fetchedObjectIndex, fetchedObjectCount = [objects count];
    
    // Let all the objects know that they still need awaking.
    for (fetchedObjectIndex = 0; fetchedObjectIndex < fetchedObjectCount; fetchedObjectIndex++) {
        ODOObjectPrepareForAwakeFromFetch([objects objectAtIndex:fetchedObjectIndex]);
    }
    
    // TODO: If we get an exception here, we could leave an object fetched w/o having ever gotten -awakeFromFetch.
    // Wake up each objects.  Some objects might wake peers.
    for (fetchedObjectIndex = 0; fetchedObjectIndex < fetchedObjectCount; fetchedObjectIndex++) {
        ODOObjectPerformAwakeFromFetchWithoutRegisteringEdits([objects objectAtIndex:fetchedObjectIndex]);
    }
    
    // Finally, let them all know they are done.
    for (fetchedObjectIndex = 0; fetchedObjectIndex < fetchedObjectCount; fetchedObjectIndex++) {
        ODOObjectFinalizeAwakeFromFetch([objects objectAtIndex:fetchedObjectIndex]);
    }
}

BOOL ODOObjectToManyRelationshipIsFault(ODOObject *self, ODORelationship *rel)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION([rel isKindOfClass:[ODORelationship class]]);
    OBPRECONDITION([rel entity] == [self entity]);
    OBPRECONDITION([rel isToMany]);
    
    NSUInteger offset = ODOPropertySnapshotIndex(rel);
    id value = _ODOObjectValueAtIndex(self, offset);
    return ODOObjectValueIsLazyToManyFault(value);
}

NSMutableSet * _Nullable ODOObjectToManyRelationshipIfNotFault(ODOObject *self, ODORelationship *rel)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION([rel isKindOfClass:[ODORelationship class]]);
    OBPRECONDITION([rel entity] == [self entity]);
    OBPRECONDITION([rel isToMany]);
    
    if (self->_flags.isFault) {
        return nil;
    }
    
    NSUInteger offset = ODOPropertySnapshotIndex(rel);
    NSMutableSet *set = _ODOObjectValueAtIndex(self, offset);

    if (ODOObjectValueIsLazyToManyFault(set)) {
        return nil;
    }
    
    return set;
}

void ODOObjectSetChangeProcessingEnabled(ODOObject *self, BOOL enabled)
{
    BOOL disabled = !enabled;
    
    OBASSERT(self->_flags.changeProcessingDisabled ^ disabled); // should only ever be toggled
    self->_flags.changeProcessingDisabled = disabled;
}

BOOL ODOObjectChangeProcessingEnabled(ODOObject *self)
{
    return !self->_flags.changeProcessingDisabled;
}

// Used in ODOEditingContext udno support.  We expect that typically only a few properties will change on each update and that undo will be relatively rare compared to 'do'ing stuff.  So, we'll try to pack this down smaller than just passing along the old snapshots.  Instead, for each update we'll build an array of <editedObjectID, prop0, oldValue0, ..., propN, oldValueN>.  We will not record differences for to-many relationships.  Those are implicit in the inverse to-one relationships.  When recording the to-one properties, we'll record only the foreign key value.  We might want to record the objectID at some point, but on undo, setting the slot to the foreign key makes it into a lazy to-one fault.
// Later optimization might include building one big array for all the updates with some marker inbetween to delimit change sets.  Probably not worth it.
_Nullable CFArrayRef ODOObjectCreateDifferenceRecordFromSnapshot(ODOObject *self, CFArrayRef snapshot)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(self->_objectID);
    OBPRECONDITION(_ODOObjectHasValues(self));
    
    OBPRECONDITION(snapshot);
    
    // Can have nils embedded, use CFArray.
    CFMutableArrayRef changeSet = CFArrayCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectArrayCallbacks);
    CFArrayAppendValue(changeSet, self->_objectID);
    
    ODOEntity *entity = [self->_objectID entity];
    NSArray *snapshotProperties = [entity snapshotProperties];
    OBASSERT(CFArrayGetCount(snapshot) == (CFIndex)[snapshotProperties count]);
    
    NSUInteger propertyIndex, propertyCount = [snapshotProperties count];
    for (propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++) {
        ODOProperty *prop = [snapshotProperties objectAtIndex:propertyIndex];
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        
        if (flags.relationship && flags.toMany) {
            continue;
        }
        
        id oldValue = (id)CFArrayGetValueAtIndex(snapshot, propertyIndex);
        id newValue = _ODOObjectValueAtIndex(self, propertyIndex);

        if (flags.relationship) {
            OBASSERT(flags.toMany == NO); // checked above
            
            // Map old/new values to their foreign keys.  This will avoid spurious diffs due to lazy to-one fault creation and we aim to store only the foreign key anyway.
            if ([oldValue isKindOfClass:[ODOObject class]])
                oldValue = [[oldValue objectID] primaryKey];
            if ([newValue isKindOfClass:[ODOObject class]])
                newValue = [[newValue objectID] primaryKey];
        }
        
        if (OFNOTEQUAL(oldValue, newValue)) {
            // encode nil as NSNull so that we can 'po' these.  Foundation blows up otherwise.
            if (oldValue == nil) {
                oldValue = [NSNull null];
            }
            
            CFArrayAppendValue(changeSet, [prop name]);
            CFArrayAppendValue(changeSet, oldValue);
        }
    }
    
    // If we had no actual local changes to return, return NULL.  Presumably some object across a to-many was inserted/deleted or changed its to-one back to us.
    CFArrayRef result;
    if (CFArrayGetCount(changeSet) == 1) {
        result = NULL;
    } else {
        // Flatten into an immutable array for smaller storage
        result = CFArrayCreateCopy(kCFAllocatorDefault, changeSet);
    }
    CFRelease(changeSet);
    
    OBPOSTCONDITION(!result || CFArrayGetCount(result) > 1); // should have the object id + at least one key/value pair
    OBPOSTCONDITION(!result || (CFArrayGetCount(result) % 2) == 1); // should be an even number of kv pairs plus one object ID
    return result;
}

void ODOObjectApplyDifferenceRecord(ODOObject *self, CFArrayRef diff)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    OBPRECONDITION(diff);
    OBPRECONDITION(CFGetTypeID(diff) == CFArrayGetTypeID());
    OBPRECONDITION(CFArrayGetCount(diff) > 1); // should have the object id + at least one key/value pair
    OBPRECONDITION((CFArrayGetCount(diff) % 2) == 1); // should be an even number of kv pairs plus one object ID
    OBPRECONDITION([self->_objectID isEqual:(id)CFArrayGetValueAtIndex(diff, 0)]);
    
    NSUInteger diffIndex, diffCount = CFArrayGetCount(diff);
    for (diffIndex = 1; diffIndex < diffCount; diffIndex += 2) {
        NSString *key = (NSString *)CFArrayGetValueAtIndex(diff, diffIndex+0);
        id value = (id)CFArrayGetValueAtIndex(diff, diffIndex+1);
        if (OFISNULL(value)) {
            // undo mapping from above
            value = nil;
        }
        
        ODOProperty *prop = [[self->_objectID entity] propertyNamed:key];
        OBASSERT(prop);
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        OBASSERT(!flags.relationship || !flags.toMany); // Only recording diffs for attributes and foreign keys for to-one relationships
        
        // We have to undo the mapping of object->primary key here so that we can use -setPrimitiveValue:forKey:.
        if (flags.relationship && !flags.toMany) {
            ODORelationship *rel = (ODORelationship *)prop;
            OBASSERT(value == nil || [value isKindOfClass:[[[rel destinationEntity] primaryKeyAttribute] valueClass]]);
            
            if (value != nil) {
                ODOObjectID *objectID = [[ODOObjectID alloc] initWithEntity:[rel destinationEntity] primaryKey:value];
                ODOObject *object = ODOEditingContextLookupObjectOrRegisterFaultForObjectID(self->_editingContext, objectID);
                [objectID release];
                value = object;
            }
        }
        
        // Set the value without going through the public KVC path.  That is, don't call -setFoo: since it was called to *do* this change in the first place.
        // Unlike CoreData, though, using the primitive setter here will not only make sure we end up in the recently updated objects, but will also make sure that inverse relationships are updated.
        // TODO: One-to-one relationships?  Maybe we should _not_ update the inverse here, but maybe it will be OK and the double-update will be OK.
        // Note that we do not currently undo the mapping of object->primary key.  We'll leave the fault to be lazily resolved again.
        [self willChangeValueForKey:key];
        ODOObjectSetPrimitiveValueForProperty(self, value, prop);
        [self didChangeValueForKey:key];
    }
}

@end

#pragma mark -

static inline void _ODOObjectAwakeSingleObjectFromUnarchive(ODOObject *self, SEL sel, id _Nullable arg, BOOL sendWithArg)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    
    if ([self isDeleted] || [self isInvalid]) {
        return;
    }
    
    OBASSERT(!self->_flags.isAwakingFromUnarchive);
    self->_flags.isAwakingFromUnarchive = YES;
    
    // Could possibly raise
    @try {
        if (sendWithArg) {
            OBSendVoidMessageWithObject(self, sel, arg);
        } else {
            OBSendVoidMessage(self, sel);
        }
    } @finally {
        self->_flags.isAwakingFromUnarchive = NO;
    }
}

void ODOObjectAwakeSingleObjectFromUnarchive(ODOObject *object)
{
    _ODOObjectAwakeSingleObjectFromUnarchive(object, @selector(awakeFromUnarchive), nil, NO);
}

void ODOObjectAwakeSingleObjectFromUnarchiveWithMessage(ODOObject *object, SEL sel, id arg)
{
    _ODOObjectAwakeSingleObjectFromUnarchive(object, sel, arg, YES);
}

void ODOObjectAwakeObjectsFromUnarchive(id <NSFastEnumeration> objects)
{
    for (ODOObject *object in objects) @autoreleasepool {
        OBPRECONDITION([object isKindOfClass:[ODOObject class]]);
        _ODOObjectAwakeSingleObjectFromUnarchive(object, @selector(awakeFromUnarchive), nil, NO);
    }
}

void ODOObjectAwakeObjectsFromUnarchiveWithMessage(id <NSFastEnumeration> objects, SEL sel, id arg)
{
    for (ODOObject *object in objects) @autoreleasepool {
        OBPRECONDITION([object isKindOfClass:[ODOObject class]]);
        _ODOObjectAwakeSingleObjectFromUnarchive(object, sel, arg, YES);
    }
}

NS_ASSUME_NONNULL_END
