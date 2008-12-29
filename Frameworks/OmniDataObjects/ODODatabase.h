// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODODatabase.h 104583 2008-09-06 21:23:18Z kc $

#import <OmniFoundation/OFObject.h>

@class NSString, NSURL, NSError, NSDictionary, NSMutableDictionary;
@class ODOModel, ODOObjectID, ODOSQLStatement;

extern BOOL ODOLogSQL; // Not set until +[ODODatabase initialize]

@interface ODODatabase : OFObject
{
@private
    ODOModel *_model;
    
    NSURL *_connectedURL;
    struct sqlite3 *_sqlite;
    ODOSQLStatement *_beginTransactionStatement;
    ODOSQLStatement *_commitTransactionStatement;
    ODOSQLStatement *_metadataInsertStatement;
    NSMutableDictionary *_cachedStatements;
    
    NSMutableDictionary *_committedMetadata;
    NSMutableDictionary *_pendingMetadataChanges;
    
    BOOL _isFreshlyCreated; // YES if we just made the schema and -didSave hasn't been called (which should be called the first time we save a transaction; presumably having an INSERT).
}

- (id)initWithModel:(ODOModel *)model;
- (ODOModel *)model;

- (NSURL *)connectedURL;
- (BOOL)connectToURL:(NSURL *)fileURL error:(NSError **)outError;
- (BOOL)disconnect:(NSError **)outError;

- (BOOL)isFreshlyCreated;
- (void)didSave;

// Values can be any plist type.  Setting a NSNull or nil will cause the metadata value to be removed.  Metadata changes are saved with the next normal save.
- (id)metadataForKey:(NSString *)key;
- (void)setMetadata:(id)value forKey:(NSString *)key;

- (NSDictionary *)committedMetadata;

// Dangerous API
- (BOOL)executeSQLWithoutResults:(NSString *)sql error:(NSError **)outError;

@end

extern NSString * const ODODatabaseConnectedURLChangedNotification;
