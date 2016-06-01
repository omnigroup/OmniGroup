// Copyright 2004-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSQLite/OSLDatabaseController.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

#import <OmniSQLite/OSLPreparedStatement.h>
#import "Errors.h"

RCS_ID("$Id$")

@interface OSLDatabaseController (Private)
- (void *)_database;
- (BOOL)_openDatabase:(NSError **)outError;
- (void)_deleteDatabase;
- (void)_closeDatabase;
- (BOOL)_executeSQL:(NSString *)sql withCallback:(OSLDatabaseCallback)callbackFunction context:(void *)callbackContext error:(NSError **)outError;
- (OSLPreparedStatement *)_prepareStatement:(NSString *)sql error:(NSError **)outError;
- (unsigned long long int)_lastInsertRowID;
@end

@implementation OSLDatabaseController

@synthesize autoRetry = _autoRetry;

- initWithDatabasePath:(NSString *)aPath error:(NSError **)outError;
{
    if (!(self = [super init]))
        return nil;
    
    databasePath = [aPath retain];    
    if (![self _openDatabase:outError]) {
        [self release];
        return nil;
    }
    
    return self;
}

- (void)dealloc;
{
    [self _closeDatabase];
    [databasePath release];
    
    [super dealloc];
}

- (NSString *)databasePath;
{
    return databasePath;
}

- (void)deleteDatabase;
{
    [self _deleteDatabase];
}

- (BOOL)executeSQL:(NSString *)sql withCallback:(OSLDatabaseCallback)callbackFunction context:(void *)callbackContext error:(NSError **)outError;
{
    return [self _executeSQL:sql withCallback:callbackFunction context:callbackContext error:outError];
}

- (OSLPreparedStatement *)prepareStatement:(NSString *)sql error:(NSError **)outError;
{
    return [self _prepareStatement:sql error:outError];
}

- (unsigned long long int)lastInsertRowID;
{
    return [self _lastInsertRowID];
}

// Convenience methods

- (BOOL)beginTransaction;
{
    return [self executeSQL:@"BEGIN;\n" withCallback:NULL context:NULL error:NULL];
}

- (BOOL)commitTransaction;
{
    return [self executeSQL:@"COMMIT;\n" withCallback:NULL context:NULL error:NULL];
}

- (BOOL)rollbackTransaction;
{
    return [self executeSQL:@"ROLLBACK;\n" withCallback:NULL context:NULL error:NULL];
}

@end

#import "sqlite3.h"

@implementation OSLDatabaseController (Private)

- (void *)_database;
{
    return sqliteDatabase;
}

#ifdef DEBUG_kc
    #define DebugLog(format, ...) NSLog(format, ## __VA_ARGS__)
#else
    #define DebugLog(format, ...) do {} while (0)
#endif

- (BOOL)_openDatabase:(NSError **)outError;
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSLog(@"Opening %@", databasePath);
    if (![fileManager createPathToFile:databasePath attributes:nil error:outError])
        return NO;
    
    sqlite3 *db;
    int errorCode = sqlite3_open([fileManager fileSystemRepresentationWithPath:databasePath], &db);
    if (errorCode != SQLITE_OK) {
        NSLog(@"Failed to open %@: %d -- %@", databasePath, errorCode, [NSString stringWithUTF8String:sqlite3_errmsg(db)]);
        sqlite3_close(db);
    }

    sqliteDatabase = db;

    unsigned long long count;
    
    [self executeSQL:@"select count(*) from sqlite_master" withCallback:SingleUnsignedLongLongCallback context:&count error:NULL];
    DebugLog(@"sqlite_master count = %llu", count);
    [self executeSQL:
	@"PRAGMA synchronous = OFF;\n"
	@"PRAGMA temp_store = MEMORY;\n" 
	withCallback:NULL context:NULL error:NULL];
    return YES;
}

- (void)_deleteDatabase;
{
    NSString *journalPath = [databasePath stringByAppendingString:@"-journal"];
    
    [[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:journalPath error:NULL];
}

- (void)_closeDatabase;
{
    sqlite3_close(sqliteDatabase);
}

- (BOOL)_executeSQL:(NSString *)sql withCallback:(OSLDatabaseCallback)callbackFunction context:(void *)callbackContext error:(NSError **)outError;
{
    char *errorMessage = NULL;

    int errorCode = SQLITE_OK;
    do {
        if (errorCode == SQLITE_BUSY)
            [[NSDate dateWithTimeIntervalSinceNow:0.01] sleepUntilDate];

        errorCode = sqlite3_exec(
            sqliteDatabase, /* An open database */
            [sql UTF8String], /* SQL to be executed */
            callbackFunction, /* Callback function */
            callbackContext, /* 1st argument to callback function */
            &errorMessage /* Error msg written here */
        );
    } while (errorCode == SQLITE_BUSY && _autoRetry);

    if (errorCode != SQLITE_OK) {
        NSLog(@"%@: %s (%d)", sql, errorMessage, errorCode);
        OSLSQLError(outError, errorCode, sqliteDatabase);
    } else {
        DebugLog(@"EXEC: %@", sql);
    }
    return errorCode == SQLITE_OK;
}

- (OSLPreparedStatement *)_prepareStatement:(NSString *)sql error:(NSError **)outError;
{
    const char *remainder;
    sqlite3_stmt *statement;
    int errorCode = 
	sqlite3_prepare(
			sqliteDatabase, /* Database handle */
			[sql UTF8String], /* SQL statement, UTF-8 encoded */
			-1, /* ... up to the first NUL */
			&statement, /* OUT: Statement handle */
			&remainder /* OUT: Pointer to unused portion of zSql */               
			);
    
    if (errorCode != SQLITE_OK) {
        const char *errorMessage = sqlite3_errmsg(sqliteDatabase);
        NSLog(@"%@: %s (%d)", sql, errorMessage, errorCode);
        OSLSQLError(outError, errorCode, sqliteDatabase);
	return nil;
    } else {
        DebugLog(@"PREPARE: %@", sql);
    }
    return [[[OSLPreparedStatement alloc] initWithSQL:sql statement:statement databaseController:self] autorelease];
}

- (unsigned long long int)_lastInsertRowID;
{
    return sqlite3_last_insert_rowid(sqliteDatabase);
}

@end

int ReadDictionaryCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames)
{
    NSMutableDictionary *dictionary = callbackContext;
    int columnIndex = columnCount;
    
    [dictionary removeAllObjects];
    while (columnIndex--) {
        if (columnValues[columnIndex] != NULL) {
            NSString *key = [NSString stringWithUTF8String:columnNames[columnIndex]];
            NSString *value = [NSString stringWithUTF8String:columnValues[columnIndex]];
            [dictionary setObject:value forKey:key];
        }
    }
    return 0;
}

int ReadDictionariesCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames)
{
    NSMutableArray *array = callbackContext;
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    int columnIndex = columnCount;
    while (columnIndex--) {
        if (columnValues[columnIndex] != NULL) {
            NSString *key = [NSString stringWithUTF8String:columnNames[columnIndex]];
            NSString *value = [NSString stringWithUTF8String:columnValues[columnIndex]];
            [dictionary setObject:value forKey:key];
        }
    }
    [array addObject:dictionary];
    return 0;
}

int SingleUnsignedLongLongCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames)
{
    unsigned long long int *countPtr = callbackContext;
    OBASSERT(columnCount == 1);
    if (columnValues[0] != NULL && *columnValues[0] != '\0')
        *countPtr = strtoull(columnValues[0], NULL, 10);
    else
        *countPtr = -1LL;
    
    return 0;
}

int SingleIntCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames)
{
    int *countPtr = callbackContext;
    OBASSERT(columnCount == 1);
    if (columnValues[0] != NULL && *columnValues[0] != '\0') {
        *countPtr = atoi(columnValues[0]);
        return 0;
    }
    return 1; // Null is an error
}

int SingleStringCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames)
{
    NSString **stringPtr = callbackContext;
    OBASSERT(columnCount == 1);
    if (columnValues[0] != NULL)
        *stringPtr = [NSString stringWithUTF8String:columnValues[0]];
    else
        *stringPtr = nil;
    return 0;
}

