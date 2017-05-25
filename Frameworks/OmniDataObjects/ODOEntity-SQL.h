// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOEntity.h>

@class ODODatabase, ODOObject, ODOSQLStatement;

@interface ODOEntity (ODO_SQL)
- (void)_buildSchemaProperties;
- (NSArray *)_schemaProperties;
- (BOOL)_createSchemaInDatabase:(ODODatabase *)database error:(NSError **)outError;
- (BOOL)_createIndexesInDatabase:(ODODatabase *)database error:(NSError **)outError;

struct sqlite3;
- (BOOL)_writeInsert:(struct sqlite3 *)sqlite database:(ODODatabase *)database object:(ODOObject *)object error:(NSError **)outError;
- (BOOL)_writeUpdate:(struct sqlite3 *)sqlite database:(ODODatabase *)database object:(ODOObject *)object error:(NSError **)outError;
- (BOOL)_writeDelete:(struct sqlite3 *)sqlite database:(ODODatabase *)database object:(ODOObject *)object error:(NSError **)outError;

- (ODOSQLStatement *)_queryByPrimaryKeyStatement:(NSError **)outError database:(ODODatabase *)database sqlite:(struct sqlite3 *)sqlite;

@end
