// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSString, NSURL, NSError, NSDictionary, NSMutableDictionary, NSPredicate;
@class ODOModel, ODOEntity, ODOAttribute, ODOObjectID, ODOSQLStatement;

NS_ASSUME_NONNULL_BEGIN

extern BOOL ODOLogSQL; // Not set until +[ODODatabase initialize]

@interface ODODatabase : OFObject

- (id)initWithModel:(ODOModel *)model;
@property(readonly) ODOModel *model;

@property(nullable, readonly) NSURL *connectedURL;
- (BOOL)connectToURL:(NSURL *)fileURL error:(NSError **)outError;
- (BOOL)disconnect:(NSError **)outError;

@property(readonly) BOOL isFreshlyCreated;
- (void)didSave;

// Values can be any plist type.  Setting a NSNull or nil will cause the metadata value to be removed.  Metadata changes are saved with the next normal save.
- (nullable id)metadataForKey:(NSString *)key;
- (void)setMetadata:(nullable id)value forKey:(NSString *)key;

- (BOOL)writePendingMetadataChanges:(NSError **)outError; // Typically this happens at save time, but we may need to force a write (for example, when closing a store before deleting the cache file)
- (BOOL)deleteCommittedMetadataForKey:(NSString *)key error:(NSError **)outError;

@property(nullable, readonly) NSDictionary *committedMetadata;

- (BOOL)fetchCommittedRowCount:(uint64_t *)outRowCount fromEntity:(ODOEntity *)entity matchingPredicate:(nullable NSPredicate *)predicate error:(NSError **)outError;

- (BOOL)fetchCommitedInt64Sum:(int64_t *)outSum fromAttribute:(ODOAttribute *)attribute entity:(ODOEntity *)entity matchingPredicate:(nullable NSPredicate *)predicate error:(NSError **)outError;

// Dangerous API
- (BOOL)executeSQLWithoutResults:(NSString *)sql error:(NSError **)outError;

@end

extern NSString * const ODODatabaseConnectedURLChangedNotification;

NS_ASSUME_NONNULL_END
