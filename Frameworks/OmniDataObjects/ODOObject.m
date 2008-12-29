// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOObject.h>

#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODORelationship.h>

#import "ODOEntity-Internal.h"
#import "ODOObject-Internal.h"
#import "ODOEditingContext-Internal.h"
#import "ODODatabase-Internal.h"
#import "ODOAttribute-Internal.h"
#import "ODOProperty-Internal.h"

RCS_ID("$Id$")

NSString * const ODODetailedErrorsKey = @"ODODetailedErrorsKey";

@implementation ODOObject

- (id)initWithEditingContext:(ODOEditingContext *)context entity:(ODOEntity *)entity primaryKey:(id)primaryKey;
{
    OBPRECONDITION(context);
    OBPRECONDITION(entity);
    OBPRECONDITION([entity instanceClass] == [self class]);
    OBPRECONDITION(!primaryKey || [primaryKey isKindOfClass:[[entity primaryKeyAttribute] valueClass]]);
    
    if (!primaryKey)
        primaryKey = [[context database] _generatePrimaryKeyForEntity:entity];
    
    ODOObjectID *objectID = [[ODOObjectID alloc] initWithEntity:entity primaryKey:primaryKey];
    self = [self initWithEditingContext:context objectID:objectID isFault:NO];
    [objectID release];
    
    return self;
}

- (void)dealloc;
{
    // For now, ODOEditingContext holds onto us until it is reset and we are made invalid.
    OBPRECONDITION(_editingContext == nil);
    OBPRECONDITION(_flags.invalid == YES);
    OBPRECONDITION(_valueArray == NULL);

    OBPRECONDITION(_objectID != nil); // This doesn't get cleared when the object is invalidated.  Notification listeners need to know the entity/pk of deleted objects.

    if (_valueArray) {
        ODOObjectClearValues(self, NO/*deleting*/);
        CFRelease(_valueArray);
        _valueArray = NULL;
    }

    [_editingContext release];
    [_objectID release];
    
    [super dealloc];
}

- (void)willAccessValueForKey:(NSString *)key;
{
    OBPRECONDITION(![self isDeleted] || [key isEqualToString:[[[_objectID entity] primaryKeyAttribute] name]]);

    if (!_flags.invalid && _flags.isFault) {
        // Don't clear faults for the primary key
        if (![key isEqualToString:[[[_objectID entity] primaryKeyAttribute] name]])
            ODOFetchObjectFault(_editingContext, self);
    }

    // We might be part of a fetch result set that is still getting awoken.  If another object awaking tries to talk to us before we are awake, wake up early.  Not that circular awaking problems are still possible.
    if (self->_flags.needsAwakeFromFetch)
        ODOObjectPerformAwakeFromFetchWithoutRegisteringEdits(self);
}

- (void)didAccessValueForKey:(NSString *)key;
{
    OBPRECONDITION(![self isDeleted] || [key isEqualToString:[[[_objectID entity] primaryKeyAttribute] name]]);

    // Nothing.
}

static void ODOObjectWillChangeValueForProperty(ODOObject *self, ODOProperty *prop, NSString *key)
{
    if (prop) {
        OBASSERT(!self->_flags.invalid);
        
        if (self->_flags.isFault) {
            OBASSERT(![self isInserted]);
            
            // Setting before looking at anything; clear the fault first
            [self willAccessValueForKey:key];
            [self didAccessValueForKey:key];
            
            // fall through and mark the object updated
        }
        
        // If we are inserted recently, _objectWillBeUpdated: will do nothing.  But if we've been inserted, -processPendingChanges has been called and *then* we get updated, we'll be put in the recently updated set.  Let ODOEditingContext sort it out.
        // TODO: Track a flag that says whether we are already in the updated (or inserted) set?
        
        // If we are being fetched, allow editing transient properties w/o registering as updated.  Non-modeled properties (caches of various sorts) will miss this by virtue of the key not mapping to a property.
        OBASSERT(!self->_flags.changeProcessingDisabled || [prop isTransient]);
        if (!self->_flags.changeProcessingDisabled)
            [self->_editingContext _objectWillBeUpdated:self];
    }
}

static void ODOObjectWillChangeValueForKey(ODOObject *self, NSString *key)
{
    ODOProperty *prop = [[self->_objectID entity] propertyNamed:key];
    ODOObjectWillChangeValueForProperty(self, prop, key);
}

- (void)willChangeValueForKey:(NSString *)key;
{
    ODOObjectWillChangeValueForKey(self, key);
    [super willChangeValueForKey:key];
}

#ifdef OMNI_ASSERTIONS_ON
- (void)didChangeValueForKey:(NSString *)key;
{
    if ([[self->_objectID entity] propertyNamed:key])
        OBASSERT(!_flags.isFault); // Cleared in 'will'
    [super didChangeValueForKey:key];
}
#endif    

// Even if the only change to an object is to a to-many, it needs to be marked updated so it will get notified on save and so it will be included in the updated object set when ODOEditingContext processes changes or saves.
- (void)willChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)inMutationKind usingObjects:(NSSet *)inObjects;
{
    ODOProperty *prop = [[self entity] propertyNamed:key];

    // These get called as we update inverse to-many relationships due to edits to to-one relationships.  ODO doesn't snapshot to-many relationships in -changedValues, so we track this here.  This adds one more reason that undo/redo needs to provide correct KVO notifiactions.
    if (prop && !_flags.hasChangedInterestingToManyRelationshipSinceLastSave) {
        
        // Only to-many relationship keys should go through here.
        OBASSERT([prop isKindOfClass:[ODORelationship class]]);
        OBASSERT([(ODORelationship *)prop isToMany]);
        
        if (![[[self class] derivedPropertyNameSet] member:[prop name]]) {
            _flags.hasChangedInterestingToManyRelationshipSinceLastSave = YES;
#if 0 && defined(DEBUG_bungi)
            NSLog(@"Setting %@._hasChangedInterestingToManyRelationshipSinceLastSave for change to %@", [self shortDescription], [prop name]);
#endif
        }
    }

    ODOObjectWillChangeValueForProperty(self, prop, key);
    
    [super willChangeValueForKey:key withSetMutation:inMutationKind usingObjects:inObjects];
}

#ifdef OMNI_ASSERTIONS_ON
- (void)didChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)inMutationKind usingObjects:(NSSet *)inObjects;
{
    if ([[self->_objectID entity] propertyNamed:key])
        OBASSERT(!_flags.isFault); // Cleared in 'will'
    [super didChangeValueForKey:key withSetMutation:inMutationKind usingObjects:inObjects];
}
#endif    


- (void)setObservationInfo:(void *)inObservationInfo; 
{
    _observationInfo = inObservationInfo;
}

- (void *)observationInfo;    
{
    return _observationInfo;
}

- (void)setPrimitiveValue:(id)value forKey:(NSString *)key;
{
    ODOProperty *prop = [[self->_objectID entity] propertyNamed:key];
    OBASSERT(prop); // shouldn't ask for non-model properties via this interface
    [self setPrimitiveValue:value forProperty:prop];
}

- (id)primitiveValueForKey:(NSString *)key;
{
    ODOEntity *entity = [self entity]; // TODO: Disallow subclassing -entity via setup check.  Then inline it here.
    ODOProperty *prop = [entity propertyNamed:key];
    OBASSERT(prop); // shouldn't ask for non-model properties via this interface
    
    return [self primitiveValueForProperty:prop];
}

- (void)setPrimitiveValue:(id)value forProperty:(ODOProperty *)prop;
{
    OBPRECONDITION(prop);
    // OBPRECONDITION(!_flags.isFault); Being a fault is allowed here since this is how faults will get set up.

    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    
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
                    // We allow mutables sets consisting of instances of the destination entity's instance class.
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
    
    if (flags.snapshotIndex == ODO_PRIMARY_KEY_SNAPSHOT_INDEX) {
        OBASSERT_NOT_REACHED("Ignoring attempt to set the primary key");
        return;
    }
    
    id newValue = value;
    id oldValue = [self primitiveValueForProperty:prop]; // It is important to use this so that we'll get lazy to-one faults created
    if (oldValue == value)
        return;

    if (!_flags.changeProcessingDisabled) { // Might be fetching an object and setting up initial values, for example
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
                        [oldValue setPrimitiveValue:nil forProperty:inverse];
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
                    [newValue setPrimitiveValue:nil forProperty:inverse];
                    [newValue didChangeValueForKey:inverseKey];

                    // Then, after the new value has been disassociated correctly, associate it to us.
                    [newValue willChangeValueForKey:inverseKey];
                    ODOObjectSetChangeProcessingEnabled(newValue, NO);
                    @try {
                        [newValue setPrimitiveValue:self forProperty:inverse];
                    } @finally {
                        ODOObjectSetChangeProcessingEnabled(newValue, YES);
                    }
                    [newValue didChangeValueForKey:inverseKey];
                }
            }
        }
    }
    
    CFArraySetValueAtIndex(_valueArray, flags.snapshotIndex, value);
}

- (id)primitiveValueForProperty:(ODOProperty *)prop;
{
    OBPRECONDITION(prop);
    OBPRECONDITION(!_flags.isFault || prop == [[_objectID entity] primaryKeyAttribute]);
    
    // Could maybe have extra info in this lookup (attr vs. rel, to-one vs. to-many)?
    unsigned int snapshotIndex = ODOPropertySnapshotIndex(prop);
    if (snapshotIndex == ODO_PRIMARY_KEY_SNAPSHOT_INDEX)
        return [[self objectID] primaryKey];

    OBASSERT(_valueArray != nil); // This is the case if the object is invalidated either due to deletion or the editing context being reset.  In CoreData, messaging an dead object will sometimes get an exception, sometimes get a crash or sometimes (if you are in the middle of invalidation) get you a stale value.  In ODO, it gets you dead.  Hopefully we won't have to relax this since it makes tracking down these (very real) problems easier.
    id value = (id)CFArrayGetValueAtIndex(_valueArray, snapshotIndex);
    
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    
    if (flags.relationship) {
        ODORelationship *rel = (ODORelationship *)prop;
        
        if (flags.toMany) {
            if (ODOObjectValueIsLazyToManyFault(value)) {
                // When asking for the to-many relationship the first time, we fetch it.  We assume that the caller is going to do something useful with it, otherwise they shouldn't even ask.  If you want to conditionally avoid faulting, we could add a -isFaultForKey: or some such.
                value = ODOFetchSetFault(_editingContext, self, rel);
                CFArraySetValueAtIndex(_valueArray, snapshotIndex, value);
            }
        } else {
            if ([value isKindOfClass:[ODOObject class]]) {
                OBASSERT([value isKindOfClass:[[rel destinationEntity] instanceClass]]);
                // All good
            } else if (value) {
                OBASSERT([value isKindOfClass:[[[rel destinationEntity] primaryKeyAttribute] valueClass]]);
                
                // Lazily find or create a to-one fault based on the primary key stored in our snapshot.
                ODOEntity *destEntity = [rel destinationEntity];

                ODOObjectID *destID = [[ODOObjectID alloc] initWithEntity:destEntity primaryKey:value];
                value = ODOEditingContextLookupObjectOrRegisterFaultForObjectID(_editingContext, destID);
                [destID release];
                
                // Replace the pk with the real fault.
                CFArraySetValueAtIndex(_valueArray, snapshotIndex, value);
            } else {
                // to-one to nil; just fine
            }
        }
    }
    
    return value;
}

- (id)valueForKey:(NSString *)key;
{
    ODOProperty *prop = [[_objectID entity] propertyNamed:key];
    if (!prop)
        return [super valueForKey:key];

    return ODOPropertyGetValue(self, prop);
}

- (void)setValue:(id)value forKey:(NSString *)key;
{
    ODOProperty *prop = [[self->_objectID entity] propertyNamed:key];
    
    if (!prop) {
        [super setValue:value forKey:key];
        return;
    }

    // We don't allow editing to-many relationships from the to-many side.  We don't have many-to-many right now; edit the to-one on the other side.
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    if (flags.relationship  && flags.toMany)
        OBRejectInvalidCall(self, _cmd, @"Attempted to set %@.%@, but we don't allow setting to-many relationships directly right now.", [self shortDescription], key);
    
    ODOPropertySetValue(self, prop, value);
}

// Subclasses should call this before doing anything in their own implementation, otherwise, this might override any setup they do.
- (void)setDefaultAttributeValues;
{
    ODOEntity *entity = [self entity];
    NSArray *properties = [entity snapshotProperties];
    unsigned int propertyIndex = [properties count];
    while (propertyIndex--) {
        ODOProperty *prop = [properties objectAtIndex:propertyIndex];
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        if (!flags.relationship) {
            // Model loading code ensures that the primary key attribute doesn't have a default value            
            ODOAttribute *attr = (ODOAttribute *)prop;
            
            // Set this even if the default value is nil in case we are re-establishing default values
            [self setPrimitiveValue:[attr defaultValue] forProperty:attr]; // Bypass this and set the primitive value to avoid and setter.
        }
    }
}

// Subclasses should call this before doing anything in their own implementation, otherwise, this might override any setup they do.
- (void)awakeFromInsert;
{
    [self setDefaultAttributeValues]; // Subclasses might override this
    
    // On insert, we also set the default relastionship values
    ODOEntity *entity = [self entity];
    NSArray *properties = [entity snapshotProperties];
    unsigned int propertyIndex = [properties count];
    while (propertyIndex--) {
        ODOProperty *prop = [properties objectAtIndex:propertyIndex];
        
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        
        if (flags.relationship && flags.toMany) {
            ODORelationship *rel = (ODORelationship *)prop;
            
            // Give it an empty set.  If we don't, then the first time the to-many is accessed, the nil will be promoted to a fault and clearing it will perform a useless fetch.
            NSMutableSet *dest = [[NSMutableSet alloc] init];
            ODOObjectSetInternalValueForProperty(self, dest, rel); // Can't directly set to-many, so set via the primitive, non-fault-clearing setter.
            [dest release];
        }
    }
}

- (void)awakeFromFetch;
{
    OBPRECONDITION(_flags.changeProcessingDisabled); // set by ODOObjectAwakeFromFetchWithoutRegisteringEdits
    OBPRECONDITION(!_flags.isFault);
    
    // Nothing for us to do, I think; for subclasses
}

- (ODOEntity *)entity;
{
    OBPRECONDITION(_objectID);
    return [_objectID entity];
}

- (ODOEditingContext *)editingContext;
{
    OBPRECONDITION(_editingContext);
    return _editingContext;
}

- (ODOObjectID *)objectID;
{
    return _objectID;
}

- (void)willSave;
{
    // Nothing; this is for subclasses
}

- (void)willInsert;
{
    [self willSave];
}

- (void)willUpdate;
{
    [self willSave];
}

- (void)willDelete;
{
    [self willSave];
}

// When an object is deleted with -[ODOEditingContext deleteObject:], it will receive this.  Other objects being deleted due to propagation will not.
- (void)prepareForDeletion;
{
    // Nothing, for subclasses
}

- (void)didSave;
{
    // Nothing; this is for subclasses
}

typedef struct {
    ODOObject *owner;
    ODORelationship *relationship;
    NSError *error;
} ValidateRelatedObjectContext;

static void _validateRelatedObjectClass(const void *value, void *context)
{
    ValidateRelatedObjectContext *ctx = context;
    ODOObject *dest = (ODOObject *)value;
    
    OBPRECONDITION([dest isKindOfClass:[ODOObject class]]); // nils should have been handled already

    // TODO: Return multiple validation errors instead of just the first
    if (ctx->error)
        return;
    
    // TODO: Make sure the objects are in the same context?  Our invariants check that.
    // TDOO: check inserted/updated objects for relationships to transient objects?  Our invariants also check for that.

    // Check the class at runtime.
    ODOEntity *expectedEntity = [ctx->relationship destinationEntity];
    Class expectedClass = [expectedEntity instanceClass];
    if (![dest isKindOfClass:expectedClass]) {
        NSString *reason = [NSString stringWithFormat:@"Relationship '%@' of '%@' lead to object of class '%@', but it should have been a '%@'", [ctx->relationship name], [ctx->owner shortDescription], NSStringFromClass([dest class]), NSStringFromClass(expectedClass)];
        ODOError(&ctx->error, ODOValueOfWrongClassValidationError, @"Cannot save.", reason, nil);
        return;
    }
    
    // Check the entity too since the same class can be used for multiple entities.  We don't support entity inheritence, so we don't need -isKindOfEntity: here.
    if ([dest entity] != expectedEntity) {
        NSString *reason = [NSString stringWithFormat:@"Relationship '%@' of '%@' lead to object of entity '%@', but it should have been a '%@'", [ctx->relationship name], [ctx->owner shortDescription], [[dest entity] name], [expectedEntity name]];
        ODOError(&ctx->error, ODOValueOfWrongClassValidationError, @"Cannot save.", reason, nil);
        return;
    }
}

- (BOOL)validateForSave:(NSError **)outError;
{
    ODOEntity *entity = [self entity];
    NSArray *snapshotProperties = [entity snapshotProperties];
    unsigned int propertyIndex = [snapshotProperties count];
    
    while (propertyIndex--) {
        ODOProperty *prop = [snapshotProperties objectAtIndex:propertyIndex];
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        
        // Directly accessing the values rather than going through the will/did lookup.  We aren't "accessing" the values.
        id value = (id)CFArrayGetValueAtIndex(_valueArray, flags.snapshotIndex);
        
        // Not localizing these validation errors right now.  OmniFocus expects users to never see these, and we don't have CoreData's human-readability mappings right now.
        
        // Check for required values in attributes and to-one relationships.  A nil in a to-many (currently) means it is an lazy to-many.  We aren't supporting required to-many relationships right now.
        if (!value && (!flags.relationship || !flags.toMany)) {
            if (!flags.optional) {
                ODOError(outError, ODORequiredValueNotPresentValidationError, @"Cannot save.", ([NSString stringWithFormat:@"Required property '%@' not set on '%@'.", [prop name], [self shortDescription]]), nil);
                return NO;
            }
            
            // Rest of the checks are for non-nil values
            continue;
        }
        
        if (flags.relationship) {
            ValidateRelatedObjectContext ctx;
            memset(&ctx, 0, sizeof(ctx));
            ctx.owner = self;
            ctx.relationship = (ODORelationship *)prop;
            
            if (flags.toMany) {
                if (value && !ODOObjectValueIsLazyToManyFault(value))
                    CFSetApplyFunction((CFSetRef)value, _validateRelatedObjectClass, &ctx);
            } else {
                if ([value isKindOfClass:[ODOObject class]])
                    _validateRelatedObjectClass(value, &ctx);
                else if (value) {
                    Class primaryKeyClass = [[[ctx.relationship destinationEntity] primaryKeyAttribute] valueClass];
                    if (![value isKindOfClass:primaryKeyClass]) {
                        ODOError(outError, ODOValueOfWrongClassValidationError, @"Cannot save.",
                                 ([NSString stringWithFormat:@"Relationship '%@' of '%@' has primary key value of class '%@' instead of '%@'.", [ctx.relationship name], [self shortDescription], NSStringFromClass([value class]), NSStringFromClass(primaryKeyClass)]), nil);
                        return NO;
                    }
                }
            }
            if (ctx.error) {
                *outError = ctx.error;
                return NO;
            }
        } else {
            if (value) {
                ODOAttribute *attr = (ODOAttribute *)prop;
                Class valueClass = [attr valueClass];
                if (![value isKindOfClass:valueClass]) {
                    ODOError(outError, ODOValueOfWrongClassValidationError, @"Cannot save.",
                             ([NSString stringWithFormat:@"Attribute '%@' of '%@' has value of class '%@' instead of '%@'.", [attr name], [self shortDescription], NSStringFromClass([value class]), NSStringFromClass(valueClass)]), nil);
                    return NO;
                }

                // TODO: check value vs constraints of type (int16 vs magnitude, for example)
            }
        }
    }

    return YES;
}

// Usually the logic for insert and update validate is the same.  Subclasses can implement these two specific methods if they have *insert* or *update* specific validation, but usually they should just override -validateForSave:.  In all cases, the superclass implementation should be called to do the default property validation.  CoreData asks that it be called first.  Not sure why that matters.
- (BOOL)validateForInsert:(NSError **)outError;
{
    return [self validateForSave:outError];
}

- (BOOL)validateForUpdate:(NSError **)outError;
{
    return [self validateForSave:outError];
}


- (void)willTurnIntoFault;
{
    // Nothing; for subclasses
}

- (BOOL)isFault;
{
    return _flags.isFault;
}

- (void)turnIntoFault;
{
    // The underlying code gets called when deleting objects, but the public API should only be called on saved objects.
    OBPRECONDITION(![self isInserted]);
    OBPRECONDITION(![self isUpdated]);
    OBPRECONDITION(![self isDeleted]);
    
    [self _turnIntoFault:NO/*deleting*/];
}

- (BOOL)hasFaultForRelationship:(ODORelationship *)rel;
{
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);
    OBPRECONDITION([rel entity] == [self entity]);
    OBPRECONDITION([rel isKindOfClass:[ODORelationship class]]);
    
    struct _ODOPropertyFlags flags = ODOPropertyFlags(rel);
    OBASSERT(flags.relationship);
    if (!flags.relationship)
        return NO;
    
    if (flags.toMany)
        return ODOObjectToManyRelationshipIsFault(self, rel);
    
    id value = (id)CFArrayGetValueAtIndex(_valueArray, flags.snapshotIndex); // to-ones are stored as the primary key if they are lazy faults
    if (value && ![value isKindOfClass:[ODOObject class]]) {
        OBASSERT([value isKindOfClass:[[[rel destinationEntity] primaryKeyAttribute] valueClass]]);
        return YES;
    }
    return [value isFault];
}

- (BOOL)hasFaultForRelationshipNamed:(NSString *)key; 
{
    ODORelationship *rel = [[[self entity] relationshipsByName] objectForKey:key];
    OBASSERT(rel);
    if (!rel)
        return NO;
    
    return [self hasFaultForRelationship:rel];
}

// Handle the check w/o causing lazy faults to be materialized.
- (BOOL)toOneRelationship:(ODORelationship *)rel isToObject:(ODOObject *)destinationObject;
{
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);
    OBPRECONDITION(!destinationObject || [destinationObject editingContext] == _editingContext);
    OBPRECONDITION([rel entity] == [self entity]);
    OBPRECONDITION([rel isKindOfClass:[ODORelationship class]]);
    OBPRECONDITION(![rel isToMany]);
    
    struct _ODOPropertyFlags flags = ODOPropertyFlags(rel);
    OBASSERT(flags.relationship);
    if (!flags.relationship || flags.toMany)
        return NO;
    
    id value = (id)CFArrayGetValueAtIndex(_valueArray, flags.snapshotIndex); // to-ones are stored as the primary key if they are lazy faults
    
    // Several early-outs could be done here if it turns out to be useful; not doing them for now.
    
    id actualKey = [value isKindOfClass:[ODOObject class]] ? [[value objectID] primaryKey] : value;
    id queryKey = [[destinationObject objectID] primaryKey];
    
    OBASSERT(!actualKey || [actualKey isKindOfClass:[[[rel destinationEntity] primaryKeyAttribute] valueClass]]);
    OBASSERT(!queryKey || [queryKey isKindOfClass:[[[rel destinationEntity] primaryKeyAttribute] valueClass]]);
    
    return OFISEQUAL(actualKey, queryKey);
}

- (BOOL)isInserted;
{
    if (_flags.invalid)
        return NO;
    
    return [[self editingContext] isInserted:self];
}

- (BOOL)isDeleted;
{
    if (_flags.invalid)
        return NO;

    return [[self editingContext] isDeleted:self];
}

- (BOOL)isUpdated;
{
    if (_flags.invalid)
        return NO;

    return [[self editingContext] isUpdated:self];
}

- (BOOL)isInvalid;
{
    return _flags.invalid;
}

// Possibly faster alternative to -changedValues (for small numbers of keys).  Returns NO if the object is inserted, YES if deleted (though a previously nil property might be "nil" after deletion in some sense, it is a whole new level of nil).  The deleted case probably shouldn't happen anyway.
- (BOOL)hasChangedKeySinceLastSave:(NSString *)key;
{
    // CoreData apparently will return non-nil here.  Probably is snapshotting after -awakeFromInsert.  We don't do that (right now) and it would be nice to avoid having to.  So, don't allow this for inserted objects.
    OBPRECONDITION(![self isInserted]);
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);
    
    NSArray *snapshot = [_editingContext _committedPropertySnapshotForObjectID:_objectID];
    if (!snapshot) {
        // We are either inserted or totally unmodified
        return NO;
    }
        
    if ([self isDeleted]) {
        OBASSERT_NOT_REACHED("Why do you ask?");
        return YES;
    }

    ODOProperty *prop = [[_objectID entity] propertyNamed:key];
    unsigned snapshotIndex = ODOPropertySnapshotIndex(prop);
    if (snapshotIndex == ODO_PRIMARY_KEY_SNAPSHOT_INDEX)
        return NO; // can't change
    
    if ([prop isTransient]) {
        OBASSERT_NOT_REACHED("Shouldn't ask this since we aren't required to keep track of it (though we do...).  CoreData only supports querying persistent properties");
        return NO;
    }
    if ([prop isKindOfClass:[ODORelationship class]]) {
        ODORelationship *rel = (ODORelationship *)prop;
        if ([rel isToMany]) {
            // We are going to avoid mutating/clearing to-many relationships when an inverse to-one is updated.  So, we won't have a good way to do this w/o a bunch of extra work.  Let's not until we need to.
            OBRequestConcreteImplementation(self, _cmd);
        }
    }
    
    id oldValue = [snapshot objectAtIndex:snapshotIndex];
    
    [self willAccessValueForKey:key];
    id newValue = [self primitiveValueForProperty:prop];
    [self didAccessValueForKey:key];
    
    return OFNOTEQUAL(oldValue, newValue);
}

/*
 CoreData sez: "Returns a dictionary containing the keys and (new) values of persistent properties that have been changed since last fetching or saving the receiver." and "Note that this method only reports changes to properties that are defined as persistent properties of the receiver, not changes to transient properties or custom instance variables. This method does not unnecessarily fire relationship faults."
 
 We can emulate the non-transient changes for now, but we _are_ snapshotting them for undo so there is no reason not to return them.
 
 */
- (NSDictionary *)changedValues;
{
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);

    // CoreData's version doesn't return changes to transient attributes.  Their documentation isn't clear as to what happens for inserted objects -- are all the values changed?  None?
    // CoreData's version mentions something about not firing faults -- unclear if we can deal with faults.
    
    NSArray *snapshot = [_editingContext _committedPropertySnapshotForObjectID:_objectID];
    if (!snapshot) {
        if ([self isInserted]) {
            // Does inserting mean all the values are changed or none?
            OBRequestConcreteImplementation(self, _cmd);
        }
        
        OBASSERT(![self isUpdated]);
        OBASSERT(![self isDeleted]);
        
        return nil;
    }
    
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    NSArray *snapshotProperties = [[_objectID entity] snapshotProperties];
    unsigned int propIndex = [snapshotProperties count];
    while (propIndex--) {
        ODOProperty *prop = [snapshotProperties objectAtIndex:propIndex];
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        OBASSERT(flags.snapshotIndex == propIndex);
        
        // CoreData doesn't return transient properties from this method.
        if (flags.transient)
            continue;
        
        id oldValue = [snapshot objectAtIndex:propIndex];
        id newValue = (id)CFArrayGetValueAtIndex(_valueArray, propIndex);
        
        // early bail on equality
        if (OFISEQUAL(oldValue, newValue))
            continue;
        
        if (flags.relationship) {
            // We'll skip all relationships.  OmniFocus doesn't need them in -changedValues.
            if (flags.toMany)
                continue;
            
            // For to-one relationships, the internal value could be a raw primary key value or a fault.  Upscale to faults if we only have pks.  New values really shouldn't be pks.
            if (newValue && ![newValue isKindOfClass:[ODOObject class]])
                OBRejectInvalidCall(self, _cmd, @"%@.%@ is not a ODOObject but a %@ (%@)", [self shortDescription], [prop name], [newValue class], newValue);

            if (oldValue && ![oldValue isKindOfClass:[ODOObject class]]) {
                ODOEntity *destEntity = [(ODORelationship *)prop destinationEntity];

                ODOObjectID *objectID = [[ODOObjectID alloc] initWithEntity:destEntity primaryKey:oldValue];
                ODOObject *object = ODOEditingContextLookupObjectOrRegisterFaultForObjectID(_editingContext, objectID);
                [objectID release];
                
                oldValue = object;
                OBASSERT(oldValue);
            }

            // Check for equality again now that we've mapped to ODOObjects.
            if (OFISEQUAL(oldValue, newValue))
                continue;
        }

        if (OFISNULL(newValue))
            newValue = [NSNull null];
        [changes setObject:newValue forKey:[prop name]];
    }
    
    return changes;
}

- (id)committedValueForKey:(NSString *)key;
{
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);

    ODOProperty *prop = [[_objectID entity] propertyNamed:key];
    if (!prop) {
        OBASSERT(prop);
        return nil;
    }

    // Not sure how to handle to-many properties.  So let's not until we need it
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    if (flags.relationship && flags.toMany)
        OBRequestConcreteImplementation(self, _cmd);
        
    NSArray *snapshot = [_editingContext _committedPropertySnapshotForObjectID:_objectID];
    if (!snapshot) {
        // Inserted or never modified.  This may perform lazy creation on a fault.
        [self willAccessValueForKey:key];
        id value = [self primitiveValueForProperty:prop];
        [self didAccessValueForKey:key];
        return value;
    }
    
    id value = [snapshot objectAtIndex:flags.snapshotIndex];

    if (value && flags.relationship && !flags.toMany) {
        if (![value isKindOfClass:[ODOObject class]]) {
            // Might be a lazy to-one fault.  Can't go through primitiveValueForKey: since we've been snapshotted and our current value obviously might differ from that in the snapshot.
            ODORelationship *rel = (ODORelationship *)prop;
            ODOEntity *destEntity = [rel destinationEntity];
            OBASSERT([value isKindOfClass:[[destEntity primaryKeyAttribute] valueClass]]);
            ODOObjectID *destID = [[ODOObjectID alloc] initWithEntity:destEntity primaryKey:value];
            value = ODOEditingContextLookupObjectOrRegisterFaultForObjectID(_editingContext, destID);
            [destID release];
        }
    }
    
    if (OFISNULL(value))
        value = nil;
    
    return value;
}

- (NSDictionary *)committedValuesForKeys:(NSArray *)keys;    
{
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);

    // CoreData's method says it only returns persistent properties.  Also, supposedly an input of nil returns all the properties more efficiently.
    // It isn't clear what is supposed to happen for to-many relationships.  We'll implement this to return a full dictionary in all cases, using a special dictionary class.
    
    NSArray *snapshot = [_editingContext _committedPropertySnapshotForObjectID:_objectID];
    if (!snapshot)
        snapshot = [self _createPropertySnapshot];
    
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

#if 0 && defined(DEBUG)
    #define DEBUG_DERIVED(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_DERIVED(format, ...)
#endif

+ (NSSet *)derivedPropertyNameSet;
{
    return [NSSet set];
}

typedef struct {
    ODOObject *self;
    NSSet *derivedPropertyNameSet;
    BOOL interesting;
} HasInterestingChangeApplierContext;

static void _hasInterestingChangeApplier(const void *key, const void *value, void *context)
{
    HasInterestingChangeApplierContext *ctx = (HasInterestingChangeApplierContext *)context;
    if ([ctx->derivedPropertyNameSet member:(id)key] == nil) {
        DEBUG_DERIVED(@"%@ has interesting change to %@", OBShortObjectDescription(ctx->self), key);
        ctx->interesting = YES;
    }
}

// Checks if there are any entries in the changed values that are not in the derived properties.
- (BOOL)changedNonDerivedChangedValue;
{
    NSDictionary *changedValues = [self changedValues];
    if (!changedValues)
        return NO;
    
    // Trival out if we've seen an interesting to-many change
    if (_flags.hasChangedInterestingToManyRelationshipSinceLastSave)
        return YES;
    
    HasInterestingChangeApplierContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.self = self;
    ctx.derivedPropertyNameSet = [[self class] derivedPropertyNameSet];
    ctx.interesting = NO;
    CFDictionaryApplyFunction((CFDictionaryRef)changedValues, _hasInterestingChangeApplier, &ctx);
    
    return ctx.interesting;
}


#pragma mark -
#pragma mark Debugging

- (NSString *)shortDescription;
{
    if (_flags.invalid)
        return [NSString stringWithFormat:@"<%@:%p INVALID>", NSStringFromClass([self class]), self];
    else
        return [NSString stringWithFormat:@"<%@:%p %@ %@>", NSStringFromClass([self class]), self, [[_objectID entity] name], [_objectID primaryKey]];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    
    if (_flags.invalid)
        return dict;

    [dict setObject:[_objectID shortDescription] forKey:@"objectID"];
    if (!_flags.isFault) {
        NSMutableDictionary *valueDict = [[NSMutableDictionary alloc] init];
        [dict setObject:valueDict forKey:@"values"];
        [valueDict release];
        
        NSArray *props = [[_objectID entity] snapshotProperties];
        unsigned int propIndex = [props count];
        while (propIndex--) {
            ODOProperty *prop = [props objectAtIndex:propIndex];
            
            unsigned snapshotIndex = ODOPropertySnapshotIndex(prop);
            id value = (id)CFArrayGetValueAtIndex(_valueArray, snapshotIndex);
            if (!value)
                value = [NSNull null];
            else if ([value isKindOfClass:[NSSet class]])
                value = [value valueForKey:@"shortDescription"];
            else if ([value isKindOfClass:[ODOObject class]])
                value = [value shortDescription];
            
            [valueDict setObject:value forKey:[prop name]];
        }
    }
    
    return dict;
}

BOOL ODOSetPropertyIfChanged(ODOObject *object, NSString *key, id value, id *outOldValue)
{
    id oldValue = [object valueForKey:key];
    
    if (outOldValue)
        *outOldValue = [[oldValue retain] autorelease];
    
    if (OFISEQUAL(value, oldValue))
        return NO;
    
    [object setValue:value forKey:key];
    return YES;
}

// Will never set nil.  Considers nil different from zero (i.e., setting zero on something that has nil will set a zero number)
BOOL ODOSetUnsignedIntPropertyIfChanged(ODOObject *object, NSString *key, unsigned int value, unsigned int *outOldValue)
{
    NSNumber *oldNumber = [object valueForKey:key];
    
    if (outOldValue)
        *outOldValue = [oldNumber unsignedIntValue];
    
    // Don't silently leave nil when zero was set.
    if (oldNumber && ([oldNumber unsignedIntValue] == value))
        return NO;
    
    [object setValue:[NSNumber numberWithUnsignedInt:value] forKey:key];
    return YES;
}

static id _ODOGetPrimitiveProperty(ODOObject *object, ODOProperty *property, NSString *key)
{
    [object willAccessValueForKey:key];
    id value = [object primitiveValueForProperty:property];
    [object didAccessValueForKey:key];
    return value;
}

id ODOGetPrimitiveProperty(ODOObject *object, NSString *key)
{
    ODOProperty *prop = [[object entity] propertyNamed:key];
    return _ODOGetPrimitiveProperty(object, prop, key);
}


BOOL ODOSetPrimitivePropertyIfChanged(ODOObject *object, NSString *key, id value, id *outOldValue)
{
    ODOProperty *prop = [[object entity] propertyNamed:key];
    id oldValue = _ODOGetPrimitiveProperty(object, prop, key);
    
    if (outOldValue)
        *outOldValue = [[oldValue retain] autorelease];
    
    if (OFISEQUAL(value, oldValue))
        return NO;
    
    [object willChangeValueForKey:key];
    [object setPrimitiveValue:value forProperty:prop];
    [object didChangeValueForKey:key];
    return YES;
}

@end
