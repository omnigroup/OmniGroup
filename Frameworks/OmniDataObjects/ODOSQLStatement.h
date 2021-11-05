// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODOFetchExtremum.h>
#import <OmniDataObjects/ODOPredicate.h> // For target-specific setup

// This is an internal class that should only be used by ODO.

@class ODOEntity, ODOEditingContext, ODOObject, ODOProperty, ODOSQLConnection;


@interface ODOSQLFetchAggregation : NSObject <NSCopying>

@property (nonatomic, readonly) ODOFetchExtremum extremum;
@property (nonatomic, readonly) ODOAttribute *attribute;

+ (instancetype)aggregationWithExtremum:(ODOFetchExtremum)extremum attribute:(ODOAttribute *)attribute;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithExtremum:(ODOFetchExtremum)extremum attribute:(ODOAttribute *)attribute;

@end


@interface ODOSQLStatement : OFObject
{
@public
    NSString *_sql;
    struct sqlite3_stmt *_statement;
}

+ (void)logBacktracesForPreparedStatements;

@property (nonatomic, readonly) ODOSQLConnection *connection;

/// Convenience that initializes and prepares a statement immediately, using -prepareIfNeededWithSQLite:error:. As with that method, must be called on a queue appropriate for interacting with the given SQLite database handle.
+ (instancetype)preparedStatementWithConnection:(ODOSQLConnection *)connection SQLite:(struct sqlite3 *)sqlite sql:(NSString *)sql error:(NSError **)outError;

- (id)init NS_UNAVAILABLE;

/// Initializes a statement with the given "raw" `sql` string.
- (instancetype)initWithConnection:(ODOSQLConnection *)connection sql:(NSString *)sql error:(NSError **)outError NS_DESIGNATED_INITIALIZER;

/// Initializes a statement that selects the given `properties` from the table corresponding to the given `rootEntity` for rows that match the given `predicate`. Produces a statement of the rough form `SELECT properties FROM rootEntity WHERE predicate;`.
- (instancetype)initSelectProperties:(NSArray<ODOProperty *> *)properties fromEntity:(ODOEntity *)rootEntity connection:(ODOSQLConnection *)connection predicate:(NSPredicate *)predicate error:(NSError **)outError;

/// Initializes a statement that selects the given `properties` from the table corresponding to the given `rootEntity` for the single row which both satisfies the given `predicate` and has the maximum or minimum value specified by the `aggreagtion`. Produces a statement similar to a plain `SELECT … FROM … WHERE …`, but including a `min(key)` or `max(key)` as the first column specification. See the SQLite documentation's discussion of special processing for `min` and `max` in the note for "Bare columns in aggregate queries" at <https://www.sqlite.org/lang_select.html#bareagg>.
- (instancetype)initSelectProperties:(NSArray<ODOProperty *> *)properties usingAggregation:(ODOSQLFetchAggregation *)aggregation fromEntity:(ODOEntity *)rootEntity connection:(ODOSQLConnection *)connection predicate:(NSPredicate *)predicate error:(NSError **)outError;

/// Initializes a statement that counts rows satisfying the given `predicate` in the table corresponding to the given `rootEntity`. Produces a statement of the rough form `SELECT count(*) FROM rootEntity WHERE predicate;`.
- (instancetype)initRowCountFromEntity:(ODOEntity *)rootEntity connection:(ODOSQLConnection *)connection predicate:(NSPredicate *)predicate error:(NSError **)outError;

/// Prepares the underlying sqlite3_stmt for the receiver. Must be called on a queue appropriate for interacting with the given SQLite database handle. (In practice, that generally means -[ODOSQLConnection performSQLAndWaitWithError:block:] or a variant thereof.)
- (BOOL)prepareIfNeededWithSQLite:(struct sqlite3 *)sqlite error:(NSError **)outError;
@property (nonatomic, readonly, getter = isPrepared) BOOL prepared;

/// Returns YES iff the receiver has an additional column specification at index 0 which was built from an ODOSQLFetchAggregation, as opposed to being a "direct" column specification naming a stored column.
@property (nonatomic, readonly) BOOL hasAggregateColumnSpecification;

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
BOOL ODOSQLStatementBindXMLDateTime(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSDate *date, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementBindFloat64(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, double value, NSError **outError) OB_HIDDEN;

BOOL ODOSQLStatementBindConstant(ODOSQLStatement *self, struct sqlite3 *sqlite, id constant, int bindIndex, NSError **outError) OB_HIDDEN;

BOOL ODOSQLStatementCreateValue(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, id *value, ODOAttributeType type, Class valueClass, NSError **outError) OB_HIDDEN;

void ODOSQLStatementLogSQL(NSString *format, ...) NS_FORMAT_FUNCTION(1,2) OB_HIDDEN;

typedef struct {
    BOOL (*row)(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError);
    BOOL (*atEnd)(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError);
} ODOSQLStatementCallbacks;

// Some common callbacks
BOOL ODOSQLStatementIgnoreUnexpectedRow(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementIgnoreExpectedRow(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError) OB_HIDDEN;
#ifdef OMNI_ASSERTIONS_ON
BOOL ODOSQLStatementCheckForSingleChangedRow(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError) OB_HIDDEN;
#endif

// Statement execution
BOOL ODOSQLStatementRun(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOSQLStatementCallbacks callbacks, void *context, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementRunWithoutResults(struct sqlite3 *sqlite, ODOSQLStatement *statement, NSError **outError) OB_HIDDEN;
BOOL ODOSQLStatementRunIgnoringResults(struct sqlite3 *sqlite, ODOSQLStatement *statement, NSError **outError) OB_HIDDEN;

BOOL ODOExtractNonPrimaryKeySchemaPropertiesFromRowIntoObject(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOObject *object, NSArray <ODOProperty *> *schemaProperties, NSUInteger primaryKeyColumnIndex, NSError **outError) OB_HIDDEN;
