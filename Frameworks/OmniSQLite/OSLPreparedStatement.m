// Copyright 2004-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSQLite/OSLPreparedStatement.h>

#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>

#import <OmniSQLite/OSLDatabaseController.h>
#import "sqlite3.h"

RCS_ID("$Id$")

@interface OSLDatabaseController (Private)
- (void *)_database;
@end

@implementation OSLPreparedStatement

- initWithSQL:(NSString *)someSQL statement:(void *)preparedStatement databaseController:(OSLDatabaseController *)aDatabaseController;
{
    if (!(self = [super init]))
        return nil;
    
    sql = [someSQL retain];
    statement = preparedStatement;
    databaseController = [aDatabaseController retain];
    
    return self;
}

- (void)dealloc;
{
    sqlite3_finalize(statement);
    [databaseController release];
    [super dealloc];
}

- (void)reset;
{
    bindIndex = 0;
    sqlite3_reset(statement);
}

#if 0 && defined(DEBUG)
    #define DebugLog(format, ...) NSLog(format, ## __VA_ARGS__)
#else
    #define DebugLog(format, ...) do {} while (0)
#endif

- (NSDictionary *)step;
{
    DebugLog(@"STEP %@", sql);
    int errorCode = sqlite3_step(statement);
    
    if (errorCode == SQLITE_ROW) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        unsigned int columnIndex = sqlite3_data_count(statement);
        id value;
        
        while (columnIndex--) {
            switch(sqlite3_column_type(statement, columnIndex)) {
                case SQLITE_INTEGER:
                    value = [NSNumber numberWithLongLong:sqlite3_column_int64(statement, columnIndex)];
                    break;
                case SQLITE_FLOAT:
                    value = [NSNumber numberWithDouble:sqlite3_column_double(statement, columnIndex)];
                    break;
                case SQLITE_TEXT:
                case SQLITE_BLOB:
                    value = [NSData dataWithBytes:sqlite3_column_blob(statement, columnIndex) length:sqlite3_column_bytes(statement, columnIndex)];
                    break;
                case SQLITE_NULL:
                default:
                    continue;
            }
            NSString *key = [NSString stringWithUTF8String:sqlite3_column_name(statement, columnIndex)];
            [dictionary setObject:value forKey:key];
        }
#ifdef DEBUG0
	DebugLog(@"-> %@", dictionary);
#else
        DebugLog(@"-> %u columns", sqlite3_data_count(statement));
#endif
        return dictionary;
    }
    if (errorCode != SQLITE_DONE)
        NSLog(@"ERROR executing sql %@: %s (%d)", sql, sqlite3_errmsg([databaseController _database]), errorCode);
    
    return nil;
}

- (void)bindInt:(int)integer;
{
    sqlite3_bind_int(statement, ++bindIndex, integer);
}

- (void)bindString:(NSString *)string;
{
    const char *value = [string UTF8String];
    size_t stringLength = strlen(value);
    OBASSERT(stringLength <= INT_MAX);
    sqlite3_bind_text(statement, ++bindIndex, value, (int)stringLength, SQLITE_TRANSIENT);
}

- (void)bindBlob:(NSData *)data;
{
    NSUInteger dataLength = [data length];
    OBASSERT(dataLength <= INT_MAX);
    sqlite3_bind_text(statement, ++bindIndex, [data bytes], (int)dataLength, SQLITE_TRANSIENT);
}

- (void)bindLongLongInt:(long long)longLong;
{
    sqlite3_bind_int64(statement, ++bindIndex, longLong);
}

- (void)bindNull;
{
    sqlite3_bind_null(statement, ++bindIndex);
}

// Convenience methods

- (void)bindPropertyList:(id)propertyList;
{
    NSData *propertyListXMLData = OFCreateNSDataFromPropertyList(propertyList, kCFPropertyListXMLFormat_v1_0, NULL);
    [self bindBlob:propertyListXMLData];
    [propertyListXMLData release];
}

@end
