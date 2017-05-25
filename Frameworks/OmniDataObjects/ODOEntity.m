// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
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
    if (_propertyNames)
        CFRelease(_propertyNames);
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
    CFRange range = CFRangeMake(0, CFArrayGetCount((CFArrayRef)_propertyNames));
    OBASSERT((CFIndex)[_properties count] == range.length);

    CFIndex propIndex = CFArrayGetFirstIndexOfValue((CFArrayRef)_propertyNames, range, name);
    if (propIndex != kCFNotFound) {
        ODOProperty *prop = (ODOProperty *)CFArrayGetValueAtIndex((CFArrayRef)_properties, propIndex);
        if (ODOPropertyHasIdenticalName(prop, name))
            return prop;
        OBASSERT_NOT_REACHED("should have had an identical name if we found it in the _propertyNames array");
    }
    
    propIndex = CFArrayBSearchValues((CFArrayRef)_properties, range, name, _comparePropertyName, name);
    if (propIndex < range.length) {
        // This might still not have the right name
        ODOProperty *prop = (ODOProperty *)CFArrayGetValueAtIndex((CFArrayRef)_properties, propIndex);
        if ([name isEqualToString:[prop name]])
            return prop;
    }
    
    return nil;
}

- (ODOProperty *)propertyWithGetter:(SEL)getter;
{
    OBPRECONDITION(_properties);
    OBPRECONDITION(_propertyGetSelectors);
    OBPRECONDITION(getter);

    CFRange range = CFRangeMake(0, CFArrayGetCount((CFArrayRef)_propertyGetSelectors));
    OBASSERT((CFIndex)[_properties count] == range.length);

    CFIndex propIndex = CFArrayGetFirstIndexOfValue((CFArrayRef)_propertyGetSelectors, range, getter);
    if (propIndex != kCFNotFound)
        return (ODOProperty *)CFArrayGetValueAtIndex((CFArrayRef)_properties, propIndex);

    return nil;
}

- (ODOProperty *)propertyWithSetter:(SEL)setter;
{
    OBPRECONDITION(_properties);
    OBPRECONDITION(_propertySetSelectors);
    OBPRECONDITION(setter);
        
    CFRange range = CFRangeMake(0, CFArrayGetCount((CFArrayRef)_propertySetSelectors));
    OBASSERT((CFIndex)[_properties count] == range.length);
    
    CFIndex propIndex = CFArrayGetFirstIndexOfValue((CFArrayRef)_propertySetSelectors, range, setter);
    if (propIndex != kCFNotFound)
        return (ODOProperty *)CFArrayGetValueAtIndex((CFArrayRef)_properties, propIndex);

    return nil;
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
                                  NSString *instanceClassName, NSArray *properties)
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

    // ODOObject instances are pointer-unique w/in their editing context and we define -hash and -isEqual: thusly.
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(hash)) == [ODOObject class]);
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(isEqual:)) == [ODOObject class]);

    // Use the -insertObject:undeletable: instead of subclassing
    OBASSERT(OBClassImplementingMethod(entity->_instanceClass, @selector(isUndeletable)) == [ODOObject class]);
    
    entity->_instanceClassName = [instanceClassName copy];

    // TODO: Could do more of this building in the Ruby script-generated code, if it is worth the effort.
    OBPRECONDITION(properties);
    entity->_properties = [properties copy];
    
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
        NSString **propertyNamesCArray = malloc(sizeof(NSString *) * propertyCount);

        for (CFIndex propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++)
            propertyNamesCArray[propertyIndex] = [[entity->_properties objectAtIndex:propertyIndex] name];
                
        CFArrayCallBacks callbacks;
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.retain = OFNSObjectRetain;
        callbacks.release = OFNSObjectRelease;
        callbacks.copyDescription = OFNSObjectCopyDescription;
        // equal NULL for pointer equality, the whole point here.
        
        entity->_propertyNames = CFArrayCreate(kCFAllocatorDefault, (const void **)propertyNamesCArray, propertyCount, &callbacks);
        free(propertyNamesCArray);
        
        
        // Some of the setters may be NULL (eventually) when we support read-only properties.
        SEL *getters = malloc(sizeof(SEL) * propertyCount);
        SEL *setters = malloc(sizeof(SEL) * propertyCount);
        
        for (CFIndex propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++) {
            ODOProperty *property = [entity->_properties objectAtIndex:propertyIndex];
            getters[propertyIndex] = ODOPropertyGetterSelector(property);
            setters[propertyIndex] = ODOPropertySetterSelector(property);
        }
        
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

- (void)finalizeModelLoading;
{
    [self _buildSchemaProperties];
    
    // Build a list of snapshot properties.  These are all the properties that the ODOObject stores internally; everything but the primary key.  CoreData doesn't seem to snapshot the transient properties.  Also, it is unclear whether relationships are supported for CoreData actual snapshots, but they do need to be stored by ODOObject, so this is easy for now.
    NSMutableArray *snapshotProperties = [[NSMutableArray alloc] initWithArray:_properties];
    [snapshotProperties removeObject:_primaryKeyAttribute];
    
    // Sort them by name and assign snapshot indexes
    [snapshotProperties sortUsingSelector:@selector(compareByName:)];
    {
        NSUInteger snapshotIndex = [snapshotProperties count];
        while (snapshotIndex--)
            ODOPropertySnapshotAssignSnapshotIndex([snapshotProperties objectAtIndex:snapshotIndex], snapshotIndex);
    }
    
    _snapshotProperties = [[NSArray alloc] initWithArray:snapshotProperties];
    [snapshotProperties release];
    
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

    // Old API that our instance class shouldn't try to implement any more since we aren't going to use it!
    OBASSERT(OBClassImplementingMethod(_instanceClass, @selector(derivedPropertyNameSet)) == Nil);
    OBASSERT(OBClassImplementingMethod(_instanceClass, @selector(nonDateModifyingPropertyNameSet)) == Nil);

    // Ensure the property didn't find a setter for the primary key attribute
    OBASSERT(ODOPropertySetterImpl(_primaryKeyAttribute) == NULL);
}

- (NSArray <__kindof ODOProperty *> *)snapshotProperties;
{
    OBPRECONDITION(_snapshotProperties);
    return _snapshotProperties;
}

- (NSArray <ODOAttribute *> *)snapshotAttributes;
{
    OBPRECONDITION(_snapshotAttributes);
    return _snapshotAttributes;
}

- (ODOProperty *)propertyWithSnapshotIndex:(NSUInteger)snapshotIndex;
{
    ODOProperty *prop = [_snapshotProperties objectAtIndex:snapshotIndex];
    OBASSERT(ODOPropertySnapshotIndex(prop) == snapshotIndex);
    return prop;
}

@end
