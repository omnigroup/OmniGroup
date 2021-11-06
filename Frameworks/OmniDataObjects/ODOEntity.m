// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOEntity.h>

#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOEditingContext.h>
#import <OmniDataObjects/ODOModel.h>
#import <OmniFoundation/NSArray-OFExtensions.h>

#import "ODOProperty-Internal.h"
#import "ODOEntity-Internal.h"
#import "ODOEntity-SQL.h"
#import "ODOSQLStatement.h"

RCS_ID("$Id$")

@implementation ODOEntity

- (void)dealloc;
{
    _nonretained_model = nil;
    [_name release];
    [_instanceClassName release];
    [_properties release];
    [_propertyNames release];
    if (_propertyGetSelectors)
        CFRelease(_propertyGetSelectors);
    if (_propertySetSelectors)
        CFRelease(_propertySetSelectors);
    [_propertiesByName release];
    [_relationshipsByName release];
    [_relationships release];
    [_toOneRelationships release];
    [_toManyRelationships release];
    [_attributesByName release];
    [_attributes release];
    [_primaryKeyAttribute release];
    [_snapshotProperties release];
    [_snapshotAttributes release];
    [_schemaProperties release];

    // We just hold uniquing keys for the statements since the database can't close if we have open statements (and the model might be used by multiple database connections anyway).
    [_insertStatementKey release];
    [_updateStatementKey release];
    [_deleteStatementKey release];
    [_queryByPrimaryKeyStatementKey release];

    [_derivedPropertyNameSet release];
    [_nonDateModifyingPropertyNameSet release];
    [_calculatedTransientPropertyNameSet release];
    [_defaultAttributeValueActions release];

    [_nonPropertyNames release];
    
    [super dealloc];
}

- (ODOModel *)model;
{
    OBPRECONDITION(_nonretained_model);
    return _nonretained_model;
}

- (NSString *)name;
{
    OBPRECONDITION(_name);
    return _name;
}

- (NSString *)instanceClassName;
{
    return _instanceClassName;
}

- (Class)instanceClass;
{
    return _instanceClass;
}

- (NSArray *)properties;
{
    OBPRECONDITION(_properties);
    return _properties;
}

- (NSDictionary *)propertiesByName;
{
    OBPRECONDITION(_propertiesByName);
    return _propertiesByName;
}

static CFComparisonResult _comparePropertyName(const void *val1, const void *val2, void *context)
{
    // One of the input values should be the name; emperically it is always the first, but we'll check by having the name in the context.
    CFStringRef name1, name2;
    
    if (val1 == context) {
        name1 = val1;
        name2 = (CFStringRef)[(ODOProperty *)val2 name];
    } else {
        OBASSERT(val2 == context);
        name1 = (CFStringRef)[(ODOProperty *)val1 name];
        name2 = val2;
    }
    
    // Property names should all be ASCII.  But, it seems that they like to store 1-byte per character strings in Mac Roman.
    //
    // Whether or not CFStringGetCStringPtr returns a valid pointer or NULL depends on many factors, all of which depend on how the string was created and its properties. In addition, the function result might change between different releases and on different platforms. So do not count on receiving a non-NULL result from this function under any circumstances.
    //
    // If we can get c-string pointers, use strcmp, otherwise use CFStringCompare.
    
    const char *str1 = CFStringGetCStringPtr(name1, kCFStringEncodingMacRoman);
    const char *str2 = CFStringGetCStringPtr(name2, kCFStringEncodingMacRoman);
    
    if (str1 && str2)
        return strcmp(str1, str2);

    return CFStringCompare((CFStringRef)name1, (CFStringRef)name2, 0/*options*/);
}

- (ODOProperty *)propertyNamed:(NSString *)name;
{
    OBPRECONDITION(_properties);
    OBPRECONDITION(_propertyNames);
    OBPRECONDITION(name);

    // Our properties should be interned; check via pointer equality first.  We have an array of just the property names so we can do this linear scan quickly.
    OBASSERT([_properties count] == [_propertyNames count]);

    NSUInteger propIndex = [_propertyNames indexOfObjectIdenticalTo:name];
    if (propIndex != NSNotFound) {
        ODOProperty *prop = _properties[propIndex];
        if (ODOPropertyHasIdenticalName(prop, name))
            return prop;
        OBASSERT_NOT_REACHED("should have had an identical name if we found it in the _propertyNames array");
    }

    if (_nonPropertyNames) {
        NSUInteger foundIndex = [_nonPropertyNames indexOfObjectIdenticalTo:name];
        if (foundIndex != NSNotFound) {
            return nil; // This is definitely not a property.
        }
    }

    CFRange range = CFRangeMake(0, [_propertyNames count]);
    propIndex = CFArrayBSearchValues((CFArrayRef)_properties, range, name, _comparePropertyName, name);
    if ((CFIndex)propIndex < range.length) {
        // This might still not have the right name
        ODOProperty *prop = _properties[propIndex];
        if ([name isEqualToString:[prop name]]) {
            // This happens when using -valueForKeyPath: where the system has to break up the key path. Often, we'll get tagged-pointer strings passed in in this case (for short keys), but be comparing to constant strings.
            //OBASSERT_NOT_REACHED("Add a comment about a valid case this gets it in... key path observations?");
            return prop;
        }
    }

    return nil;
}

- (ODOProperty *)propertyWithGetter:(SEL)getter;
{
    OBPRECONDITION(_properties);
    OBPRECONDITION(_propertyGetSelectors);
    OBPRECONDITION(getter);

    CFRange range = CFRangeMake(0, CFArrayGetCount(_propertyGetSelectors));
    OBASSERT((CFIndex)[_properties count] == range.length);

    CFIndex propIndex = CFArrayGetFirstIndexOfValue(_propertyGetSelectors, range, getter);
    if (propIndex != kCFNotFound)
        return _properties[propIndex];

    return nil;
}

- (ODOProperty *)propertyWithSetter:(SEL)setter;
{
    OBPRECONDITION(_properties);
    OBPRECONDITION(_propertySetSelectors);
    OBPRECONDITION(setter);
        
    CFRange range = CFRangeMake(0, CFArrayGetCount(_propertySetSelectors));
    OBASSERT((CFIndex)[_properties count] == range.length);
    
    CFIndex propIndex = CFArrayGetFirstIndexOfValue(_propertySetSelectors, range, setter);
    if (propIndex != kCFNotFound) {
        return _properties[propIndex];
    }

    return nil;
}

- (void)setNonPropertyNames:(NSArray<NSString *> *)nonPropertyNames;
{
    OBPRECONDITION(_properties);
    OBPRECONDITION(_properties);
    OBPRECONDITION(_nonPropertyNames == nil, "Should be called once at startup");

    OBASSERT([nonPropertyNames first:^BOOL(NSString *name){
        return _propertiesByName[name] != nil;
    }] == NO, "No given names should map to actual properties");

    _nonPropertyNames = [nonPropertyNames copy];
}

- (NSDictionary *)relationshipsByName;
{
    OBPRECONDITION(_relationshipsByName);
    return _relationshipsByName;
}

- (NSArray *)relationships;
{
    OBPRECONDITION(_relationships);
    return _relationships;
}

- (NSArray *)toOneRelationships;
{
    OBPRECONDITION(_toOneRelationships);
    return _toOneRelationships;
}

- (NSArray *)toManyRelationships;
{
    OBPRECONDITION(_toManyRelationships);
    return _toManyRelationships;
}

- (NSArray *)attributes;
{
    OBPRECONDITION(_attributes);
    return _attributes;
}

- (NSDictionary *)attributesByName;
{
    OBPRECONDITION(_attributesByName);
    return _attributesByName;
}

- (ODOAttribute *)primaryKeyAttribute;
{
    OBPRECONDITION(_primaryKeyAttribute);
    return _primaryKeyAttribute;
}

- (NSSet *)derivedPropertyNameSet;
{
    OBPRECONDITION(_derivedPropertyNameSet);
    return _derivedPropertyNameSet;
}

- (NSSet *)nonDateModifyingPropertyNameSet;
{
    OBPRECONDITION(_nonDateModifyingPropertyNameSet);
    return _nonDateModifyingPropertyNameSet;
}

- (NSSet *)calculatedTransientPropertyNameSet;
{
    OBPRECONDITION(_calculatedTransientPropertyNameSet);
    return _calculatedTransientPropertyNameSet;
}

#ifdef DEBUG
- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:_name forKey:@"name"];
    NSMutableArray *propertyDescriptions = [NSMutableArray array];
    for (ODOProperty *property in _properties)
        [propertyDescriptions addObject:[property debugDictionary]];
    [dict setObject:propertyDescriptions forKey:@"properties"];
    return dict;
}
#endif

//

+ (id)insertNewObjectForEntityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context primaryKey:(id)primaryKey;
{
    OBPRECONDITION(entityName);
    OBPRECONDITION(context);
    // primaryKey == nil means that the object should make a new primary key
    
    ODOEntity *entity = [self entityForName:entityName inEditingContext:context];
    if (entity == nil) {
        OBASSERT_NOT_REACHED("Bad entity name passed in?");
        return nil;
    }
    
    ODOObject *object = [[[entity instanceClass] alloc] initWithEntity:entity primaryKey:primaryKey insertingIntoEditingContext:context];
    return [object autorelease];
}

+ (id)insertNewObjectForEntityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context;
{
    return [self insertNewObjectForEntityForName:entityName inEditingContext:context primaryKey:nil];
}

+ (ODOEntity *)entityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context;
{
    ODOEntity *entity = [[[[context database] model] entitiesByName] objectForKey:entityName];
    if (!entity)
        OBASSERT_NOT_REACHED("Bad entity name passed in?");
    return entity;
}

@end

#import <OmniDataObjects/ODOModel-Creation.h>
#import <OmniDataObjects/ODOAttribute.h>

@implementation ODOEntity (Internal)

#ifdef OMNI_ASSERTIONS_ON
static CFComparisonResult _compareByName(const void *val1, const void *val2, void *context)
{
    return (CFComparisonResult)[(ODOProperty *)val1 compareByName:(ODOProperty *)val2];
}
#endif

extern ODOEntity *ODOEntityCreate(NSString *entityName, NSString *insertKey, NSString *updateKey, NSString *deleteKey, NSString *pkQueryKey,
                                  NSString *instanceClassName, NSArray *properties, NSUInteger prefetchOrder)
{
    // We don't support inheritance, so require at least some properties for now. This may need revisiting in the future if we come up with a good use case for a zero-property entity, like an abstract parent.
    OBPRECONDITION([properties count] > 0, "ODO expects every entity to have at least one property");
    
    ODOEntity *entity = [[ODOEntity alloc] init];
    entity->_nonretained_model = (id)0xdeadbeef; // TODO: Hook this up

    OBASSERT([entityName length] > 0);
    entity->_name = [entityName copy];

    OBASSERT(insertKey);
    OBASSERT(updateKey);
    OBASSERT(deleteKey);
    OBASSERT(pkQueryKey);
    entity->_insertStatementKey = [insertKey copy];
    entity->_updateStatementKey = [updateKey copy];
    entity->_deleteStatementKey = [deleteKey copy];
    entity->_queryByPrimaryKeyStatementKey = [pkQueryKey copy];
    
    OBASSERT(instanceClassName);
    entity->_instanceClass = NSClassFromString(instanceClassName);
    OBASSERT(OBClassIsSubclassOfClass(entity->_instanceClass, [ODOObject class]));

#if 0
    // Turns out nothing declares or implements -validateForDelete: right now. (The OFMTask implementation is #if'd out as well.)
    OBASSERT(![entity->_instanceClass instancesRespondToSelector:@selector(validateForDelete:)]); // OmniFocus doesn't need this right now, so ODOEditingContext doesn't support it.
#endif
	
    // Disallow subclassing some of the ODOObject methods for now.  We may want to optimize them or inline them in certain places
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(entity)) == [ODOObject class]);
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(objectID)) == [ODOObject class]);
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(primitiveValueForKey:)) == [ODOObject class]);
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(setPrimitiveValue:forKey:)) == [ODOObject class]);
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(setDefaultAttributeValues)) == [ODOObject class], "Override +addDefaultAttributeValueActions:entity: instead");

    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(valueForKey:)) == [ODOObject class], "ODOObjectValueForProperty depends on there being no subclasses of -valueForKey:");
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(setValue:forKey:)) == [ODOObject class], "ODOObjectSetValueForProperty depends on there being no subclasses of -setValue:forKey:");

    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(willChangeValueForKey:)) == [ODOObject class], "Override +addChangeActionsForProperty:willActions:didActions: instead");
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(didChangeValueForKey:)) == [ODOObject class], "Override +addChangeActionsForProperty:willActions:didActions: instead");

    // ODOObject instances are pointer-unique w/in their editing context and we define -hash and -isEqual: thusly.
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(hash)) == [ODOObject class]);
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(isEqual:)) == [ODOObject class]);

    // Use the -insertObject:undeletable: instead of subclassing
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(isUndeletable)) == [ODOObject class]);
    
    entity->_instanceClassName = [instanceClassName copy];

    // TODO: Could do more of this building in the Ruby script-generated code, if it is worth the effort.
    OBPRECONDITION(properties);
    entity->_properties = [properties copy];

    entity->_prefetchOrder = prefetchOrder;
    
    NSMutableDictionary *propertiesByName = [NSMutableDictionary dictionary];
    NSMutableDictionary *attributesByName = [NSMutableDictionary dictionary];
    NSMutableDictionary *relationshipsByName = [NSMutableDictionary dictionary];
    NSMutableArray *attributes = [NSMutableArray array];
    NSMutableArray *relationships = [NSMutableArray array];
    NSMutableArray *toOneRelationships = [NSMutableArray array];
    NSMutableArray *toManyRelationships = [NSMutableArray array];
    
    for (ODOProperty *prop in entity->_properties) {
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        NSString *propertyName = [prop name];
        
        OBASSERT([propertiesByName objectForKey:propertyName] == nil);
        OBASSERT([attributesByName objectForKey:propertyName] == nil);
        OBASSERT([relationshipsByName objectForKey:propertyName] == nil);
        
        [propertiesByName setObject:prop forKey:propertyName];
        if (flags.relationship) {
            ODORelationship *rel = (ODORelationship *)prop;
            
            [relationships addObject:rel];
            [flags.toMany ? toManyRelationships : toOneRelationships addObject:rel];
            [relationshipsByName setObject:rel forKey:propertyName];
        } else {
            ODOAttribute *attr = (ODOAttribute *)prop;
            
            [attributes addObject:attr];
            [attributesByName setObject:attr forKey:propertyName];
            if ([attr isPrimaryKey]) {
                OBASSERT(entity->_primaryKeyAttribute == nil);
                entity->_primaryKeyAttribute = [attr retain];
            }
        }
    }
    
    // Should have found a primary key attribute.  Makes no sense for pk attribute to have a default value
    OBASSERT(entity->_primaryKeyAttribute);
    OBASSERT([entity->_primaryKeyAttribute defaultValue] == nil);
    OBASSERT([entity->_primaryKeyAttribute type] == ODOAttributeTypeString); // See -[ODODatabase _generatePrimaryKeyForEntity:].

    entity->_propertiesByName = [[NSDictionary alloc] initWithDictionary:propertiesByName];
    entity->_attributes = [[NSArray alloc] initWithArray:attributes];
    entity->_attributesByName = [[NSDictionary alloc] initWithDictionary:attributesByName];
    entity->_relationshipsByName = [[NSDictionary alloc] initWithDictionary:relationshipsByName];
    entity->_relationships = [[NSArray alloc] initWithArray:relationships];
    entity->_toOneRelationships = [[NSArray alloc] initWithArray:toOneRelationships];
    entity->_toManyRelationships = [[NSArray alloc] initWithArray:toManyRelationships];
    
    // Input properties must have been sorted by name so that -propertyNamed: can use binary search if it wants.
    // _properties and _propertyNames must be in exactly the same order.
    OBASSERT(OFCFArrayIsSortedAscendingUsingFunction((CFArrayRef)entity->_properties, _compareByName, NULL));
    
    // Make immutable CFArrays that do NOT use CFEqual for equality, but just pointer equality (since we've interned our property names and selectors are pointer-uniqued).
    CFIndex propertyCount = [entity->_properties count];
    if (propertyCount == 0) { // Avoid clang-sa warnings about malloc(0)
        entity->_propertyGetSelectors = CFArrayCreate(kCFAllocatorDefault, NULL, 0, NULL);
        entity->_propertySetSelectors = CFArrayCreate(kCFAllocatorDefault, NULL, 0, NULL);
    } else {
        entity->_propertyNames = [[entity->_properties arrayByPerformingBlock:^(ODOProperty *property){
            return property.name;
        }] copy];
        
        // Some of the setters may be NULL (eventually) when we support read-only properties.
        SEL *getters = malloc(sizeof(SEL) * propertyCount);
        SEL *setters = malloc(sizeof(SEL) * propertyCount);
        
        for (CFIndex propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++) {
            ODOProperty *property = [entity->_properties objectAtIndex:propertyIndex];
            getters[propertyIndex] = ODOPropertyGetterSelector(property);
            setters[propertyIndex] = ODOPropertySetterSelector(property);
        }
        
        CFArrayCallBacks callbacks;
        memset(&callbacks, 0, sizeof(callbacks));
        entity->_propertyGetSelectors = CFArrayCreate(kCFAllocatorDefault, (const void **)getters, propertyCount, &callbacks);
        entity->_propertySetSelectors = CFArrayCreate(kCFAllocatorDefault, (const void **)setters, propertyCount, &callbacks);
        
        free(getters);
        free(setters);
    }

    return entity;
}

void ODOEntityBind(ODOEntity *self, ODOModel *model)
{
    OBPRECONDITION([self isKindOfClass:[ODOEntity class]]);
    self->_nonretained_model = model;
}

static size_t ODOPropertyStorageSize(ODOProperty *prop)
{
    if (prop->_flags.relationship) {
        return sizeof(intptr_t);
    }
    ODOAttribute *attribute = OB_CHECKED_CAST(ODOAttribute, prop);
    ODOAttributeType type = attribute.type;

    switch (type) {
        case ODOAttributeTypeUndefined: // Transient objects
        case ODOAttributeTypeString:
        case ODOAttributeTypeDate:
        case ODOAttributeTypeXMLDateTime:
        case ODOAttributeTypeData:
            return sizeof(intptr_t);

        case ODOAttributeTypeBoolean:
            // We don't use a full byte for booleans, but as noted below we temporarily track our used bits in the bytesUsed local in ODOEntityAssignSnapshotStorageKeys.
            return 1;

        case ODOAttributeTypeInt16:
            return sizeof(int16_t);

        case ODOAttributeTypeInt32:
            return sizeof(int32_t);

        case ODOAttributeTypeInt64:
            return sizeof(int64_t);

        case ODOAttributeTypeFloat32:
            return sizeof(float);

        case ODOAttributeTypeFloat64:
            return sizeof(double);

        default:
            OBASSERT_NOT_REACHED("Unknown type %ld!", type);
            return 0;
    }
}

static void ODOEntityAssignSnapshotStorageKeys(ODOEntity *self, NSArray <__kindof ODOProperty *> *snapshotProperties)
{
    // Check for optional scalars and set aside that many bits for their isNull flags.
    NSUInteger nonNullIndexNeeded = 0;
    for (ODOProperty *prop in snapshotProperties) {
        if (ODOPropertyUseScalarStorage(prop) && prop->_flags.optional) {
            nonNullIndexNeeded++;
        }
    }

    /*
     Each property that is part of the snapshotted properties has a ODOStorageKey that specifies how to pack the value for that property into a storage buffer.
     
     To make this easier to reason about, we'll loop over the properties and set up the storage key starting with the smallest type and going to larger and larger types. We could sort the properties by size and try to be clever about stepping through the array, but that seems not worth the effort to write and verify.
     
     We pack properties with the smallest size first (BOOL values going into individual bits), and we assume that all types must be aligned the same as their size.
     For each set of scalar or object accessor functions the storage key's storageIndex argument is as if the entire snapshot was of that type. For example, if we have one bit, one int32 and one object, we'd pack like:
     
     [B:xxx xxxx][xxxx xxxx][xxxx xxxx][xxxx xxxx][IIII IIII IIII IIII IIII IIII IIII IIII][OOOO OOOO OOOO .... 64 bits ... OOOO OOOO OOOO OOOO]
     
     The storageIndex of the bit (B) would be 0, for the int32 (I) it would be 1 since the first 32 bits were used by the one bit and padding to align I to a 4 byte boundary. Likewise, the storageIndex of the object (O) would be 2.
    */
    
    __block size_t bytesUsed = nonNullIndexNeeded; // As noted elsewhere, while we are doing bits, the bytesUsed is actually the bits used.

    void (^roundUp)(size_t align) = ^(size_t align){
        if ((bytesUsed % align) != 0) {
            bytesUsed = ((bytesUsed / align) + 1) * align;
        }
    };

    __block NSUInteger nextNonNullIndex = 0;
    
    void (^assignStorage)(size_t) = ^(size_t size) {
        
        // Snap to this new size's alignment.
        roundUp(size);
        
        // Handle each property with this size/alignment
        [snapshotProperties enumerateObjectsUsingBlock:^(ODOProperty *property, NSUInteger snapshotIndex, BOOL *stop) {
            if (ODOPropertyStorageSize(property) != size) {
                return;
            }
            
            // For the BOOL case, the calculation of storageIndex is fine (but depends on our temporary miscalculation of bytesUsed).
            OBASSERT((bytesUsed % size) == 0);
            NSUInteger storageIndex = bytesUsed / size;
            NSUInteger nonNullIndex;
            
            // If this is a nullable scalar property, take one of the previously reserved bits set aside for this purpose.
            if (ODOPropertyUseScalarStorage(property) && property->_flags.optional) {
                OBASSERT(nextNonNullIndex < nonNullIndexNeeded);
                nonNullIndex = nextNonNullIndex;
                nextNonNullIndex++;
            } else {
                nonNullIndex = ODO_STORAGE_KEY_NON_SNAPSHOT_PROPERTY_INDEX;
            }
            
            ODOStorageKey storageKey = (ODOStorageKey){
                ODOPropertyGetStorageType(property),
                snapshotIndex,
                nonNullIndex,
                storageIndex
            };
            
            // Make sure nothing got truncated.
            OBASSERT(storageKey.type == ODOPropertyGetStorageType(property));
            OBASSERT(storageKey.snapshotIndex == snapshotIndex);
            OBASSERT(storageKey.nonNullIndex == nonNullIndex);
            OBASSERT(storageKey.storageIndex == storageIndex);

            ODOPropertySnapshotAssignStorageKey(property, storageKey);

            bytesUsed += size;
        }];
    };

    assignStorage(1);
    
    // As noted above, bytesUsed will be the number of bits used here. Round it to the number of bytes needed for this number of bits.
    bytesUsed = (bytesUsed + 7) / 8;

    assignStorage(2);
    assignStorage(4);
    assignStorage(8);

    self->_snapshotPropertyCount = [snapshotProperties count];
    self->_snapshotStorageKeys = malloc(self->_snapshotPropertyCount * sizeof(*self->_snapshotStorageKeys));
    
    [snapshotProperties enumerateObjectsUsingBlock:^(ODOProperty *property, NSUInteger snapshotIndex, BOOL *stop) {
        OBASSERT(property->_storageKey.snapshotIndex != ODO_STORAGE_KEY_NON_SNAPSHOT_PROPERTY_INDEX, "All snapshot properties should have gotten a snapshot index");
        
        self->_snapshotStorageKeys[snapshotIndex] = property->_storageKey;
    }];
    
    self->_snapshotSize = bytesUsed;
}

- (void)finalizeModelLoading;
{
    [self _buildSchemaProperties];

    _prefetchRelationships = [[_relationships select:^BOOL(ODORelationship *relationship) {
        return relationship.shouldPrefetch;
    }] copy];

    if ([_prefetchRelationships count] == 0) {
        [_prefetchRelationships release];
        _prefetchRelationships = nil;
    }
    OBASSERT(([_prefetchRelationships count] == 0) == (_prefetchOrder == NSNotFound), "Must specify a prefetch order if the entity has any prefetched relationships");

    // Build a list of snapshot properties.  These are all the properties that the ODOObject stores internally; everything but the primary key.  CoreData doesn't seem to snapshot the transient properties.  Also, it is unclear whether relationships are supported for CoreData actual snapshots, but they do need to be stored by ODOObject, so this is easy for now.
    NSMutableArray <__kindof ODOProperty *> *snapshotProperties = [[NSMutableArray alloc] initWithArray:_properties];
    [snapshotProperties removeObject:_primaryKeyAttribute];

    // Sort by name for binary search when looking up by name.

    _snapshotProperties = [[NSArray alloc] initWithArray:snapshotProperties];
    [snapshotProperties release];

    
    ODOEntityAssignSnapshotStorageKeys(self, _snapshotProperties);

    _snapshotAttributes = [[_snapshotProperties arrayByPerformingBlock:^(ODOProperty *prop){
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
        if (!flags.relationship) {
            return (ODOAttribute *)prop;
        } else {
            return (ODOAttribute *)nil;
        }
    }] copy];

    // Since we don't support many-to-many relationships, to-manys are totally derived from the inverse to-one.  Let the instance class add more derived properties.
    NSMutableSet *derivedPropertyNameSet = [NSMutableSet set];
    [_instanceClass addDerivedPropertyNames:derivedPropertyNameSet withEntity:self];
    
    // Allow instance classes to filter out properties that don't provoke date modified changes.
    NSMutableSet *nonDateModifyingPropertyNameSet = [NSMutableSet set];
    [_instanceClass computeNonDateModifyingPropertyNameSet:nonDateModifyingPropertyNameSet withEntity:self];
    
#ifdef OMNI_ASSERTIONS_ON
    // Make sure the to-many relationships and transient or computed properties got added in ODOObject and not removed by subclasses.
    for (ODOProperty *property in _properties) {
        struct _ODOPropertyFlags flags = ODOPropertyFlags(property);
        if (flags.transient) {
            OBASSERT([derivedPropertyNameSet member:property.name]);
            OBASSERT([nonDateModifyingPropertyNameSet member:property.name]);
        }
    }

    for (ODORelationship *rel in _toManyRelationships) {
        OBASSERT([derivedPropertyNameSet member:rel.name]);
    }
#endif
    
    NSMutableSet *calculatedTransientPropertyNameSet = [NSMutableSet set];
    for (ODOProperty *property in _properties) {
        struct _ODOPropertyFlags flags = ODOPropertyFlags(property);
        if (!flags.relationship && flags.transient && flags.calculated) {
            [calculatedTransientPropertyNameSet addObject:property.name];
        }
    }
    
    _derivedPropertyNameSet = [derivedPropertyNameSet copy];
    _nonDateModifyingPropertyNameSet = [nonDateModifyingPropertyNameSet copy];
    _calculatedTransientPropertyNameSet = [calculatedTransientPropertyNameSet copy];

    _nonDerivedSnapshotProperties = [[_snapshotProperties select:^BOOL(ODOProperty *property) {
        return [_derivedPropertyNameSet member:property.name] == nil;
    }] copy];


    ODOObjectSetDefaultAttributeValueActions *actions = [[ODOObjectSetDefaultAttributeValueActions alloc] init];
    [_instanceClass addDefaultAttributeValueActions:actions entity:self];
    _defaultAttributeValueActions = [actions.actions copy];
    [actions release];
    
    // Old API that our instance class shouldn't try to implement any more since we aren't going to use it!
    OBASSERT(OBClassImplementingMethod(_instanceClass, @selector(derivedPropertyNameSet)) == Nil);
    OBASSERT(OBClassImplementingMethod(_instanceClass, @selector(nonDateModifyingPropertyNameSet)) == Nil);

    // Ensure the property didn't find a setter for the primary key attribute
    OBASSERT(ODOPropertySetterImpl(_primaryKeyAttribute) == NULL);
}

- (NSArray<ODORelationship *> *)prefetchRelationships;
{
    return _prefetchRelationships;
}

- (NSUInteger)prefetchOrder;
{
    return _prefetchOrder;
}

- (size_t)snapshotSize;
{
    return _snapshotSize;
}

- (NSArray <__kindof ODOProperty *> *)snapshotProperties;
{
    OBPRECONDITION(_snapshotProperties);
    return _snapshotProperties;
}

- (NSArray <__kindof ODOProperty *> *)nonDerivedSnapshotProperties;
{
    OBPRECONDITION(_nonDerivedSnapshotProperties);
    return _nonDerivedSnapshotProperties;
}

- (NSArray <ODOAttribute *> *)snapshotAttributes;
{
    OBPRECONDITION(_snapshotAttributes);
    return _snapshotAttributes;
}

- (ODOProperty *)propertyWithSnapshotIndex:(NSUInteger)snapshotIndex;
{
    return _snapshotProperties[snapshotIndex];
}

- (NSArray <ODOObjectSetDefaultAttributeValues> *)defaultAttributeValueActions;
{
    OBPRECONDITION(_defaultAttributeValueActions);
    return _defaultAttributeValueActions;
}

@end
