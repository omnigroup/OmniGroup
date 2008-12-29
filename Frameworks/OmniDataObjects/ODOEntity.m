// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOEntity.h>

#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOEditingContext.h>
#import <OmniDataObjects/ODOModel.h>

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
    [_propertiesByName release];
    [_relationshipsByName release];
    [_relationships release];
    [_toOneRelationships release];
    [_attributesByName release];
    [_primaryKeyAttribute release];
    [_snapshotProperties release];
    [_schemaProperties release];

    // We just hold uniquing keys for the statements since the database can't close if we have open statements (and the model might be used by multiple database connections anyway).
    [_insertStatementKey release];
    [_updateStatementKey release];
    [_deleteStatementKey release];
    [_queryByPrimaryKeyStatementKey release];

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
    const char *str1 = CFStringGetCStringPtr(name1, kCFStringEncodingMacRoman);
    const char *str2 = CFStringGetCStringPtr(name2, kCFStringEncodingMacRoman);
    
    if (str1 && str2)
        return strcmp(str1, str2);
    
    OBASSERT_NOT_REACHED("non-ASCII property name?");
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

#ifdef DEBUG
- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:_name forKey:@"name"];
    [dict setObject:[_properties arrayByPerformingSelector:_cmd] forKey:@"properties"];
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
    if (!entity) {
        OBASSERT_NOT_REACHED("Bad entity name passed in?");
        return nil;
    }
    
    ODOObject *object = [[[entity instanceClass] alloc] initWithEditingContext:context entity:entity primaryKey:primaryKey];
    [context insertObject:object]; // retains it
    [object release];
    
    return object;
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

#import "ODOEntity-Internal.h"
#import "ODOAttribute-Internal.h"
#import "ODORelationship-Internal.h"

NSString * const ODOEntityElementName = @"entity";
NSString * const ODOEntityNameAttributeName = @"name";
NSString * const ODOEntityInstanceClassAttributeName = @"class";

@implementation ODOEntity (Internal)

- (id)initWithCursor:(OFXMLCursor *)cursor model:(ODOModel *)model error:(NSError **)outError;
{
    OBPRECONDITION(OFISEQUAL([cursor name], ODOEntityElementName));
    
    _nonretained_model = model;
    _name = [[cursor attributeNamed:ODOEntityNameAttributeName] copy];
    if ([NSString isEmptyString:_name]) {
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Entity has no name.", nil, OMNI_BUNDLE, @"error reason");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    _insertStatementKey = [[NSString alloc] initWithFormat:@"INSERT:%@", _name];
    _updateStatementKey = [[NSString alloc] initWithFormat:@"UPDATE:%@", _name];
    _deleteStatementKey = [[NSString alloc] initWithFormat:@"DELETE:%@", _name];
    _queryByPrimaryKeyStatementKey = [[NSString alloc] initWithFormat:@"PK:%@", _name];
    
    _instanceClassName = [[cursor attributeNamed:ODOEntityInstanceClassAttributeName] copy];
    if ([NSString isEmptyString:_instanceClassName]) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Entity '%@' has no instance class name.", nil, OMNI_BUNDLE, @"error reason"), _name];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    _instanceClass = NSClassFromString(_instanceClassName);
    if (!_instanceClass) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Entity '%@' specified instance class name of '%@', but no such class was found.", nil, OMNI_BUNDLE, @"error reason"), _name, _instanceClassName];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    if (!OBClassIsSubclassOfClass(_instanceClass, [ODOObject class])) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Entity '%@' specified instance class name of '%@', but this class is not a subclass of ODOObject.", nil, OMNI_BUNDLE, @"error reason"), _name, _instanceClassName];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }

    OBASSERT(![_instanceClass instancesRespondToSelector:@selector(validateForDelete:)]); // OmniFocus doesn't need this right now, so ODOEditingContext doesn't support it.
    
    // Disallow subclassing some of the ODOObject methods for now.  We may want to optimize them or inline them in certain places
    OBASSERT(OBClassImplementingMethod(_instanceClass, @selector(entity)) == [ODOObject class]);
    OBASSERT(OBClassImplementingMethod(_instanceClass, @selector(primitiveValueForKey:)) == [ODOObject class]);
    OBASSERT(OBClassImplementingMethod(_instanceClass, @selector(setPrimitiveValue:forKey:)) == [ODOObject class]);
    
    
    NSMutableArray *properties = [NSMutableArray array];
    NSMutableDictionary *propertiesByName = [NSMutableDictionary dictionary];
    
    // Read attributes
    NSMutableDictionary *attributesByName = [NSMutableDictionary dictionary];
    while (([cursor openNextChildElementNamed:ODOAttributeElementName])) {
        ODOAttribute *attribute = [[ODOAttribute alloc] initWithCursor:cursor entity:self error:outError];
        if (!attribute) {
            [self release];
            return nil;
        }
        
        NSString *name = [attribute name];
        if ([propertiesByName objectForKey:name]) {
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Entity '%@' has multiple properties named '%@'.", nil, OMNI_BUNDLE, @"error reason"), _name];
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
            ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
            [self release];
            return nil;
        }

        BOOL isPrimaryKey = [attribute isPrimaryKey];
        if (isPrimaryKey) {
            if (_primaryKeyAttribute) {
                // We don't support compound primary keys
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Entity '%@' has multiple primary key attributes.", nil, OMNI_BUNDLE, @"error reason"), _name];
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
                ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
                [self release];
                return nil;
            }
            _primaryKeyAttribute = [attribute retain];
        }
        
        [properties addObject:attribute];
        [propertiesByName setObject:attribute forKey:name];
        [attributesByName setObject:attribute forKey:name];

        [cursor closeElement];
    }
    _attributesByName = [[NSDictionary alloc] initWithDictionary:attributesByName];
    
    if (!_primaryKeyAttribute) {
        // Must have a primary key
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Entity '%@' has no primary key attributes.", nil, OMNI_BUNDLE, @"error reason"), _name];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }

    if ([_primaryKeyAttribute defaultValue]) {
        // Silly for a primary key to have a default value
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Entity '%@' specified primary key attribute '%@' with a default value.", nil, OMNI_BUNDLE, @"error reason"), _name, [_primaryKeyAttribute name]];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    // See -[ODODatabase _generatePrimaryKeyForEntity:].
    if ([_primaryKeyAttribute type] != ODOAttributeTypeString) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Entity '%@' specified primary key attribute '%@' with type %d, but only strings are supported.", nil, OMNI_BUNDLE, @"error reason"), _name, [_primaryKeyAttribute name], [_primaryKeyAttribute type]];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    // Read relationships; their destination entity will be a string still since all the entities might not yet read.
    NSMutableDictionary *relationshipsByName = [NSMutableDictionary dictionary];
    NSMutableArray *relationships = [NSMutableArray array];
    NSMutableArray *toOneRelationships = [NSMutableArray array];
    
    while (([cursor openNextChildElementNamed:ODORelationshipElementName])) {
        ODORelationship *rel = [[ODORelationship alloc] initWithCursor:cursor entity:self error:outError];
        if (!rel) {
            [self release];
            return nil;
        }
        
        NSString *name = [rel name];
        if ([propertiesByName objectForKey:name]) {
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Entity '%@' has multiple properties named '%@'.", nil, OMNI_BUNDLE, @"error reason"), _name];
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
            ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
            [self release];
            return nil;
        }
        
        [properties addObject:rel];
        [propertiesByName setObject:rel forKey:name];
        [relationshipsByName setObject:rel forKey:name];
        [relationships addObject:rel];
        if ([rel isToMany] == NO)
            [toOneRelationships addObject:rel];
        
        [cursor closeElement];
    }
    
    // Sort so that -propertyNamed: can use binary search if it wants.  _properties and _propertyNames must be in exactly the same order.
    [properties sortUsingSelector:@selector(compareByName:)];
    _properties = [[NSArray alloc] initWithArray:properties];
    
    // Make an immutable CFArray that does NOT use CFEqual for equality, but just pointer equality (since we've interned our property names).
    {
        NSArray *propertyNames = [_properties arrayByPerformingSelector:@selector(name)];
        CFIndex propertyNameCount = [propertyNames count];
        
        NSString **propertyNamesCArray = malloc(sizeof(NSString *) * propertyNameCount);
        [propertyNames getObjects:propertyNamesCArray];
        
        CFArrayCallBacks callbacks;
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.retain = OFNSObjectRetain;
        callbacks.release = OFNSObjectRelease;
        callbacks.copyDescription = OFNSObjectCopyDescription;
        // equal NULL for pointer equality, the whole point here.
        
        _propertyNames = CFArrayCreate(kCFAllocatorDefault, (const void **)propertyNamesCArray, propertyNameCount, &callbacks);
        free(propertyNamesCArray);
    }
    
    _propertiesByName = [[NSDictionary alloc] initWithDictionary:propertiesByName];
    _relationshipsByName = [[NSDictionary alloc] initWithDictionary:relationshipsByName];
    _relationships = [[NSArray alloc] initWithArray:relationships];
    _toOneRelationships = [[NSArray alloc] initWithArray:toOneRelationships];
    
    return self;
}

- (BOOL)finalizeModelLoading:(NSError **)outError;
{
    // hook up relationships, validating destination names
    NSEnumerator *relationshipEnum = [_relationshipsByName objectEnumerator];
    ODORelationship *rel;
    while ((rel = [relationshipEnum nextObject])) {
        if (![rel finalizeModelLoading:outError])
            return NO;
    }

    [self _buildSchemaProperties];
    
    // Build a list of snapshot properties.  These are all the properties that the ODOObject stores internally; everything but the primary key.  CoreData doesn't seem to snapshot the transient properties.  Also, it is unclear whether relationships are supported for CoreData actual snapshots, but they do need to be stored by ODOObject, so this is easy for now.
    NSMutableArray *snapshotProperties = [[NSMutableArray alloc] initWithArray:_properties];
    [snapshotProperties removeObject:_primaryKeyAttribute];
    
    // Sort them by name and assign snapshot indexes
    [snapshotProperties sortUsingSelector:@selector(compareByName:)];
    {
        unsigned int snapshotIndex = [snapshotProperties count];
        while (snapshotIndex--)
            ODOPropertySnapshotAssignSnapshotIndex([snapshotProperties objectAtIndex:snapshotIndex], snapshotIndex);
    }
    
    _snapshotProperties = [[NSArray alloc] initWithArray:snapshotProperties];
    [snapshotProperties release];
    
    return YES;
}

- (NSArray *)snapshotProperties;
{
    OBPRECONDITION(_snapshotProperties);
    return _snapshotProperties;
}

@end
