// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSPredicate, NSURL, NSError, NSString, NSArray;
@class ODOModel, ODOEntity, ODOAttribute, ODOObjectID, ODOSQLConnection, ODOSQLStatement;

NS_ASSUME_NONNULL_BEGIN

extern BOOL ODOLogSQL; // Not set until +[ODODatabase initialize]

@interface ODODatabase : OFObject

- (instancetype)initWithModel:(ODOModel *)model;

@property (nullable, readonly) ODOSQLConnection *connection;
@property (nullable, readonly) NSURL *connectedURL; // convenience for connection.URL
@property (nonatomic, readonly) ODOModel *model;

- (BOOL)connectToURL:(NSURL *)fileURL error:(NSError **)outError;
- (BOOL)disconnect:(NSError **)outError;

@property(nonatomic, readonly, getter=isFreshlyCreated) BOOL freshlyCreated;

- (void)didSave;

// Values can be any plist type.  Setting a NSNull or nil will cause the metadata value to be removed.  Metadata changes are saved with the next normal save.
- (nullable id)metadataForKey:(NSString *)key;
- (void)setMetadata:(nullable id)value forKey:(NSString *)key;

- (BOOL)writePendingMetadataChanges:(NSError **)outError; // Typically this happens at save time, but we may need to force a write (for example, when closing a store before deleting the cache file)
- (BOOL)deleteCommittedMetadataForKey:(NSString *)key error:(NSError **)outError;

@property(nullable, readonly) NSDictionary *committedMetadata;

- (BOOL)fetchCommittedRowCount:(uint64_t *)outRowCount fromEntity:(ODOEntity *)entity matchingPredicate:(nullable NSPredicate *)predicate error:(NSError **)outError;

- (BOOL)fetchCommitedInt64Sum:(int64_t *)outSum fromAttribute:(ODOAttribute *)attribute entity:(ODOEntity *)entity matchingPredicate:(nullable NSPredicate *)predicate error:(NSError **)outError;

- (nullable NSArray<NSArray<id> *> *)fetchCommittedAttributes:(NSArray<ODOAttribute *> *)attributes fromEntity:(ODOEntity *)entity matchingPredicate:(nullable NSPredicate *)predicate error:(NSError **)outError;

// Dangerous API
- (BOOL)executeSQLWithoutResults:(NSString *)sql error:(NSError **)outError;

@end

extern NSNotificationName ODODatabaseConnectedURLChangedNotification;

NS_ASSUME_NONNULL_END
