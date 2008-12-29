// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODODatabase-Internal.h 104581 2008-09-06 21:18:23Z kc $

#import <OmniDataObjects/ODODatabase.h>

@class ODOEntity, ODORelationship, ODOSQLStatement;

extern NSString * const ODODatabaseMetadataTableName;
extern NSString * const ODODatabaseMetadataKeyColumnName;
extern NSString * const ODODatabaseMetadataPlistColumnName;

@interface ODODatabase (Internal)
- (struct sqlite3 *)_sqlite;
- (id)_generatePrimaryKeyForEntity:(ODOEntity *)entity;
- (BOOL)_beginTransaction:(NSError **)outError;
- (BOOL)_commitTransaction:(NSError **)outError;
- (BOOL)_writeMetadataChanges:(NSError **)outError;
- (void)_committedPendingMetadataChanges;
- (void)_discardPendingMetadataChanges;

- (ODOSQLStatement *)_cachedStatementForKey:(NSObject <NSCopying> *)key;
- (void)_setCachedStatement:(ODOSQLStatement *)statement forKey:(NSObject <NSCopying> *)key;

- (ODOSQLStatement *)_queryForDestinationPrimaryKeysByDestinationForeignKeyStatement:(ODORelationship *)rel error:(NSError **)outError;

@end
