// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODODatabase.h>
#import <OmniDataObjects/ODOSQLConnection.h>

@class ODOEntity, ODORelationship, ODOSQLStatement, ODOSQLConnection;

extern NSString * const ODODatabaseMetadataTableName;
extern NSString * const ODODatabaseMetadataKeyColumnName;
extern NSString * const ODODatabaseMetadataPlistColumnName;

@interface ODODatabase (Internal)

- (id)_generatePrimaryKeyForEntity:(ODOEntity *)entity;

/// Convenience for calling -performSQLAndWaitWithError:block:, wrapping the given block in `BEGIN EXCLUSIVE`/`COMMIT` to form a SQLite transaction.
- (BOOL)_performTransactionWithError:(NSError **)outError block:(ODOSQLFailablePerformBlock)block;

// Flushes pending metadata changes to the connected database. Must be called from within a block passed to one of ODOSQLConnection's perform-SQL methods.
- (BOOL)_queue_writeMetadataChangesToSQLite:(struct sqlite3 *)sqlite error:(NSError **)outError;

- (void)_committedPendingMetadataChanges;
- (void)_discardPendingMetadataChanges;

- (ODOSQLStatement *)_cachedStatementForKey:(NSObject <NSCopying> *)key;
- (void)_setCachedStatement:(ODOSQLStatement *)statement forKey:(NSObject <NSCopying> *)key;

- (ODOSQLStatement *)_queryForDestinationPrimaryKeysByDestinationForeignKeyStatement:(ODORelationship *)rel error:(NSError **)outError;

@end
