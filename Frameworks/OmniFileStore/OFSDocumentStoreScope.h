// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFSDocumentStore, OFSDocumentStoreFileItem;

typedef enum {
    OFSDocumentStoreAddNormally,
    OFSDocumentStoreAddByReplacing,
    OFSDocumentStoreAddByRenaming,
} OFSDocumentStoreAddOption;

typedef void (^OFSDocumentStoreScopeDocumentCreationAction)(void (^handler)(NSURL *resultURL, NSError *errorOrNil));
typedef void (^OFSDocumentStoreScopeDocumentCreationHandler)(OFSDocumentStoreFileItem *createdFileItem, NSError *error);

@interface OFSDocumentStoreScope : NSObject <NSCopying>

- initWithDocumentStore:(OFSDocumentStore *)documentStore;

@property(weak,nonatomic) OFSDocumentStore *documentStore; // Set while this scope is in a store.

+ (BOOL)isFile:(NSURL *)fileURL inContainer:(NSURL *)containerURL;

- (BOOL)isFileInContainer:(NSURL *)fileURL;

// The items in this scope. Subclasses should fill this out, possibly building file items on a background queue, but updating the set on the main queue.
@property(nonatomic,readonly,copy) NSSet *fileItems;

 // The top level file items (ungrouped) and any groups
@property(nonatomic,readonly) NSSet *topLevelItems;

- (OFSDocumentStoreFileItem *)fileItemWithURL:(NSURL *)url;
- (OFSDocumentStoreFileItem *)fileItemWithName:(NSString *)fileName inFolder:(NSString *)folder;
- (OFSDocumentStoreFileItem *)makeFileItemForURL:(NSURL *)fileURL date:(NSDate *)date;

- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void))block;
- (void)afterAsynchronousFileAccessFinishes:(void (^)(void))block;

- (NSURL *)urlForNewDocumentInFolderNamed:(NSString *)folderName baseName:(NSString *)name fileType:(NSString *)documentUTI;
- (void)performDocumentCreationAction:(OFSDocumentStoreScopeDocumentCreationAction)createDocument handler:(OFSDocumentStoreScopeDocumentCreationHandler)handler;

// Added the ability to pass in a baseName which will be substitute in for the files name in to toURL. We use this for handling localized names when restoring sample documents. If you don't want the name changed when adding an item, either pass in nil for the baseName or call the alternate method that doesn't take a baseName. Pass in nil for scope to add to the default scope.
- (void)addDocumentInFolderNamed:(NSString *)folderName baseName:(NSString *)baseName fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
- (void)addDocumentInFolderNamed:(NSString *)folderName fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;

- (void)renameFileItem:(OFSDocumentStoreFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionQueue:(NSOperationQueue *)completionQueue handler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;

- (void)deleteItem:(OFSDocumentStoreFileItem *)fileItem completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)migrateDocumentsFromScope:(OFSDocumentStoreScope *)sourceScope byMoving:(BOOL)shouldMove completionHandler:(void (^)(NSDictionary *migratedURLs, NSDictionary *errorURLs))completionHandler;
#endif

// When moving documents between scopes, the current scope must be asked if this is OK first. The on-disk representation may out of date or otherwise not ready to be moved.
- (BOOL)prepareToMoveFileItem:(OFSDocumentStoreFileItem *)fileItem toScope:(OFSDocumentStoreScope *)otherScope error:(NSError **)outError;

@end

// Subclasses must implement these methods
@protocol OFSDocumentStoreConcreteScope <NSObject>
@property(nonatomic,readonly) NSString *identifier;
@property(nonatomic,readonly) NSString *displayName;
@property(nonatomic,readonly) BOOL hasFinishedInitialScan; // Must be KVO compliant
- (NSURL *)documentsURL:(NSError **)outError;
- (BOOL)requestDownloadOfFileItem:(OFSDocumentStoreFileItem *)fileItem error:(NSError **)outError;
@end

// Claim all instances implement the concrete protocol to avoid casting.
@interface OFSDocumentStoreScope (OFSDocumentStoreConcreteScope) <OFSDocumentStoreConcreteScope>
@end
