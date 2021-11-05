// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOObject-Accessors.h"

#import <OmniDataObjects/ODOEntity.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODOModel.h>

#import "ODOAttribute-Internal.h"
#import "ODOObject-Internal.h"
#import "ODOProperty-Internal.h"
#import "ODOEditingContext-Internal.h"
#import "ODOInternal.h"

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface _ODOObject_Accessors : NSObject

@property (nonatomic, copy) NSObject *_object_property;

@property (nonatomic) BOOL _bool_property;
@property (nonatomic) int16_t _int16_property;
@property (nonatomic) int32_t _int32_property;
@property (nonatomic) int64_t _int64_property;
@property (nonatomic) float _float32_property;
@property (nonatomic) double _float64_property;

@end

#pragma mark -

// Used for getting type signatures
@implementation _ODOObject_Accessors

@dynamic _object_property;
@dynamic _int16_property;
@dynamic _int32_property;
@dynamic _int64_property;
@dynamic _float32_property;
@dynamic _float64_property;

- (nullable id)_object_getter_signature;
{
    OBASSERT_NOT_REACHED("Unused getter.");
    return nil;
}

- (void)_object_setter_signature:(nullable id)arg;
{
    OBASSERT_NOT_REACHED("Unused setter.");
}

- (BOOL)_bool_getter_signature;
{
    OBASSERT_NOT_REACHED("Unused getter.");
    return NO;
}

- (void)_bool_setter_signature:(BOOL)arg;
{
    OBASSERT_NOT_REACHED("Unused setter.");
}

- (int16_t)_int16_getter_signature;
{
    OBASSERT_NOT_REACHED("Unused getter.");
    return 0;
}

- (void)_int16_setter_signature:(int16_t)arg;
{
    OBASSERT_NOT_REACHED("Unused setter.");
}

- (int32_t)_int32_getter_signature;
{
    OBASSERT_NOT_REACHED("Unused getter.");
    return 0;
}

- (void)_int32_setter_signature:(int32_t)arg;
{
    OBASSERT_NOT_REACHED("Unused setter.");
}

- (int64_t)_int64_getter_signature;
{
    OBASSERT_NOT_REACHED("Unused getter.");
    return 0;
}

- (void)_int64_setter_signature:(int64_t)arg;
{
    OBASSERT_NOT_REACHED("Unused setter.");
}

- (float)_float32_getter_signature;
{
    OBASSERT_NOT_REACHED("Unused getter.");
    return 0;
}

- (void)_float32_setter_signature:(float)arg;
{
    OBASSERT_NOT_REACHED("Unused setter.");
}

- (double)_float64_getter_signature;
{
    OBASSERT_NOT_REACHED("Unused getter.");
    return 0;
}

- (void)_float64_setter_signature:(double)arg;
{
    OBASSERT_NOT_REACHED("Unused setter.");
}

@end

#pragma mark -

// Pass a key of nil if you don't know or care what the key is and just want to clear the fault.  Right now we short circuit on the primary key attribute name.
static inline void __inline_ODOObjectWillAccessValueForKey(ODOObject *self, NSString * _Nullable key)
{
    if (self->_flags.hasFinishedDeletion) {
        return;
    }
    
    if (!self->_flags.invalid && self->_flags.isFault) {
        // Don't clear faults for the primary key
        if (![key isEqualToString:[[[self->_objectID entity] primaryKeyAttribute] name]]) {
            ODOFetchObjectFault(self->_editingContext, self);
        }
    }
    
    // We might be part of a fetch result set that is still getting awoken.  If another object awaking tries to talk to us before we are awake, wake up early.  Note that circular awaking problems are still possible.
    if (self->_flags.needsAwakeFromFetch) {
        ODOObjectPerformAwakeFromFetchWithoutRegisteringEdits(self);
    }
}

void ODOObjectWillAccessValueForKey(ODOObject *self, NSString * _Nullable key)
{
    __inline_ODOObjectWillAccessValueForKey(self, key);
}

// Can pass a relationship if you already know it, or nil if you don't.
static ODORelationship *_ODOLookupRelationshipBySnapshotIndex(ODOObject *self, NSUInteger snapshotIndex, BOOL toMany, ODORelationship * _Nullable rel)
{
    OBPRECONDITION(rel == nil || [rel isKindOfClass:[ODORelationship class]]);
    OBPRECONDITION(rel == nil || rel->_storageKey.snapshotIndex == snapshotIndex);
    
    if (rel == nil) {
        // Caller needs us to look it up; not sure if this will be rare or not.
        rel = (ODORelationship *)[[self->_objectID entity] propertyWithSnapshotIndex:snapshotIndex];
        OBASSERT(rel->_storageKey.type == ODOStorageTypeObject);
        OBASSERT([rel isKindOfClass:[ODORelationship class]]);
        OBASSERT([rel isToMany] == toMany);
    }
    
    OBPOSTCONDITION([rel isKindOfClass:[ODORelationship class]]);
    OBPOSTCONDITION(rel->_storageKey.snapshotIndex == snapshotIndex);
    return rel;
}

// Can pass a relationship if you already know it, or nil if you don't.
static inline id _ODOObjectCheckForLazyToOneFaultCreation(ODOObject *self, id value, NSUInteger snapshotIndex, ODORelationship * _Nullable rel)
{
    OBPRECONDITION(rel == nil || [rel isKindOfClass:[ODORelationship class]]);
    OBASSERT(rel == nil || [rel isToMany] == NO);
    
    if ([value _isODOObject]) {
#ifdef OMNI_ASSERTIONS_ON
        rel = _ODOLookupRelationshipBySnapshotIndex(self, snapshotIndex, NO/*toMany*/, rel);
        OBASSERT([value isKindOfClass:[[rel destinationEntity] instanceClass]]);
#endif
        // All good
    } else if (value != nil) {
        rel = _ODOLookupRelationshipBySnapshotIndex(self, snapshotIndex, NO/*toMany*/, rel);
        OBASSERT([value isKindOfClass:[[[rel destinationEntity] primaryKeyAttribute] valueClass]]);
        
        // Lazily find or create a to-one fault based on the primary key stored in our snapshot.
        ODOEntity *destEntity = [rel destinationEntity];
        
        ODOObjectID *destID = [[ODOObjectID alloc] initWithEntity:destEntity primaryKey:value];
        value = ODOEditingContextLookupObjectOrRegisterFaultForObjectID(self->_editingContext, destID);
        [destID release];
        
        // Replace the pk with the real fault.
        ODOStorageSetObject(self->_objectID.entity, self->_valueStorage, rel->_storageKey, value);
    } else {
        // to-one to nil; just fine
    }
    return value;
}

static inline id _ODOObjectCheckForLazyToManyFaultCreation(ODOObject *self, id value, NSUInteger snapshotIndex, ODORelationship * _Nullable rel)
{
    if (ODOObjectValueIsLazyToManyFault(value)) {
        // When asking for the to-many relationship the first time, we fetch it.  We assume that the caller is going to do something useful with it, otherwise they shouldn't even ask.  If you want to conditionally avoid faulting, we could add a -isFaultForKey: or some such.
        rel = _ODOLookupRelationshipBySnapshotIndex(self, snapshotIndex, YES/*toMany*/, rel);
        value = ODOFetchSetFault(self->_editingContext, self, rel);
        _ODOObjectSetObjectValueForProperty(self, rel, value);
    }
    return value;
}

// Generic property getter; logic here and in the specific index cases must match up
id ODOObjectPrimitiveValueForProperty(ODOObject *self, ODOProperty *prop)
{
    return ODOObjectPrimitiveValueForPropertyWithOptions(self, prop, ODOObjectPrimitiveValueForPropertyOptionDefault);
}

id ODOObjectPrimitiveValueForPropertyWithOptions(ODOObject *self, ODOProperty *prop, ODOObjectPrimitiveValueForPropertyOptions options)
{
    OBPRECONDITION(prop != nil);
    OBPRECONDITION(!self->_flags.isFault || prop == [[self->_objectID entity] primaryKeyAttribute]);
    
    // Could maybe have extra info in this lookup (attr vs. rel, to-one vs. to-many)?
    ODOStorageKey storageKey = prop->_storageKey;
    if (storageKey.snapshotIndex == ODO_STORAGE_KEY_PRIMARY_KEY_SNAPSHOT_INDEX) {
        return self.objectID.primaryKey;
    }
    
    id value = _ODOObjectGetObjectValueForProperty(self, prop);
    
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    
    if (flags.relationship) {
        ODORelationship *rel = (ODORelationship *)prop;
        if (flags.toMany) {
            // TODO: Use something like __builtin_expect to tell the inline that rel != nil?  This is the slow path, so I'm not sure it matters...
            value = _ODOObjectCheckForLazyToManyFaultCreation(self, value, storageKey.snapshotIndex, rel);
        } else {
            // TODO: Use something like __builtin_expect to tell the inline that rel != nil?  This is the slow path, so I'm not sure it matters...
            value = _ODOObjectCheckForLazyToOneFaultCreation(self, value, storageKey.snapshotIndex, rel);
        }
    } else if (value == nil && flags.transient && flags.calculated && ((options & ODOObjectPrimitiveValueForPropertyOptionAllowCalculationOfLazyTransientValues) != 0)) {
        BOOL isAlreadyCalculatingValue = [self _isCalculatingValueForProperty:prop];
        OBASSERT(!isAlreadyCalculatingValue);
        if (!isAlreadyCalculatingValue) {
            value = [self calculateValueForProperty:prop];
            if (value != nil) {
                if ([value conformsToProtocol:@protocol(NSCopying)]) {
                    value = [[value copy] autorelease];
                }
                
                _ODOObjectSetObjectValueForProperty(self, prop, value);
            }
        }
    }
    
    return value;
}

// Getters for specific cases; logic here must match up with generic getter above.  Unlike the function above, though, these include the will/did access calls (the function above is wrapped in the generic getter).

static id _ODOObjectPrimaryKeyGetter(ODOObject *self, SEL _cmd)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    return [self->_objectID primaryKey];
}

static id _ODOObjectAttributeGetterAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
#ifdef OMNI_ASSERTIONS_ON
    {
        // This can be called for both object-typed properties and optional scalars (where the external interface is a nullable NSNumber).
        ODOProperty *prop = [self->_objectID.entity propertyWithSnapshotIndex:snapshotIndex];
        OBASSERT([prop isKindOfClass:[ODOAttribute class]]);
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        OBASSERT(flags.relationship == NO);

        ODOAttribute *attr = (ODOAttribute *)prop;
        OBASSERT(![attr isPrimaryKey]);
    }
#endif

    ODOEntity *entity = self->_objectID.entity;
    ODOStorageKey storageKey = ODOEntityStorageKeyForSnapshotIndex(entity, snapshotIndex);

    // As noted above, we could be looking up an optional scalar, so call the boxing getter.
    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    return ODOStorageGetObjectValue(entity, self->_valueStorage, storageKey);
}

static BOOL _ODOObjectBoolAttributeGetterAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
    ODOEntity *entity = self->_objectID.entity;
    ODOStorageKey storageKey = ODOEntityStorageKeyForSnapshotIndex(entity, snapshotIndex);

    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    return ODOStorageGetBoolean(entity, self->_valueStorage, storageKey);
}

static int16_t _ODOObjectInt16AttributeGetterAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
    ODOEntity *entity = self->_objectID.entity;
    ODOStorageKey storageKey = ODOEntityStorageKeyForSnapshotIndex(entity, snapshotIndex);

    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    return ODOStorageGetInt16(entity, self->_valueStorage, storageKey);
}

static int32_t _ODOObjectInt32AttributeGetterAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
    ODOEntity *entity = self->_objectID.entity;
    ODOStorageKey storageKey = ODOEntityStorageKeyForSnapshotIndex(entity, snapshotIndex);

    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    return ODOStorageGetInt32(entity, self->_valueStorage, storageKey);
}

static int64_t _ODOObjectInt64AttributeGetterAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
    ODOEntity *entity = self->_objectID.entity;
    ODOStorageKey storageKey = ODOEntityStorageKeyForSnapshotIndex(entity, snapshotIndex);

    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    return ODOStorageGetInt64(entity, self->_valueStorage, storageKey);
}

static float _ODOObjectFloat32AttributeGetterAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
    ODOEntity *entity = self->_objectID.entity;
    ODOStorageKey storageKey = ODOEntityStorageKeyForSnapshotIndex(entity, snapshotIndex);

    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    return ODOStorageGetFloat32(entity, self->_valueStorage, storageKey);
}

static double _ODOObjectFloat64AttributeGetterAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
    ODOEntity *entity = self->_objectID.entity;
    ODOStorageKey storageKey = ODOEntityStorageKeyForSnapshotIndex(entity, snapshotIndex);

    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    return ODOStorageGetFloat64(entity, self->_valueStorage, storageKey);
}

static _Nullable id _ODOObjectToOneRelationshipGetterAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
    ODOEntity *entity = self->_objectID.entity;
    ODOStorageKey storageKey = ODOEntityStorageKeyForSnapshotIndex(entity, snapshotIndex);

#ifdef OMNI_ASSERTIONS_ON
    {
        ODOProperty *prop = [entity propertyWithSnapshotIndex:snapshotIndex];
        OBASSERT(prop->_storageKey.type == ODOStorageTypeObject);
        OBASSERT([prop isKindOfClass:[ODORelationship class]]);
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        OBASSERT(flags.relationship == YES);
        OBASSERT(flags.toMany == NO);
    }
#endif

    if (self->_flags.invalid) {
        OBASSERT_NOT_REACHED("Shouldn't call accessors on invalidated objects");
        return nil;
    }

    // Deleted objects clear all their to-one relationships to ensure that KVO unsubscription is accurate across multi-step keyPaths. Deleted objects also keep their storage buffer and should have a nil in the to-one relationship slots.

    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    id result = _ODOObjectCheckForLazyToOneFaultCreation(self, ODOStorageGetObject(entity, self->_valueStorage, storageKey), snapshotIndex, nil/*relationship == we has it not!*/);

    OBASSERT_IF(self->_flags.hasFinishedDeletion, result == nil);
    
    return result;
}

static id _ODOObjectToManyRelationshipGetterAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
    ODOEntity *entity = self->_objectID.entity;
    ODOStorageKey storageKey = ODOEntityStorageKeyForSnapshotIndex(entity, snapshotIndex);

#ifdef OMNI_ASSERTIONS_ON
    {
        ODOProperty *prop = [entity propertyWithSnapshotIndex:snapshotIndex];
        OBASSERT(prop->_storageKey.type == ODOStorageTypeObject);
        OBASSERT([prop isKindOfClass:[ODORelationship class]]);
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        OBASSERT(flags.relationship == YES);
        OBASSERT(flags.toMany == YES);
    }
#endif
    
    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    return _ODOObjectCheckForLazyToManyFaultCreation(self, ODOStorageGetObject(entity, self->_valueStorage, storageKey), snapshotIndex, nil/*relationship == we has it not!*/);
}

// Generic property setter; for now we aren't doing specific-index setters (we are already a little faster than CoreData here, but we could still add them if it ends up showing up on a profile).
void ODOObjectSetPrimitiveValueForProperty(ODOObject *self, _Nullable id value, ODOProperty *prop)
{
    OBPRECONDITION(prop);
    // OBPRECONDITION(!_flags.isFault); Being a fault is allowed here since this is how faults will get set up.
    
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    
    ODOStorageKey storageKey = prop->_storageKey;
    if (storageKey.snapshotIndex == ODO_STORAGE_KEY_PRIMARY_KEY_SNAPSHOT_INDEX) {
        OBASSERT_NOT_REACHED("Ignoring attempt to set the primary key");
        return;
    }

    // We allow property changes after deletion starts (for nullifying relationships), but not after it is finished.
    if (self->_flags.hasFinishedDeletion) {
        OBASSERT_NOT_REACHED("Ignoring attempt to set a property on a deleted object");
        return;
    }

#ifdef OMNI_ASSERTIONS_ON
    {
        // The value should match the property.  We allow nil here, even if th property doesn't (that should only be enforced when saving).
        if (value) {
            if (!flags.relationship)
                OBASSERT([value isKindOfClass:[(ODOAttribute *)prop valueClass]]);
            else {
                OBASSERT([prop isKindOfClass:[ODORelationship class]]);
                ODORelationship *rel = (ODORelationship *)prop;
                
                if (flags.toMany) {
                    // We allow mutable sets consisting of instances of the destination entity's instance class.
                    OBASSERT([value isKindOfClass:[NSMutableSet class]]); // Not sure the mutable will take effect...
                    NSEnumerator *destEnum = [value objectEnumerator];
                    ODOObject *dest;
                    while ((dest = [destEnum nextObject]))
                        OBASSERT([dest isKindOfClass:[[rel destinationEntity] instanceClass]]);
                } else {
                    // Destination object shouldn't be invalidated
                    if (value) {
                        if ([value isKindOfClass:[ODOObject class]])
                            OBASSERT(![value isInvalid]);
                    }
                    
                    // For now, see if we can require ODOObjects, not primary keys.  Otherwise, we can't easily compare the new and old values (and we need the old value to be the the realized object for updating the inverse).
                    OBASSERT(!value || [value isKindOfClass:[[rel destinationEntity] instanceClass]]);
#if 0
                    // We allow either instances of the destination entity or its primary key attribute (primitive value is the foreign key before the fault is created).
                    if ([value isKindOfClass:[ODOObject class]])
                        OBASSERT([value isKindOfClass:[[rel destinationEntity] instanceClass]]);
                    else
                        OBASSERT([value isKindOfClass:[[[rel destinationEntity] primaryKeyAttribute] valueClass]]);
#endif
                }
            }
        }
    }
#endif
    
    ODOObjectPrimitiveValueForPropertyOptions options = ODOObjectPrimitiveValueForPropertyOptionDefault & ~(ODOObjectPrimitiveValueForPropertyOptionAllowCalculationOfLazyTransientValues);
    
    id newValue = value;
    id oldValue = ODOObjectPrimitiveValueForPropertyWithOptions(self, prop, options); // It is important to use this so that we'll get lazy to-one faults created
    if (oldValue == value)
        return;
    
    if (!self->_flags.changeProcessingDisabled) { // Might be fetching an object and setting up initial values, for example
        // TODO: If we tweak inverses here, then it seems like we should tweak inverses in the to-many setter.
        
        // If we set a to-one relationship, the inverse must be updated (possibly another to-one or possibly a to-many)
        if (flags.relationship && !flags.toMany) {
            ODORelationship *rel = (ODORelationship *)prop;
            ODORelationship *inverse = [rel inverseRelationship];
            NSString *inverseKey = [inverse name];
            
            struct _ODOPropertyFlags inverseFlags = ODOPropertyFlags(inverse);
            OBASSERT(inverseFlags.relationship);
            
            if (inverseFlags.toMany) {
                NSSet *change = [NSSet setWithObject:self];
                
                if (oldValue) {
                    NSMutableSet *inverseSet = ODOObjectToManyRelationshipIfNotFault(oldValue, inverse);
                    OBASSERT(!inverseSet || [inverseSet member:self]);
                    
                    // Remove from the old set.  Have to send KVO even if we've not created the to-many relationship set.  Also, this will possibly put the to-many holder in the updated objects so that it'll get a -willUpdate (if it isn't inserted).
                    // Actually any chance of being deallocated here?
                    [[self retain] autorelease];
                    
                    [oldValue willChangeValueForKey:inverseKey withSetMutation:NSKeyValueMinusSetMutation usingObjects:change];
                    [inverseSet removeObject:self];
                    [oldValue didChangeValueForKey:inverseKey withSetMutation:NSKeyValueMinusSetMutation usingObjects:change];
                }
                
                if (newValue) {
                    NSMutableSet *inverseSet = ODOObjectToManyRelationshipIfNotFault(newValue, inverse);
                    OBASSERT(![inverseSet member:self]);

                    if (inverseSet == _ODOEmptyToManySet) {
                        // Promote to a real mutable set now that we are adding something.
                        inverseSet = [[NSMutableSet alloc] init];
                        _ODOObjectSetObjectValueForProperty(newValue, inverse, inverseSet);
                        [inverseSet release];
                    }

                    // Add to the new set.  Have to send KVO even if we've not created the to-many relationship set.  Also, this will possibly put the to-many holder in the updated objects so that it'll get a -willUpdate (if it isn't inserted).
                    [newValue willChangeValueForKey:inverseKey withSetMutation:NSKeyValueUnionSetMutation usingObjects:change];
                    [inverseSet addObject:self];
                    [newValue didChangeValueForKey:inverseKey withSetMutation:NSKeyValueUnionSetMutation usingObjects:change];
                }
            } else {
                // One-to-one
                // There are up to 4 objects involved here.  If we had A<->B and C<->D and we are wanting A<->D then we need to update B and C too.
                
                if (oldValue) {
                    // Say we are A.  This will clear A->B and since change processing is on for the old value, it will clear B->A.
                    OBASSERT(ODOObjectChangeProcessingEnabled(oldValue));
                    [oldValue willChangeValueForKey:inverseKey];
                    
                    // turn off change processing while setting the internal value so it won't try to set the inverse inverse
                    ODOObjectSetChangeProcessingEnabled(oldValue, NO);
                    @try {
                        ODOObjectSetPrimitiveValueForProperty(oldValue, nil, inverse);
                    } @finally {
                        ODOObjectSetChangeProcessingEnabled(oldValue, YES);
                    }
                    
                    [oldValue didChangeValueForKey:inverseKey];
                }
                
                // Kinda lame; need to set the back pointer w/o having it try to set us.  We *do* want it to get put in the update set.
                if (newValue) {
                    // First *clear* the inverse with change processing on.  This lets it clear the inverse inverse backpointer.  Feh.  This will terminate due to the nil.
                    OBASSERT(ODOObjectChangeProcessingEnabled(newValue));
                    [newValue willChangeValueForKey:inverseKey];
                    ODOObjectSetPrimitiveValueForProperty(newValue, nil, inverse);
                    [newValue didChangeValueForKey:inverseKey];
                    
                    // Then, after the new value has been disassociated correctly, associate it to us.
                    [newValue willChangeValueForKey:inverseKey];
                    ODOObjectSetChangeProcessingEnabled(newValue, NO);
                    @try {
                        ODOObjectSetPrimitiveValueForProperty(newValue, self, inverse);
                    } @finally {
                        ODOObjectSetChangeProcessingEnabled(newValue, YES);
                    }
                    [newValue didChangeValueForKey:inverseKey];
                }
            }
        }
    }
    
    id valueCopy = nil;
    if (!flags.relationship) {
        ODOAttribute *attribute = OB_CHECKED_CAST(ODOAttribute, prop);

        // There are some cases where nils are stored in non-optional fields, and that's OK as long as the object isn't saved.
        OBASSERT_IF(value != nil, [value isKindOfClass:[attribute valueClass]]);

        // Plain date columns should never contain floating dates
        OBASSERT_IF(attribute.type == ODOAttributeTypeDate, [value isKindOfClass:[ODOFloatingDate class]] == NO);

        switch (_ODOAttributeSetterBehavior(attribute)) {
            case ODOAttributeSetterBehaviorCopy: {
                valueCopy = [value copy];
                value = valueCopy;
                break;
            }
                
            case ODOAttributeSetterBehaviorRetain: {
                break;
            }
                
            case ODOAttributeSetterBehaviorDetermineAtRuntime: {
                if ([value conformsToProtocol:@protocol(NSCopying)]) {
                    valueCopy = [value copy];
                    value = valueCopy;
                }
                break;
            }
        }
    }

    _ODOObjectSetObjectValueForProperty(self, prop, value);
    
    [valueCopy release];
}

NS_ASSUME_NONNULL_END

// If you copy the OmniDataObjects source into your project, you'll also need a shell script build phase like the "Generate Accessors" one in the OmniDataObjects framework project. This build phase needs to be ordered before the 'Compile Sources' phase.  If you prefer, you could run the script once (see its source to figure out how) and add the result to your project.  In this case you run the risk of a new version of ODO requiring a new format for this file.
#import "ODOObject-GeneratedAccessors.m"

NS_ASSUME_NONNULL_BEGIN

id ODODynamicValueForProperty(ODOObject *object, ODOProperty *prop)
{
    NSString *key = ODOPropertyName(prop);
    [object willAccessValueForKey:key];
    return ODOObjectPrimitiveValueForProperty(object, prop);
}

void ODODynamicSetValueForProperty(ODOObject *object, SEL _cmd, ODOProperty *prop, id value)
{
    // We don't allow editing to-many relationships from the to-many side.  We don't have many-to-many right now; edit the to-one on the other side.
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    if (flags.relationship  && flags.toMany) {
        OBRejectInvalidCall(object, _cmd, @"Attempted to set %@.%@, but we don't allow setting to-many relationships directly right now.", [object shortDescription], [prop name]);
    }
    
    if (flags.relationship  && !flags.toMany && value != nil) {
        if (![value isKindOfClass:[ODOObject class]]) {
            OBRejectInvalidCall(object, _cmd, @"Attempted to set %@.%@ to something other than an ODOObject or nil.", [object shortDescription], [prop name]);
        }
        
        ODOObject *objectValue = OB_CHECKED_CAST(ODOObject, value);
        ODORelationship *rel = OB_CHECKED_CAST(ODORelationship, prop);
        if (objectValue.entity != rel.destinationEntity) {
            OBRejectInvalidCall(object, _cmd, @"Attempted to set %@.%@ to an ODOObject of the wrong entity type.", [object shortDescription], [prop name]);
        }
    }
    
    ODOObjectWillChangeValueForProperty(object, prop);
    ODOObjectSetPrimitiveValueForProperty(object, value, prop);
    ODOObjectDidChangeValueForProperty(object, prop);
}

id ODOGetScalarValueForProperty(ODOObject *object, ODOProperty *prop)
{
    OBPRECONDITION([prop isKindOfClass:[ODOAttribute class]]);
    if (![prop isKindOfClass:[ODOAttribute class]]) {
        return nil;
    }
    
    ODOAttribute *attr = (ODOAttribute *)prop;
    switch (attr->_type) {
        case ODOAttributeTypeInvalid: {
            OBASSERT_NOT_REACHED("Invalid attribute type.");
            return nil;
        }
            
        case ODOAttributeTypeUndefined:
        case ODOAttributeTypeString:
        case ODOAttributeTypeDate:
        case ODOAttributeTypeXMLDateTime:
        case ODOAttributeTypeData: {
            typedef id (*ObjectGetter)(ODOObject *object, SEL _cmd);
            ObjectGetter getter = (ObjectGetter)attr->_imp.get;
            return getter(object, attr->_sel.get);
        }
            
        case ODOAttributeTypeInt16: {
            typedef int16_t (*Int16Getter)(ODOObject *object, SEL _cmd);
            Int16Getter getter = (Int16Getter)attr->_imp.get;
            int16_t value = getter(object, attr->_sel.get);
            return [NSNumber numberWithShort:value];
        }
            
        case ODOAttributeTypeInt32: {
            typedef int32_t (*Int32Getter)(ODOObject *object, SEL _cmd);
            Int32Getter getter = (Int32Getter)attr->_imp.get;
            int32_t value = getter(object, attr->_sel.get);
            return [NSNumber numberWithInt:value];
        }
            
        case ODOAttributeTypeInt64: {
            typedef int64_t (*Int64Getter)(ODOObject *object, SEL _cmd);
            Int64Getter getter = (Int64Getter)attr->_imp.get;
            int64_t value = getter(object, attr->_sel.get);
            return [NSNumber numberWithLongLong:value];
        }
            
        case ODOAttributeTypeFloat32: {
            typedef float (*Float32Getter)(ODOObject *object, SEL _cmd);
            Float32Getter getter = (Float32Getter)attr->_imp.get;
            float value = getter(object, attr->_sel.get);
            return [NSNumber numberWithFloat:value];
        }
            
        case ODOAttributeTypeFloat64: {
            typedef double (*Float64Getter)(ODOObject *object, SEL _cmd);
            Float64Getter getter = (Float64Getter)attr->_imp.get;
            double value = getter(object, attr->_sel.get);
            return [NSNumber numberWithDouble:value];
        }
            
        case ODOAttributeTypeBoolean: {
            typedef BOOL (*BoolGetter)(ODOObject *object, SEL _cmd);
            BoolGetter getter = (BoolGetter)attr->_imp.get;
            BOOL value = getter(object, attr->_sel.get);
            return [NSNumber numberWithBool:value];
        }
    }
    
    OBASSERT_NOT_REACHED("Unreachable.");
    return nil;
}

void ODOSetScalarValueForProperty(ODOObject *object, ODOProperty *prop, _Nullable id value)
{
    OBPRECONDITION([prop isKindOfClass:[ODOAttribute class]]);
    if (![prop isKindOfClass:[ODOAttribute class]]) {
        return;
    }

    ODOAttribute *attr = (ODOAttribute *)prop;

    switch (attr->_type) {
        case ODOAttributeTypeInvalid: {
            OBASSERT_NOT_REACHED("Invalid attribute type.");
            break;
        }
            
        case ODOAttributeTypeUndefined:
        case ODOAttributeTypeString:
        case ODOAttributeTypeDate:
        case ODOAttributeTypeXMLDateTime:
        case ODOAttributeTypeData: {
            typedef void (*ObjectSetter)(ODOObject *object, SEL _cmd, _Nullable id value);
            ObjectSetter setter = (ObjectSetter)attr->_imp.set;
            setter(object, attr->_sel.set, value);
            break;
        }
            
        case ODOAttributeTypeInt16: {
            typedef void (*Int16Setter)(ODOObject *object, SEL _cmd, int16_t value);
            Int16Setter setter = (Int16Setter)attr->_imp.set;
            NSNumber *number = OB_CHECKED_CAST(NSNumber, value);
            setter(object, attr->_sel.set, [number shortValue]);
            break;
        }
            
        case ODOAttributeTypeInt32: {
            typedef void (*Int32Setter)(ODOObject *object, SEL _cmd, int32_t value);
            Int32Setter setter = (Int32Setter)attr->_imp.set;
            NSNumber *number = OB_CHECKED_CAST(NSNumber, value);
            setter(object, attr->_sel.set, [number intValue]);
            break;
        }
            
        case ODOAttributeTypeInt64: {
            typedef void (*Int64Setter)(ODOObject *object, SEL _cmd, int64_t value);
            Int64Setter setter = (Int64Setter)attr->_imp.set;
            NSNumber *number = OB_CHECKED_CAST(NSNumber, value);
            setter(object, attr->_sel.set, [number longLongValue]);
            break;
        }
            
        case ODOAttributeTypeFloat32: {
            typedef void (*Float32Setter)(ODOObject *object, SEL _cmd, float value);
            Float32Setter setter = (Float32Setter)attr->_imp.set;
            NSNumber *number = OB_CHECKED_CAST(NSNumber, value);
            setter(object, attr->_sel.set, [number floatValue]);
            break;
        }
            
        case ODOAttributeTypeFloat64: {
            typedef void (*Float64Setter)(ODOObject *object, SEL _cmd, double value);
            Float64Setter setter = (Float64Setter)attr->_imp.set;
            NSNumber *number = OB_CHECKED_CAST(NSNumber, value);
            setter(object, attr->_sel.set, [number doubleValue]);
            break;
        }

        case ODOAttributeTypeBoolean: {
            typedef void (*BooleanSetter)(ODOObject *object, SEL _cmd, BOOL value);
            BooleanSetter setter = (BooleanSetter)attr->_imp.set;
            NSNumber *number = OB_CHECKED_CAST(NSNumber, value);
            setter(object, attr->_sel.set, [number boolValue]);
            break;
        }
    }

    return;
}

// These only work for object-valued properties, but that is all we support right now.  We aren't currently verifying that any @dynamic properties _are_ object valued, but we should
id ODOGetterForUnknownOffset(ODOObject *self, SEL _cmd)
{
    ODOProperty *prop = [[self->_objectID entity] propertyWithGetter:_cmd];
    OBASSERT(prop != nil); // should only be installed for actual properties, unlike -valueForKey: which might be called for other keys
    return ODODynamicValueForProperty(self, prop);
}

static BOOL ODOBoolGetterForUnknownOffset(ODOObject *self, SEL _cmd)
{
    ODOProperty *prop = [[self->_objectID entity] propertyWithGetter:_cmd];
    ODOASSERT_ATTRIBUTE_OF_TYPE(prop, ODOAttributeTypeBoolean);
    
    id value = ODODynamicValueForProperty(self, prop);
    OBASSERT(value != nil);
    return [value boolValue];
}

static int16_t ODOInt16GetterForUnknownOffset(ODOObject *self, SEL _cmd)
{
    ODOProperty *prop = [[self->_objectID entity] propertyWithGetter:_cmd];
    ODOASSERT_ATTRIBUTE_OF_TYPE(prop, ODOAttributeTypeInt16);
    
    id value = ODODynamicValueForProperty(self, prop);
    OBASSERT(value != nil);
    return [value shortValue];
}

static int32_t ODOInt32GetterForUnknownOffset(ODOObject *self, SEL _cmd)
{
    ODOProperty *prop = [[self->_objectID entity] propertyWithGetter:_cmd];
    ODOASSERT_ATTRIBUTE_OF_TYPE(prop, ODOAttributeTypeInt32);
    
    id value = ODODynamicValueForProperty(self, prop);
    OBASSERT(value != nil);
    return [value intValue];
}

static int64_t ODOInt64GetterForUnknownOffset(ODOObject *self, SEL _cmd)
{
    ODOProperty *prop = [[self->_objectID entity] propertyWithGetter:_cmd];
    ODOASSERT_ATTRIBUTE_OF_TYPE(prop, ODOAttributeTypeInt64);
    
    id value = ODODynamicValueForProperty(self, prop);
    OBASSERT(value != nil);
    return [value longLongValue];
}

static float ODOFloat32GetterForUnknownOffset(ODOObject *self, SEL _cmd)
{
    ODOProperty *prop = [[self->_objectID entity] propertyWithGetter:_cmd];
    ODOASSERT_ATTRIBUTE_OF_TYPE(prop, ODOAttributeTypeFloat32);
    
    id value = ODODynamicValueForProperty(self, prop);
    OBASSERT(value != nil);
    return [value floatValue];
}

static double ODOFloat64GetterForUnknownOffset(ODOObject *self, SEL _cmd)
{
    ODOProperty *prop = [[self->_objectID entity] propertyWithGetter:_cmd];
    ODOASSERT_ATTRIBUTE_OF_TYPE(prop, ODOAttributeTypeFloat64);
    
    id value = ODODynamicValueForProperty(self, prop);
    OBASSERT(value != nil);
    return [value doubleValue];
}

void ODOSetterForUnknownOffset(ODOObject *self, SEL _cmd, _Nullable id value)
{
    ODOProperty *prop = [[self->_objectID entity] propertyWithSetter:_cmd];
    OBASSERT(prop); // should only be installed for actual properties, unlike -setValue:forKey: which might be called for other keys
    
    ODODynamicSetValueForProperty(self, _cmd, prop, value);
}

static void ODOBoolSetterForUnknownOffset(ODOObject *self, SEL _cmd, BOOL value)
{
    ODOSetterForUnknownOffset(self, _cmd, @(value));
}

static void ODOInt16SetterForUnknownOffset(ODOObject *self, SEL _cmd, int16_t value)
{
    ODOSetterForUnknownOffset(self, _cmd, @(value));
}

static void ODOInt32SetterForUnknownOffset(ODOObject *self, SEL _cmd, int32_t value)
{
    ODOSetterForUnknownOffset(self, _cmd, @(value));
}

static void ODOInt64SetterForUnknownOffset(ODOObject *self, SEL _cmd, int64_t value)
{
    ODOSetterForUnknownOffset(self, _cmd, @(value));
}

static void ODOFloat32SetterForUnknownOffset(ODOObject *self, SEL _cmd, float value)
{
    ODOSetterForUnknownOffset(self, _cmd, @(value));
}

static void ODOFloat64SetterForUnknownOffset(ODOObject *self, SEL _cmd, double value)
{
    ODOSetterForUnknownOffset(self, _cmd, @(value));
}

static const char * _SignatureForSelector(SEL sel)
{
    Method method = class_getInstanceMethod([_ODOObject_Accessors class], sel);
    const char *signature = method_getTypeEncoding(method);
    return signature;
}

static const char * _ODOGetterSignatureForAttributeType(ODOAttributeType attrType)
{
    static const char * GetterSignatures[ODOAttributeTypeCount];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        GetterSignatures[ODOAttributeTypeUndefined] = _SignatureForSelector(@selector(_object_getter_signature));
        GetterSignatures[ODOAttributeTypeInt16] = _SignatureForSelector(@selector(_int16_getter_signature));
        GetterSignatures[ODOAttributeTypeInt32] = _SignatureForSelector(@selector(_int32_getter_signature));
        GetterSignatures[ODOAttributeTypeInt64] = _SignatureForSelector(@selector(_int64_getter_signature));
        GetterSignatures[ODOAttributeTypeFloat32] = _SignatureForSelector(@selector(_float32_getter_signature));
        GetterSignatures[ODOAttributeTypeFloat64] = _SignatureForSelector(@selector(_float64_getter_signature));
        GetterSignatures[ODOAttributeTypeString] = _SignatureForSelector(@selector(_object_getter_signature));
        GetterSignatures[ODOAttributeTypeBoolean] = _SignatureForSelector(@selector(_bool_getter_signature));
        GetterSignatures[ODOAttributeTypeDate] = _SignatureForSelector(@selector(_object_getter_signature));
        GetterSignatures[ODOAttributeTypeXMLDateTime] = _SignatureForSelector(@selector(_object_getter_signature));
        GetterSignatures[ODOAttributeTypeData] = _SignatureForSelector(@selector(_object_getter_signature));
    });

    return GetterSignatures[attrType];
}

const char * ODOGetterSignatureForProperty(ODOProperty *prop)
{
    ODOAttributeType attrType = ODOAttributeTypeUndefined;
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);

    if (flags.relationship || !flags.scalarAccessors) {
        attrType = ODOAttributeTypeUndefined; // object style accessor
    } else {
        OBASSERT([prop isKindOfClass:[ODOAttribute class]]);
        ODOAttribute *attr = (ODOAttribute *)prop;
        OBASSERT(attr->_type >= 0 && attr->_type < ODOAttributeTypeCount);
        if (attr->_type >= 0 && attr->_type < ODOAttributeTypeCount) {
            attrType = attr->_type;
        }
    }

    return _ODOGetterSignatureForAttributeType(attrType);
}

const char * ODOObjectGetterSignature(void)
{
    return _ODOGetterSignatureForAttributeType(ODOAttributeTypeUndefined);
}

const char * ODOSetterSignatureForProperty(ODOProperty *prop)
{
    static const char * SetterSignatures[ODOAttributeTypeCount];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SetterSignatures[ODOAttributeTypeUndefined] = _SignatureForSelector(@selector(_object_setter_signature:));
        SetterSignatures[ODOAttributeTypeInt16] = _SignatureForSelector(@selector(_int16_setter_signature:));
        SetterSignatures[ODOAttributeTypeInt32] = _SignatureForSelector(@selector(_int32_setter_signature:));
        SetterSignatures[ODOAttributeTypeInt64] = _SignatureForSelector(@selector(_int64_setter_signature:));
        SetterSignatures[ODOAttributeTypeFloat32] = _SignatureForSelector(@selector(_float32_setter_signature:));
        SetterSignatures[ODOAttributeTypeFloat64] = _SignatureForSelector(@selector(_float64_setter_signature:));
        SetterSignatures[ODOAttributeTypeString] = _SignatureForSelector(@selector(_object_setter_signature:));
        SetterSignatures[ODOAttributeTypeBoolean] = _SignatureForSelector(@selector(_bool_setter_signature:));
        SetterSignatures[ODOAttributeTypeDate] = _SignatureForSelector(@selector(_object_setter_signature:));
        SetterSignatures[ODOAttributeTypeXMLDateTime] = _SignatureForSelector(@selector(_object_setter_signature:));
        SetterSignatures[ODOAttributeTypeData] = _SignatureForSelector(@selector(_object_setter_signature:));
    });
    
    ODOAttributeType attrType = ODOAttributeTypeUndefined;
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    
    if (flags.relationship || !flags.scalarAccessors) {
        attrType = ODOAttributeTypeUndefined; // object style accessor
    } else {
        OBASSERT([prop isKindOfClass:[ODOAttribute class]]);
        ODOAttribute *attr = (ODOAttribute *)prop;
        OBASSERT(attr->_type >= 0 && attr->_type < ODOAttributeTypeCount);
        if (attr->_type >= 0 && attr->_type < ODOAttributeTypeCount) {
            attrType = attr->_type;
        }
    }
    
    return SetterSignatures[attrType];
}

static const char * _AttributesForProperty(SEL sel)
{
    const char *name = [NSStringFromSelector(sel) UTF8String];
    objc_property_t objcProperty = class_getProperty([_ODOObject_Accessors class], name);
    OBASSERT(objcProperty != NULL);
    
    // https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html
    const char *attributes = property_getAttributes(objcProperty);
    return attributes;
}

const char * ODOPropertyAttributesForProperty(ODOProperty *prop)
{
    static const char * PropertyAttributes[ODOAttributeTypeCount];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PropertyAttributes[ODOAttributeTypeUndefined] = _AttributesForProperty(@selector(_object_property));
        PropertyAttributes[ODOAttributeTypeInt16] = _AttributesForProperty(@selector(_int16_property));
        PropertyAttributes[ODOAttributeTypeInt32] = _AttributesForProperty(@selector(_int32_property));
        PropertyAttributes[ODOAttributeTypeInt64] = _AttributesForProperty(@selector(_int64_property));
        PropertyAttributes[ODOAttributeTypeFloat32] = _AttributesForProperty(@selector(_float32_property));
        PropertyAttributes[ODOAttributeTypeFloat64] = _AttributesForProperty(@selector(_float64_property));
        PropertyAttributes[ODOAttributeTypeString] = _AttributesForProperty(@selector(_object_property));
        PropertyAttributes[ODOAttributeTypeBoolean] = _AttributesForProperty(@selector(_bool_property));
        PropertyAttributes[ODOAttributeTypeDate] = _AttributesForProperty(@selector(_object_property));
        PropertyAttributes[ODOAttributeTypeXMLDateTime] = _AttributesForProperty(@selector(_object_property));
        PropertyAttributes[ODOAttributeTypeData] = _AttributesForProperty(@selector(_object_property));
    });

    ODOAttributeType attrType = ODOAttributeTypeUndefined;
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    
    if (flags.relationship || !flags.scalarAccessors) {
        attrType = ODOAttributeTypeUndefined; // object style accessor
    } else {
        OBASSERT([prop isKindOfClass:[ODOAttribute class]]);
        ODOAttribute *attr = (ODOAttribute *)prop;
        OBASSERT(attr->_type >= 0 && attr->_type < ODOAttributeTypeCount);
        if (attr->_type >= 0 && attr->_type < ODOAttributeTypeCount) {
            attrType = attr->_type;
        }
    }
    
    return PropertyAttributes[attrType];
}

IMP ODOGetterForProperty(ODOProperty *prop)
{
    NSUInteger snapshotIndex = prop->_storageKey.snapshotIndex;
    if (snapshotIndex == ODO_STORAGE_KEY_PRIMARY_KEY_SNAPSHOT_INDEX) {
        return (IMP)_ODOObjectPrimaryKeyGetter;
    }
    
    IMP getter = NULL;
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);

    // We have different paths for attributes and relationships to allow for lazy fault creation on the relationship paths.
    if (snapshotIndex < ODOObjectIndexedAccessorCount) {
        const ODOAccessors *accessors = &IndexedAccessors[snapshotIndex];
        if (flags.relationship) {
            getter = (IMP)(flags.toMany ? accessors->to_many.get : accessors->to_one.get);
        } else if (flags.transient && flags.calculated) {
            getter = (IMP)ODOGetterForUnknownOffset;
        } else if (flags.scalarAccessors) {
            OBASSERT([prop isKindOfClass:[ODOAttribute class]]);
            ODOAttribute *attr = (ODOAttribute *)prop;
            
            switch (attr->_type) {
                case ODOAttributeTypeInvalid: {
                    OBASSERT_NOT_REACHED("Invalid attribute type.");
                    break;
                }
                    
                case ODOAttributeTypeUndefined: {
                    getter = (IMP)accessors->attribute.get;
                    break;
                }
                    
                case ODOAttributeTypeInt16: {
                    getter = (IMP)accessors->attribute.get_int16;
                    break;
                }

                case ODOAttributeTypeInt32: {
                    getter = (IMP)accessors->attribute.get_int32;
                    break;
                }

                case ODOAttributeTypeInt64: {
                    getter = (IMP)accessors->attribute.get_int64;
                    break;
                }

                case ODOAttributeTypeFloat32: {
                    getter = (IMP)accessors->attribute.get_float32;
                    break;
                }

                case ODOAttributeTypeFloat64: {
                    getter = (IMP)accessors->attribute.get_float64;
                    break;
                }

                case ODOAttributeTypeString: {
                    getter = (IMP)accessors->attribute.get;
                    break;
                }

                case ODOAttributeTypeBoolean: {
                    getter = (IMP)accessors->attribute.get_bool;
                    break;
                }

                case ODOAttributeTypeDate:
                case ODOAttributeTypeXMLDateTime:
                case ODOAttributeTypeData: {
                    getter = (IMP)accessors->attribute.get;
                    break;
                }
            }
        } else {
            getter = (IMP)accessors->attribute.get;
        }
    } else {
        #if defined(DEBUG_bungi) || defined(DEBUG_correia)
            OBASSERT_NOT_REACHED("Need more attribute at-offset getters.");
        #endif

        if (flags.relationship) {
            getter = (IMP)ODOGetterForUnknownOffset;
        } else if (flags.transient && flags.calculated) {
            getter = (IMP)ODOGetterForUnknownOffset;
        } else if (flags.scalarAccessors) {
            static IMP UnknownOffsetAccessors[ODOAttributeTypeCount];
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                UnknownOffsetAccessors[ODOAttributeTypeUndefined] = (IMP)ODOGetterForUnknownOffset;
                UnknownOffsetAccessors[ODOAttributeTypeInt16] = (IMP)ODOInt16GetterForUnknownOffset;
                UnknownOffsetAccessors[ODOAttributeTypeInt32] = (IMP)ODOInt32GetterForUnknownOffset;
                UnknownOffsetAccessors[ODOAttributeTypeInt64] = (IMP)ODOInt64GetterForUnknownOffset;
                UnknownOffsetAccessors[ODOAttributeTypeFloat32] = (IMP)ODOFloat32GetterForUnknownOffset;
                UnknownOffsetAccessors[ODOAttributeTypeFloat64] = (IMP)ODOFloat64GetterForUnknownOffset;
                UnknownOffsetAccessors[ODOAttributeTypeString] = (IMP)ODOGetterForUnknownOffset;
                UnknownOffsetAccessors[ODOAttributeTypeBoolean] = (IMP)ODOBoolGetterForUnknownOffset;
                UnknownOffsetAccessors[ODOAttributeTypeDate] = (IMP)ODOGetterForUnknownOffset;
                UnknownOffsetAccessors[ODOAttributeTypeXMLDateTime] = (IMP)ODOGetterForUnknownOffset;
                UnknownOffsetAccessors[ODOAttributeTypeData] = (IMP)ODOGetterForUnknownOffset;
            });

            OBASSERT([prop isKindOfClass:[ODOAttribute class]]);
            ODOAttribute *attr = (ODOAttribute *)prop;

            OBASSERT(attr->_type >= 0 && attr->_type < ODOAttributeTypeCount);
            getter = UnknownOffsetAccessors[attr->_type];
        } else {
            getter = (IMP)ODOGetterForUnknownOffset;
        }
    }

    OBASSERT(getter != NULL);
    return getter;
}

IMP ODOSetterForProperty(ODOProperty *prop)
{
    static IMP Setters[ODOAttributeTypeCount];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Setters[ODOAttributeTypeUndefined] = (IMP)ODOSetterForUnknownOffset;
        Setters[ODOAttributeTypeInt16] = (IMP)ODOInt16SetterForUnknownOffset;
        Setters[ODOAttributeTypeInt32] = (IMP)ODOInt32SetterForUnknownOffset;
        Setters[ODOAttributeTypeInt64] = (IMP)ODOInt64SetterForUnknownOffset;
        Setters[ODOAttributeTypeFloat32] = (IMP)ODOFloat32SetterForUnknownOffset;
        Setters[ODOAttributeTypeFloat64] = (IMP)ODOFloat64SetterForUnknownOffset;
        Setters[ODOAttributeTypeString] = (IMP)ODOSetterForUnknownOffset;
        Setters[ODOAttributeTypeBoolean] = (IMP)ODOBoolSetterForUnknownOffset;
        Setters[ODOAttributeTypeDate] = (IMP)ODOSetterForUnknownOffset;
        Setters[ODOAttributeTypeXMLDateTime] = (IMP)ODOSetterForUnknownOffset;
        Setters[ODOAttributeTypeData] = (IMP)ODOSetterForUnknownOffset;
    });
    
    ODOAttributeType attrType = ODOAttributeTypeUndefined;
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    
    if (flags.relationship || !flags.scalarAccessors) {
        attrType = ODOAttributeTypeUndefined; // object style accessor
    } else {
        OBASSERT([prop isKindOfClass:[ODOAttribute class]]);
        ODOAttribute *attr = (ODOAttribute *)prop;
        OBASSERT(attr->_type >= 0 && attr->_type < ODOAttributeTypeCount);
        if (attr->_type >= 0 && attr->_type < ODOAttributeTypeCount) {
            attrType = attr->_type;
        }
    }
    
    return Setters[attrType];
}

// See the disabled implementation of +[ODOObject resolveInstanceMethod:].
#if !LAZY_DYNAMIC_ACCESSORS
void ODOObjectCreateDynamicAccessorsForEntity(ODOEntity *entity)
{
    Class instanceClass = [entity instanceClass];
    OBASSERT(instanceClass != [ODOObject class]);
    OBASSERT(entity == [ODOModel entityForClass:[entity instanceClass]]);

    DEBUG_DYNAMIC_METHODS(@"Registering dynamic methods for %@ -> %@", [entity name], NSStringFromClass(instanceClass));
    
#ifdef OMNI_ASSERTIONS_ON
    BOOL missingDynamicProperty = NO;
#endif
    
    // Force dynamic property accessors to be registered now. The NSKVO cover class screws this up.
    for (ODOProperty *prop in entity.properties) {
        SEL sel = NULL;
        
        // All the matching ObjC properties must be @dynamic since ODOObject maintains its own storage for persistent properties.
#ifdef OMNI_ASSERTIONS_ON
        {
            objc_property_t objcProperty = class_getProperty(instanceClass, [prop->_name UTF8String]);
            OBASSERT(objcProperty != NULL);
            
            // https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html
            const char *attributes = property_getAttributes(objcProperty);
            DEBUG_DYNAMIC_METHODS(@"  property attributes = %s", attributes);
            
            // 'T' is first, so ',D' should be there somewhere (typically last). Need to check if @encode for structs can have commas in them, but for now we require that all properties are object typed.
            struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
            if (flags.relationship || !flags.scalarAccessors) {
                OBASSERT(strstr(attributes, "T@") == attributes, "Property %@.%@ should be object-typed!", NSStringFromClass(instanceClass), prop->_name);

                BOOL expectCopyAttribute = NO;
                if (flags.relationship) {
                    ODORelationship *rel = OB_CHECKED_CAST(ODORelationship, prop);
                    expectCopyAttribute = rel.toMany && !flags.calculated;
                } else {
                    ODOAttribute *attr = OB_CHECKED_CAST(ODOAttribute, prop);
                    expectCopyAttribute = attr->_setterBehavior == ODOAttributeSetterBehaviorCopy;
                }
                
                if (expectCopyAttribute && strstr(attributes, ",C") == NULL) {
                    NSLog(@"Property %@.%@ should be marked copy!", NSStringFromClass(instanceClass), prop->_name);
                }
            } else {
                OBASSERT(strlen(attributes) > 2 && attributes[0] == 'T');
                char typeEncoding = attributes[1];
                char typeEncodingString[3] = {'T', typeEncoding, '\0'};
                if (strstr(attributes, typeEncodingString) != attributes) {
                    NSLog(@"Property %@.%@ has unexpected type!", NSStringFromClass(instanceClass), prop->_name);
                }
            }
            
            if (flags.calculated && strstr(attributes, ",R") == NULL) {
                NSLog(@"Property %@.%@ should be marked readonly!", NSStringFromClass(instanceClass), prop->_name);
            } else if (!flags.calculated && strstr(attributes, ",R") != NULL) {
                NSLog(@"Property %@.%@ should not be marked readonly!", NSStringFromClass(instanceClass), prop->_name);
            }
            
            if (strstr(attributes, ",N") == NULL) {
                NSLog(@"Property %@.%@ should be marked nonatomic!", NSStringFromClass(instanceClass), prop->_name);
            }

            if (strstr(attributes, ",D") == NULL) {
                NSLog(@"Property %@.%@ should be marked @dynamic!", NSStringFromClass(instanceClass), prop->_name);
                missingDynamicProperty = YES;
            }
        }
#endif
        
        sel = prop->_sel.get;
        if (sel != NULL && class_getInstanceMethod(instanceClass, sel) == NULL) {
            IMP imp = (IMP)ODOGetterForProperty(prop);
            const char *signature = ODOGetterSignatureForProperty(prop);
            DEBUG_DYNAMIC_METHODS(@"  Adding -[%@ %@] with %p %s", NSStringFromClass(instanceClass), NSStringFromSelector(sel), imp, signature);
            class_addMethod(instanceClass, sel, imp, signature);
        }
        
        sel = prop->_sel.set;
        if (sel != NULL && class_getInstanceMethod(instanceClass, sel) == NULL) {
            IMP imp = (IMP)ODOSetterForProperty(prop);
            const char *signature = ODOSetterSignatureForProperty(prop);
            DEBUG_DYNAMIC_METHODS(@"  Adding -[%@ %@] with %p %s", NSStringFromClass(instanceClass), NSStringFromSelector(sel), imp, signature);
            class_addMethod(instanceClass, sel, imp, signature);
        }
    }
    
    OBASSERT(missingDynamicProperty == NO, "Missing @dynamic property definitions");
}
#endif

NS_ASSUME_NONNULL_END
