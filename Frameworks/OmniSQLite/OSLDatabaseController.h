// Copyright 2004-2015 Omni Development, Inc. All rights reserved.
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
    BOOL _autoRetry;
}

@property (assign, nonatomic) BOOL autoRetry;

- initWithDatabasePath:(NSString *)aPath error:(NSError **)outError;
- (NSString *)databasePath;

- (void)deleteDatabase;

- (BOOL)executeSQL:(NSString *)sql withCallback:(OSLDatabaseCallback)callbackFunction context:(void *)callbackContext error:(NSError **)outError;
- (OSLPreparedStatement *)prepareStatement:(NSString *)sql error:(NSError **)outError;
- (unsigned long long int)lastInsertRowID;

// Convenience methods

- (BOOL)beginTransaction;
- (BOOL)commitTransaction;
- (BOOL)rollbackTransaction;

@end

extern int ReadDictionaryCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames);
extern int ReadDictionariesCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames);
extern int SingleUnsignedLongLongCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames);
extern int SingleIntCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames);
extern int SingleStringCallback(void *callbackContext, int columnCount, char **columnValues, char **columnNames);
