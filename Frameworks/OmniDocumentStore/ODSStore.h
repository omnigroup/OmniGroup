// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
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

typedef enum {
    ODSDocumentTypeNormal,
    ODSDocumentTypeTemplate,
    ODSDocumentTypeOther,
} ODSDocumentType;

@interface ODSStore : NSObject

- initWithDelegate:(id <ODSStoreDelegate>)delegate;

@property(nonatomic,readonly) NSArray *scopes;
- (void)addScope:(ODSScope *)scope;
- (void)removeScope:(ODSScope *)scope;

@property(nonatomic,readonly) ODSScope *defaultUsableScope;
@property(nonatomic,readonly) ODSScope *trashScope;
@property(nonatomic,readonly) ODSScope *templateScope;

@property(nonatomic,readonly) NSSet *mergedFileItems; // All the file items from all scopes.

- (Class)fileItemClassForURL:(NSURL *)fileURL; // Defaults to asking the delegate. The URL may not exist yet!
- (BOOL)canViewFileTypeWithIdentifier:(NSString *)fileType;
- (ODSFileItem *)preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;

- (void)addAfterInitialDocumentScanAction:(void (^)(void))action;

// Allow external objects to synchronize with our operations.
- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void))block;
- (void)afterAsynchronousFileAccessFinishes:(void (^)(void))block;

- (void)moveItems:(NSSet *)items fromScope:(ODSScope *)fromScope toScope:(ODSScope *)toScope inFolder:(ODSFolderItem *)parentFolder completionHandler:(void (^)(NSSet *movedFileItems, NSArray *errorsOrNil))completionHandler;

- (void)makeFolderFromItems:(NSSet *)items inParentFolder:(ODSFolderItem *)parentFolder ofScope:(ODSScope *)scope completionHandler:(void (^)(ODSFolderItem *createdFolder, NSArray *errorsOrNil))completionHandler;

- (void)scanItemsWithCompletionHandler:(void (^)(void))completionHandler;
- (void)startDeferringScanRequests;
- (void)stopDeferringScanRequests:(void (^)(void))completionHandler;

- (ODSFileItem *)fileItemWithURL:(NSURL *)url;

@property(readonly,nonatomic) NSString *documentTypeForNewFiles;
- (NSString *)documentTypeForNewFilesOfType:(ODSDocumentType)type;
- (NSString *)defaultFilenameForDocumentType:(ODSDocumentType)type isDirectory:(BOOL *)outIsDirectory;
- (NSURL *)temporaryURLForCreatingNewDocumentOfType:(ODSDocumentType)type;
- (void)moveNewTemporaryDocumentAtURL:(NSURL *)fileURL toScope:(ODSScope *)scope folder:(ODSFolderItem *)folder documentType:(ODSDocumentType)type completionHandler:(void (^)(ODSFileItem *createdFileItem, NSError *error))handler;

@end

