// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniUI/OUIDocumentStoreScope.h>

@protocol OUIDocumentStoreDelegate;
@class OUIDocumentStoreFileItem, OUIDocumentStoreGroupItem;

typedef enum {
    OUIDocumentStoreAddNormally,
    OUIDocumentStoreAddByReplacing,
    OUIDocumentStoreAddByRenaming,
} OUIDocumentStoreAddOption;

extern NSString * const OUIDocumentStoreFileItemsBinding;
extern NSString * const OUIDocumentStoreTopLevelItemsBinding;

@interface OUIDocumentStore : OFObject

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
+ (NSURL *)userDocumentsDirectoryURL;
#endif

- (NSString *)availableFileNameWithBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
- (NSURL *)availableURLInDirectoryAtURL:(NSURL *)directoryURL baseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSURL *)availableURLWithFileName:(NSString *)fileName;
#endif
- (BOOL)userFileExistsWithFileNameOfURL:(NSURL *)fileURL;

- initWithDirectoryURL:(NSURL *)directoryURL delegate:(id <OUIDocumentStoreDelegate>)delegate;

- (void)addAfterInitialDocumentScanAction:(void (^)(void))action;

// Allow external objects to synchronize with our operations.
- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void))block;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSOperation *)addDocumentWithScope:(OUIDocumentStoreScope)scope inFolderNamed:(NSString *)folderName fromURL:(NSURL *)fromURL option:(OUIDocumentStoreAddOption)option completionHandler:(void (^)(OUIDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
- (NSOperation *)addDocumentFromURL:(NSURL *)fromURL option:(OUIDocumentStoreAddOption)option completionHandler:(void (^)(OUIDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
#endif

// The caller should ensure this method is invoked on a thread that won't cause deadload with any registered NSFilePresenters and that will synchronize with other document I/O (see -[UIDocument performAsynchronousFileAccessUsingBlock:])
- (void)renameFileItem:(OUIDocumentStoreFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionQueue:(NSOperationQueue *)completionQueue handler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)makeGroupWithFileItems:(NSSet *)fileItems completionHandler:(void (^)(OUIDocumentStoreGroupItem *group, NSError *error))completionHandler;
- (void)moveItems:(NSSet *)fileItems toFolderNamed:(NSString *)folderName completionHandler:(void (^)(OUIDocumentStoreGroupItem *group, NSError *error))completionHandler;
#endif

// The caller must ensure this method is invoked on a thread that won't cause deadlock with any registered NSFilePresenters and that will synchronize with other document I/O (see -[NSDocument performAsynchronousFileAccessUsingBlock:])
- (void)moveItemsAtURLs:(NSSet *)urls toFolderInCloudWithName:(NSString *)folderNameOrNil completionHandler:(void (^)(NSDictionary *movedURLs, NSDictionary *errorURLs))completionHandler;

// This does not automatically call -rescanItems
- (NSOperation *)deleteItem:(OUIDocumentStoreFileItem *)fileItem completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

@property(copy, nonatomic) NSURL *directoryURL;

@property(nonatomic,readonly) NSSet *fileItems; // All the file items, no matter if they are in a group
@property(nonatomic,readonly) NSSet *topLevelItems; // The top level file items (ungrouped) and any groups

@property(nonatomic,readonly) BOOL hasFinishedInitialMetdataQuery;

- (void)scanItemsWithCompletionHandler:(void (^)(void))completionHandler;

- (BOOL)hasDocuments;
- (OUIDocumentStoreFileItem *)fileItemWithURL:(NSURL *)url;
- (OUIDocumentStoreFileItem *)fileItemNamed:(NSString *)documentName;

- (OUIDocumentStoreScope)scopeForFileURL:(NSURL *)fileURL;
                                                  
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
@property(readonly,nonatomic) NSString *documentTypeForNewFiles;
- (NSURL *)urlForNewDocumentOfType:(NSString *)documentUTI;
- (NSURL *)urlForNewDocumentWithName:(NSString *)name ofType:(NSString *)documentUTI;
- (void)createNewDocument:(void (^)(NSURL *createdURL, NSError *error))handler;

- (void)moveFileItems:(NSSet *)fileItems toCloud:(BOOL)shouldBeInCloud completionHandler:(void (^)(OUIDocumentStoreFileItem *failingItem, NSError *errorOrNil))completionHandler;
#endif

@end
