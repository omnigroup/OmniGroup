// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOEntity-SQL.h"

#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/ODOEditingContext.h>
#import <OmniDataObjects/NSPredicate-ODOExtensions.h>

#import "ODOObject-Accessors.h"
#import "ODOProperty-Internal.h"
#import "ODODatabase-Internal.h"
#import "ODOSQLStatement.h"

RCS_ID("$Id$")

@implementation ODOEntity (ODO_SQL)

// Builds the subset of properties in the order they are used in the actual schema.
- (void)_buildSchemaProperties;
{
    OBPRECONDITION(!_schemaProperties);

    // Put our primary key first.  Dunno if this matters for performance.    
    NSMutableArray *schemaProperties = [[NSMutableArray alloc] init];
    [schemaProperties addObject:_primaryKeyAttribute];
    
    // Append all the other relevant attributes and to-one relationships (where we store the destination's primary key in our foreign key column).
    for (ODOProperty *prop in _properties) {
        if ([prop isKindOfClass:[ODOAttribute class]]) {
            ODOAttribute *attr = (ODOAttribute *)prop;
            if (attr == _primaryKeyAttribute)
                continue; // done above
            if ([attr isTransient])
                continue; // only in memory
            [schemaProperties addObject:prop];
        } else {
            OBASSERT([prop isKindOfClass:[ODORelationship class]]);
            ODORelationship *rel = (ODORelationship *)prop;
            
            // If we are a to-one relationship, then we record the destination object's primary key in our foreign key column.  If we are to-many, then the inverse records *our* primary key and there is nothing for us to do.
            if ([rel isToMany])
                continue;
            
            OBASSERT(![rel isTransient]); // Need to support transient relationships?
            
            [schemaProperties addObject:prop];
        }
    }
    
    _schemaProperties = [[NSArray alloc] initWithArray:schemaProperties];
    [schemaProperties release];
}

- (NSArray *)_schemaProperties;
{
    OBPRECONDITION(_schemaProperties);
    return _schemaProperties;
}

static BOOL _appendColumnWithNameAndType(NSMutableString *str, ODOEntity *entity, NSString *name, ODOAttributeType type, NSError **outError)
{
    // We assume our attribute names are valid for SQL.  They are used as method names, so that seems pretty reasonable.
    NSString *typeString;
    
    switch (type) {
        case ODOAttributeTypeInt16:
        case ODOAttributeTypeInt32:
        case ODOAttributeTypeInt64:
        case ODOAttributeTypeBoolean:
            typeString = @"integer";
            break;
        case ODOAttributeTypeString:
            typeString = @"text";
            break;
        case ODOAttributeTypeData:
            typeString = @"blob";
            break;
        case ODOAttributeTypeDate:
            typeString = @"timestamp"; // will result in 'real', but this at least encodes our intention
            break;
        case ODOAttributeTypeFloat32:
            typeString = @"real";
            break;
        case ODOAttributeTypeFloat64:
            typeString = @"real";
            break;
            
        default: {
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Attribute %@.%@ has type %d with unknown SQL column type.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), [entity name], name, type];
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to create schema.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
            ODOError(outError, ODOUnableToCreateSchema, description, reason);
            return NO;
        }
    }
    
    [str appendFormat:@"%@ %@", name, typeString];
    return YES;
}

static BOOL _appendColumnForAttribute(NSMutableString *str, ODOAttribute *attr, NSError **outError)
{
    if (!_appendColumnWithNameAndType(str, [attr entity], [attr name], [attr type], outError))
        return NO;
    
    if (![attr isOptional])
        [str appendString:@" NOT NULL"];
    if ([attr isPrimaryKey])
        [str appendString:@" PRIMARY KEY"];
    
    return YES;
}

static BOOL _appendColumnForToOneRelationship(NSMutableString *str, ODORelationship *rel, NSError **outError)
{
    OBPRECONDITION([rel isToMany] == NO);
    
    ODOEntity *entity = [rel destinationEntity];
    ODOAttribute *foreignKey = [entity primaryKeyAttribute];
    
    // Add a column in *our* entity/relationship using the type from the foreign key.
    return _appendColumnWithNameAndType(str, [rel entity], [rel name], [foreignKey type], outError);
}

- (BOOL)_createSchemaInDatabase:(ODODatabase *)database error:(NSError **)outError;
{
    NSMutableString *sql = [NSMutableString stringWithFormat:@"create table %@ (", _name];

    // Only consider the schema properties.
    NSUInteger propertyIndex, propertyCount = [_schemaProperties count];
    for (propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++) {
        if (propertyIndex > 0)
            [sql appendString:@", "];

        ODOProperty *prop = [_schemaProperties objectAtIndex:propertyIndex];
        if ([prop isKindOfClass:[ODOAttribute class]]) {
            ODOAttribute *attr = (ODOAttribute *)prop;
            if (!_appendColumnForAttribute(sql, attr, outError))
                return NO;
        } else {
            OBASSERT([prop isKindOfClass:[ODORelationship class]]);
            ODORelationship *rel = (ODORelationship *)prop;
            if (!_appendColumnForToOneRelationship(sql, rel, outError))
                return NO;
        }
    }
    
    [sql appendString:@")"];
    
    return [database executeSQLWithoutResults:sql error:outError];
}

// The 'PRIMARY KEY' column spec creates the main index implicitly.  We create indexes for each of the foreign keys so that to-many fault clearing it fast.
- (BOOL)_createIndexesInDatabase:(ODODatabase *)database error:(NSError **)outError;
{
    for (ODOProperty *prop in _schemaProperties) {
        struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);

        if (!flags.relationship || flags.toMany)
            continue;
        
        // To-one relationships have a foreign key embedded in the owning entity.
        NSString *propName = [prop name];
        NSString *sql = [NSString stringWithFormat:@"CREATE INDEX %@_%@ on %@ (%@)", _name, propName, _name, propName];
        if (![database executeSQLWithoutResults:sql error:outError])
            return NO;
    }
    
    return YES;
}

static BOOL _bindAttributeValue(struct sqlite3 *sqlite, ODOSQLStatement *statement, NSUInteger zeroBasedPropertyIndex, ODOAttributeType type, id value, NSError **outError)
{
    OBPRECONDITION(statement);

    OBASSERT(zeroBasedPropertyIndex < INT_MAX);
    int oneBasedPropertyIndex = (int)zeroBasedPropertyIndex + 1;
    
    if (OFISNULL(value))
        return ODOSQLStatementBindNull(sqlite, statement, oneBasedPropertyIndex, outError);
    
    switch (type) {
        case ODOAttributeTypeString:
            OBASSERT([value isKindOfClass:[NSString class]]);
            return ODOSQLStatementBindString(sqlite, statement, oneBasedPropertyIndex, value, outError);
        case ODOAttributeTypeInt16:
            OBASSERT([value isKindOfClass:[NSNumber class]]);
            return ODOSQLStatementBindInt16(sqlite, statement, oneBasedPropertyIndex, [value shortValue], outError);
        case ODOAttributeTypeInt32:
            OBASSERT([value isKindOfClass:[NSNumber class]]);
            return ODOSQLStatementBindInt32(sqlite, statement, oneBasedPropertyIndex, [value intValue], outError);
        case ODOAttributeTypeInt64:
            OBASSERT([value isKindOfClass:[NSNumber class]]);
            return ODOSQLStatementBindInt64(sqlite, statement, oneBasedPropertyIndex, [value longLongValue], outError);
        case ODOAttributeTypeBoolean:
            OBASSERT([value isKindOfClass:[NSNumber class]]);
            return ODOSQLStatementBindBoolean(sqlite, statement, oneBasedPropertyIndex, [value boolValue], outError);
        case ODOAttributeTypeDate:
            OBASSERT([value isKindOfClass:[NSDate class]]);
            return ODOSQLStatementBindDate(sqlite, statement, oneBasedPropertyIndex, value, outError);
        case ODOAttributeTypeData:
            OBASSERT([value isKindOfClass:[NSData class]]);
            return ODOSQLStatementBindData(sqlite, statement, oneBasedPropertyIndex, value, outError);
        case ODOAttributeTypeFloat32: // No independent float32 value in sqlite3
        case ODOAttributeTypeFloat64:
            OBASSERT([value isKindOfClass:[NSNumber class]]);
            return ODOSQLStatementBindFloat64(sqlite, statement, oneBasedPropertyIndex, [value doubleValue], outError);
        default: {
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Attribute has type unsupported type %d.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), type];
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind attribute value to SQL.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
            ODOError(outError, ODOUnableToSave, description, reason);
            return NO;
        }
    }
    return YES;
}

static BOOL _bindRelationshipForeignKey(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOObject *object, NSUInteger zeroBasedPropertyIndex, ODORelationship *rel, NSError **outError)
{
    ODOAttribute *attr = [[rel destinationEntity] primaryKeyAttribute];
    ODOAttributeType type = [attr type];
    ODOObject *destObject = ODOObjectPrimitiveValueForProperty(object, rel);
    
    id foreignKey;
    if (destObject)
        foreignKey = ODOObjectPrimitiveValueForProperty(destObject, attr);
    else
        foreignKey = nil;
    OBASSERT(!foreignKey || [foreignKey isKindOfClass:[attr valueClass]]);
    
    return _bindAttributeValue(sqlite, statement, zeroBasedPropertyIndex, type, foreignKey, outError);
}

static BOOL _bindPlainAttribute(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOObject *object, NSUInteger zeroBasedPropertyIndex, ODOAttribute *attr, NSError **outError)
{
    ODOAttributeType type = [attr type];
    id value = ODOObjectPrimitiveValueForProperty(object, attr);
    
    OBASSERT(!value || [value isKindOfClass:[attr valueClass]]);
    
    return _bindAttributeValue(sqlite, statement, zeroBasedPropertyIndex, type, value, outError);
}

static BOOL _bindSchemaProperty(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOObject *object, NSUInteger zeroBasedPropertyIndex, ODOProperty *prop, NSError **outError)
{
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    if (flags.relationship)
        return _bindRelationshipForeignKey(sqlite, statement, object, zeroBasedPropertyIndex, (ODORelationship *)prop, outError);
    else
        return _bindPlainAttribute(sqlite, statement, object, zeroBasedPropertyIndex, (ODOAttribute *)prop, outError);
}

static BOOL _bindInsertSchemaProperties(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOObject *object, NSArray *schemaProperties, NSError **outError)
{
    NSUInteger propertyIndex = [schemaProperties count];
    while (propertyIndex--) {
        ODOProperty *prop = [schemaProperties objectAtIndex:propertyIndex];
        if (!_bindSchemaProperty(sqlite, statement, object, propertyIndex, prop, outError))
            return NO;
    }
    
    return YES;
}

- (BOOL)_writeInsert:(struct sqlite3 *)sqlite database:(ODODatabase *)database object:(ODOObject *)object error:(NSError **)outError;
{
    OBPRECONDITION(sqlite);
    OBPRECONDITION(database);
    OBPRECONDITION(object);
    
    ODOSQLStatement *insertStatement = [database _cachedStatementForKey:_insertStatementKey];
    if (!insertStatement) {
        NSMutableString *sql = [[NSMutableString alloc] initWithFormat:@"INSERT INTO %@ VALUES (", _name];
        NSUInteger propertyIndex, propertyCount = [_schemaProperties count];
        for (propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++) {
            if (propertyIndex == 0)
                [sql appendString:@"?"];
            else
                [sql appendString:@", ?"];
        }
        [sql appendString:@")"];
        
        ODODatabase *database = [[object editingContext] database];
        insertStatement = [[ODOSQLStatement alloc] initWithDatabase:database sql:sql error:outError];
        [sql release];
        if (!insertStatement)
            return NO;
        
        [database _setCachedStatement:insertStatement forKey:_insertStatementKey];
        [insertStatement release];
        
        // clang scan-build will issue a use-after release warning below if we don't do this (since it doesn't know that -_setCachedStatement:forKey: will retain.  Really, this makes sense since the method might do anything, including rejecting the new statement for some reason.  So, look it up again.
        insertStatement = [database _cachedStatementForKey:_insertStatementKey];
    }
    
    // Bind all the property values.
    if (!_bindInsertSchemaProperties(sqlite, insertStatement, object, _schemaProperties, outError))
        return NO;
    
    return ODOSQLStatementRunWithoutResults(sqlite, insertStatement, outError);
}

// All the _non_ primary key values get bound first and then the pk.
static BOOL _bindUpdateSchemaProperties(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOObject *object, NSArray *schemaProperties, ODOAttribute *primaryKeyAttribute, NSError **outError)
{
    OBPRECONDITION([primaryKeyAttribute isPrimaryKey]);
    OBPRECONDITION([schemaProperties containsObject:primaryKeyAttribute]);
    
    NSUInteger bindIndex = 0;
    NSUInteger propertyIndex, propertyCount = [schemaProperties count];
    
    for (propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++) {
        ODOProperty *prop = [schemaProperties objectAtIndex:propertyIndex];
        if (prop == primaryKeyAttribute) // Primary key gets bound last in the "WHERE" clause
            continue;
        
        if (!_bindSchemaProperty(sqlite, statement, object, bindIndex, prop, outError))
            return NO;

        bindIndex++;
    }
    
    // Bind the primary key attribute at the last slot for the WHERE
    return _bindPlainAttribute(sqlite, statement, object, bindIndex, primaryKeyAttribute, outError);
}

- (BOOL)_writeUpdate:(struct sqlite3 *)sqlite database:(ODODatabase *)database object:(ODOObject *)object error:(NSError **)outError;
{
    OBPRECONDITION(sqlite);
    OBPRECONDITION(database);
    OBPRECONDITION(object);

    ODOSQLStatement *updateStatement = [database _cachedStatementForKey:_updateStatementKey];
    if (!updateStatement) {
        NSMutableString *sql = [[NSMutableString alloc] initWithFormat:@"UPDATE %@ SET ", _name];
        NSUInteger propertyIndex, propertyCount = [_schemaProperties count];
        BOOL firstProp = YES;
        for (propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++) {
            ODOProperty *prop = [_schemaProperties objectAtIndex:propertyIndex];
            if (prop == _primaryKeyAttribute) // Primary key gets bound last in the "WHERE" clause
                continue;

            if (firstProp) {
                [sql appendFormat:@"%@=?", [prop name]];
                firstProp = NO;
            } else
                [sql appendFormat:@", %@=?", [prop name]];
        }
        [sql appendFormat:@" WHERE %@ = ?", [_primaryKeyAttribute name]];
        
        ODODatabase *database = [[object editingContext] database];
        updateStatement = [[ODOSQLStatement alloc] initWithDatabase:database sql:sql error:outError];
        [sql release];
        if (!updateStatement)
            return NO;

        [database _setCachedStatement:updateStatement forKey:_updateStatementKey];
        [updateStatement release];

        // clang scan-build will issue a use-after release warning below if we don't do this (since it doesn't know that -_setCachedStatement:forKey: will retain.  Really, this makes sense since the method might do anything, including rejecting the new statement for some reason.  So, look it up again.
        updateStatement = [database _cachedStatementForKey:_updateStatementKey];
}
    
    // Bind all the property values.
    if (!_bindUpdateSchemaProperties(sqlite, updateStatement, object, _schemaProperties, _primaryKeyAttribute, outError))
        return NO;
    
    return ODOSQLStatementRunWithoutResults(sqlite, updateStatement, outError);
}

- (BOOL)_writeDelete:(struct sqlite3 *)sqlite database:(ODODatabase *)database object:(ODOObject *)object error:(NSError **)outError;
{
    OBPRECONDITION(sqlite);
    OBPRECONDITION(database);
    OBPRECONDITION(object);
    
    ODOSQLStatement *statement = [database _cachedStatementForKey:_deleteStatementKey];
    if (!statement) {
        NSMutableString *sql = [[NSMutableString alloc] initWithFormat:@"DELETE FROM %@ WHERE %@ = ?", _name, [_primaryKeyAttribute name]];
        
        ODODatabase *database = [[object editingContext] database];
        statement = [[ODOSQLStatement alloc] initWithDatabase:database sql:sql error:outError];
        [sql release];
        if (!statement)
            return NO;
        
        [database _setCachedStatement:statement forKey:_deleteStatementKey];
        [statement release];

    
        // clang scan-build will issue a use-after release warning below if we don't do this (since it doesn't know that -_setCachedStatement:forKey: will retain.  Really, this makes sense since the method might do anything, including rejecting the new statement for some reason.  So, look it up again.
        statement = [database _cachedStatementForKey:_deleteStatementKey];
    }
    
    // Bind the primary key attribute in the single slot for the WHERE
    if (!_bindPlainAttribute(sqlite, statement, object, 0, _primaryKeyAttribute, outError))
        return NO;
    
    ODOSQLStatementCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.row = ODOSQLStatementIgnoreUnexpectedRow;
#ifdef OMNI_ASSERTIONS_ON
    callbacks.atEnd = ODOSQLStatementCheckForSingleChangedRow;
#endif
    
    return ODOSQLStatementRun(sqlite, statement, callbacks, NULL, outError);
}

- (ODOSQLStatement *)_queryByPrimaryKeyStatement:(NSError **)outError database:(ODODatabase *)database;
{
    ODOSQLStatement *queryByPrimaryKeyStatement = [database _cachedStatementForKey:_queryByPrimaryKeyStatementKey];
    if (!queryByPrimaryKeyStatement) {
        NSPredicate *predicate = ODOKeyPathEqualToValuePredicate([_primaryKeyAttribute name], @"something"); // Fake up a constant for the build.  Don't use nil/null since that'd get translated to 'IS NULL'.
        queryByPrimaryKeyStatement = [[ODOSQLStatement alloc] initSelectProperties:[self _schemaProperties] fromEntity:self database:database predicate:predicate error:outError];
        if (!queryByPrimaryKeyStatement)
            return nil;
        
        [database _setCachedStatement:queryByPrimaryKeyStatement forKey:_queryByPrimaryKeyStatementKey];
        [queryByPrimaryKeyStatement release];
    }
    return queryByPrimaryKeyStatement;
}

@end
