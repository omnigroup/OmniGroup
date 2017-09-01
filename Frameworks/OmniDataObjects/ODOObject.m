// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
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

#import <OmniBase/objc.h>

#import <OmniFoundation/NSArray-OFExtensions.h>

#import "ODOEntity-Internal.h"
#import "ODOObject-Accessors.h"
#import "ODOObject-Internal.h"
#import "ODOEditingContext-Internal.h"
#import "ODODatabase-Internal.h"
#import "ODOProperty-Internal.h"
#import "ODOInternal.h"

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation ODOObject

+ (BOOL)objectIDShouldBeUndeletable:(ODOObjectID *)objectID;
{
    return NO;
}

+ (BOOL)shouldIncludeSnapshotForTransientCalculatedProperty:(ODOProperty *)property;
{
    return YES;
}

+ (ODOEntity *)entity;
{
    ODOEntity *entity = [ODOModel entityForClass:self];
    OBASSERT(entity != nil);
    if (entity == nil) {
        NSDictionary *userInfo = @{
            @"class": self,
        };
        NSString *reason = [NSString stringWithFormat:@"Couldn't find the entity represented by the implementation class \"%@\"", NSStringFromClass(self)];
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:reason userInfo:userInfo];
    }
    return entity;
}

+ (NSString *)entityName;
{
    return [self entity].name;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key;
{
    ODOEntity *entity = [ODOModel entityForClass:self];
    if (entity != nil && entity.propertiesByName[key] != nil) {
        // ODO sends manual notifications when setting the primitive value. Overridden/dynamic accessors should not do automatic notification.
        return NO;
    }
    
    return [super automaticallyNotifiesObserversForKey:key];
}

- (instancetype)init NS_UNAVAILABLE;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (instancetype)initWithEntity:(ODOEntity *)entity primaryKey:(nullable id)primaryKey insertingIntoEditingContext:(ODOEditingContext *)context;
{
    OBPRECONDITION(entity != nil);
    OBPRECONDITION(context != nil);
    OBPRECONDITION([entity instanceClass] == [self class]);
    OBPRECONDITION(primaryKey == nil || [primaryKey isKindOfClass:[[entity primaryKeyAttribute] valueClass]]);
    
    if (primaryKey == nil) {
        primaryKey = [context.database _generatePrimaryKeyForEntity:entity];
    }
    
    ODOObjectID *objectID = [[ODOObjectID alloc] initWithEntity:entity primaryKey:primaryKey];
    self = [self initWithEditingContext:context objectID:objectID isFault:NO];
    [objectID release];
    
    // Record whether this should be undeletable. This only gets called
    self->_flags.undeletable = [[self class] objectIDShouldBeUndeletable:objectID];
    
    [context insertObject:self];
    
    return self;
}

- (instancetype)initWithContext:(ODOEditingContext *)context;
{
    return [self initWithContext:context primaryKey:nil];
}

- (instancetype)initWithContext:(ODOEditingContext *)context primaryKey:(nullable id)primaryKey;
{
    ODOEntity *entity = [context.database.model entityForClass:[self class]];
    OBASSERT(entity != nil);
    if (entity == nil) {
        return nil;
    }
    
    return [self initWithEntity:entity primaryKey:primaryKey insertingIntoEditingContext:context];
}

- (instancetype)initWithEditingContext:(ODOEditingContext *)context objectID:(ODOObjectID *)objectID isFault:(BOOL)isFault;
{
    OBPRECONDITION(context);
    OBPRECONDITION(objectID);
    OBPRECONDITION(ODO_OBJECT_LAZY_TO_MANY_FAULT_MARKER == nil); // since we use calloc to start our _values
    
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _editingContext = [context retain];
    _objectID = [objectID copy];
    _flags.isFault = isFault;
    _flags.undeletable = [[self class] objectIDShouldBeUndeletable:objectID];
    
    // Only create values up front if we aren't a fault
    if (_flags.isFault == NO) {
        _ODOObjectCreateNullValues(self);
    }
    
    return self;
}

- (instancetype)initWithEditingContext:(ODOEditingContext *)context objectID:(ODOObjectID *)objectID snapshot:(CFArrayRef)snapshot;
{
    OBPRECONDITION(context);
    OBPRECONDITION(objectID);
    OBPRECONDITION(ODO_OBJECT_LAZY_TO_MANY_FAULT_MARKER == nil); // since we use calloc to start our _values
    OBPRECONDITION(snapshot);
    OBPRECONDITION((CFIndex)[[[objectID entity] snapshotProperties] count] == CFArrayGetCount(snapshot));
    
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    _editingContext = [context retain];
    _objectID = [objectID copy];
    _flags.isFault = NO;
    _flags.undeletable = [[self class] objectIDShouldBeUndeletable:objectID];
    
    _ODOObjectCreateValuesFromSnapshot(self, snapshot);
    
    return self;
}

- (void)dealloc;
{
    // For now, ODOEditingContext holds onto us until it is reset and we are made invalid.
    OBPRECONDITION(_editingContext == nil);
    OBPRECONDITION(_flags.invalid == YES);
    OBPRECONDITION(!_ODOObjectHasValues(self));

    OBPRECONDITION(_objectID != nil); // This doesn't get cleared when the object is invalidated.  Notification listeners need to know the entity/pk of deleted objects.
    OBPRECONDITION(_keysForPropertiesBeingCalculated == nil);

    _ODOObjectReleaseValuesIfPresent(self); // Just in case

    [_editingContext release];
    [_objectID release];
    [_keysForPropertiesBeingCalculated release];
    
    [super dealloc];
}

// This *mostly* works, but we discovered a problem where the dynamically generated KVO subclasses (NSKVONotifying_*) could get asked to resolve a method (if the getter/setter method had never been invoked before being observed).  In this case, we would correctly add the method on the real class, but the method resolution wouldn't restart and would fail to note our new addition on the superclass and would instead call -doesNotRecognizeSelector:.  See ODOObjectCreateDynamicAccessorsForEntity(), where we force register all @dynamic property methods at model creation time for now.
#if LAZY_DYNAMIC_ACCESSORS
// The vastly common case is that a single model is loaded once and never released.  Additionally, we assume that there is a 1-1 mapping between entities and instance classes AND that only 'leaf' classes are instance classes for an entity.  This won't satisfy everyone, but it should be the common case.  I'm not a big fan of making this assumption, but otherwise we're kinda screwed for @dynamic properties here.  I'm not sure which cases CoreData handles...
+ (BOOL)resolveInstanceMethod:(SEL)sel;
{
    OBFinishPorting; // If this does get re-enabled, it'll need to be checked vs updates in ODOObjectCreateDynamicAccessorsForEntity()
    
    DEBUG_DYNAMIC_METHODS(@"+[%s %s] %s", class_getName(self), sel_getName(_cmd), sel_getName(sel));
    
    ODOEntity *entity = [ODOModel entityForClass:self];
    if (entity == nil) {
        DEBUG_DYNAMIC_METHODS(@"  no entity");
        goto not_handled;
    }
    
    if ([entity instanceClass] != self) {
        DEBUG_DYNAMIC_METHODS(@"  %s isn't the instance class of %s", class_getName(self), class_getName([entity instanceClass])); // Likely we are the NSKVONotifying subclass automatically created.  Call super, which should be the real class.
        goto not_handled;
    }
    
    // TODO: Verify that the property in class_copyPropertyList for each prop has the right attributes.  Should be an object, copy and dynamic. See implement of ODOObjectCreateDynamicAccessorsForEntity and factor out validation logic.
    ODOProperty *prop = nil;
    
    prop = [entity propertyWithGetter:sel];
    if (prop != nil) {
        IMP imp = (IMP)ODOGetterForProperty(prop);
        const char *signature = ODOGetterSignatureForProperty(prop);
        DEBUG_DYNAMIC_METHODS(@"  Adding -[%@ %@] with %p %s", NSStringFromClass(self), NSStringFromSelector(sel), imp, signature);
        class_addMethod(self, sel, imp, signature);
        return YES;
    }
    
    prop = [entity propertyWithSetter:sel];
    if (prop != nil) {
        IMP imp = (IMP)ODOSetterForProperty(prop);
        const char *signature = ODOSetterSignatureForProperty(prop);
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
- (void)willAccessValueForKey:(nullable NSString *)key;
{
    ODOObjectWillAccessValueForKey(self, key);
}

- (void)didAccessValueForKey:(NSString *)key;
{
#ifdef OMNI_ASSERTIONS_ON
    // See commentary in __inline_ODOObjectWillAccessValueForKey()
    if (key != nil && ![key isEqualToString:_objectID.entity.primaryKeyAttribute.name]) {
        OBPRECONDITION(![self isDeleted] || [_editingContext _isBeingDeleted:self]);
    }
#endif
    
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
    if (!self->_flags.changeProcessingDisabled) {
        // If we are in -awakeFromFetch and mutate our properties, we shouldn't publish KVO since we aren't really changing, just getting set up.
        OBASSERT(!self->_flags.needsAwakeFromFetch, "We shouldn't be in -awakeFromFetch");
        [super willChangeValueForKey:key];
    }
}

#ifdef OMNI_ASSERTIONS_ON
- (void)didChangeValueForKey:(NSString *)key;
{
    if ([[self->_objectID entity] propertyNamed:key])
        OBASSERT(!_flags.isFault); // Cleared in 'will'
    if (!self->_flags.changeProcessingDisabled) {
        // If we are in -awakeFromFetch and mutate our properties, we shouldn't publish KVO since we aren't really changing, just getting set up.
        OBASSERT(!self->_flags.needsAwakeFromFetch, "We shouldn't be in -awakeFromFetch");
        [super didChangeValueForKey:key];
    }
}
#endif    

// Even if the only change to an object is to a to-many, it needs to be marked updated so it will get notified on save and so it will be included in the updated object set when ODOEditingContext processes changes or saves.
- (void)willChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)inMutationKind usingObjects:(NSSet *)inObjects;
{
    OBPRECONDITION(self->_flags.changeProcessingDisabled == NO, "Do we need to handle the case of mutations in -awakeFromFetch here too?");
    
    ODOProperty *prop = [[self entity] propertyNamed:key];

    // These get called as we update inverse to-many relationships due to edits to to-one relationships.  ODO doesn't snapshot to-many relationships in -changedValues, so we track this here.  This adds one more reason that undo/redo needs to provide correct KVO notifiactions.
    if (prop != nil && !_flags.hasChangedModifyingToManyRelationshipSinceLastSave) {
        
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

    if (prop != nil) {
        ODOObjectWillChangeValueForProperty(self, prop, key);
    }
    
    [super willChangeValueForKey:key withSetMutation:inMutationKind usingObjects:inObjects];
}

#ifdef OMNI_ASSERTIONS_ON
- (void)didChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)inMutationKind usingObjects:(NSSet *)inObjects;
{
    OBPRECONDITION(self->_flags.changeProcessingDisabled == NO, "Do we need to handle the case of mutations in -awakeFromFetch here too?");

    if ([[self->_objectID entity] propertyNamed:key])
        OBASSERT(!_flags.isFault); // Cleared in 'will'
    [super didChangeValueForKey:key withSetMutation:inMutationKind usingObjects:inObjects];
}
#endif    


- (void)setObservationInfo:(nullable void *)inObservationInfo;
{
    _observationInfo = inObservationInfo;
}

- (nullable void *)observationInfo;
{
    return _observationInfo;
}

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(nullable void *)context;
{
    OBPRECONDITION(self->_flags.changeProcessingDisabled == NO, "Adding an observer when changeProcessingDisabled. willChangeValueForKey:/didChangeValueForKey: may not fire.");

    // If this is a leaf key path associated with a transient + calculated property, calculate it now if needed.
    
    ODOEntity *entity = self.entity; // TODO: Disallow subclassing -entity via setup check.  Then inline it here.
    if ([entity.calculatedTransientPropertyNameSet containsObject:keyPath]) {
        ODOProperty *prop = [entity propertyNamed:keyPath];
        id value = ODOObjectPrimitiveValueForProperty(self, prop);
        if (value == nil) {
            value = [self calculateValueForKey:keyPath];
            ODOObjectSetPrimitiveValueForProperty(self, value, prop);
        }
    }

    [super addObserver:observer forKeyPath:keyPath options:options context:context];
}

- (nullable id)primitiveValueForKey:(NSString *)key;
{
    ODOEntity *entity = [self entity]; // TODO: Disallow subclassing -entity via setup check.  Then inline it here.
    ODOProperty *prop = [entity propertyNamed:key];
    OBASSERT(prop); // shouldn't ask for non-model properties via this interface
    
    return ODOObjectPrimitiveValueForProperty(self, prop);
}

- (void)setPrimitiveValue:(nullable id)value forKey:(NSString *)key;
{
    ODOProperty *prop = [[self->_objectID entity] propertyNamed:key];
    OBASSERT(prop); // shouldn't ask for non-model properties via this interface
    ODOObjectSetPrimitiveValueForProperty(self, value, prop);
}

- (nullable id)calculateValueForKey:(NSString *)key;
{
    OBPRECONDITION(key.length > 0);
    
    NSString *selectorString = [NSString stringWithFormat:@"calculateValueFor%@%@", [key substringToIndex:1].capitalizedString, [key substringFromIndex:1]];
    SEL selector = NSSelectorFromString(selectorString);

    if ([self respondsToSelector:selector]) {
        return OBSendObjectReturnMessage(self, selector);
    }
    
    OBASSERT_NOT_REACHED("Unhandled value for key: %@ and/or missing implementation of -%@.", key, selectorString);
    return nil;
}

- (void)invalidateCalculatedValueForKey:(NSString *)key;
{
    OBPRECONDITION(![self isDeleted]);
    if ([self isDeleted]) {
        return;
    }
    
    ODOProperty *prop = [[_objectID entity] propertyNamed:key];

#ifdef OMNI_ASSERTIONS_ON
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    OBASSERT(!flags.relationship && flags.transient && flags.calculated);
#endif
    
    id value = [self calculateValueForKey:key];
    if (value != nil) {
        [self _setIsCalculatingValueForKey:key];

        [self willChangeValueForKey:key];
        ODOObjectSetPrimitiveValueForProperty(self, value, prop);
        [self didChangeValueForKey:key];
        
        [self _clearIsCalculatingValueForKey:key];
    }
}

- (nullable id)valueForKey:(NSString *)key;
{
    ODOProperty *prop = [[_objectID entity] propertyNamed:key];
    if (prop == nil) {
        return [super valueForKey:key];
    }

    IMP getter = ODOPropertyGetterImpl(prop);
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    
    // Avoid looking up the property again.
    if (getter == (IMP)ODOGetterForUnknownOffset) {
        return ODODynamicValueForProperty(self, prop);
    }
    
    if (!flags.relationship && flags.scalarAccessors) {
        // Make sure we go through the user-defined getter, if appropriate
        return ODOGetScalarValueForProperty(self, prop);
    }

    SEL sel = ODOPropertyGetterSelector(prop);
    return OBCallObjectReturnIMP(getter, self, sel);
}

- (void)setValue:(nullable id)value forKey:(NSString *)key;
{
    ODOProperty *prop = [[self->_objectID entity] propertyNamed:key];
    if (prop == nil) {
        [super setValue:value forKey:key];
        return;
    }

    // We only prevent write access via the generic KVC method for now.  The issue is that we want to allow a class to redefined a property as writable internally if it wants, so it should be able to use 'self.foo = value' (going through the dynamic or any self-defined method). But subclasses could still -setValue:forKey: and get away with it w/o a warning. This does prevent the class itself from using generic KVC, but hopefully that is rare enough for this to be a good tradeoff.
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    if (flags.calculated) {
        OBRejectInvalidCall(self, _cmd, @"Attempt to -setValue:forKey: on the calculated key '%@'.", key);
    }
    
    IMP setter = ODOPropertySetterImpl(prop);
    SEL sel = ODOPropertySetterSelector(prop);
    if (setter == nil) {
        // We have a property but no setter; presumably it is read-only.
        [self doesNotRecognizeSelector:sel];
        OBAnalyzerNotReached(); // <http://llvm.org/bugs/show_bug.cgi?id=9486> -doesNotRecognizeSelector: not flagged as being "no return"
    }
    
    // Avoid looking up the property again
    if (setter == (IMP)ODOSetterForUnknownOffset) {
        ODODynamicSetValueForProperty(self, sel, prop, value);
    } else if (!flags.relationship && flags.scalarAccessors) {
        // Make sure we go through the user-defined setter, if appropriate
        ODOSetScalarValueForProperty(self, prop, value);
    } else {
        OBCallVoidIMPWithObject(setter, self, sel, value);
    }
}

// Subclasses should call this before doing anything in their own implementation, otherwise, this might override any setup they do.
- (void)setDefaultAttributeValues;
{
    ODOEntity *entity = self.entity;
    NSArray <ODOAttribute *> *attributes = entity.snapshotAttributes;

    // Send all the -willChangeValueForKey: notifications, change all the values, then send all the -didChangeValueForKey: notifications.
    // This is necessary because side effects of -didChangeValueForKey: may cause reading of properties which don't have a default value yet. We expect to have default values for required scalars, and must ensure that they are set before they are accessed.
    
    [attributes enumerateObjectsWithOptions:0 usingBlock:^(ODOAttribute *attr, NSUInteger index, BOOL *stop){
        [self willChangeValueForKey:attr.name];
    }];

    [attributes enumerateObjectsWithOptions:0 usingBlock:^(ODOAttribute *attr, NSUInteger index, BOOL *stop){
        // Model loading code ensures that the primary key attribute doesn't have a default value
        // Set this even if the default value is nil in case we are re-establishing default values

        BOOL isTransientCalculated = [attr isTransient] && [attr isCalculated];
        
        if (isTransientCalculated) {
            // When setting the default value, avoid calculating the value when ODOObjectSetPrimitiveValueForProperty queries the previous value.
            [self _setIsCalculatingValueForKey:attr.name];
        }

        ODOObjectSetPrimitiveValueForProperty(self, attr.defaultValue, attr); // Bypass this and set the primitive value to avoid and setter.

        if (isTransientCalculated) {
            [self _clearIsCalculatingValueForKey:attr.name];
        }
    }];

    [attributes enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(ODOAttribute *attr, NSUInteger index, BOOL *stop){
        [self didChangeValueForKey:attr.name];
    }];
}

- (BOOL)isAwakingFromInsert;
{
    return _flags.isAwakingFromInsert;
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

- (BOOL)isAwakingFromFetch;
{
    return _flags.isAwakingFromFetch;
}

- (void)awakeFromFetch;
{
    OBPRECONDITION(_flags.changeProcessingDisabled); // set by ODOObjectAwakeFromFetchWithoutRegisteringEdits
    OBPRECONDITION(!_flags.isFault);
    OBPRECONDITION(_flags.isAwakingFromFetch);
    
    // Nothing for us to do, I think; for subclasses
}

// This is in OmniDataObjects so that model classes can call it on super w/o worring about whether they are the base class.  ODO doesn't itself support unarchiving, but this is a convenient place to put a generic awake method that is agnostic about the unarchiving strategy.  For example, and XML-base archiving might call a more complex method that does something specific to that archiver type and then call this generic method.

- (BOOL)isAwakingFromUnarchive;
{
    return _flags.isAwakingFromUnarchive;
}

- (void)awakeFromUnarchive;
{
    // Nothing; for model classes
}

- (void)didAwakeFromFetch;
{
    OBPRECONDITION(!_flags.changeProcessingDisabled); // set by ODOObjectAwakeFromFetchWithoutRegisteringEdits
    OBPRECONDITION(!_flags.isFault);
    OBPRECONDITION(!_flags.isAwakingFromFetch);

    // Nothing for us to do; for subclasses to add observers after change processing (re)enabled
}

- (BOOL)isAwakingFromReinsertionAfterUndoneDeletion;
{
    return _flags.isAwakingFromReinsertionAfterUndoneDeletion;
}

- (void)awakeFromReinsertionAfterUndoneDeletion;
{
    OBPRECONDITION(_flags.isAwakingFromReinsertionAfterUndoneDeletion);
    
    // Nothing for us to do; for subclasses
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
    _flags.hasChangedModifyingToManyRelationshipSinceLastSave = NO;
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
                if (outError != NULL)
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

- (BOOL)isFault;
{
    return _flags.isFault;
}

- (void)willTurnIntoFault;
{
    // Nothing; for subclasses
}

- (void)didTurnIntoFault;
{
    // Nothing; for subclasses
}

- (void)turnIntoFault;
{
    // The underlying code gets called when deleting objects, but the public API should only be called on saved objects.
    OBPRECONDITION(![self isInserted]);
    OBPRECONDITION(![self isUpdated]);
    OBPRECONDITION(![self isDeleted]);
    
    [self _turnIntoFault:NO/*deleting*/];
}

- (BOOL)hasFaultForRelationship:(ODORelationship *)relationship;
{
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);
    OBPRECONDITION(relationship.entity == self.entity);
    OBPRECONDITION([relationship isKindOfClass:[ODORelationship class]]);
    
    struct _ODOPropertyFlags flags = ODOPropertyFlags(relationship);
    OBASSERT(flags.relationship);
    if (!flags.relationship) {
        return NO;
    }
    
    if (flags.toMany) {
        return ODOObjectToManyRelationshipIsFault(self, relationship);
    }
    
    id value = _ODOObjectValueAtIndex(self, flags.snapshotIndex); // to-ones are stored as the primary key if they are lazy faults
    if (value && ![value isKindOfClass:[ODOObject class]]) {
        OBASSERT([value isKindOfClass:relationship.destinationEntity.primaryKeyAttribute.valueClass]);
        return YES;
    }
    
    return [value isFault];
}

- (BOOL)hasFaultForRelationshipNamed:(NSString *)key; 
{
    ODORelationship *relationship = self.entity.relationshipsByName[key];
    OBASSERT(relationship != nil);
    if (relationship == nil) {
        return NO;
    }
    
    return [self hasFaultForRelationship:relationship];
}

// Handle the check w/o causing lazy faults to be materialized.
- (BOOL)toOneRelationship:(ODORelationship *)relationship isToObject:(ODOObject *)destinationObject;
{
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);
    OBPRECONDITION(!destinationObject || [destinationObject editingContext] == _editingContext);
    OBPRECONDITION([relationship entity] == [self entity]);
    OBPRECONDITION([relationship isKindOfClass:[ODORelationship class]]);
    OBPRECONDITION(![relationship isToMany]);
    
    struct _ODOPropertyFlags flags = ODOPropertyFlags(relationship);
    OBASSERT(flags.relationship);
    if (!flags.relationship || flags.toMany) {
        return NO;
    }
    
    id value = _ODOObjectValueAtIndex(self, flags.snapshotIndex); // to-ones are stored as the primary key if they are lazy faults
    
    // Several early-outs could be done here if it turns out to be useful; not doing them for now.
    
    id actualKey = [value isKindOfClass:[ODOObject class]] ? [[value objectID] primaryKey] : value;
    id queryKey = destinationObject.objectID.primaryKey;
    
    OBASSERT(!actualKey || [actualKey isKindOfClass:relationship.destinationEntity.primaryKeyAttribute.valueClass]);
    OBASSERT(!queryKey || [queryKey isKindOfClass:relationship.destinationEntity.primaryKeyAttribute.valueClass]);
    
    return OFISEQUAL(actualKey, queryKey);
}

- (void)willNullifyRelationships:(NSSet<ODORelationship *> *)relationships;
{
    // For subclasses
}

- (void)didNullifyRelationships:(NSSet<ODORelationship *> *)relationships;
{
    // For subclasses
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
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);
    
    if ([self isInserted]) {
        // Return YES if we have a value for this key ("changed" from nil). Might be better to snapshot after -awakeFromInsert, but it would be nice to avoid that.
        return ([self valueForKey:key] != nil);
    }
    
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
    
    id oldValue = [snapshot objectAtIndex:snapshotIndex];
    
    [self willAccessValueForKey:key];
    id newValue = ODOObjectPrimitiveValueForProperty(self, prop);
    [self didAccessValueForKey:key];
    
    if ([prop isKindOfClass:[ODORelationship class]]) {
        ODORelationship *rel = (ODORelationship *)prop;
        if ([rel isToMany]) {
            // We are going to avoid mutating/clearing to-many relationships when an inverse to-one is updated.  So, we won't have a good way to do this w/o a bunch of extra work.  Let's not until we need to.
            OBRequestConcreteImplementation(self, _cmd);
        } else {
            if (oldValue != nil && ![oldValue isKindOfClass:[ODOObject class]]) {
                OBASSERT([oldValue isKindOfClass:[[[rel destinationEntity] primaryKeyAttribute] valueClass]]);
                id oldPrimaryKey = oldValue;
                id newPrimaryKey = [newValue valueForKey:[[[rel destinationEntity] primaryKeyAttribute] name]];
                return OFNOTEQUAL(oldPrimaryKey, newPrimaryKey);
            }
            
            // fall through
        }
    }
    
    return OFNOTEQUAL(oldValue, newValue);
}

/*
 CoreData sez: "Returns a dictionary containing the keys and (new) values of persistent properties that have been changed since last fetching or saving the receiver." and "Note that this method only reports changes to properties that are defined as persistent properties of the receiver, not changes to transient properties or custom instance variables. This method does not unnecessarily fire relationship faults."
 
 We can emulate the non-transient changes for now, but we _are_ snapshotting them for undo so there is no reason not to return them.
 
 */
- (nullable NSDictionary *)changedValues;
{
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);

    // CoreData's version doesn't return changes to transient attributes.  Their documentation isn't clear as to what happens for inserted objects -- are all the values changed?  None?
    // CoreData's version mentions something about not firing faults -- unclear if we can deal with faults.
    
    NSArray *snapshot = [_editingContext _committedPropertySnapshotForObjectID:_objectID];
    if (!snapshot) {
        if ([self isInserted]) {
            // Does inserting mean all the values are changed or none? We'll fall through and report all values as changes (or at least if they are different from nil).
        } else {
            OBASSERT(![self isUpdated]);
            OBASSERT(![self isDeleted]);
            
            return nil;
        }
    }
    
    NSArray *snapshotProperties = [[_objectID entity] snapshotProperties];
    NSUInteger propIndex = [snapshotProperties count];
    
    // The dictionary we return will have a short lifetime and we want to avoid time spent re-hashing as the dictionary grows (particularly for inserts where we report all the properties as changed). Maybe we should stop doing that...

    NSMutableDictionary *changes = [NSMutableDictionary dictionaryWithCapacity:propIndex];
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
            
            // For to-one relationships, the internal value could be a raw primary key value or a fault.  Upscale to faults if we only have pks.  New values really shouldn't be pks (unless we're undoing), but even if they are, fall back on -primitiveValueForProperty: to get a real value instead of (presumably) the pk.
            if (newValue && ![newValue isKindOfClass:[ODOObject class]]) {
                newValue = ODOObjectPrimitiveValueForProperty(self, prop);
            }

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

        // Checking for OFISNULL ought to be good enough, but without the additional nil check the static analyzer warns:
        //    ODOObject.m:904:9: Value argument to 'setObject:forKey:' cannot be nil
        if (newValue == nil || OFISNULL(newValue))
            newValue = [NSNull null];
        
        [changes setObject:newValue forKey:[prop name]];
    }
    
    return changes;
}

- (nullable NSDictionary *)changedNonDerivedValues;
{
    NSDictionary *changedValues = [self changedValues];
    if ([changedValues count] == 0) {
        return changedValues;
    }
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    NSSet *derivedPropertyNameSet = [[self entity] derivedPropertyNameSet];
    for (NSString *key in changedValues) {
        if (![derivedPropertyNameSet member:key]) {
            result[key] = changedValues[key];
        }
    }
    
    return result;
}

- (nullable id)lastProcessedValueForKey:(NSString *)key;
{
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);
    
    NSArray *snapshot = [_editingContext _lastProcessedPropertySnapshotForObjectID:_objectID];
    if (snapshot == nil && ![self isInserted]) {
        snapshot = [_editingContext _committedPropertySnapshotForObjectID:_objectID];
    }
    
    OBASSERT_NOTNULL(snapshot);
    
    return ODOObjectSnapshotValueForKey(self, _editingContext, snapshot, key, NULL);
}

- (nullable id)committedValueForKey:(NSString *)key;
{
    OBPRECONDITION(_editingContext);
    OBPRECONDITION(!_flags.invalid);

    return ODOObjectSnapshotValueForKey(self, _editingContext, [_editingContext _committedPropertySnapshotForObjectID:_objectID], key, NULL);
}

_Nullable id ODOObjectSnapshotValueForKey(ODOObject *self, ODOEditingContext *editingContext, NSArray *snapshot, NSString *key, _Nullable ODOObjectSnapshotFallbackLookupHandler fallbackLookupHandler)
{
    ODOProperty *prop = [[self.objectID entity] propertyNamed:key];
    if (prop == nil) {
        OBASSERT(prop);
        return nil;
    }

    // Not sure how to handle to-many properties.  So let's not until we need it
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    if (flags.relationship && flags.toMany) {
        OBASSERT_NOT_REACHED();
        NSString *reason = [NSString stringWithFormat:@"%s needs a concrete implementation at %s:%d", __PRETTY_FUNCTION__, __FILE__, __LINE__];
        @throw [NSException exceptionWithName:OBAbstractImplementation reason:reason userInfo:nil];
    }
    
    if (!snapshot) {
        // Inserted or never modified.  This may perform lazy creation on a fault.
        [self willAccessValueForKey:key];
        id value = ODOObjectPrimitiveValueForProperty(self, prop);
        [self didAccessValueForKey:key];
        return value;
    }
    
    id value = [snapshot objectAtIndex:flags.snapshotIndex];

    if (value != nil && flags.relationship && !flags.toMany) {
        if (![value isKindOfClass:[ODOObject class]]) {
            // Might be a lazy to-one fault.  Can't go through primitiveValueForKey: since we've been snapshotted and our current value obviously might differ from that in the snapshot.
            ODORelationship *rel = (ODORelationship *)prop;
            ODOEntity *destEntity = [rel destinationEntity];
            OBASSERT([value isKindOfClass:[[destEntity primaryKeyAttribute] valueClass]]);
            ODOObjectID *destID = [[ODOObjectID alloc] initWithEntity:destEntity primaryKey:value];
            
            value = [editingContext objectRegisteredForID:destID];
            // If the object has been deleted, we won't be able to look it up in the context.
            // In that case, use the fallback handler. An XMLExporter should be able to find the object for us.
            // That object is going to be deleted/invalidated, so we can't touch an ODOObject aspects of it, but it is still useful for XML exporting.
            if (value == nil && fallbackLookupHandler != NULL) {
                value = fallbackLookupHandler(destID);
            }
            
            OBASSERT(value != nil);
            [destID release];
        }
    }
    
    if (OFISNULL(value)) {
        value = nil;
    }
    
    return value;
}

#if 0
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
#endif

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
        if ([prop isTransient] || [prop isCalculated])
            [set addObject:prop.name];
}

// Checks if there are any entries in the changed values that are not in the derived properties.
- (BOOL)hasChangedNonDerivedChangedValue;
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
            if (value == nil) {
                value = [NSNull null];
            } else if ([value isKindOfClass:[NSSet class]]) {
                value = [value valueForKey:@"shortDescription"];
            } else if ([value isKindOfClass:[NSArray class]]) {
                value = [value valueForKey:@"shortDescription"];
            } else if ([value isKindOfClass:[ODOObject class]]) {
                value = [value shortDescription];
            }
            
            [valueDict setObject:value forKey:[prop name]];
        }
    }
    
    return dict;
}

BOOL ODOSetPropertyIfChanged(ODOObject *object, NSString *key, _Nullable id value, _Nullable id * _Nullable outOldValue)
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
BOOL ODOSetInt32PropertyIfChanged(ODOObject *object, NSString *key, int32_t value, int32_t * _Nullable outOldValue)
{
    NSNumber *oldNumber = [object valueForKey:key];
    
    if (outOldValue)
        *outOldValue = [oldNumber intValue];
    
    // Don't silently leave nil when zero was set.
    if (oldNumber && ([oldNumber intValue] == value))
        return NO;
    
    [object setValue:[NSNumber numberWithInt:value] forKey:key];
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


BOOL ODOSetPrimitivePropertyIfChanged(ODOObject *object, NSString *key, _Nullable id value, _Nullable id * _Nullable outOldValue)
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

NS_ASSUME_NONNULL_END
