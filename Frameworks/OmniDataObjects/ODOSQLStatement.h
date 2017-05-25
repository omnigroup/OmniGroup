// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODOPredicate.h> // For target-specific setup

// This is an internal class that should only be used by ODO.

@class ODOEntity, ODOEditingContext, ODOObject, ODOProperty, ODOSQLConnection;

@interface ODOSQLStatement : OFObject
{
@public
    NSString *_sql;
    struct sqlite3_stmt *_statement;
}

@property (nonatomic, readonly) ODOSQLConnection *connection;

/// Convenience that initializes and prepares a statement immediately, using -prepareIfNeededWithSQLite:error:. As with that method, must be called on a queue appropriate for interacting with the given SQLite database handle.
+ (instancetype)preparedStatementWithConnection:(ODOSQLConnection *)connection SQLite:(struct sqlite3 *)sqlite sql:(NSString *)sql error:(NSError **)outError;

- (id)init NS_UNAVAILABLE;
- (instancetype)initWithConnection:(ODOSQLConnection *)connection sql:(NSString *)sql error:(NSError **)outError NS_DESIGNATED_INITIALIZER;
- (instancetype)initSelectProperties:(NSArray<ODOProperty *> *)properties fromEntity:(ODOEntity *)rootEntity connection:(ODOSQLConnection *)connection predicate:(NSPredicate *)predicate error:(NSError **)outError;
- (instancetype)initRowCountFromEntity:(ODOEntity *)rootEntity connection:(ODOSQLConnection *)connection predicate:(NSPredicate *)predicate error:(NSError **)outError;

/// Prepares the underlying sqlite3_stmt for the receiver. Must be called on a queue appropriate for interacting with the given SQLite database handle. (In practice, that generally means -[ODOSQLConnection performSQLAndWaitWithError:block:] or a variant thereof.)
- (BOOL)prepareIfNeededWithSQLite:(struct sqlite3 *)sqlite error:(NSError **)outError;
@property (nonatomic, readonly, getter = isPrepared) BOOL prepared;

- (void)invalidate;

@end

// Bind variables are 1-indexed and are not reset by sqlite3_reset.
BOOL ODOSQLStatementBindNull(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementBindString(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSString *string, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementBindData(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSData *data, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementBindInt16(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, int16_t value, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementBindInt32(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, int32_t value, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementBindInt64(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, int64_t value, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementBindBoolean(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, BOOL value, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementBindDate(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSDate *date, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementBindFloat64(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, double value, NSError **outError) OB_HIDDEN;

BOOL ODOSQLStatementBindConstant(ODOSQLStatement *self, struct sqlite3 *sqlite, id constant, int bindIndex, NSError **outError) OB_HIDDEN;

BOOL ODOSQLStatementCreateValue(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, id *value, ODOAttributeType type, Class valueClass, NSError **outError) OB_HIDDEN;

void ODOSQLStatementLogSQL(NSString *format, ...) OB_HIDDEN;

typedef struct {
    BOOL (*row)(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError);
    BOOL (*atEnd)(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError);
} ODOSQLStatementCallbacks;

// Some common callbacks
BOOL ODOSQLStatementIgnoreUnexpectedRow(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError) OB_HIDDEN;
#ifdef OMNI_ASSERTIONS_ON
BOOL ODOSQLStatementCheckForSingleChangedRow(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError) OB_HIDDEN;
#endif

// Statement execution
BOOL ODOSQLStatementRun(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOSQLStatementCallbacks callbacks, void *context, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementRunWithoutResults(struct sqlite3 *sqlite, ODOSQLStatement *statement, NSError **outError) OB_HIDDEN;

// Fetching
typedef struct {
    ODOEntity *entity;
    Class instanceClass;
    NSArray *schemaProperties;
    ODOAttribute *primaryKeyAttribute;
    NSUInteger primaryKeyColumnIndex;
    ODOEditingContext *editingContext;
    NSMutableArray *results; // objects that resulted from the fetch.  some might have been previously fetched
    NSMutableArray *fetched; // objects included in the results that are newly fetched and need -awakeFromFetch
} ODORowFetchContext;

BOOL ODOExtractNonPrimaryKeySchemaPropertiesFromRowIntoObject(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOObject *object, ODORowFetchContext *ctx, NSError **outError) OB_HIDDEN;
