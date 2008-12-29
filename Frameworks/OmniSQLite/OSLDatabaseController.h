// Copyright 2004-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSArray, NSData, NSError;
@class OSLPreparedStatement;

typedef int (*OSLDatabaseCallback)(void *, int, char **, char **);

@interface OSLDatabaseController : OFObject
{
    NSString *databasePath;
    void *sqliteDatabase;
}

- initWithDatabasePath:(NSString *)aPath error:(NSError **)outError;
- (NSString *)databasePath;

- (void)deleteDatabase;

- (void)executeSQL:(NSString *)sql withCallback:(OSLDatabaseCallback)callbackFunction context:(void *)callbackContext;
- (OSLPreparedStatement *)prepareStatement:(NSString *)sql;
- (unsigned long long int)lastInsertRowID;

// Convenience methods

- (void)beginTransaction;
- (void)commitTransaction;
- (void)rollbackTransaction;

@end

extern int ReadDictionaryCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames);
extern int ReadDictionariesCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames);
extern int SingleUnsignedLongLongCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames);
extern int SingleIntCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames);
extern int SingleStringCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames);
