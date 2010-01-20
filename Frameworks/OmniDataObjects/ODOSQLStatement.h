// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
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

@class ODODatabase, ODOEntity, ODOEditingContext, ODOObject;

@interface ODOSQLStatement : OFObject
{
@public
    NSString *_sql;
    struct sqlite3_stmt *_statement;
}

- initWithDatabase:(ODODatabase *)database sql:(NSString *)sql error:(NSError **)outError;
- initSelectProperties:(NSArray *)properties fromEntity:(ODOEntity *)rootEntity database:(ODODatabase *)database predicate:(NSPredicate *)predicate error:(NSError **)outError;
- initRowCountFromEntity:(ODOEntity *)rootEntity database:(ODODatabase *)database predicate:(NSPredicate *)predicate error:(NSError **)outError;

- (void)invalidate;

@end

// Bind variables are 1-indexed and are not reset by sqlite3_reset.
__private_extern__ BOOL ODOSQLStatementBindNull(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSError **outError);
__private_extern__ BOOL ODOSQLStatementBindString(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSString *string, NSError **outError);
__private_extern__ BOOL ODOSQLStatementBindData(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSData *data, NSError **outError);
__private_extern__ BOOL ODOSQLStatementBindInt16(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, int16_t value, NSError **outError);
__private_extern__ BOOL ODOSQLStatementBindInt32(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, int32_t value, NSError **outError);
__private_extern__ BOOL ODOSQLStatementBindInt64(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, int64_t value, NSError **outError);
__private_extern__ BOOL ODOSQLStatementBindBoolean(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, BOOL value, NSError **outError);
__private_extern__ BOOL ODOSQLStatementBindDate(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, NSDate *date, NSError **outError);
__private_extern__ BOOL ODOSQLStatementBindFloat64(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, double value, NSError **outError);

__private_extern__ BOOL ODOSQLStatementBindConstant(ODOSQLStatement *self, struct sqlite3 *sqlite, id constant, int bindIndex, NSError **outError);

__private_extern__ BOOL ODOSQLStatementCreateValue(struct sqlite3 *sqlite, ODOSQLStatement *statement, int bindIndex, id *value, ODOAttributeType type, Class valueClass, NSError **outError);

__private_extern__ void ODOSQLStatementLogSQL(NSString *format, ...);

typedef struct {
    BOOL (*row)(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError);
    BOOL (*atEnd)(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError);
} ODOSQLStatementCallbacks;

// Some common callbacks
__private_extern__ BOOL ODOSQLStatementIgnoreUnexpectedRow(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError);
#ifdef OMNI_ASSERTIONS_ON
__private_extern__ BOOL ODOSQLStatementCheckForSingleChangedRow(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError);
#endif

// Statement execution
__private_extern__ BOOL ODOSQLStatementRun(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOSQLStatementCallbacks callbacks, void *context, NSError **outError);
__private_extern__ BOOL ODOSQLStatementRunWithoutResults(struct sqlite3 *sqlite, ODOSQLStatement *statement, NSError **outError);

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

__private_extern__ BOOL ODOExtractNonPrimaryKeySchemaPropertiesFromRowIntoObject(struct sqlite3 *sqlite, ODOSQLStatement *statement, ODOObject *object, ODORowFetchContext *ctx, NSError **outError);
