// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOObject.h>

#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODOModel.h>

#import "ODOEntity-Internal.h"
#import "ODOObject-Accessors.h"
#import "ODOObject-Internal.h"
#import "ODOEditingContext-Internal.h"
#import "ODODatabase-Internal.h"
#import "ODOProperty-Internal.h"
#import "ODOInternal.h"

RCS_ID("$Id$")

NSString * const ODODetailedErrorsKey = @"ODODetailedErrorsKey";

@implementation ODOObject

+ (BOOL)objectIDShouldBeUndeletable:(ODOObjectID *)objectID;
{
    return NO;
}

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
    
    // Record whether this should be undeletable. This only gets called
    self->_flags.undeletable = [[self class] objectIDShouldBeUndeletable:objectID];
    
    return self;
}

- (void)dealloc;
{
    // For now, ODOEditingContext holds onto us until it is reset and we are made invalid.
    OBPRECONDITION(_editingContext == nil);
    OBPRECONDITION(_flags.invalid == YES);
    OBPRECONDITION(!_ODOObjectHasValues(self));

    OBPRECONDITION(_objectID != nil); // This doesn't get cleared when the object is invalidated.  Notification listeners need to know the entity/pk of deleted objects.

    _ODOObjectReleaseValuesIfPresent(self); // Just in case

    [_editingContext release];
    [_objectID release];
    
    [super dealloc];
}

// This *mostly* works, but we discovered a problem where the dynamically generated KVO subclasses (NSKVONotifying_*) could get asked to resolve a method (if the getter/setter method had never been invoked before being observed).  In this case, we would correctly add the method on the real class, but the method resolution wouldn't restart and would fail to note our new addition on the superclass and would instead call -doesNotRecognizeSelector:.  See ODOObjectCreateDynamicAccessorsForEntity(), where we force register all @dynamic property methods at model creation time for now.
#if LAZY_DYNAMIC_ACCESSORS
// The vastly common case is that a single model is loaded once and never released.  Additionally, we assume that there is a 1-1 mapping between entities and instance classes AND that only 'leaf' classes are instance classes for an entity.  This won't satisfy everyone, but it should be the common case.  I'm not a big fan of making this assumption, but otherwise we're kinda screwed for @dynamic properties here.  I'm not sure which cases CoreData handles...
+ (BOOL)resolveInstanceMethod:(SEL)sel;
{
    DEBUG_DYNAMIC_METHODS(@"+[%s %s] %s", class_getName(self), sel_getName(_cmd), sel_getName(sel));
    
    ODOEntity *entity = [ODOModel entityForClass:self];
    if (!entity) {
        DEBUG_DYNAMIC_METHODS(@"  no entity");
        goto not_handled;
    }
    
    if ([entity instanceClass] != self) {
        DEBUG_DYNAMIC_METHODS(@"  %s isn't the instance class of %s", class_getName(self), class_getName([entity instanceClass])); // Likely we are the NSKVONotifying subclass automatically created.  Call super, which should be the real class.
        goto not_handled;
    }
    
    // TODO: Verify that the property in class_copyPropertyList for each prop has the right attributes.  Should be an object, copy and dynamic.
    ODOProperty *prop;
    
    if ((prop = [entity propertyWithGetter:sel])) {
        IMP imp = (IMP)ODOGetterForProperty(prop);
        const char *signature = ODOObjectGetterSignature();
        DEBUG_DYNAMIC_METHODS(@"  Adding -[%@ %@] with %p %s", NSStringFromClass(self), NSStringFromSelector(sel), imp, signature);
        class_addMethod(self, sel, imp, signature);
        return YES;
    }
    if ((prop = [entity propertyWithSetter:sel])) {
        IMP imp = (IMP)ODOSetterForProperty(prop);
        const char *signature = ODOObjectSetterSignature();
        DEBUG_DYNAMIC_METHODS(@"  Adding -[%@ %@] with %p %s", NSStringFromClass(self), NSStringFromSelector(sel), imp, signature);
        class_addMethod(self, sel, imp, signature);
        return YES;
    }
    
    DEBUG_DYNAMIC_METHODS(@"  neither a getter nor setter");
    return NO;
    
not_handled:
    return [super resolveInstanceMethod:sel];
}
#endif

// Primarily for the benefit of subclasses.  Like CoreData, ODOObject won't guarantee this is called on every key access, but only if the object is a fault.
- (void)willAccessValueForKey:(NSString *)key;
{
    ODOObjectWillAccessValueForKey(self, key);
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
    if (prop && !_flags.hasChangedModifyingToManyRelationshipSinceLastSave) {
        
        // Only to-many relationship keys should go through here.
        OBASSERT([prop isKindOfClass:[ODORelationship class]]);
        OBASSERT([(ODORelationship *)prop isToMany]);
        
        if ([[[self entity] nonDateModifyingPropertyNameSet] member:[prop name]] == nil) {
            _flags.hasChangedModifyingToManyRelationshipSinceLastSave = YES;
#if 0 && defined(DEBUG_bungi)
            NSLog(@"Setting %@._hasChangedNonDerivedToManyRelationshipSinceLastSave for change to %@", [self shortDescription], [prop name]);
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
    ODOObjectSetPrimitiveValueForProperty(self, value, prop);
}

- (id)primitiveValueForKey:(NSString *)key;
{
    ODOEntity *entity = [self entity]; // TODO: Disallow subclassing -entity via setup check.  Then inline it here.
    ODOProperty *prop = [entity propertyNamed:key];
    OBASSERT(prop); // shouldn't ask for non-model properties via this interface
    
    return ODOObjectPrimitiveValueForProperty(self, prop);
}

- (id)valueForKey:(NSString *)key;
{
    ODOProperty *prop = [[_objectID entity] propertyNamed:key];
    if (!prop)
        return [super valueForKey:key];

    ODOPropertyGetter getter = ODOPropertyGetterImpl(prop);
    
    // Avoid looking up the property again
    if (getter == ODOGetterForUnknownOffset)
        return ODODynamicValueForProperty(self, prop);

    SEL sel = ODOPropertyGetterSelector(prop);
    return getter(self, sel);
}

- (void)setValue:(id)value forKey:(NSString *)key;
{
    ODOProperty *prop = [[self->_objectID entity] propertyNamed:key];
    if (!prop) {
        [super setValue:value forKey:key];
        return;
    }

    // We only prevent write access via the generic KVC method for now.  The issue is that we want to allow a class to redefined a property as writable internally if it wants, so it should be able to use 'self.foo = value' (going through the dynamic or any self-defined method). But subclasses could still -setValue:forKey: and get away with it w/o a warning. This does prevent the class itself from using generic KVC, but hopefully that is rare enough for this to be a good tradeoff.
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    if (flags.calculated)
        OBRejectInvalidCall(self, _cmd, @"Attempt to -setValue:forKey: on the calculated key '%@'.", key);
    
    ODOPropertySetter setter = ODOPropertySetterImpl(prop);
    SEL sel = ODOPropertySetterSelector(prop);
    if (!setter) {
        // We have a property but no setter; presumably it is read-only.
        [self doesNotRecognizeSelector:sel];
    }
    
    // Avoid looking up the property again
    if (setter == ODOSetterForUnknownOffset)
        ODODynamicSetValueForProperty(self, sel, prop, value);
    else
        setter(self, sel, value);
}

// Subclasses should call this before doing anything in their own implementation, otherwise, this might override any setup they do.
- (void)setDefaultAttributeValues;
{
    ODOEntity *entity = [self entity];
    for (ODOProperty *prop in entity.snapshotProperties) {
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        if (!flags.relationship) {
            // Model loading code ensures that the primary key attribute doesn't have a default value            
            ODOAttribute *attr = (ODOAttribute *)prop;
            NSString *key = [attr name];
            
            // Set this even if the default value is nil in case we are re-establishing default values
            [self willChangeValueForKey:key];
            ODOObjectSetPrimitiveValueForProperty(self, [attr defaultValue], attr); // Bypass this and set the primitive value to avoid and setter.
            [self didChangeValueForKey:key];
        }
    }
}

// Subclasses should call this before doing anything in their own implementation, otherwise, this might override any setup they do.
- (void)awakeFromInsert;
{
    [self setDefaultAttributeValues]; // Subclasses might override this
    
    // On insert, we also set the default relastionship values
    for (ODOProperty *prop in self.entity.snapshotProperties) {
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

// This is in OmniDataObjects so that model classes can call it on super w/o worring about whether they are the base class.  ODO doesn't itself support unarchiving, but this is a convenient place to put a generic awake method that is agnostic about the unarchiving strategy.  For example, and XML-base archiving might call a more complex method that does something specific to that archiver type and then call this generic method.
- (void)awakeFromUnarchive;
{
    
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
        ODOError(&ctx->error, ODOValueOfWrongClassValidationError, @"Cannot save.", reason);
        return;
    }
    
    // Check the entity too since the same class can be used for multiple entities.  We don't support entity inheritence, so we don't need -isKindOfEntity: here.
    if ([dest entity] != expectedEntity) {
        NSString *reason = [NSString stringWithFormat:@"Relationship '%@' of '%@' lead to object of entity '%@', but it should have been a '%@'", [ctx->relationship name], [ctx->owner shortDescription], [[dest entity] name], [expectedEntity name]];
        ODOError(&ctx->error, ODOValueOfWrongClassValidationError, @"Cannot save.", reason);
        return;
    }
}

- (BOOL)validateForSave:(NSError **)outError;
{
    for (ODOProperty *prop in self.entity.snapshotProperties) {
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        
        // Directly accessing the values rather than going through the will/did lookup.  We aren't "accessing" the values.
        id value = _ODOObjectValueAtIndex(self, flags.snapshotIndex);
        
        // Not localizing these validation errors right now.  OmniFocus expects users to never see these, and we don't have CoreData's human-readability mappings right now.
        
        // Check for required values in attributes and to-one relationships.  A nil in a to-many (currently) means it is an lazy to-many.  We aren't supporting required to-many relationships right now.
        if (!value && (!flags.relationship || !flags.toMany)) {
            if (!flags.optional) {
                ODOError(outError, ODORequiredValueNotPresentValidationError, @"Cannot save.", ([NSString stringWithFormat:@"Required property '%@' not set on '%@'.", [prop name], [self shortDescription]]));
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
                                 ([NSString stringWithFormat:@"Relationship '%@' of '%@' has primary key value of class '%@' instead of '%@'.", [ctx.relationship name], [self shortDescription], NSStringFromClass([value class]), NSStringFromClass(primaryKeyClass)]));
                        return NO;
                    }
                }
            }
            if (ctx.error) {
                if (outError)
                    *outError = ctx.error;
                return NO;
            }
        } else {
            if (value) {
                ODOAttribute *attr = (ODOAttribute *)prop;
                Class valueClass = [attr valueClass];
                if (![value isKindOfClass:valueClass]) {
                    ODOError(outError, ODOValueOfWrongClassValidationError, @"Cannot save.",
                             ([NSString stringWithFormat:@"Attribute '%@' of '%@' has value of class '%@' instead of '%@'.", [attr name], [self shortDescription], NSStringFromClass([value class]), NSStringFromClass(valueClass)]));
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
    
    id value = _ODOObjectValueAtIndex(self, flags.snapshotIndex); // to-ones are stored as the primary key if they are lazy faults
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
    
    id value = _ODOObjectValueAtIndex(self, flags.snapshotIndex); // to-ones are stored as the primary key if they are lazy faults
    
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

- (BOOL)isUndeletable;
{
    return _ODOObjectIsUndeletable(self);
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
    NSUInteger snapshotIndex = ODOPropertySnapshotIndex(prop);
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
    id newValue = ODOObjectPrimitiveValueForProperty(self, prop);
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
    NSUInteger propIndex = [snapshotProperties count];
    while (propIndex--) {
        ODOProperty *prop = [snapshotProperties objectAtIndex:propIndex];
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        OBASSERT(flags.snapshotIndex == propIndex);
        
        // CoreData doesn't return transient properties from this method.
        if (flags.transient)
            continue;
        
        id oldValue = [snapshot objectAtIndex:propIndex];
        id newValue = _ODOObjectValueAtIndex(self, propIndex);
        
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
        id value = ODOObjectPrimitiveValueForProperty(self, prop);
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
#if 0    
    NSArray *snapshot = [_editingContext _committedPropertySnapshotForObjectID:_objectID];
    if (!snapshot)
        snapshot = _ODOObjectCreatePropertySnapshot(self);
#endif
    
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

#if 0 && defined(DEBUG)
    #define DEBUG_CHANGE_SET(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_CHANGE_SET(format, ...) do {} while (0)
#endif

typedef struct {
    ODOObject *self;
    const char *caller;
    NSSet *ignoredPropertySet;
    BOOL hasChanged;
} HasChangedApplierContext;

static void _hasInterestingChangeApplier(const void *key, const void *value, void *context)
{
    HasChangedApplierContext *ctx = (HasChangedApplierContext *)context;
    if ([ctx->ignoredPropertySet member:(id)key] == nil) {
        DEBUG_CHANGE_SET(@"%@ will return YES to %s due to %@", [ctx->self shortDescription], ctx->caller, key);
        ctx->hasChanged = YES;
    }
}

static BOOL _changedPropertyNotInSet(ODOObject *self, NSSet *ignoredPropertySet, const char *caller)
{
    NSDictionary *changedValues = [self changedValues];
    if (!changedValues)
        return NO;
    
    HasChangedApplierContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.self = self;
    ctx.ignoredPropertySet = ignoredPropertySet;
    ctx.hasChanged = NO;
    ctx.caller = caller;
    CFDictionaryApplyFunction((CFDictionaryRef)changedValues, _hasInterestingChangeApplier, &ctx);
    
    return ctx.hasChanged;
}

+ (void)addDerivedPropertyNames:(NSMutableSet *)set withEntity:(ODOEntity *)entity;
{
    // Should add the names of properties that are totally derived from other state, but are cached in the database for performance. Since we don't support many-to-many relationships, to-manys are totally derived from the inverse to-one.
    for (ODORelationship *rel in entity.toManyRelationships)
        [set addObject:rel.name];
    
    for (ODOProperty *prop in entity.properties)
        if (prop.isTransient || prop.isCalculated)
            [set addObject:prop.name];
}

// Checks if there are any entries in the changed values that are not in the derived properties.
- (BOOL)changedNonDerivedChangedValue;
{
    NSSet *set = [[self entity] derivedPropertyNameSet];
    return _changedPropertyNotInSet(self, set, __PRETTY_FUNCTION__);
}

// Utility for subclasses that want to try a 'date modified' property.  Usually an object is considered 'modified' when it has any non-derived property changed.  Sometimes, though, we want to restrict this even further.  For exampe, we might decide that moving an object from one container to another changes the container but not the object itself.  The object's to-one relationship to its container is still non-derived, but we don't want to consider it a 'change' for the purposes of tracking any 'date modified'.
+ (void)computeNonDateModifyingPropertyNameSet:(NSMutableSet *)set withEntity:(ODOEntity *)entity;
{
    // Default to derived properties not causing modification date changes.
    [self addDerivedPropertyNames:set withEntity:entity];
}

- (BOOL)shouldChangeDateModified;
{
    // Trival out if we've seen an pertinent to-many change
    if (_flags.hasChangedModifyingToManyRelationshipSinceLastSave)
        return YES;
    
    NSSet *set = [[self entity] nonDateModifyingPropertyNameSet];
    return _changedPropertyNotInSet(self, set, __PRETTY_FUNCTION__);
}

#pragma mark -
#pragma mark Comparison

// Objects are uniqued w/in their editing context, so really we should be pointer equal. This presumes that we don't want the same object in two different editing contexts to be considered -isEqual:, which I think we don't.  The superclass should give us pointer equality anyway, but we'll make it official here as well as having assertions that these aren't subclassed in ODOEntity.

- (NSUInteger)hash;
{
    return [_objectID hash];
}

- (BOOL)isEqual:(id)object;
{
    // It is tempting to try to check that the other object is of the right class here, but we put ODOObjects into heterogeneous sets fairly often (recent/processed edits in ODOEditingContext, children-of-node in OmniFocus -- which can contain things that aren't even ODOObjects).
    return (self == object);
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
        for (ODOProperty *prop in props) {
            NSUInteger snapshotIndex = ODOPropertySnapshotIndex(prop);
            id value = _ODOObjectValueAtIndex(self, snapshotIndex);
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
BOOL ODOSetUInt32PropertyIfChanged(ODOObject *object, NSString *key, uint32_t value, uint32_t *outOldValue)
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
    id value = ODOObjectPrimitiveValueForProperty(object, property);
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
    ODOObjectSetPrimitiveValueForProperty(object, value, prop);
    [object didChangeValueForKey:key];
    return YES;
}

@end
