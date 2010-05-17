// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODODatabase.h>

#import <OmniDataObjects/ODOEntity.h>
#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/ODOFetchRequest.h>
#import <OmniDataObjects/ODOEditingContext.h>
#import <OmniDataObjects/NSPredicate-ODOExtensions.h>

#import <OmniFoundation/OFXMLIdentifier.h>

#import "ODODatabase-Internal.h"
#import "ODOEntity-Internal.h"
#import "ODOModel-SQL.h"
#import "ODOSQLStatement.h"
#import "ODOPredicate-SQL.h"

#import <sqlite3.h>
#import <Foundation/NSFileManager.h>

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
    
    // Diacritic insensitivity is only on 10.5 or the iPhone, so this won't work on the Mac under 10.4.
    CFOptionFlags cfOptions = 0;
    if (options & NSCaseInsensitivePredicateOption)
        cfOptions |= kCFCompareCaseInsensitive;
#if (defined(MAC_OS_X_VERSION_10_5) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5) || (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE)
    if (options & NSDiacriticInsensitivePredicateOption)
        cfOptions |= kCFCompareDiacriticInsensitive;
#endif
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
- (BOOL)_setupNewDatabase:(NSError **)outError;
- (BOOL)_populateCachedMetadata:(NSError **)outError;
- (BOOL)_disconnectWithoutNotifying:(NSError **)outError;
#ifdef DEBUG
- (BOOL)_checkInvariants;
#endif
@end

@implementation ODODatabase

+ (void)initialize;
{
    OBINITIALIZE;
    ODOLogSQL = [[NSUserDefaults standardUserDefaults] boolForKey:@"ODOLogSQL"];
    ODOAsynchronousWrites = [[NSUserDefaults standardUserDefaults] boolForKey:@"ODOAsynchronousWrites"];
    ODOKeepTemporaryStoreInMemory = [[NSUserDefaults standardUserDefaults] boolForKey:@"ODOKeepTemporaryStoreInMemory"];
    ODOVacuumOnDisconnect = [[NSUserDefaults standardUserDefaults] boolForKey:@"ODOVacuumOnDisconnect"];
}

- (id)initWithModel:(ODOModel *)model;
{
    OBPRECONDITION(model);
    
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
    
    if (_connectedURL) {
        NSError *error = nil;
        if (![self disconnect:&error]) {
            NSLog(@"Error disconnecting from '%@': %@", [_connectedURL absoluteString], [error toPropertyList]);
        }
        [_connectedURL release];
    }
    OBASSERT(_sqlite == NULL); // Might have gotten an error in -disconnect:, but if so, there is nothing better we can do here

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
    OBINVARIANT([self _checkInvariants]);
    return _connectedURL;
}

- (BOOL)connectToURL:(NSURL *)fileURL error:(NSError **)outError;
{
    OBINVARIANT([self _checkInvariants]);
    
    if (ODOLogSQL)
        NSLog(@"Connecting to %@", [fileURL absoluteURL]);
    
    if (_connectedURL) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to connect to database.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot connect to '%@' since the database is already connected to '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), [_connectedURL absoluteString], [fileURL absoluteString]];
        ODOError(outError, ODOUnableToConnectDatabase, description, reason);
        return NO;
    }
    
    OBASSERT(_sqlite == NULL); // invariant should ensure this.

    fileURL = [fileURL absoluteURL];
    NSString *path = [fileURL path];

    // SQLite will silently create the database file if it didn't exist already.  Check if it exists before trying (alternatively, we could do some select to see if it is empty after opening).
    BOOL existed = [[NSFileManager defaultManager] fileExistsAtPath:path];
    
    // Even on error the output sqlite will supposedly be set and we need to close it.
    sqlite3 *sql = NULL;
    int rc = sqlite3_open([path UTF8String], &sql);
    if (rc != SQLITE_OK) {
        ODOSQLiteError(outError, rc, sql); // stack the underlying error
        sqlite3_close(sql);
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to open database.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot open database at '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), [fileURL absoluteString]];
        ODOError(outError, ODOUnableToConnectDatabase, description, reason);
        return NO;
    }
    
    // Optimistically assign these.  If we are installing schema, we might fail stil.
    _sqlite = sql;
    _connectedURL = [fileURL copy];
    _committedMetadata = [[NSMutableDictionary alloc] init];

    if (ODOAsynchronousWrites) {
        if (![self executeSQLWithoutResults:@"PRAGMA synchronous = off" error:outError])
            return NO;
    } else {
        if (![self executeSQLWithoutResults:@"PRAGMA synchronous = normal" error:outError])
            return NO;
    }

    if (ODOKeepTemporaryStoreInMemory) {
        if (![self executeSQLWithoutResults:@"PRAGMA temp_store = memory" error:outError])
            return NO;
    }

    if (![self executeSQLWithoutResults:@"PRAGMA auto_vacuum = none" error:outError]) // According to the sqlite documentation: "Auto-vacuum does not defragment the database nor repack individual database pages the way that the VACUUM command does. In fact, because it moves pages around within the file, auto-vacuum can actually make fragmentation worse."
        return NO;

#if 0
    // "The maximum size of any string or BLOB or table row."
    int blobSize = sqlite3_limit(_sqlite, SQLITE_LIMIT_LENGTH, -1/* negative means to not change*/);
    NSLog(@"blobSize = %d", blobSize);
#endif
    
    // string compare functions
    rc = sqlite3_create_function(_sqlite, ODOComparisonPredicateStartsWithFunctionName, 
                                 3/*nArg*/,
                                 SQLITE_UTF8, NULL/*data*/,
                                 ODOComparisonPredicateStartsWithFunction,
                                 NULL /*step*/,
                                 NULL /*final*/);
    if (rc != SQLITE_OK) {
        ODOSQLiteError(outError, rc, _sqlite); // stack the underlying error
        return NO;
    }
    rc = sqlite3_create_function(_sqlite, ODOComparisonPredicateContainsFunctionName, 
                                 3/*nArg*/,
                                 SQLITE_UTF8, NULL/*data*/,
                                 ODOComparisonPredicateContainsFunction,
                                 NULL /*step*/,
                                 NULL /*final*/);
    if (rc != SQLITE_OK) {
        ODOSQLiteError(outError, rc, _sqlite); // stack the underlying error
        return NO;
    }
    
    if (!existed) {
        if (![self _setupNewDatabase:outError]) {
            // Not so much with the working.  Disconnect (tossing any error that might happen) to clear out the optimistic connection state.
            NSError *disconnectError = nil;
            [self _disconnectWithoutNotifying:&disconnectError];
            
            // Since we created the file and it is bogus; blow it away.
            NSError *removeError = nil;
            if (![[NSFileManager defaultManager] removeItemAtPath:path error:&removeError])
		NSLog(@"Unable to remove '%@' - %@", path, [removeError toPropertyList]);
	    
            return NO;
        }
    } else {
        // TODO: Validate the existing schema vs. our model?  OmniFocus doesn't need this since it puts the SVN revision in the metadata, but this might be nice.  On the other hand, it will be wasted effort, on launch no less, for the iPhone where the SVN revision would have caught the problem anyway.
        
        if (![self _populateCachedMetadata:outError]) {
            // Not so much with the working.  Disconnect (tossing any error that might happen) to clear out the optimistic connection state.
            NSError *disconnectError = nil;
            [self _disconnectWithoutNotifying:&disconnectError];
            
            return NO;
        }
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ODODatabaseConnectedURLChangedNotification object:self];
    
    OBINVARIANT([self _checkInvariants]);
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

static BOOL _fetchRowCountCallback(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
    uint64_t *outRowCount = context;
    OBASSERT(sqlite3_column_count(statement->_statement) == 1);
    *outRowCount = sqlite3_column_int64(statement->_statement, 0);
    return YES;
}

- (BOOL)fetchCommittedRowCount:(uint64_t *)outRowCount fromEntity:entity matchingPredicate:(NSPredicate *)predicate error:(NSError **)outError;
{
    OBPRECONDITION(_sqlite);
    
    ODOSQLStatement *statement = [[ODOSQLStatement alloc] initRowCountFromEntity:entity database:self predicate:predicate error:outError];
    if (!statement)
        return NO;
    
    ODOSQLStatementCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.row = _fetchRowCountCallback;

    BOOL success = ODOSQLStatementRun(_sqlite, statement, callbacks, outRowCount, outError);

    [statement release];

    return success;
}

#pragma mark Dangerous API

// The given SQL is expected to be a single statement that is executed once and returns no result rows.  Any quoting should have already happened.
- (BOOL)executeSQLWithoutResults:(NSString *)sql error:(NSError **)outError;
{
    OBPRECONDITION(_sqlite);
    
    ODOSQLStatement *statement = [[ODOSQLStatement alloc] initWithDatabase:self sql:sql error:outError];
    if (!statement)
        return NO;
    
    BOOL success = ODOSQLStatementRunWithoutResults(_sqlite, statement, outError);
    [statement release];
    return success;
}


#pragma mark Private

NSString * const ODODatabaseConnectedURLChangedNotification = @"ODODatabaseConnectedURLChanged";

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
    
    NSString *errorString = nil;
    id plist = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:kCFPropertyListImmutable format:NULL errorDescription:&errorString];
    if (!plist) {
        NSLog(@"Unable to archive plist for metadata key '%@': %@", key, errorString);
        return YES;
    }
    
    [committedMetadata setObject:plist forKey:key];
    return YES;
}

- (BOOL)_populateCachedMetadata:(NSError **)outError;
{
    OBPRECONDITION(_sqlite);
    
    NSString *sql = [NSString stringWithFormat:@"select %@, %@ from %@", ODODatabaseMetadataKeyColumnName, ODODatabaseMetadataPlistColumnName, ODODatabaseMetadataTableName];
    ODOSQLStatement *statement = [[ODOSQLStatement alloc] initWithDatabase:self sql:sql error:outError];
    if (!statement)
        return NO;
    
    ODOSQLStatementCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.row = _populateCachedMetadataRowCallback;

    BOOL success = ODOSQLStatementRun(_sqlite, statement, callbacks, _committedMetadata, outError);

    [statement release];

    return success;
}

- (BOOL)_disconnectWithoutNotifying:(NSError **)outError;
{
    OBINVARIANT([self _checkInvariants]);
    
    if (!_connectedURL) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Error disconnecting from database.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Attempted to disconnect while not connected.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason");
        ODOError(outError, ODOErrorDisconnectingFromDatabase, description, reason);
        return NO;
    }
    
    if (ODOLogSQL)
        NSLog(@"Disconnecting from %@", [_connectedURL absoluteURL]);

    // Doing this first right now so that we can have an assertion when building a ODOSQLStatement that the database is connected.  Any indication would do, though.
    [_connectedURL release];
    _connectedURL = nil;
    
    [_beginTransactionStatement invalidate];
    [_beginTransactionStatement release];
    _beginTransactionStatement = nil;

    [_commitTransactionStatement invalidate];
    [_commitTransactionStatement release];
    _commitTransactionStatement = nil;
    
    [_metadataInsertStatement invalidate];
    [_metadataInsertStatement release];
    _metadataInsertStatement = nil;

    for (ODOSQLStatement *statement in [_cachedStatements objectEnumerator])
        [statement invalidate];
    [_cachedStatements removeAllObjects];
    
    /* From the docs:
     ** All SQL statements prepared using sqlite3_prepare() or
     ** sqlite3_prepare16() must be deallocated using sqlite3_finalize() before
     ** this routine is called. Otherwise, SQLITE_BUSY is returned and the
     ** database connection remains open.
     */
    int rc = sqlite3_close(_sqlite);
    if (rc != SQLITE_OK) {
        ODOSQLiteError(outError, rc, _sqlite); // stack the underlying error
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to disconnect from database.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot disconnect from database at '%@'.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), [_connectedURL absoluteString]];
        ODOError(outError, ODOUnableToConnectDatabase, description, reason);
        return NO;
    } else {
        _sqlite = NULL;
    }
    
    OBASSERT([_pendingMetadataChanges count] == 0); // Otherwise, metadata changes are getting lost.
    [_pendingMetadataChanges release];
    _pendingMetadataChanges = nil;
    
    [_committedMetadata release];
    _committedMetadata = nil;
    
    OBINVARIANT([self _checkInvariants]);
    return YES;
}

#ifdef DEBUG
- (BOOL)_checkInvariants;
{
    OBINVARIANT((_connectedURL == nil) == (_sqlite == NULL));
    return YES;
}
#endif
@end

@implementation ODODatabase (Internal)

- (sqlite3 *)_sqlite;
{
    OBPRECONDITION(_sqlite);
    return _sqlite;
}

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

- (BOOL)_beginTransaction:(NSError **)outError;
{
    OBPRECONDITION(_sqlite);

    if (!_beginTransactionStatement) {
        _beginTransactionStatement = [[ODOSQLStatement alloc] initWithDatabase:self sql:@"BEGIN EXCLUSIVE" error:outError];
        if (!_beginTransactionStatement)
            return NO;
    }

    return ODOSQLStatementRunWithoutResults(_sqlite, _beginTransactionStatement, outError);
}

- (BOOL)_commitTransaction:(NSError **)outError;
{
    OBPRECONDITION(_sqlite);

    if (!_commitTransactionStatement) {
        _commitTransactionStatement = [[ODOSQLStatement alloc] initWithDatabase:self sql:@"COMMIT" error:outError];
        if (!_commitTransactionStatement)
            return NO;
    }
    
    return ODOSQLStatementRunWithoutResults(_sqlite, _commitTransactionStatement, outError);
}

typedef struct {
    sqlite3 *sqlite;
    BOOL errorOccurred;
    NSError **outError;
    ODOSQLStatement *insertStatement;
} ODOWriteMetadataContext;

static void ODOWriteMetadataApplier(const void *key, const void *value, void *context)
{
    NSString *keyString = (NSString *)key;
    id plistObject = (id)value;
    ODOWriteMetadataContext *ctx = context;
    
    if (ctx->errorOccurred)
        return;
    
    if (OFISNULL(plistObject)) {
        // Use a delete statement
        OBRequestConcreteImplementation(nil, @selector(_writeMetadataChanges:));
    } else {
        if (!ODOSQLStatementBindString(ctx->sqlite, ctx->insertStatement, 1, keyString, ctx->outError)) {
            ctx->errorOccurred = YES;
            return;
        }
        
        NSString *errorDesc = nil;
        NSData *plistData = [NSPropertyListSerialization dataFromPropertyList:plistObject format:NSPropertyListBinaryFormat_v1_0 errorDescription:&errorDesc];
        if (!plistData) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to save metadata to database.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Failed to convert '%@' to a property list data: %@.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), plistObject, plistData];
            ODOError(ctx->outError, ODOUnableToSaveMetadata, description, reason);
            ctx->errorOccurred = YES;
            return;
        }

        if (!ODOSQLStatementBindData(ctx->sqlite, ctx->insertStatement, 2, plistData, ctx->outError)) {
            ctx->errorOccurred = YES;
            return;
        }
        
        if (!ODOSQLStatementRunWithoutResults(ctx->sqlite, ctx->insertStatement, ctx->outError)) {
            ctx->errorOccurred = YES;
            return;
        }
    }
}

- (BOOL)_writeMetadataChanges:(NSError **)outError;
{
    OBPRECONDITION(_sqlite);

    if (!_pendingMetadataChanges)
        return YES;
    
    if (!_metadataInsertStatement) {
        _metadataInsertStatement = [[ODOSQLStatement alloc] initWithDatabase:self sql:[NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ VALUES (?, ?)", ODODatabaseMetadataTableName] error:outError];
        if (!_metadataInsertStatement)
            return NO;
    }

   // Result is a repeat of whatever error last came out of sqlite3_step.  Not relevant here.
   sqlite3_reset(_metadataInsertStatement->_statement);
                                       
    ODOWriteMetadataContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.sqlite = _sqlite;
    ctx.insertStatement = _metadataInsertStatement;
    ctx.outError = outError;
    
    CFDictionaryApplyFunction((CFDictionaryRef)_pendingMetadataChanges, ODOWriteMetadataApplier, &ctx);
    
    return !ctx.errorOccurred;
}

// Merge the pending changes into the committed metadata.  This is on the commit-succeeded path so it must not fail.

static void _committedPendingMetadataChangesApplier(const void *key, const void *value, void *context)
{
    NSString *keyString = (NSString *)key;
    id plistObject = (id)value;
    NSMutableDictionary *committedMetadata = (NSMutableDictionary *)context;
    
    if (OFISNULL(plistObject))
        [committedMetadata removeObjectForKey:keyString];
    else
        [committedMetadata setObject:plistObject forKey:keyString];
}

- (void)_committedPendingMetadataChanges;
{
    OBPRECONDITION(_committedMetadata);
    
    if (!_pendingMetadataChanges)
        return;
    CFDictionaryApplyFunction((CFDictionaryRef)_pendingMetadataChanges, _committedPendingMetadataChangesApplier, _committedMetadata);
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
    OBPRECONDITION(statement->_statement); // Need a 'isInvalidated'?
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
    query = [[ODOSQLStatement alloc] initSelectProperties:[NSArray arrayWithObject:destPrimaryKey] fromEntity:destEntity database:self predicate:predicate error:outError];
    if (!query)
        return nil;
    
    [self _setCachedStatement:query forKey:rel];
    return query;
}

@end


