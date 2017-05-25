// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODODatabase.h>

#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODOEditingContext.h>
#import <OmniDataObjects/ODOEntity.h>
#import <OmniDataObjects/ODOFetchRequest.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/ODOSQLConnection.h>
#import <OmniDataObjects/NSPredicate-ODOExtensions.h>

#import <OmniFoundation/OFXMLIdentifier.h>

#import "ODODatabase-Internal.h"
#import "ODOEntity-Internal.h"
#import "ODOModel-SQL.h"
#import "ODOSQLStatement.h"
#import "ODOPredicate-SQL.h"

#import <sqlite3.h>

RCS_ID("$Id$")

NSString * const ODODatabaseMetadataTableName = @"ODOMetadata";
NSString * const ODODatabaseMetadataKeyColumnName = @"key";
NSString * const ODODatabaseMetadataPlistColumnName = @"value";

static BOOL isPlainASCII(const unsigned char *str)
{
    char c;
    while ((c = *str)) {
        if (c & 0x80)
            return NO;
        str++;
    }
    return YES;
}

typedef enum {
    ODOComparisonPredicateContainsStartLocation,
    ODOComparisonPredicateContainsAnywhereLocation,
} ODOComparisonPredicateContainsLocation;

static void ODOComparisonPredicateContainsStringGeneric(sqlite3_context *ctx, int nArgs, sqlite3_value **values, ODOComparisonPredicateContainsLocation location)
{
    if (nArgs != 3) {
        sqlite3_result_error(ctx, "Required 3 arguments.", SQLITE_ERROR);
        return;
    }
    
    const unsigned char *lhs = sqlite3_value_text(values[0]);
    if (lhs == NULL) { // A null value does not contain anything
        sqlite3_result_int(ctx, false);
        return;
    }

    const unsigned char *rhs = sqlite3_value_text(values[1]);
    int options = sqlite3_value_int(values[2]);
    
    // If the inputs are plain ASCII or we want to do an exact match, we can do this in terms of byte matching.
    if (options == 0 || (isPlainASCII(lhs) && isPlainASCII(rhs))) {
        const char *foundPointer = strcasestr((const char *)lhs, (const char *)rhs); // LHS starts-with/contains RHS
        if (foundPointer == NULL) {
            sqlite3_result_int(ctx, false);
            return;
        }
        
        if (location == ODOComparisonPredicateContainsAnywhereLocation) {
            sqlite3_result_int(ctx, true);
            return;
        } else {
            OBASSERT(location == ODOComparisonPredicateContainsStartLocation);
            sqlite3_result_int(ctx, (const char *)foundPointer == (const char *)lhs);
            return;
        }
    }
    
    // Need to do the hard case.
    CFStringRef lhsString = CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, (const char *)lhs, kCFStringEncodingUTF8, kCFAllocatorNull);
    CFStringRef rhsString = CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, (const char *)rhs, kCFStringEncodingUTF8, kCFAllocatorNull);
    
    // Diacritic/case insensitivity
    CFOptionFlags cfOptions = 0;
    if (options & NSCaseInsensitivePredicateOption)
        cfOptions |= kCFCompareCaseInsensitive;
    if (options & NSDiacriticInsensitivePredicateOption)
        cfOptions |= kCFCompareDiacriticInsensitive;
    OBASSERT((options & (NSCaseInsensitivePredicateOption|NSDiacriticInsensitivePredicateOption)) == options); // should be the only flags
    
    if (location == ODOComparisonPredicateContainsStartLocation)
        cfOptions |= kCFCompareAnchored;
    else
        OBASSERT(location == ODOComparisonPredicateContainsAnywhereLocation);

    CFRange foundRange = CFStringFind(lhsString, rhsString, cfOptions);
    CFRelease(lhsString);
    CFRelease(rhsString);

    sqlite3_result_int(ctx, foundRange.length > 0);
}

static void ODOComparisonPredicateStartsWithFunction(sqlite3_context *ctx, int nArgs, sqlite3_value **values)
{
    ODOComparisonPredicateContainsStringGeneric(ctx, nArgs, values, ODOComparisonPredicateContainsStartLocation);
}
static void ODOComparisonPredicateContainsFunction(sqlite3_context *ctx, int nArgs, sqlite3_value **values)
{
    ODOComparisonPredicateContainsStringGeneric(ctx, nArgs, values, ODOComparisonPredicateContainsAnywhereLocation);
}

BOOL ODOLogSQL = NO;
static BOOL ODOAsynchronousWrites = NO;
static BOOL ODOKeepTemporaryStoreInMemory = NO;
static BOOL ODOVacuumOnDisconnect = NO;

@interface ODODatabase (/*Private*/)

@property (nonatomic, strong, readwrite) ODOSQLConnection *connection;

- (BOOL)_setupNewDatabase:(NSError **)outError;
- (BOOL)_populateCachedMetadata:(NSError **)outError;
- (BOOL)_disconnectWithoutNotifying:(NSError **)outError;

@end

@implementation ODODatabase {
  @private
    ODOModel *_model;
    
    ODOSQLStatement *_metadataInsertStatement;
    ODOSQLStatement *_beginTransactionStatement;
    ODOSQLStatement *_commitTransactionStatement;
    NSMutableDictionary<NSObject<NSCopying> *, ODOSQLStatement *> *_cachedStatements;
    
    NSMutableDictionary<NSString *, id> *_committedMetadata;
    NSMutableDictionary<NSString *, id> *_pendingMetadataChanges;
    
    BOOL _isFreshlyCreated; // YES if we just made the schema and -didSave hasn't been called (which should be called the first time we save a transaction; presumably having an INSERT).
}

+ (void)initialize;
{
    OBINITIALIZE;
    ODOLogSQL = [[NSUserDefaults standardUserDefaults] boolForKey:@"ODOLogSQL"];
    ODOAsynchronousWrites = [[NSUserDefaults standardUserDefaults] boolForKey:@"ODOAsynchronousWrites"];
    ODOKeepTemporaryStoreInMemory = [[NSUserDefaults standardUserDefaults] boolForKey:@"ODOKeepTemporaryStoreInMemory"];
    ODOVacuumOnDisconnect = [[NSUserDefaults standardUserDefaults] boolForKey:@"ODOVacuumOnDisconnect"];
}

- (instancetype)initWithModel:(ODOModel *)model;
{
    OBPRECONDITION(model);
    
    if (!(self = [super init]))
        return nil;

    _model = [model retain];
    _cachedStatements = [[NSMutableDictionary alloc] init];
    
    return self;
}

- (void)dealloc;
{
    // Won't be able to close the database connection until all sqlite3 statements are gone
    for (ODOSQLStatement *statement in [_cachedStatements objectEnumerator])
        [statement invalidate];
    [_cachedStatements removeAllObjects];
    [_cachedStatements release];
    _cachedStatements = nil;
    
    if (_connection) {
        NSError *error = nil;
        if (![self disconnect:&error]) {
            NSLog(@"Error disconnecting from '%@': %@", [_connection.URL absoluteString], [error toPropertyList]);
        }
        [_connection release];
    }
    
    // These three should have been cleared by the -disconnect: call above
    OBASSERT(_beginTransactionStatement == nil);
    OBASSERT(_commitTransactionStatement == nil);
    OBASSERT(_metadataInsertStatement == nil);

    OBASSERT(_pendingMetadataChanges == nil); // Why didn't they get saved and cleared?
    [_pendingMetadataChanges release]; // ... in case.
    [_committedMetadata release];
    
    [_model release];
    [super dealloc];
}

- (ODOModel *)model;
{
    OBPRECONDITION(_model);
    return _model;
}

- (NSURL *)connectedURL;
{
    return _connection.URL;
}

- (BOOL)connectToURL:(NSURL *)fileURL error:(NSError **)outError;
{
    if (ODOLogSQL)
        NSLog(@"Connecting to %@", [fileURL absoluteURL]);
    
    if (_connection) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to connect to database.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot connect to '%@' since the database is already connected to '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), [_connection.URL absoluteString], [fileURL absoluteString]];
        ODOError(outError, ODOUnableToConnectDatabase, description, reason);
        return NO;
    }
    
    // SQLite will silently create the database file if it didn't exist already.  Check if it exists before trying (alternatively, we could do some select to see if it is empty after opening).
    NSString *path = [[fileURL absoluteURL] path];
    BOOL existed = [[NSFileManager defaultManager] fileExistsAtPath:path];
    
    ODOSQLConnectionOptions options = 0;
    if (ODOAsynchronousWrites) {
        options |= ODOSQLConnectionAsynchronousWrites;
    }
    if (ODOKeepTemporaryStoreInMemory) {
        options |= ODOSQLConnectionKeepTemporaryStoreInMemory;
    }
    
    _connection = [[ODOSQLConnection alloc] initWithURL:fileURL options:options error:outError];
    if (_connection == nil) {
        return NO;
    }
    
    // Set up string compare functions
    BOOL stringCompareSuccess = [_connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        int rc;
        
        rc = sqlite3_create_function(sqlite, ODOComparisonPredicateStartsWithFunctionName,
                                     3/*nArg*/,
                                     SQLITE_UTF8, NULL/*data*/,
                                     ODOComparisonPredicateStartsWithFunction,
                                     NULL /*step*/,
                                     NULL /*final*/);
        if (rc != SQLITE_OK) {
            ODOSQLiteError(blockError, rc, sqlite); // stack the underlying error
            return NO;
        }
        
        rc = sqlite3_create_function(sqlite, ODOComparisonPredicateContainsFunctionName,
                                     3/*nArg*/,
                                     SQLITE_UTF8, NULL/*data*/,
                                     ODOComparisonPredicateContainsFunction,
                                     NULL /*step*/,
                                     NULL /*final*/);
        if (rc != SQLITE_OK) {
            ODOSQLiteError(blockError, rc, sqlite); // stack the underlying error
            return NO;
        }
        
        return YES;
    }];
    if (!stringCompareSuccess) {
        return NO;
    }
    
    // Set up transaction statements
    _beginTransactionStatement = [[ODOSQLStatement alloc] initWithConnection:_connection sql:@"BEGIN EXCLUSIVE" error:outError];
    if (!_beginTransactionStatement) {
        return NO;
    }
    _commitTransactionStatement = [[ODOSQLStatement alloc] initWithConnection:_connection sql:@"COMMIT" error:outError];
    if (!_commitTransactionStatement) {
        return NO;
    }
    
    BOOL prepareSuccess = [_connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        if (![_beginTransactionStatement prepareIfNeededWithSQLite:sqlite error:blockError]) {
            return NO;
        }
        if (![_commitTransactionStatement prepareIfNeededWithSQLite:sqlite error:blockError]) {
            return NO;
        }
        return YES;
    }];
    if (!prepareSuccess) {
        [self _disconnectWithoutNotifying:NULL];
        return NO;
    }
    
    _committedMetadata = [[NSMutableDictionary alloc] init];
    
    if (!existed) {
        if (![self _setupNewDatabase:outError]) {
            // Not so much with the working.  Disconnect (ignoring any error that might happen) to clear out the optimistic connection state.
            [self _disconnectWithoutNotifying:NULL];
            
            // Since we created the file and it is bogus; blow it away.
            NSError *removeError = nil;
            if (![[NSFileManager defaultManager] removeItemAtPath:path error:&removeError]) {
                NSLog(@"Unable to remove '%@' - %@", path, [removeError toPropertyList]);
            }
            
            return NO;
        }
    } else {
        // TODO: Validate the existing schema vs. our model?  OmniFocus doesn't need this since it puts the SVN revision in the metadata, but this might be nice.  On the other hand, it will be wasted effort, on launch no less, for the iPhone where the SVN revision would have caught the problem anyway.
        
        if (![self _populateCachedMetadata:outError]) {
            // Not so much with the working.  Disconnect (ignoring any error that might happen) to clear out the optimistic connection state.
            [self _disconnectWithoutNotifying:NULL];
            
            return NO;
        }
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ODODatabaseConnectedURLChangedNotification object:self];
    
    return YES;
}

// TODO: This should poke the attached ODOEditingContext into resetting or the like.
- (BOOL)disconnect:(NSError **)outError;
{
    if (ODOVacuumOnDisconnect && ![self executeSQLWithoutResults:@"VACUUM" error:outError])
        return NO;

    if (![self _disconnectWithoutNotifying:outError])
        return NO;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ODODatabaseConnectedURLChangedNotification object:self];
    return YES;
}

- (BOOL)isFreshlyCreated;
{
    return _isFreshlyCreated;
}

- (void)didSave;
{
    _isFreshlyCreated = NO;
}

- (NSDictionary *)committedMetadata;
{
    return [[_committedMetadata copy] autorelease];
}
    
- (id)metadataForKey:(NSString *)key;
{
    id value = [_pendingMetadataChanges objectForKey:key];
    if (!value)
        value = [_committedMetadata objectForKey:key];
    if (OFISNULL(value))
        value = nil;
    return value;
}

- (void)setMetadata:(id)value forKey:(NSString *)key;
{
    if (OFISEQUAL(value, [self metadataForKey:key]))
        return;
    
    if (!value)
        value = [NSNull null];
    if (!_pendingMetadataChanges)
        _pendingMetadataChanges = [[NSMutableDictionary alloc] init];
    [_pendingMetadataChanges setObject:value forKey:key];
}

- (BOOL)writePendingMetadataChanges:(NSError **)outError;
{
    OBPRECONDITION(_pendingMetadataChanges != nil, @"bug:///139901 (Mac-OmniFocus Engineering: Precondition failure writing metadata changes before desync correction)");
    
    BOOL transactionSuccess = [self _performTransactionWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        return [self _queue_writeMetadataChangesToSQLite:sqlite error:blockError];
    }];
    if (!transactionSuccess) {
        return NO;
    }
    
    [self _committedPendingMetadataChanges];
    return YES;
}

- (BOOL)deleteCommittedMetadataForKey:(NSString *)key error:(NSError **)outError;
{
    return [self executeSQLWithoutResults:[NSString stringWithFormat:@"DELETE FROM %@ WHERE key = '%@';", ODODatabaseMetadataTableName, key] error:outError];
}

static BOOL _fetchRowCountCallback(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
    OBASSERT([statement.connection checkIsManagedSQLite:sqlite]);
    OBASSERT([statement.connection checkExecutingOnDispatchQueue]);
    uint64_t *outRowCount = context;
    OBASSERT(sqlite3_column_count(statement->_statement) == 1);
    *outRowCount = sqlite3_column_int64(statement->_statement, 0);
    return YES;
}

- (BOOL)fetchCommittedRowCount:(uint64_t *)outRowCount fromEntity:(ODOEntity *)entity matchingPredicate:(NSPredicate *)predicate error:(NSError **)outError;
{
    ODOSQLStatement *statement = [[ODOSQLStatement alloc] initRowCountFromEntity:entity connection:self.connection predicate:predicate error:outError];
    if (!statement)
        return NO;
    
    BOOL success = [self.connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        ODOSQLStatementCallbacks callbacks;
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.row = _fetchRowCountCallback;
        
        return ODOSQLStatementRun(sqlite, statement, callbacks, outRowCount, blockError);
    }];
    
    OBExpectDeallocation(statement);
    [statement release];
    return success;
}

static BOOL _fetchSumCallback(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
    int64_t *outSum = context;
    OBASSERT(sqlite3_column_count(statement->_statement) == 1);
    *outSum = sqlite3_column_int64(statement->_statement, 0);
    return YES;
}

- (BOOL)fetchCommitedInt64Sum:(int64_t *)outSum fromAttribute:(ODOAttribute *)attribute entity:(ODOEntity *)entity matchingPredicate:(nullable NSPredicate *)predicate error:(NSError **)outError;
{
    OBPRECONDITION(attribute != nil);
    
    if (predicate != nil) {
        OBFinishPorting;
    }
    
    NSString *sql = [NSString stringWithFormat:@"SELECT SUM(%@) FROM %@", [attribute name], [entity name]];
    ODOSQLStatement *statement = [[ODOSQLStatement alloc] initWithConnection:self.connection sql:sql error:outError];
    if (!statement)
        return NO;
    
    BOOL success = [self.connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        ODOSQLStatementCallbacks callbacks;
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.row = _fetchSumCallback;
        
        return ODOSQLStatementRun(sqlite, statement, callbacks, outSum, blockError);
    }];
    
    OBExpectDeallocation(statement);
    [statement release];
    return success;
}

typedef struct {
    NSArray<ODOAttribute *> *attributes;
    NSMutableArray<NSArray *> *results;
} FetchAttributesCallbackContext;

static BOOL _fetchAttributesCallback(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
    FetchAttributesCallbackContext *callbackContext = (FetchAttributesCallbackContext *)context;
    
    int columnCount = sqlite3_column_count(statement->_statement);
    NSMutableArray *row = [NSMutableArray array];
    
    for (int column = 0; column < columnCount; column++) {
        ODOAttribute *attribute = [callbackContext->attributes objectAtIndex:column];
        id value = nil;
        if (!ODOSQLStatementCreateValue(sqlite, statement, column, &value, attribute.type, attribute.valueClass, outError)) {
            callbackContext->results = nil;
            return NO;
        }
        [row addObject:(value ?: [NSNull null])];
        [value release]; // returned retained by ODOSQLStatementCreateValue, but now owned by the row array
    }
    
    [callbackContext->results addObject:row];
    return YES;
}

- (nullable NSArray *)fetchCommittedAttributes:(NSArray<ODOAttribute *> *)attributes fromEntity:(ODOEntity *)entity matchingPredicate:(nullable NSPredicate *)predicate error:(NSError **)outError;
{
    OBPRECONDITION(attributes != nil);
    NSMutableArray *results = [NSMutableArray array];
    
    ODOSQLStatement *statement = [[ODOSQLStatement alloc] initSelectProperties:attributes fromEntity:entity connection:self.connection predicate:predicate error:outError];
    if (statement == nil) {
        return nil;
    }
    
    BOOL success = [self.connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        ODOSQLStatementCallbacks callbacks;
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.row = _fetchAttributesCallback;
        
        FetchAttributesCallbackContext context;
        context.attributes = attributes;
        context.results = results;
        return ODOSQLStatementRun(sqlite, statement, callbacks, &context, blockError);
    }];
    
    OBExpectDeallocation(statement);
    [statement release];
    return (success ? results : nil);
}

#pragma mark Dangerous API

- (BOOL)executeSQLWithoutResults:(NSString *)sql error:(NSError **)outError;
{
    return [self.connection executeSQLWithoutResults:sql error:outError];
}

#pragma mark Private

NSNotificationName ODODatabaseConnectedURLChangedNotification = @"ODODatabaseConnectedURLChanged";

- (BOOL)_setupNewDatabase:(NSError **)outError;
{
    // Create the metadata table
    NSString *metadataSchema = [NSString stringWithFormat:@"CREATE TABLE %@ (%@ VARCHAR NOT NULL PRIMARY KEY, %@ BLOB NOT NULL)", ODODatabaseMetadataTableName, ODODatabaseMetadataKeyColumnName, ODODatabaseMetadataPlistColumnName];
    if (![self executeSQLWithoutResults:metadataSchema error:outError])
        return NO;

    // Create the schema specified by the model
    if (![_model _createSchemaInDatabase:self error:outError])
        return NO;
    
    // Note that, as of now, this database is totally empty.
    _isFreshlyCreated = YES;
    
    return YES;
}

static BOOL _populateCachedMetadataRowCallback(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
    NSMutableDictionary *committedMetadata = (NSMutableDictionary *)context;
    
    OBASSERT(sqlite3_column_count(statement->_statement) == 2);
    
    const uint8_t *keyString = sqlite3_column_text(statement->_statement, 0);
    if (!keyString) {
        OBASSERT(keyString);
        return YES;
    }
    
    NSString *key = [NSString stringWithUTF8String:(const char *)keyString];
    
    const void *bytes = sqlite3_column_blob(statement->_statement, 1);
    if (bytes == NULL) {
        OBASSERT(bytes);
        return YES;
    }
    
    int length = sqlite3_column_bytes(statement->_statement, 1);
    NSData *data = [NSData dataWithBytesNoCopy:(void *)bytes length:length freeWhenDone:NO];
    
    NSError *error = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
    if (!plist) {
        NSLog(@"Unable to archive plist for metadata key '%@': %@", key, error);
        return YES;
    }
    
    [committedMetadata setObject:plist forKey:key];
    return YES;
}

- (BOOL)_populateCachedMetadata:(NSError **)outError;
{
    NSString *sql = [NSString stringWithFormat:@"select %@, %@ from %@", ODODatabaseMetadataKeyColumnName, ODODatabaseMetadataPlistColumnName, ODODatabaseMetadataTableName];
    ODOSQLStatement *statement = [[ODOSQLStatement alloc] initWithConnection:self.connection sql:sql error:outError];
    if (!statement)
        return NO;
    
    BOOL success = [self.connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        ODOSQLStatementCallbacks callbacks;
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.row = _populateCachedMetadataRowCallback;
        
        return ODOSQLStatementRun(sqlite, statement, callbacks, _committedMetadata, blockError);
    }];
    
    OBExpectDeallocation(statement);
    [statement release];
    return success;
}

- (BOOL)_disconnectWithoutNotifying:(NSError **)outError;
{
    if (!_connection) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Error disconnecting from database.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Attempted to disconnect while not connected.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason");
        ODOError(outError, ODOErrorDisconnectingFromDatabase, description, reason);
        return NO;
    }
    
    if (ODOLogSQL)
        NSLog(@"Disconnecting from %@", [_connection.URL absoluteURL]);
    
    [_beginTransactionStatement invalidate];
    [_beginTransactionStatement release];
    _beginTransactionStatement = nil;
    
    [_commitTransactionStatement invalidate];
    [_commitTransactionStatement release];
    _commitTransactionStatement = nil;
    
    [_metadataInsertStatement invalidate];
    [_metadataInsertStatement release];
    _metadataInsertStatement = nil;

    for (ODOSQLStatement *statement in [_cachedStatements objectEnumerator]) {
        [statement invalidate];
    }
    [_cachedStatements removeAllObjects];
    
    OBExpectDeallocation(_connection);
    [_connection release];
    _connection = nil;
    
    OBASSERT([_pendingMetadataChanges count] == 0); // Otherwise, metadata changes are getting lost.
    [_pendingMetadataChanges release];
    _pendingMetadataChanges = nil;
    
    [_committedMetadata release];
    _committedMetadata = nil;
    
    return YES;
}

@end

@implementation ODODatabase (Internal)

- (id)_generatePrimaryKeyForEntity:(ODOEntity *)entity;
{
    switch ([[entity primaryKeyAttribute] type]) {
        case ODOAttributeTypeString:
            return [OFXMLCreateID() autorelease];
        default:
            OBASSERT_NOT_REACHED("Unsupported primary key attribute"); // should have been caught when loading the model.  See ODOEntity's loading code.
            return nil;
    }
}

- (BOOL)_performTransactionWithError:(NSError **)outError block:(ODOSQLFailablePerformBlock)block;
{
    return [self.connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        if (!ODOSQLStatementRunWithoutResults(sqlite, _beginTransactionStatement, blockError)) {
            return NO;
        }
        
        if (!block(sqlite, blockError)) {
            return NO;
        }
        
        if (!ODOSQLStatementRunWithoutResults(sqlite, _commitTransactionStatement, blockError)) {
            return NO;
        }
        
        return YES;
    }];
}

- (BOOL)_queue_writeMetadataValue:(id)plistObject forKey:(NSString *)keyString toSQLite:(struct sqlite3 *)sqlite error:(NSError **)outError;
{
    OBPRECONDITION(_metadataInsertStatement != nil);
    OBPRECONDITION(sqlite != NULL);
    OBPRECONDITION([_connection checkExecutingOnDispatchQueue]);
    OBPRECONDITION([_connection checkIsManagedSQLite:sqlite]);
    
    if (OFISNULL(plistObject)) {
        // Use a DELETE statement
        OBRequestConcreteImplementation(nil, _cmd);
    } else {
        if (!ODOSQLStatementBindString(sqlite, _metadataInsertStatement, 1, keyString, outError)) {
            return NO;
        }
        
        NSError *plistError = nil;
        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:plistObject format:NSPropertyListBinaryFormat_v1_0 options:0 error:&plistError];
        if (!plistData) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to save metadata to database.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Failed to convert '%@' to a property list data: %@.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), plistObject, plistData];
            ODOError(outError, ODOUnableToSaveMetadata, description, reason);
            return NO;
        }
        
        if (!ODOSQLStatementBindData(sqlite, _metadataInsertStatement, 2, plistData, outError)) {
            return NO;
        }
        
        if (!ODOSQLStatementRunWithoutResults(sqlite, _metadataInsertStatement, outError)) {
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)_queue_writeMetadataChangesToSQLite:(struct sqlite3 *)sqlite error:(NSError **)outError;
{
    OBPRECONDITION([_connection checkExecutingOnDispatchQueue]);
    OBPRECONDITION([_connection checkIsManagedSQLite:sqlite]);
    
    if (!_pendingMetadataChanges)
        return YES;
    
    if (!_metadataInsertStatement) {
        _metadataInsertStatement = [[ODOSQLStatement alloc] initWithConnection:self.connection sql:[NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ VALUES (?, ?)", ODODatabaseMetadataTableName] error:outError];
        if (!_metadataInsertStatement) {
            return NO;
        }
        if (![_metadataInsertStatement prepareIfNeededWithSQLite:sqlite error:outError]) {
            [_metadataInsertStatement release];
            _metadataInsertStatement = nil;
            return NO;
        }
    }
    
    // Result is a repeat of whatever error last came out of sqlite3_step.  Not relevant here.
    sqlite3_reset(_metadataInsertStatement->_statement);
    
    for (NSString *key in _pendingMetadataChanges) {
        id value = _pendingMetadataChanges[key];
        if (![self _queue_writeMetadataValue:value forKey:key toSQLite:sqlite error:outError]) {
            return NO;
        }
    }
    
    return YES;
}

// Merge the pending changes into the committed metadata.  This is on the commit-succeeded path so it must not fail.
- (void)_committedPendingMetadataChanges;
{
    OBPRECONDITION(_committedMetadata);
    
    if (!_pendingMetadataChanges)
        return;
    
    for (NSString *key in _pendingMetadataChanges) {
        id plistObject = _pendingMetadataChanges[key];
        
        if (OFISNULL(plistObject)) {
            [_committedMetadata removeObjectForKey:key];
        } else {
            [_committedMetadata setObject:plistObject forKey:key];
        }
    }
    
    [_pendingMetadataChanges release];
    _pendingMetadataChanges = nil;
}

- (void)_discardPendingMetadataChanges;
{
    [_pendingMetadataChanges release];
    _pendingMetadataChanges = nil;
}

- (ODOSQLStatement *)_cachedStatementForKey:(NSObject <NSCopying> *)key;
{
    OBPRECONDITION([key conformsToProtocol:@protocol(NSCopying)]);
    
    return [_cachedStatements objectForKey:key];
}

- (void)_setCachedStatement:(ODOSQLStatement *)statement forKey:(NSObject <NSCopying> *)key;
{
    OBPRECONDITION([statement isKindOfClass:[ODOSQLStatement class]]);
    OBPRECONDITION([statement isPrepared]);
    OBPRECONDITION([key conformsToProtocol:@protocol(NSCopying)]);

    // Unlikely that we will replace keys -- let's check
    OBASSERT([_cachedStatements objectForKey:key] == nil);
    
    [_cachedStatements setObject:statement forKey:key];
}

// Selects only primary key of the relationship destination.  Has a single bind parameter which is for the destination's foreign key pointing back at the source entity.
- (ODOSQLStatement *)_queryForDestinationPrimaryKeysByDestinationForeignKeyStatement:(ODORelationship *)rel error:(NSError **)outError;
{
    ODOSQLStatement *query = [self _cachedStatementForKey:rel];
    if (query)
        return query;

    ODORelationship *inverseRel = [rel inverseRelationship];
    OBASSERT(inverseRel);
    OBASSERT([inverseRel isToMany] == NO);
    
    ODOEntity *destEntity = [rel destinationEntity];
    ODOAttribute *destPrimaryKey = [destEntity primaryKeyAttribute];
    
    NSPredicate *predicate = ODOKeyPathEqualToValuePredicate([inverseRel name], @"something"); // Fake up a constant for the build.  Don't use nil/null since that'd get translated to 'IS NULL'.
    
    query = [[ODOSQLStatement alloc] initSelectProperties:[NSArray arrayWithObject:destPrimaryKey] fromEntity:destEntity connection:self.connection predicate:predicate error:outError];
    if (query == nil) {
        return nil;
    }
    
    BOOL prepareSuccess = [self.connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
        return [query prepareIfNeededWithSQLite:sqlite error:blockError];
    }];
    if (!prepareSuccess) {
        [query release];
        return nil;
    }
    
    [self _setCachedStatement:query forKey:rel];
    
    return [query autorelease];
}

@end
