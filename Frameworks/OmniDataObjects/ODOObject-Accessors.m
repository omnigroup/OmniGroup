// Copyright 2008-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOObject-Accessors.h>

#import <OmniDataObjects/ODOEntity.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODOModel.h>

#import "ODOObject-Internal.h"
#import "ODOProperty-Internal.h"
#import "ODOEditingContext-Internal.h"
#import "ODOInternal.h"

RCS_ID("$Id$")

@interface ODOObject (Accessors)
@end
@implementation ODOObject (Accessors)
// Used for getting type signatures
- (id)_getter_signature;
{
    return nil;
}
- (void)_setter_signature:(id)arg;
{
}
@end

const char *ODOObjectGetterSignature(void)
{
    static const char *signature = NULL;
    if (!signature) {
        Method method = class_getInstanceMethod([ODOObject class], @selector(_getter_signature));
        signature = method_getTypeEncoding(method);
    }
    return signature;
}

const char *ODOObjectSetterSignature(void)
{
    static const char *signature = NULL;
    if (!signature) {
        Method method = class_getInstanceMethod([ODOObject class], @selector(_setter_signature:));
        signature = method_getTypeEncoding(method);
    }
    return signature;
}


// Pass a key of nil if you don't know or care what the key is and just want to clear the fault.  Right now we short circuit on the primary key attribute name.
static inline void __inline_ODOObjectWillAccessValueForKey(ODOObject *self, NSString *key)
{
#ifdef OMNI_ASSERTIONS_ON
    // We can always access the primary key. But, other properties we can't access once we are deleted. We let in-progress deletes look up properties here, though, so since -isDeleted returns YES for objects that are in the middle of deletion (so that triggering OFMLiveFetch updates won't return result sets with about-to-be-deleted objects). See r202914 with the fix for <bug:///98546> (Crash updating forecast/inbox badge after sync? -[HomeController _forecastCount])
    if ([key isEqualToString:self->_objectID.entity.primaryKeyAttribute.name] == NO) {
        OBPRECONDITION(![self isDeleted] || [self->_editingContext _isBeingDeleted:self]);
    }
#endif
    
    if (!self->_flags.invalid && self->_flags.isFault) {
        // Don't clear faults for the primary key
        if (![key isEqualToString:[[[self->_objectID entity] primaryKeyAttribute] name]])
            ODOFetchObjectFault(self->_editingContext, self);
    }
    
    // We might be part of a fetch result set that is still getting awoken.  If another object awaking tries to talk to us before we are awake, wake up early.  Note that circular awaking problems are still possible.
    if (self->_flags.needsAwakeFromFetch)
        ODOObjectPerformAwakeFromFetchWithoutRegisteringEdits(self);
}

void ODOObjectWillAccessValueForKey(ODOObject *self, NSString *key)
{
    __inline_ODOObjectWillAccessValueForKey(self, key);
}

// Can pass a relationship if you already know it, or nil if you don't.
static ODORelationship *_ODOLookupRelationshipBySnapshotIndex(ODOObject *self, NSUInteger snapshotIndex, BOOL toMany, ODORelationship *rel)
{
    OBPRECONDITION(!rel || [rel isKindOfClass:[ODORelationship class]]);
    OBPRECONDITION(!rel || ODOPropertySnapshotIndex(rel) == snapshotIndex);
    
    if (!rel) {
        // Caller needs us to look it up; not sure if this will be rare or not.
        rel = (ODORelationship *)[[self->_objectID entity] propertyWithSnapshotIndex:snapshotIndex];
        OBASSERT([rel isKindOfClass:[ODORelationship class]]);
        OBASSERT([rel isToMany] == toMany);
    }
    
    OBPOSTCONDITION([rel isKindOfClass:[ODORelationship class]]);
    OBPOSTCONDITION(ODOPropertySnapshotIndex(rel) == snapshotIndex);
    return rel;
}

// Can pass a relationship if you already know it, or nil if you don't.
static inline id _ODOObjectCheckForLazyToOneFaultCreation(ODOObject *self, id value, NSUInteger snapshotIndex, ODORelationship *rel)
{
    OBPRECONDITION(!rel || [rel isKindOfClass:[ODORelationship class]]);
    OBASSERT(!rel || [rel isToMany] == NO);
    
    if ([value isKindOfClass:[ODOObject class]]) {
#ifdef OMNI_ASSERTIONS_ON
        rel = _ODOLookupRelationshipBySnapshotIndex(self, snapshotIndex, NO/*toMany*/, rel);
        OBASSERT([value isKindOfClass:[[rel destinationEntity] instanceClass]]);
#endif
        // All good
    } else if (value) {
        rel = _ODOLookupRelationshipBySnapshotIndex(self, snapshotIndex, NO/*toMany*/, rel);
        OBASSERT([value isKindOfClass:[[[rel destinationEntity] primaryKeyAttribute] valueClass]]);
        
        // Lazily find or create a to-one fault based on the primary key stored in our snapshot.
        ODOEntity *destEntity = [rel destinationEntity];
        
        ODOObjectID *destID = [[ODOObjectID alloc] initWithEntity:destEntity primaryKey:value];
        value = ODOEditingContextLookupObjectOrRegisterFaultForObjectID(self->_editingContext, destID);
        [destID release];
        
        // Replace the pk with the real fault.
        _ODOObjectSetValueAtIndex(self, snapshotIndex, value);
    } else {
        // to-one to nil; just fine
    }
    return value;
}

static inline id _ODOObjectCheckForLazyToManyFaultCreation(ODOObject *self, id value, NSUInteger snapshotIndex, ODORelationship *rel)
{
    if (ODOObjectValueIsLazyToManyFault(value)) {
        // When asking for the to-many relationship the first time, we fetch it.  We assume that the caller is going to do something useful with it, otherwise they shouldn't even ask.  If you want to conditionally avoid faulting, we could add a -isFaultForKey: or some such.
        rel = _ODOLookupRelationshipBySnapshotIndex(self, snapshotIndex, YES/*toMany*/, rel);
        value = ODOFetchSetFault(self->_editingContext, self, rel);
        _ODOObjectSetValueAtIndex(self, snapshotIndex, value);
    }
    return value;
}

// Generic property getter; logic here and in the specific index cases must match up
id ODOObjectPrimitiveValueForProperty(ODOObject *self, ODOProperty *prop)
{
    OBPRECONDITION(prop);
    OBPRECONDITION(!self->_flags.isFault || prop == [[self->_objectID entity] primaryKeyAttribute]);
    
    // Could maybe have extra info in this lookup (attr vs. rel, to-one vs. to-many)?
    NSUInteger snapshotIndex = ODOPropertySnapshotIndex(prop);
    if (snapshotIndex == ODO_PRIMARY_KEY_SNAPSHOT_INDEX)
        return [[self objectID] primaryKey];
    
    id value = _ODOObjectValueAtIndex(self, snapshotIndex);
    
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    
    if (flags.relationship) {
        ODORelationship *rel = (ODORelationship *)prop;
        if (flags.toMany) {
            // TODO: Use something like __builtin_expect to tell the inline that rel != nil?  This is the slow path, so I'm not sure it matters...
            value = _ODOObjectCheckForLazyToManyFaultCreation(self, value, snapshotIndex, rel);
        } else {
            // TODO: Use something like __builtin_expect to tell the inline that rel != nil?  This is the slow path, so I'm not sure it matters...
            value = _ODOObjectCheckForLazyToOneFaultCreation(self, value, snapshotIndex, rel);
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
        ODOProperty *prop = [[self->_objectID entity] propertyWithSnapshotIndex:snapshotIndex];
        OBASSERT([prop isKindOfClass:[ODOAttribute class]]);
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        OBASSERT(flags.relationship == NO);
        
        ODOAttribute *attr = (ODOAttribute *)prop;
        OBASSERT(![attr isPrimaryKey]);
    }
#endif
    
    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    return _ODOObjectValueAtIndex(self, snapshotIndex);
}

static id _ODOObjectToOneRelationshipGetterAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
#ifdef OMNI_ASSERTIONS_ON
    {
        ODOProperty *prop = [[self->_objectID entity] propertyWithSnapshotIndex:snapshotIndex];
        OBASSERT([prop isKindOfClass:[ODORelationship class]]);
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        OBASSERT(flags.relationship == YES);
        OBASSERT(flags.toMany == NO);
    }
#endif
    
    // Deleted objects clear all their to-one relationships to ensure that KVO unsubscription is accurate across multi-step keyPaths.  So, we can and should return nil here (since the receiver of a did-delete notification can remove observation of a keyPath that will cause lookups of intermediate objects).
    {
        // If we are a saved delete or reverted object or our editing context was -reset, we should have cleaned up already and can return nil.
        if (self->_flags.invalid)
            return nil;
        
        // Ensure that this early-out we are going to use is valid -- deleted objects should be faults.
        OBASSERT(![self isDeleted] || self->_flags.isFault);
        if (self->_flags.isFault && [self isDeleted])
            return nil;
    }
    
    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    return _ODOObjectCheckForLazyToOneFaultCreation(self, _ODOObjectValueAtIndex(self, snapshotIndex), snapshotIndex, nil/*relationship == we has it not!*/);
}

static id _ODOObjectToManyRelationshipGetterAtIndex(ODOObject *self, NSUInteger snapshotIndex)
{
#ifdef OMNI_ASSERTIONS_ON
    {
        ODOProperty *prop = [[self->_objectID entity] propertyWithSnapshotIndex:snapshotIndex];
        OBASSERT([prop isKindOfClass:[ODORelationship class]]);
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        OBASSERT(flags.relationship == YES);
        OBASSERT(flags.toMany == YES);
    }
#endif
    
    __inline_ODOObjectWillAccessValueForKey(self, nil/*we know it isn't the pk in this case*/);
    return _ODOObjectCheckForLazyToManyFaultCreation(self, _ODOObjectValueAtIndex(self, snapshotIndex), snapshotIndex, nil/*relationship == we has it not!*/);
}

// Generic property setter; for now we aren't doing specific-index setters (we are already a little faster than CoreData here, but we could still add them if it ends up showing up on a profile).
void ODOObjectSetPrimitiveValueForProperty(ODOObject *self, id value, ODOProperty *prop)
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
    id oldValue = ODOObjectPrimitiveValueForProperty(self, prop); // It is important to use this so that we'll get lazy to-one faults created
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
    
    _ODOObjectSetValueAtIndex(self, flags.snapshotIndex, value);
}

// If you copy the OmniDataObjects source into your project, you'll also need a shell script build phase like the "Generate Accessors" one in the OmniDataObjects framework project. This build phase needs to be ordered before the 'Compile Sources' phase.  If you prefer, you could run the script once (see its source to figure out how) and add the result to your project.  In this case you run the risk of a new version of ODO requiring a new format for this file.
#import "ODOObject-GeneratedAccessors.m"

id ODODynamicValueForProperty(ODOObject *object, ODOProperty *prop)
{
    NSString *key = ODOPropertyName(prop);
    [object willAccessValueForKey:key];
    id value = ODOObjectPrimitiveValueForProperty(object, prop);
    [object didAccessValueForKey:key];
    return value;
}

void ODODynamicSetValueForProperty(ODOObject *object, SEL _cmd, ODOProperty *prop, id value)
{
    // We don't allow editing to-many relationships from the to-many side.  We don't have many-to-many right now; edit the to-one on the other side.
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    if (flags.relationship  && flags.toMany)
        OBRejectInvalidCall(object, _cmd, @"Attempted to set %@.%@, but we don't allow setting to-many relationships directly right now.", [object shortDescription], [prop name]);
    
    NSString *key = prop->_name;
    [object willChangeValueForKey:key];
    ODOObjectSetPrimitiveValueForProperty(object, value, prop);
    [object didChangeValueForKey:key];
}

// These only work for object-valued properties, but that is all we support right now.  We aren't currently verifying that any @dynamic properties _are_ object valued, but we should
id ODOGetterForUnknownOffset(ODOObject *self, SEL _cmd)
{
    ODOProperty *prop = [[self->_objectID entity] propertyWithGetter:_cmd];
    OBASSERT(prop); // should only be installed for actual properties, unlike -valueForKey: which might be called for other keys
    return ODODynamicValueForProperty(self, prop);
}

void ODOSetterForUnknownOffset(ODOObject *self, SEL _cmd, id value)
{
    ODOProperty *prop = [[self->_objectID entity] propertyWithSetter:_cmd];
    OBASSERT(prop); // should only be installed for actual properties, unlike -setValue:forKey: which might be called for other keys
    ODODynamicSetValueForProperty(self, _cmd, prop, value);
}

ODOPropertyGetter ODOGetterForProperty(ODOProperty *prop)
{
    NSUInteger snapshotIndex = ODOPropertySnapshotIndex(prop);
    if (snapshotIndex == ODO_PRIMARY_KEY_SNAPSHOT_INDEX)
        return _ODOObjectPrimaryKeyGetter;
    
    // We have different paths for attributes and relationships to allow for lazy fault creation on the relationship paths.
    if (snapshotIndex < ODOObjectIndexedAccessorCount) {
        ODOPropertyGetter getter = NULL;
        const ODOAccessors *accessors = &IndexedAccessors[snapshotIndex];
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        if (flags.relationship)
            getter = flags.toMany ? accessors->to_many.get : accessors->to_one.get;
        else
            getter = accessors->attribute.get;
        OBASSERT(getter);
        return getter;
    }
#ifdef DEBUG_bungi
    NSLog(@"Need more attribute at-offset getters");
#endif
    return ODOGetterForUnknownOffset;
}

ODOPropertySetter ODOSetterForProperty(ODOProperty *prop)
{
    // Generic property setter; for now we aren't doing specific-index setters (we are already a little faster than CoreData here, but we could still add them if it ends up showing up on a profile).
    return ODOSetterForUnknownOffset;
}


void ODOObjectSetInternalValueForProperty(ODOObject *self, id value, ODOProperty *prop)
{
    OBPRECONDITION([self isKindOfClass:[ODOObject class]]);
    //OBPRECONDITION(!self->_flags.isFault); // Might be a fault if we are just clearing it.  TODO: Swap the order of filling in the values and clearing the fault flag?
    OBPRECONDITION(!self->_flags.invalid);
    OBPRECONDITION(self->_editingContext);
    OBPRECONDITION(self->_objectID);
    
    NSUInteger snapshotIndex = ODOPropertySnapshotIndex(prop);
    _ODOObjectSetValueAtIndex(self, snapshotIndex, value);
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
        SEL sel;
        
        // All the matching ObjC properties must be @dynamic since ODOObject maintains its own storage for persistent properties.
#ifdef OMNI_ASSERTIONS_ON
        {
            objc_property_t objcProperty = class_getProperty(instanceClass, [prop->_name UTF8String]);
            OBASSERT(objcProperty);
            
            // https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html
            const char *attributes = property_getAttributes(objcProperty);
            DEBUG_DYNAMIC_METHODS(@"  property attributes = %s", attributes);
            
            // 'T' is first, so ',D' should be there somewhere (typically last). Need to check if @encode for structs can have commas in them, but for now we require that all propertyes are object typed.
            OBASSERT(strstr(attributes, "T@") == attributes, "Property %@.%@ should be object-typed!", NSStringFromClass(instanceClass), prop->_name);

            if (strstr(attributes, ",D") == NULL) {
                NSLog(@"Property %@.%@ should be marked @dynamic!", NSStringFromClass(instanceClass), prop->_name);
                missingDynamicProperty = YES;
            }
        }
#endif
        
        if ((sel = prop->_sel.get) && !class_getInstanceMethod(instanceClass, sel)) {
            IMP imp = (IMP)ODOGetterForProperty(prop);
            const char *signature = ODOObjectGetterSignature();
            DEBUG_DYNAMIC_METHODS(@"  Adding -[%@ %@] with %p %s", NSStringFromClass(instanceClass), NSStringFromSelector(sel), imp, signature);
            class_addMethod(instanceClass, sel, imp, signature);
        }
        if ((sel = prop->_sel.set) && !class_getInstanceMethod(instanceClass, sel)) {
            IMP imp = (IMP)ODOSetterForProperty(prop);
            const char *signature = ODOObjectSetterSignature();
            DEBUG_DYNAMIC_METHODS(@"  Adding -[%@ %@] with %p %s", NSStringFromClass(instanceClass), NSStringFromSelector(sel), imp, signature);
            class_addMethod(instanceClass, sel, imp, signature);
        }
    }
    
    OBASSERT(missingDynamicProperty == NO, "Missing @dynamic property definitions");
}
#endif
