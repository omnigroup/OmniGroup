// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOSQLStatement.h"

#import <OmniFoundation/NSDate-OFExtensions.h> // For -[NSDate xmlString]
#import <OmniDataObjects/ODOFloatingDate.h>
#import <OmniDataObjects/ODOProperty.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/ODOSQLConnection.h>
#import <OmniDataObjects/ODOPredicate-SQL.h>

#import "ODOObject-Accessors.h"
#import "ODOObject-Internal.h"
#import "ODOEntity-SQL.h"
#import "ODODatabase-Internal.h"

#import <sqlite3.h>

#if 0 && defined(DEBUG)
    #define TRACK_INSTANCES(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define TRACK_INSTANCES(format, ...) do {} while (0)
#endif

RCS_ID("$Id$")

@implementation ODOSQLFetchAggregation

+ (instancetype)aggregationWithExtremum:(ODOFetchExtremum)extremum attribute:(ODOAttribute *)attribute;
{
    return [[[self alloc] initWithExtremum:extremum attribute:attribute] autorelease];
}

- (instancetype)initWithExtremum:(ODOFetchExtremum)extremum attribute:(ODOAttribute *)attribute;
{
    if (!(self = [super init])) {
        return nil;
    }
    _extremum = extremum;
    _attribute = [attribute retain];
    return self;
}

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

- (void)dealloc;
{
    [_attribute release];
    [super dealloc];
}

- (NSString *)debugDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, [self _sqliteAggregateColumnSpecification]];
}

- (NSString *)_sqliteAggregateColumnSpecification;
{
    NSString *key = [_attribute name];
    switch (self.extremum) {
        case ODOFetchMinimum: return [NSString stringWithFormat:@"min(%@)", key];
        case ODOFetchMaximum: return [NSString stringWithFormat:@"max(%@)", key];
    }
}

@end

#pragma mark -

@interface ODOSQLStatement (/*Private*/)

@property (nonatomic, strong, readwrite) ODOSQLConnection *connection;
@property (nonatomic, copy) NSArray *bindingConstants;

- (instancetype)_initSelectStatement:(NSMutableString *)mutableSQL fromTable:(ODOSQLTable *)table connection:(ODOSQLConnection *)connection predicate:(NSPredicate *)predicate error:(NSError **)outError;

@end

@implementation ODOSQLStatement
{
    struct OBBacktraceBuffer *_creationBacktrace;
}

static NSNotificationName ODOSQLStatementLogBacktraceIfPreparedNotification = @"ODOSQLStatementLogBacktraceIfPrepared";

+ (void)logBacktracesForPreparedStatements;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:ODOSQLStatementLogBacktraceIfPreparedNotification object:nil];
}

+ (instancetype)preparedStatementWithConnection:(ODOSQLConnection *)connection SQLite:(struct sqlite3 *)sqlite sql:(NSString *)sql error:(NSError **)outError;
{
    ODOSQLStatement *result = [[self alloc] initWithConnection:connection sql:sql error:outError];
    if (result == nil) {
        return nil;
    }
    
    if (![result prepareIfNeededWithSQLite:sqlite error:outError]) {
        [result release];
        return nil;
    }
    
    return [result autorelease];
}

- (instancetype)initWithConnection:(ODOSQLConnection *)connection sql:(NSString *)sql error:(NSError **)outError;
{
    OBPRECONDITION(connection);
    OBPRECONDITION([sql length] > 0);
    
    if (!(self = [super init])) {
        return nil;
    }
    
    _sql = [sql copy];
    _connection = [connection retain];
    _creationBacktrace = OBCreateBacktraceBuffer("create statement", OBBacktraceBuffer_Generic, self);

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_logBacktraceIfPrepared:) name:ODOSQLStatementLogBacktraceIfPreparedNotification object:nil];

    return self;
}

- (instancetype)initSelectProperties:(NSArray *)properties fromEntity:(ODOEntity *)rootEntity connection:(ODOSQLConnection *)connection predicate:(NSPredicate *)predicate error:(NSError **)outError;
{
    return [self initSelectProperties:properties usingAggregation:nil fromEntity:rootEntity connection:connection predicate:predicate error:outError];
}

- (instancetype)initSelectProperties:(NSArray<ODOProperty *> *)properties usingAggregation:(ODOSQLFetchAggregation *)aggregation fromEntity:(ODOEntity *)rootEntity connection:(ODOSQLConnection *)connection predicate:(NSPredicate *)predicate error:(NSError **)outError;
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
    
    if (aggregation != nil) {
        // We are guaranteed to have at least one column spec by now because we asserted `[properties count] > 0` above
        [sql appendString:@", "];
        [sql appendString:[aggregation _sqliteAggregateColumnSpecification]];
        _hasAggregateColumnSpecification = YES;
    }

    ODOSQLTable *table = [[ODOSQLTable alloc] initWithEntity:rootEntity];
    [sql appendFormat:@" FROM %@ %@", rootEntity.name, [table aliasForEntity:rootEntity]];
    
    ODOSQLStatement *result = [self _initSelectStatement:sql fromTable:table connection:connection predicate:predicate error:outError];

    [table release];
    return result;
}

- (instancetype)initRowCountFromEntity:(ODOEntity *)rootEntity connection:(ODOSQLConnection *)connection predicate:(NSPredicate *)predicate error:(NSError **)outError;
{
    OBPRECONDITION(rootEntity != nil);

    ODOSQLTable *table = [[ODOSQLTable alloc] initWithEntity:rootEntity];
    NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT COUNT(*) FROM %@ %@", rootEntity.name, [table aliasForEntity:rootEntity]];
    ODOSQLStatement *result = [self _initSelectStatement:sql fromTable:table connection:connection predicate:predicate error:outError];
    [table release];
    return result;
}

- (instancetype)_initSelectStatement:(NSMutableString *)mutableSQL fromTable:(ODOSQLTable *)table connection:(ODOSQLConnection *)connection predicate:(NSPredicate *)predicate error:(NSError **)outError;
{
    OBPRECONDITION(table != nil);
    OBPRECONDITION(connection != nil);
    
    // TODO: Not handling joins until we actually need them.
    
    NSMutableArray *constants = nil;
    if (predicate) {
        constants = [NSMutableArray array];
        [mutableSQL appendString:@" WHERE "];
        if (![predicate appendSQL:mutableSQL table:table constants:constants error:outError]) {
            [self release];
            return nil;
        }
    }
    
    if (!(self = [self initWithConnection:connection sql:mutableSQL error:outError])) {
        return nil;
    }
    
    _bindingConstants = [constants copy];
    
#if 0 && defined(DEBUG)
    NSLog(@"predicate:%@ -> sql:%@ constants:%@", predicate, _sql, constants);
#endif
    
    return self;
}

- (void)dealloc;
{
    if (_statement) {
        [self invalidate];
    }
    [_bindingConstants release];
    [_connection release];
    [_sql release];
    OBFreeBacktraceBuffer(_creationBacktrace);

    [[NSNotificationCenter defaultCenter] removeObserver:self name:ODOSQLStatementLogBacktraceIfPreparedNotification object:nil];

    [super dealloc];
}

- (void)invalidate;
{
    // N.B. We no longer have a precondition that _statement != NULL. Since we lazy evaluate the statement in -prepareIfNeededWithSQLite:error:, we can have a fully formed object which failed to ever create a statement. -invalidate should be a no-op in that case.
    if (_statement == NULL) {
        return;
    }
    
    // We can't leave an ivar reference in the block below – in the case that we're called on the -dealloc path, referencing an ivar in the block would attempt to retain self, which is an error.
    // Instead, copy the ivar to a local, then clear it right away. The finalization path is still synchronous, so everything will be accurate as of the end of this method.
    TRACK_INSTANCES(@"STMT %p:FIN", self);
    struct sqlite3_stmt *finalizingStatement = _statement;
    _statement = NULL;
    [_connection performSQLBlock:^(struct sqlite3 *sqlite) {
        sqlite3_finalize(finalizingStatement);
    }];
}

- (BOOL)isPrepared;
{
    return (_statement != NULL);
}

- (BOOL)prepareIfNeededWithSQLite:(struct sqlite3 *)sqlite error:(NSError **)outError;
{
    OBPRECONDITION([_connection checkExecutingOnDispatchQueue]);
    OBPRECONDITION([_connection checkIsManagedSQLite:sqlite]);
    
    if ([self isPrepared]) {
        return YES;
    }

    const char *sqlTail = NULL;
    int rc = sqlite3_prepare_v2(sqlite, [_sql UTF8String], -1/*length -> to NUL*/, &_statement, &sqlTail);
    if (rc != SQLITE_OK) {
        OBASSERT(_statement == NULL);
        ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
        
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to create SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable prepare statement for SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), _sql];
        ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
        return NO;
    }
    
    // Bind the constants we found.  We only know their manifest type here.  We *could* try to enforce type safety when we are doing key/comp/value.
    NSUInteger constIndex, constCount = [_bindingConstants count];
    for (constIndex = 0; constIndex < constCount; constIndex++) {
        id constant = [_bindingConstants objectAtIndex:constIndex];
        NSUInteger bindIndex = constIndex + 1; // one-based.
        OBASSERT(bindIndex < INT_MAX);
        if (!ODOSQLStatementBindConstant(self, sqlite, constant, (int)bindIndex, outError)) {
            return NO;
        }
    }
    
    TRACK_INSTANCES(@"STMT %p:INI on db %p with sql '%@'", self, database, sql);
    return YES;
}

- (void)_logBacktraceIfPrepared:(NSNotification *)note;
{
    // We aren't properly on the right queue here and shouldn't be looking at the _statement ivar normally, but this is only called if sqlite_close failed with SQLITE_BUSY and we are about to crash on an unhandled exception.
    if (_statement != NULL) {
        OBAddBacktraceBuffer(_creationBacktrace);
    }
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

BOOL ODOSQLStatementBindXMLDateTime(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSDate *date, NSError **outError)
{
    OBPRECONDITION(date); // use Null otherwise
    OBPRECONDITION([date isKindOfClass:[NSDate class]]);

    // Avoid float-returning message to nil.
    if (!date)
        return ODOSQLStatementBindNull(sqlite, statement, bindIndex, outError);

    NSString *xmlString = [date xmlString];

    // TODO: Performance; SQLITE_TRANSIENT causes SQLite to make a copy.  But, we should typically be binding and then executing immediately.  To be sure, we could always clear values after executing.
    int rc = sqlite3_bind_text(statement->_statement, bindIndex, [xmlString UTF8String], -1, SQLITE_TRANSIENT);
    if (rc == SQLITE_OK)
        return YES;

    ODOSQLiteError(outError, rc, sqlite); // stack the underlying error
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind value to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind XML date/time to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), bindIndex, statement->_sql];
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
            case kCFNumberIntType: {
                if (!ODOSQLStatementBindInt32(sqlite, self, bindIndex, [constant intValue], outError))
                    return NO;
                break;
            }
            case kCFNumberSInt64Type:
            case kCFNumberLongLongType:
            case kCFNumberNSIntegerType: {
                if (!ODOSQLStatementBindInt64(sqlite, self, bindIndex, [constant longLongValue], outError))
                    return NO;
                break;
            }
            default: {
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to bind constant to SQL statement.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable bind number '%@' of type %ld to slot %d of statement with SQL '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), constant, type, bindIndex, self->_sql];
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
        case ODOAttributeTypeInt32: {
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
            if (utf8 == NULL) {
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

        case ODOAttributeTypeXMLDateTime: {
            const uint8_t *utf8 = sqlite3_column_text(statement->_statement, columnIndex);
            if (utf8 == NULL) {
                OBASSERT_NOT_REACHED("Should have been caught by the SQLITE_NULL check");
                *value = nil;
                return YES;
            }

            int byteCount = sqlite3_column_bytes(statement->_statement, columnIndex); // sqlite3.h says this includes the NUL, but it doesn't seem to.
            OBASSERT(utf8[byteCount] == 0); // Check that the null is where we expected, since there is some confusion
            NSString *xmlString = [[NSString alloc] initWithBytes:utf8 length:byteCount encoding:NSUTF8StringEncoding];
            Class dateParsingClass = [ODOFloatingDate class];
            NSDate *result = [[dateParsingClass alloc] initWithXMLString:xmlString];
            [xmlString release];
            if (result == nil)
                *value = result;
            else if ([result isKindOfClass:valueClass])
                *value = result;
            else {
                *value = [[valueClass alloc] initWithTimeIntervalSinceReferenceDate:result.timeIntervalSinceReferenceDate];
                [result release];
            }
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
            int byteCount = sqlite3_column_bytes(statement->_statement, columnIndex);

            if (valueClass == Nil) {
                valueClass = [NSData class];
            }

            // sqlite will return SQLITE_NULL for the column type for a NULL blob, but returns SQLITE_BLOB and NULL bytes for a 0-length blog.
            if (bytes == NULL) {
                OBASSERT(byteCount == 0);
                *value = [[valueClass alloc] initWithBytes:NULL length:0];
                return YES;
            }
            
            *value = [[valueClass alloc] initWithBytes:bytes length:byteCount];
            return YES;
        }

        default: {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to execute SQL.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable get value of type %ld for result column %d of '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), type, columnIndex, statement->_sql];
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
    OBPRECONDITION([statement.connection checkExecutingOnDispatchQueue]);
    OBPRECONDITION([statement.connection checkIsManagedSQLite:sqlite]);
    
    if (![statement prepareIfNeededWithSQLite:sqlite error:outError]) {
        return NO;
    }
    
    static CFAbsoluteTime totalTime = 0;
    static unsigned int totalRowCount = 0;
    
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    NSUInteger rowCount = 0;
    if (ODOSQLDebugLogLevel > 0)
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
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to run SQL for statement '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), statement->_sql];
        ODOError(outError, ODOUnableToExecuteSQL, description, reason);
        return NO;
    }
    
    if (ODOSQLDebugLogLevel > 0) {
        CFAbsoluteTime delta = CFAbsoluteTimeGetCurrent() - start;
        
        totalTime += delta;
        totalRowCount += rowCount;
        
        ODOSQLStatementLogSQL(@"/* ... %ld rows fetched, %d rows changed, %g sec, total now %g sec, %d rows */\n", rowCount, sqlite3_changes(sqlite), delta, totalTime, totalRowCount);
    }
    
    if (callbacks.atEnd && !callbacks.atEnd(sqlite, statement, context, outError))
        return NO;

    // This does not reset bound variables, just puts the virtual machine back at its starting state.  The return code from sqlite3_reset is just a repeat of the last error from sqlite3_step (or SQLITE_OK if a row/done was last returned);
#ifdef OMNI_ASSERTIONS_ON
    rc = 
#endif
    sqlite3_reset(statement->_statement);
    OBASSERT(rc == SQLITE_OK);
#pragma unused(rc)
    return YES;
}


BOOL ODOSQLStatementIgnoreUnexpectedRow(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
    OBASSERT_NOT_REACHED("Caller shouldn't give us stuff that returns results");
    return YES;
}

BOOL ODOSQLStatementIgnoreExpectedRow(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
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

BOOL ODOSQLStatementRunIgnoringResults(struct sqlite3 *sqlite, ODOSQLStatement *statement, NSError **outError)
{
    ODOSQLStatementCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.row = ODOSQLStatementIgnoreExpectedRow;

    return ODOSQLStatementRun(sqlite, statement, callbacks, NULL, outError);
}

BOOL ODOExtractNonPrimaryKeySchemaPropertiesFromRowIntoObject(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOObject *object, NSArray <ODOProperty *> *schemaProperties, NSUInteger primaryKeyColumnIndex, NSError **outError)
{
    ODOObjectSetChangeProcessingEnabled(object, NO);
    @try {
        NSUInteger propertyIndex = [schemaProperties count];
        while (propertyIndex--) {
            if (propertyIndex == primaryKeyColumnIndex)
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
            if (!ODOSQLStatementCreateValue(sqlite, statement, (int)propertyIndex, &value, [attr type], [attr valueClass], outError)) {
                return NO;
            }
            
            // DO NOT use -willChangeValueForKey: and -didChangeValueForKey: here.  We don't want KVO and we don't want changes to get logged since we aren't "changing" the object.
            OBASSERT(!ODOObjectChangeProcessingEnabled(object)); // this should be off anyway since we haven't yet awoken from fetch.
            
            // Set the internal value directly
            _ODOObjectSetObjectValueForProperty(object, prop, value);
            [value release];
            
            OBASSERT(![object isUpdated]); // In this case, mutating the object should not have marked it edited
        }
    } @finally {
        ODOObjectSetChangeProcessingEnabled(object, YES);
    }
    
    return YES;
}
