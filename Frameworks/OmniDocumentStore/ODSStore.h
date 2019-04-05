// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSOperation;

@protocol ODSStoreDelegate;
@class ODSFileItem, ODSFolderItem, ODSScope, ODSLocalDirectoryScope;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ODSDocumentType) {
    ODSDocumentTypeNormal,
    ODSDocumentTypeTemplate,
    ODSDocumentTypeOther,
};

@interface ODSStore : NSObject

- initWithDelegate:(id <ODSStoreDelegate>)delegate;

@property(nonatomic,readonly) NSArray <__kindof ODSScope *> *scopes;
- (void)addScope:(ODSScope *)scope;
- (void)removeScope:(ODSScope *)scope;

@property(nonatomic,readonly) ODSScope *defaultUsableScope;
@property(nonatomic,readonly) ODSScope *trashScope;
@property(nonatomic,readonly) ODSScope *templateScope;

@property(nonatomic,readonly) NSSet <__kindof ODSFileItem *> *mergedFileItems; // All the file items from all scopes.

- (Class)fileItemClassForURL:(NSURL *)fileURL; // Defaults to asking the delegate. The URL may not exist yet!
- (BOOL)canViewFileTypeWithIdentifier:(NSString *)fileType;
- (nullable ODSFileItem *)preferredFileItemForNextAutomaticDownload:(NSSet <__kindof ODSFileItem *> *)fileItems;

- (void)addAfterInitialDocumentScanAction:(void (^)(void))action;

- (void)moveItems:(NSSet <__kindof ODSFileItem *> *)items fromScope:(ODSScope *)fromScope toScope:(ODSScope *)toScope inFolder:(ODSFolderItem *)parentFolder completionHandler:(void (^ _Nullable)(NSSet <__kindof ODSFileItem *> * _Nullable movedFileItems, NSArray <NSError *> * _Nullable errorsOrNil))completionHandler;

- (void)makeFolderFromItems:(NSSet <__kindof ODSFileItem *> *)items inParentFolder:(ODSFolderItem *)parentFolder ofScope:(ODSScope *)scope completionHandler:(void (^)(ODSFolderItem * _Nullable createdFolder, NSArray <NSError *> * _Nullable errorsOrNil))completionHandler;

- (void)scanItemsWithCompletionHandler:(void (^ _Nullable)(void))completionHandler;
- (void)startDeferringScanRequests;
- (void)stopDeferringScanRequests:(void (^ _Nullable)(void))completionHandler;

- (nullable ODSFileItem *)fileItemWithURL:(NSURL *)url;

@property(readonly,nonatomic) NSString *documentTypeForNewFiles;
- (nullable NSString *)documentTypeForNewFilesOfType:(ODSDocumentType)type;
- (NSString *)defaultFilenameForDocumentType:(ODSDocumentType)type isDirectory:(BOOL *)outIsDirectory;
- (NSURL *)temporaryURLForCreatingNewDocumentOfType:(ODSDocumentType)type;
// IF the provided documentName is nil, then we will use the default name for that new document type.
- (void)moveNewTemporaryDocumentAtURL:(NSURL *)fileURL toScope:(ODSScope *)scope folder:(nullable ODSFolderItem *)folder documentType:(ODSDocumentType)type documentName:(nullable)documentName completionHandler:(void (^)(ODSFileItem *createdFileItem, NSError *error))handler;
- (void)moveNewTemporaryDocumentAtURL:(NSURL *)fileURL toScope:(ODSScope *)scope folder:(nullable ODSFolderItem *)folder documentType:(ODSDocumentType)type completionHandler:(void (^)(ODSFileItem *createdFileItem, NSError *error))handler;

@end

NS_ASSUME_NONNULL_END

