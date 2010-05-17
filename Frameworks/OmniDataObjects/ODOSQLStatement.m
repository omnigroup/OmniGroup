// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOSQLStatement.h"

#import <OmniDataObjects/ODOProperty.h>
#import <OmniDataObjects/ODORelationship.h>

#import "ODOObject-Accessors.h"
#import "ODOObject-Internal.h"
#import "ODOEntity-SQL.h"
#import "ODODatabase-Internal.h"
#import "ODOPredicate-SQL.h"

#import <sqlite3.h>

#if 0 && defined(DEBUG)
    #define TRACK_INSTANCES(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define TRACK_INSTANCES(format, ...) do {} while (0)
#endif

RCS_ID("$Id$")

@interface ODOSQLStatement (Private)
- (id)_initSelectStatement:(NSMutableString *)mutableSQL fromEntity:(ODOEntity *)rootEntity database:(ODODatabase *)database predicate:(NSPredicate *)predicate error:(NSError **)outError;
@end

@implementation ODOSQLStatement

- initWithDatabase:(ODODatabase *)database sql:(NSString *)sql error:(NSError **)outError;
{
    OBPRECONDITION(database);
    OBPRECONDITION([database connectedURL]);
    OBPRECONDITION([sql length] > 0);
    
    _sql = [sql copy];
    
    sqlite3 *sqlite = [database _sqlite];

    const char *sqlTail = NULL;
    int rc = sqlite3_prepare(sqlite, [_sql UTF8String], -1/*length -> to NUL*/, &_statement, &sqlTail);
    if (rc != SQLITE_OK) {
        OBASSERT(_statement == NULL);
        ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
        
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to create SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable prepare statement for SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), _sql];
        ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
        [self release];
        return nil;
    }
    
    TRACK_INSTANCES(@"STMT %p:INI on db %p with sql '%@'", self, database, sql);
    return self;
}

- initSelectProperties:(NSArray *)properties fromEntity:(ODOEntity *)rootEntity database:(ODODatabase *)database predicate:(NSPredicate *)predicate error:(NSError **)outError;
{
    OBPRECONDITION([properties count] > 0);
    
    // TODO: Not handling joins until we actually need them.
    
    NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT "];

    // TODO: Map ODOObject constants to their primary keys (but allow raw primary key values too).
    
    // This will usually either be just the pk for the root entity or all the schema attributes of the root entity.
    NSUInteger propertyIndex, propertyCount = [properties count];
    for (propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++) {
        ODOProperty *prop = [properties objectAtIndex:propertyIndex];
#ifdef OMNI_ASSERTIONS_ON
        OBASSERT([[rootEntity _schemaProperties] containsObject:prop]);
#endif
        
        if (propertyIndex != 0)
            [sql appendString:@", "];
        [sql appendString:[prop name]];
    }

    [sql appendFormat:@" FROM %@", [rootEntity name]];
    
    return [self _initSelectStatement:sql fromEntity:rootEntity database:database predicate:predicate error:outError];
}

- initRowCountFromEntity:(ODOEntity *)rootEntity database:(ODODatabase *)database predicate:(NSPredicate *)predicate error:(NSError **)outError;
{
    OBPRECONDITION(rootEntity != nil);

    NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT COUNT(*) FROM %@", [rootEntity name]];
    return [self _initSelectStatement:sql fromEntity:rootEntity database:database predicate:predicate error:outError];
}

- (void)dealloc;
{
    if (_statement)
        [self invalidate];
    [_sql release];
    [super dealloc];
}

- (void)invalidate;
{
    OBPRECONDITION(_statement);
    
    if (!_statement)
        return;
    
    TRACK_INSTANCES(@"STMT %p:FIN", self);
    sqlite3_finalize(_statement);
    _statement = NULL;
}

@end

@implementation ODOSQLStatement (Private)

- (id)_initSelectStatement:(NSMutableString *)mutableSQL fromEntity:(ODOEntity *)rootEntity database:(ODODatabase *)database predicate:(NSPredicate *)predicate error:(NSError **)outError;
{
    OBPRECONDITION(rootEntity != nil);
    OBPRECONDITION(database != nil);
    OBPRECONDITION([rootEntity model] == [database model]);
    
    // TODO: Not handling joins until we actually need them.
    
    NSMutableArray *constants = nil;
    if (predicate) {
        constants = [NSMutableArray array];
        [mutableSQL appendString:@" WHERE "];
        if (![predicate _appendSQL:mutableSQL entity:rootEntity constants:constants error:outError]) {
            [self release];
            return nil;
        }
    }
    
    if (![self initWithDatabase:database sql:mutableSQL error:outError])
        return nil;
    
    if (constants) {
        // Bind the constants we found.  We only know their manifest type here.  We *could* try to enforce type safety when we are doing key/comp/value.
        sqlite3 *sqlite = [database _sqlite];
        
        NSUInteger constIndex, constCount = [constants count];
        for (constIndex = 0; constIndex < constCount; constIndex++) {
            id constant = [constants objectAtIndex:constIndex];
            NSUInteger bindIndex = constIndex + 1; // one-based.
            OBASSERT(bindIndex < INT_MAX);
            if (!ODOSQLStatementBindConstant(self, sqlite, constant, (int)bindIndex, outError)) {
                [self release];
                return nil;
            }
        }
    }
    
#if 0 && defined(DEBUG)
    NSLog(@"predicate:%@ -> sql:%@ constants:%@", predicate, _sql, constants);
#endif
    
    return self;
}

@end

BOOL ODOSQLStatementBindNull(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSError **outError)
{
    int rc = sqlite3_bind_null(statement->_statement, bindIndex);
    if (rc == SQLITE_OK)
        return YES;
    
    ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind null to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind null to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), bindIndex, statement->_sql];
    ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
    return NO;
}

BOOL ODOSQLStatementBindString(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSString *string, NSError **outError)
{
    // TODO: Performance; SQLITE_TRANSIENT causes SQLite to make a copy.  But, we should typically be binding and then executing immediately.  To be sure, we could always clear values after executing.
    int rc = sqlite3_bind_text(statement->_statement, bindIndex, [string UTF8String], -1, SQLITE_TRANSIENT);
    if (rc == SQLITE_OK)
        return YES;
    
    ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind value to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind string to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), bindIndex, statement->_sql];
    ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
    return NO;
}

BOOL ODOSQLStatementBindData(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSData *data, NSError **outError)
{
    // TODO: Performance; SQLITE_TRANSIENT causes SQLite to make a copy.  But, we should typically be binding and then executing immediately.  To be sure, we could always clear values after executing.

    size_t dataLength = [data length];
    OBASSERT(dataLength < INT_MAX); // Not handling >4GB blobs
    
    int rc = sqlite3_bind_blob(statement->_statement, bindIndex, [data bytes], (int)dataLength, SQLITE_TRANSIENT);
    if (rc == SQLITE_OK)
        return YES;
    
    ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind value to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind data to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), bindIndex, statement->_sql];
    ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
    return NO;
}

BOOL ODOSQLStatementBindInt16(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, int16_t value, NSError **outError)
{
    int rc = sqlite3_bind_int(statement->_statement, bindIndex, value); // No int16 binding in SQLite; upgrade to a full int.
    if (rc == SQLITE_OK)
        return YES;
    
    ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind value to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind int16 to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), bindIndex, statement->_sql];
    ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
    return NO;
}

BOOL ODOSQLStatementBindInt32(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, int32_t value, NSError **outError)
{
    int rc = sqlite3_bind_int(statement->_statement, bindIndex, value);
    if (rc == SQLITE_OK)
        return YES;
    
    ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind value to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind int32 to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), bindIndex, statement->_sql];
    ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
    return NO;
}

BOOL ODOSQLStatementBindInt64(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, int64_t value, NSError **outError)
{
    int rc = sqlite3_bind_int64(statement->_statement, bindIndex, value);
    if (rc == SQLITE_OK)
        return YES;
    
    ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind value to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind int64 to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), bindIndex, statement->_sql];
    ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
    return NO;
}

BOOL ODOSQLStatementBindBoolean(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, BOOL value, NSError **outError)
{
    OBPRECONDITION(value == 0 || value == 1);
    
    int rc = sqlite3_bind_int(statement->_statement, bindIndex, value);
    if (rc == SQLITE_OK)
        return YES;
    
    ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind value to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind boolean to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), bindIndex, statement->_sql];
    ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
    return NO;
}

BOOL ODOSQLStatementBindDate(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSDate *date, NSError **outError)
{
    OBPRECONDITION(date); // use Null otherwise
    OBPRECONDITION([date isKindOfClass:[NSDate class]]);
    
    // Avoid float-returning message to nil.
    if (!date)
        return ODOSQLStatementBindNull(sqlite, statement, bindIndex, outError);
    
    NSTimeInterval ti = [date timeIntervalSinceReferenceDate];
    
    int rc = sqlite3_bind_double(statement->_statement, bindIndex, ti);
    if (rc == SQLITE_OK)
        return YES;
    
    ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind value to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind date to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), bindIndex, statement->_sql];
    ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
    return NO;
}

// No float32 value in sqlite3, just double.
BOOL ODOSQLStatementBindFloat64(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, double value, NSError **outError)
{
    int rc = sqlite3_bind_double(statement->_statement, bindIndex, value);
    if (rc == SQLITE_OK)
        return YES;
    
    ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind value to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind float64 to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), bindIndex, statement->_sql];
    ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
    return NO;
}

BOOL ODOSQLStatementBindConstant(ODOSQLStatement *self, struct sqlite3 *sqlite, id constant, int bindIndex, NSError **outError)
{
    if (OFISNULL(constant)) {
        if (!ODOSQLStatementBindNull(sqlite, self, bindIndex, outError))
            return NO;
    } else if ([constant isKindOfClass:[NSString class]]) {
        if (!ODOSQLStatementBindString(sqlite, self, bindIndex, constant, outError))
            return NO;
    } else if ([constant isKindOfClass:[NSNumber class]]) {
        // We do try to get the int vs float here
        CFNumberType type = CFNumberGetType((CFNumberRef)constant);
        switch (type) {
            case kCFNumberSInt8Type:
            case kCFNumberSInt16Type:
            case kCFNumberSInt32Type:
            case kCFNumberCharType:
            case kCFNumberShortType:
            case kCFNumberIntType:
                if (!ODOSQLStatementBindInt32(sqlite, self, bindIndex, [constant intValue], outError))
                    return NO;
                break;
                default: {
                    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind constant to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
                    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind number '%@' of type %d to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), constant, type, bindIndex, self->_sql];
                    ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
                    return NO;
                }
        }
    } else if ([constant isKindOfClass:[NSDate class]]) {
        if (!ODOSQLStatementBindDate(sqlite, self, bindIndex, constant, outError))
            return NO;
    } else {
        OBASSERT_NOT_REACHED("Unknown constant type");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind constant to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind constant '%@' of unknown type to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), constant, bindIndex, self->_sql];
        ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
        return NO;
    }
    
    return YES;
}

// Returns a retained object via 'value' on success.  Unlike binding, the columnIndex is zero-based.
BOOL ODOSQLStatementCreateValue(struct sqlite3 *sqlite, ODOSQLStatement *statement, int columnIndex, id *value, ODOAttributeType type, Class valueClass, NSError **outError)
{
    OBPRECONDITION(valueClass);
    
    // Check for NULL before any of the types below (since we can't tell for scalar types).
    if (sqlite3_column_type(statement->_statement, columnIndex) == SQLITE_NULL) {
        *value = nil;
        return YES;
    }
        
    switch (type) {
        case ODOAttributeTypeInt16:
        case ODOAttributeTypeInt32:
        {
            // Could fetch as int64 and check the range.  Maybe in DEBUG builds?
            int intValue = sqlite3_column_int(statement->_statement, columnIndex);
            *value = [[valueClass alloc] initWithInt:intValue];
            return YES;
        }
        case ODOAttributeTypeInt64: {
            int64_t intValue = sqlite3_column_int64(statement->_statement, columnIndex);
            *value = [[valueClass alloc] initWithLongLong:intValue];
            return YES;
        }
        case ODOAttributeTypeString: {
            const uint8_t *utf8 = sqlite3_column_text(statement->_statement, columnIndex);
            if (!utf8) {
                OBASSERT_NOT_REACHED("Should have been caught by the SQLITE_NULL check");
                *value = nil;
                return YES;
            }
                
            int byteCount = sqlite3_column_bytes(statement->_statement, columnIndex); // sqlite3.h says this includes the NUL, but it doesn't seem to.
            OBASSERT(utf8[byteCount] == 0); // Check that the null is where we expected, since there is some confusion
            *value = [[valueClass alloc] initWithBytes:utf8 length:byteCount encoding:NSUTF8StringEncoding];
            return YES;
        }
        case ODOAttributeTypeBoolean: {
            int intValue = sqlite3_column_int(statement->_statement, columnIndex);
            OBASSERT(intValue == 0 || intValue == 1);
            *value = [[valueClass alloc] initWithBool:intValue ? YES : NO];
            return YES;
        }
        case ODOAttributeTypeDate: {
            NSTimeInterval ti = sqlite3_column_double(statement->_statement, columnIndex);
            *value = [[valueClass alloc] initWithTimeIntervalSinceReferenceDate:ti];
            return YES;
        }
        case ODOAttributeTypeFloat32: // No independent float32 value in sqlite3
        case ODOAttributeTypeFloat64: {
            double f = sqlite3_column_double(statement->_statement, columnIndex);
            *value = [[valueClass alloc] initWithDouble:f];
            return YES;
        }
        case ODOAttributeTypeData: {
            const void *bytes = sqlite3_column_blob(statement->_statement, columnIndex);
            if (!bytes) {
                OBASSERT_NOT_REACHED("Should have been caught by the SQLITE_NULL check");
                *value = nil;
                return YES;
            }

            if (!valueClass)
                valueClass = [NSData class];

            int byteCount = sqlite3_column_bytes(statement->_statement, columnIndex);
            *value = [[valueClass alloc] initWithBytes:bytes length:byteCount];
            return YES;
        }
        default: {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to execute SQL.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable get value of type %d for result column %d of '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), type, columnIndex, statement->_sql];
            ODOError(outError, ODOUnableToExecuteSQL, description, reason);
            return NO;
        }
    }
}


void ODOSQLStatementLogSQL(NSString *format, ...)
{
    va_list args;
    
    va_start(args, format);
    NSString *sql = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    if ([sql length] > 0) {
        CFDataRef data = CFStringCreateExternalRepresentation(kCFAllocatorDefault, (CFStringRef)sql, kCFStringEncodingUTF8, '?');
        OBASSERT(data);
        if (data) {
            fwrite(CFDataGetBytePtr(data), CFDataGetLength(data), 1, stderr);
            CFRelease(data);
        }
    }
    [sql release];
}

BOOL ODOSQLStatementRun(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOSQLStatementCallbacks callbacks, void *context, NSError **outError)
{
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    NSUInteger rowCount = 0;
    if (ODOLogSQL)
        ODOSQLStatementLogSQL(@"%@;\n", statement->_sql); // ';' not included when we build the SQL.  Of course, this will still have bind '?' placeholders
    
    int rc;
    while (YES) {
        rc = sqlite3_step(statement->_statement);
        if (rc == SQLITE_ROW) {
            if (!callbacks.row(sqlite, statement, context, outError)) {
                sqlite3_reset(statement->_statement); // result should just be a repeat of the error we already got
                return NO;
            }
            rowCount++;
            continue;
        }
        if (rc == SQLITE_DONE)
            break;
        
        sqlite3_reset(statement->_statement);
        
        ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to execute SQL.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable run SQL for statement '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), statement->_sql];
        ODOError(outError, ODOUnableToExecuteSQL, description, reason);
        return NO;
    }
    
    if (ODOLogSQL) {
        CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
        ODOSQLStatementLogSQL(@"/* ... %d rows fetched, %d rows changed, %g sec */\n", rowCount, sqlite3_changes(sqlite), end - start);
    }
    
    if (callbacks.atEnd && !callbacks.atEnd(sqlite, statement, context, outError))
        return NO;

    // This does not reset bound variables, just puts the virtual machine back at its starting state.  The return code from sqlite3_reset is just a repeat of the last error from sqlite3_step (or SQLITE_OK if a row/done was last returned);
#ifdef OMNI_ASSERTIONS_ON
    rc = 
#endif
    sqlite3_reset(statement->_statement);
    OBASSERT(rc == SQLITE_OK);
    return YES;
}


BOOL ODOSQLStatementIgnoreUnexpectedRow(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
    OBASSERT_NOT_REACHED("Caller shouldn't give us stuff that returns results");
    return YES;
}

#ifdef OMNI_ASSERTIONS_ON
BOOL ODOSQLStatementCheckForSingleChangedRow(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
    // For example, when deleting by primary key, there should be exactly one row changed.
    OBASSERT(sqlite3_changes(sqlite) == 1);
    return YES;
}
#endif

BOOL ODOSQLStatementRunWithoutResults(struct sqlite3 *sqlite, ODOSQLStatement *statement, NSError **outError)
{
    ODOSQLStatementCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.row = ODOSQLStatementIgnoreUnexpectedRow;

    return ODOSQLStatementRun(sqlite, statement, callbacks, NULL, outError);
}


BOOL ODOExtractNonPrimaryKeySchemaPropertiesFromRowIntoObject(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOObject *object, ODORowFetchContext *ctx, NSError **outError)
{
    ODOObjectSetChangeProcessingEnabled(object, NO);
    @try {
        NSArray *schemaProperties = ctx->schemaProperties;
        NSUInteger propertyIndex = [schemaProperties count];
        while (propertyIndex--) {
            if (propertyIndex == ctx->primaryKeyColumnIndex)
                continue;
            
            ODOProperty *prop = [schemaProperties objectAtIndex:propertyIndex];
            id value;
            
            ODOAttribute *attr;
            if ([prop isKindOfClass:[ODOAttribute class]]) {
                attr = (ODOAttribute *)prop;
            } else {
                ODORelationship *rel = (ODORelationship *)prop;
                OBASSERT([rel isKindOfClass:[ODORelationship class]]);
                OBASSERT(![rel isToMany]);
                
                // Here we fetch the foreign key.  Note this means that the primitive value for this property might be a raw primary key value instead of a fault/object.  This is nice since it saves memory (over creating a fault that might never be used).
                attr = [[rel destinationEntity] primaryKeyAttribute];
            }
            
            OBASSERT(propertyIndex <= INT_MAX);
            if (!ODOSQLStatementCreateValue(sqlite, statement, (int)propertyIndex, &value, [attr type], [attr valueClass], outError))
                return NO;
            
            // DO NOT use -willChangeValueForKey: and -didChangeValueForKey: here.  We don't want KVO and we don't want changes to get logged since we aren't "changing" the object.
            OBASSERT(!ODOObjectChangeProcessingEnabled(object)); // this should be off anyway since we haven't yet awoken from fetch.
            
            // Set the internal value directly
            ODOObjectSetInternalValueForProperty(object, value, prop);
            [value release];
            
            OBASSERT(![object isUpdated]); // In this case, mutating the object should not have marked it edited
        }
    } @finally {
        ODOObjectSetChangeProcessingEnabled(object, YES);
    }
    
    return YES;
}
