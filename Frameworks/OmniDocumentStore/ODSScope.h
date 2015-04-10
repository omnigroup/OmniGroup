// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class ODSStore, ODSFileItem, ODSFolderItem, ODSItem, OFFileEdit, ODSFileItemEdit;

typedef enum {
    ODSStoreAddByCopyingSourceToDestinationURL, // Will return an error if the destination already exists
    ODSStoreAddByCopyingSourceToReplaceDestinationURL, // Overwrite with a copy
    ODSStoreAddByCopyingSourceToAvailableDestinationURL, // If the destination URL is taken, a sibling with an available name will be used
    ODSStoreAddByMovingTemporarySourceToAvailableDestinationURL, // Same as ODSStoreAddByCopyingSourceToAvailableDestinationURL, but the source is moved into place (and is presumed to be a file outside of any scope that doesn't need file coordination applied).
} ODSStoreAddOption;

typedef void (^ODSScopeDocumentCreationAction)(void (^handler)(OFFileEdit *resultFileEdit, NSError *errorOrNil));
typedef void (^ODSScopeDocumentCreationHandler)(ODSFileItem *createdFileItem, NSError *error);

@interface ODSFileItemMotion : NSObject

@property(nonatomic,readonly) ODSFileItem *fileItem;
@property(nonatomic,readonly) ODSFileItemEdit *originalItemEdit; // Might be nil for files that haven't been downloaded
@property(nonatomic,readonly) NSURL *sourceFileURL;
@property(nonatomic,readonly) NSURL *destinationFileURL;

@end

// destinationEditOrNil is nil if the copy failed
typedef void (^ODSScopeItemMotionStatus)(ODSFileItemMotion *itemMotion, NSURL *destinationURL, ODSFileItemEdit *destinationEditOrNil, NSError *errorOrNil);

@interface ODSScope : NSObject <NSCopying>

- initWithDocumentStore:(ODSStore *)documentStore;

@property(weak,nonatomic,readonly) ODSStore *documentStore;

+ (BOOL)isFile:(NSURL *)fileURL inContainer:(NSURL *)containerURL;

- (BOOL)isFileInContainer:(NSURL *)fileURL;

// The items in this scope. Subclasses should fill this out, possibly building file items on a background queue, but updating the set on the main queue.
@property(nonatomic,readonly,copy) NSSet *fileItems;

@property(nonatomic,readonly) ODSFolderItem *rootFolder; // Relative path of @""
@property(nonatomic,readonly) NSSet *topLevelItems; // A KVO observable alias for rootFolder.childItems

- (ODSFileItem *)fileItemWithURL:(NSURL *)url;
- (ODSFolderItem *)folderItemContainingItem:(ODSItem *)item;
- (ODSFileItem *)makeFileItemForURL:(NSURL *)fileURL isDirectory:(BOOL)isDirectory fileEdit:(OFFileEdit *)fileEdit userModificationDate:(NSDate *)userModificationDate;

- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void))block;
- (void)afterAsynchronousFileAccessFinishes:(void (^)(void))block;

// Passing nil means the scope's documentsURL.
- (NSURL *)urlForNewDocumentInFolder:(ODSFolderItem *)folder baseName:(NSString *)baseName fileType:(NSString *)documentUTI;
- (NSURL *)urlForNewDocumentInFolderAtURL:(NSURL *)folderURL baseName:(NSString *)baseName fileType:(NSString *)documentUTI;
- (void)performDocumentCreationAction:(ODSScopeDocumentCreationAction)createDocument handler:(ODSScopeDocumentCreationHandler)handler;

// Infers the file type for the new document based on fromURL. Useful for duplicating documents.
- (void)addDocumentInFolder:(ODSFolderItem *)folderItem baseName:(NSString *)baseName fromURL:(NSURL *)fromURL option:(ODSStoreAddOption)option completionHandler:(void (^)(ODSFileItem *duplicateFileItem, NSError *error))completionHandler;

// Allows for a specific type. Useful for instantiating templates, when the template file type has a different file type.
- (void)addDocumentInFolder:(ODSFolderItem *)folderItem baseName:(NSString *)baseName fileType:(NSString *)fileType fromURL:(NSURL *)fromURL option:(ODSStoreAddOption)option completionHandler:(void (^)(ODSFileItem *duplicateFileItem, NSError *error))completionHandler;

// Uses a default base name for the new document.
- (void)addDocumentInFolder:(ODSFolderItem *)folderItem fromURL:(NSURL *)fromURL option:(ODSStoreAddOption)option completionHandler:(void (^)(ODSFileItem *duplicateFileItem, NSError *error))completionHandler;

// Somewhat like -addDocumentInFolderAtURL:... but this duplicates folders as well as files and only works for duplicating things currently in the scope (where -addDocumentInFolderAtURL: can be used to copy items into a copy from the iOS document Inbox). The status handler is called once for each copied file. If there is an error copying a file, the duplicateFileItem argument will be nil, but originalFileItem will not be. Once all the copying is done, the completion handler will be called with the top level items that resulted from the duplication (which will include folders for source folders, whereas the status block gets called recursively).
- (void)copyItems:(NSSet *)items toFolder:(ODSFolderItem *)parentFolder status:(ODSScopeItemMotionStatus)status completionHandler:(void (^)(NSSet *finalItems))completionHandler;

- (void)updateFileItem:(ODSFileItem *)fileItem withBlock:(void (^)(void (^updateCompletionHandler)(BOOL success, NSURL *destinationURL, NSError *error)))block completionHandler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
- (void)renameFileItem:(ODSFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionHandler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;
- (void)renameFolderItem:(ODSFolderItem *)folderItem baseName:(NSString *)baseName completionHandler:(void (^)(NSSet *movedFileItems, NSArray *errorsOrNil))completionHandler;

// When moving documents between scopes, the current scope must be asked if this is OK first. The on-disk representation may out of date or otherwise not ready to be moved.
- (BOOL)prepareToRelinquishItem:(ODSItem *)item error:(NSError **)outError;
- (void)takeItems:(NSSet *)items toFolder:(ODSFolderItem *)folderItem ignoringFileItems:(NSSet *)ignoredFileItems completionHandler:(void (^)(NSSet *movedFileItems, NSArray *errorsOrNil))completionHandler;

// Moving within a single scope
- (void)moveItems:(NSSet *)items toFolder:(ODSFolderItem *)folderItem completionHandler:(void (^)(NSSet *movedFileItems, NSArray *errorsOrNil))completionHandler;

- (void)makeFolderFromItems:(NSSet *)items inParentFolder:(ODSFolderItem *)parentFolder completionHandler:(void (^)(ODSFolderItem *createdFolder, NSArray *errorsOrNil))completionHandler;

- (BOOL)isTrash;
+ (ODSScope *)trashScope;
+ (void)setTrashScope:(ODSScope *)trashScope;

+ (BOOL)trashItemAtURL:(NSURL *)url resultingItemURL:(NSURL **)outResultingURL error:(NSError **)error;

- (BOOL)isTemplate;
+ (ODSScope *)templateScope;
+ (void)setTemplateScope:(ODSScope *)templateScope;


- (NSComparisonResult)compareDocumentScope:(ODSScope *)otherScope;
- (NSInteger)documentScopeGroupRank;

@end

// Subclasses must implement these methods
@protocol ODSConcreteScope <NSObject>
@property(nonatomic,readonly) NSString *identifier;
@property(nonatomic,readonly) NSString *displayName;
@property(nonatomic,readonly) BOOL hasFinishedInitialScan; // Must be KVO compliant
@property(nonatomic,readonly) NSURL *documentsURL;
- (BOOL)requestDownloadOfFileItem:(ODSFileItem *)fileItem error:(NSError **)outError;

- (void)deleteItems:(NSSet *)items completionHandler:(void (^)(NSSet *deletedFileItems, NSArray *errorsOrNil))completionHandler;

@optional
- (void)wasAddedToDocumentStore;
- (void)willBeRemovedFromDocumentStore;

@end

// Claim all instances implement the concrete protocol to avoid casting.
@interface ODSScope (ODSConcreteScope) <ODSConcreteScope>
@end
