// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSFeatures.h>

#if OFS_DOCUMENT_STORE_SUPPORTED

#import <OmniFoundation/OFObject.h>
#import <OmniFileStore/OFSDocumentStoreScope.h>

@class NSOperation;

@protocol OFSDocumentStoreDelegate;
@class OFSDocumentStoreFileItem, OFSDocumentStoreGroupItem;

typedef enum {
    OFSDocumentStoreAddNormally,
    OFSDocumentStoreAddByReplacing,
    OFSDocumentStoreAddByRenaming,
} OFSDocumentStoreAddOption;

extern NSString * const OFSDocumentStoreFileItemsBinding;
extern NSString * const OFSDocumentStoreTopLevelItemsBinding;

@interface OFSDocumentStore : OFObject

+ (BOOL)shouldPromptForUbiquityAccess; // User has never responded to a prompt since the last time iCloud Documents & Data was enabled
+ (BOOL)canPromptForUbiquityAccess; // iCloud is supported, but the user might have opted out for this app.
+ (void)didPromptForUbiquityAccessWithResult:(BOOL)allowUbiquityAccess;
+ (BOOL)isUbiquityAccessEnabled;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// Returns yes if url directly points to the Inbox or to a file directly in the Inbox.
+ (BOOL)isURLInInbox:(NSURL *)url;
+ (NSURL *)userDocumentsDirectoryURL;

// The app controller is expected to call these when its foreground status changes (giving it more control over the timing of other the rescan).
- (void)applicationDidEnterBackground;
- (void)applicationWillEnterForegroundWithCompletionHandler:(void (^)(void))completionHandler;
#endif

- (NSString *)availableFileNameWithBaseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
- (NSURL *)availableURLInDirectoryAtURL:(NSURL *)directoryURL baseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSURL *)availableURLWithFileName:(NSString *)fileName;
#endif
- (BOOL)userFileExistsWithFileNameOfURL:(NSURL *)fileURL;

- initWithDirectoryURL:(NSURL *)directoryURL delegate:(id <OFSDocumentStoreDelegate>)delegate scanCompletionHandler:(void (^)(void))completionHandler;

- (void)addAfterInitialDocumentScanAction:(void (^)(void))action;

// Allow external objects to synchronize with our operations.
- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void))block;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSOperation *)addDocumentWithScope:(OFSDocumentStoreScope)scope inFolderNamed:(NSString *)folderName fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
- (NSOperation *)addDocumentFromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
#endif

// The caller should ensure this method is invoked on a thread that won't cause deadload with any registered NSFilePresenters and that will synchronize with other document I/O (see -[UIDocument performAsynchronousFileAccessUsingBlock:])
- (void)renameFileItem:(OFSDocumentStoreFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionQueue:(NSOperationQueue *)completionQueue handler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)makeGroupWithFileItems:(NSSet *)fileItems completionHandler:(void (^)(OFSDocumentStoreGroupItem *group, NSError *error))completionHandler;
- (void)moveItems:(NSSet *)fileItems toFolderNamed:(NSString *)folderName completionHandler:(void (^)(OFSDocumentStoreGroupItem *group, NSError *error))completionHandler;
#endif

// Call this method on the main thread to asynchronously move a file to the cloud. The completionHandler will be executed on the main thread sometime after this method returns.
- (void)moveItemsAtURLs:(NSSet *)urls toFolderInCloudWithName:(NSString *)folderNameOrNil completionHandler:(void (^)(NSDictionary *movedURLs, NSDictionary *errorURLs))completionHandler;

// This does not automatically call -rescanItems
- (void)deleteItem:(OFSDocumentStoreFileItem *)fileItem completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

@property(copy, nonatomic) NSURL *directoryURL;

@property(nonatomic,readonly) NSSet *fileItems; // All the file items, no matter if they are in a group
@property(nonatomic,readonly) NSSet *topLevelItems; // The top level file items (ungrouped) and any groups

@property(nonatomic,readonly) BOOL hasFinishedInitialMetdataQuery;

- (void)scanItemsWithCompletionHandler:(void (^)(void))completionHandler;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)moveLocalDocumentsToCloudWithCompletionHandler:(void (^)(NSDictionary *movedURLs, NSDictionary *errorURLs))completionHandler;
#endif

- (BOOL)hasDocuments;
- (OFSDocumentStoreFileItem *)fileItemWithURL:(NSURL *)url;
- (OFSDocumentStoreFileItem *)fileItemNamed:(NSString *)documentName;

- (OFSDocumentStoreScope)scopeForFileURL:(NSURL *)fileURL;
                                                  
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
@property(readonly,nonatomic) NSString *documentTypeForNewFiles;
- (NSURL *)urlForNewDocumentOfType:(NSString *)documentUTI;
- (NSURL *)urlForNewDocumentWithName:(NSString *)name ofType:(NSString *)documentUTI;
- (void)createNewDocument:(void (^)(OFSDocumentStoreFileItem *createdFileItem, NSError *error))handler;

- (void)moveFileItems:(NSSet *)fileItems toCloud:(BOOL)shouldBeInCloud completionHandler:(void (^)(OFSDocumentStoreFileItem *failingItem, NSError *errorOrNil))completionHandler;
- (void)cloneInboxItem:(NSURL *)inboxURL completionHandler:(void (^)(OFSDocumentStoreFileItem *newFileItem, NSError *errorOrNil))completionHandler;
- (BOOL)deleteInbox:(NSError **)outError;
#endif

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
