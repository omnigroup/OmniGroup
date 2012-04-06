// Copyright 2010-2012 The Omni Group. All rights reserved.
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

@class NSOperation;

@protocol OFSDocumentStoreDelegate;
@class OFSDocumentStoreFileItem, OFSDocumentStoreGroupItem, OFSDocumentStoreScope, OFPreference;

typedef enum {
    OFSDocumentStoreAddNormally,
    OFSDocumentStoreAddByReplacing,
    OFSDocumentStoreAddByRenaming,
} OFSDocumentStoreAddOption;

extern NSString * const OFSDocumentStoreUbiquityEnabledChangedNotification;

extern NSString * const OFSDocumentStoreFileItemsBinding;
extern NSString * const OFSDocumentStoreTopLevelItemsBinding;
extern OFPreference *OFSDocumentStoreDisableUbiquityPreference; // Even if ubiquity is enabled, don't ask the user -- just pretend we don't see it.

@interface OFSDocumentStore : OFObject

+ (BOOL)shouldPromptForUbiquityAccess; // User has never responded to a prompt since the last time iCloud Documents & Data was enabled
+ (BOOL)canPromptForUbiquityAccess; // iCloud is supported, but the user might have opted out for this app.
+ (void)didPromptForUbiquityAccessWithResult:(BOOL)allowUbiquityAccess;
+ (BOOL)isUbiquityAccessEnabled;
+ (NSArray *)defaultUbiquitousScopes;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// Returns yes if url directly points to the Inbox or to a file directly in the Inbox.
+ (BOOL)isURLInInbox:(NSURL *)url;
+ (NSURL *)userDocumentsDirectoryURL;

// The app controller is expected to call these when its foreground status changes (giving it more control over the timing of other the rescan).
- (void)applicationDidEnterBackground;
- (void)applicationWillEnterForegroundWithCompletionHandler:(void (^)(void))completionHandler;
#endif

- (OFSDocumentStoreScope *)scopeForFileName:(NSString *)fileName inFolder:(NSString *)folder;

- initWithDirectoryURL:(NSURL *)directoryURL containerScopes:(NSArray *)containerScopes delegate:(id <OFSDocumentStoreDelegate>)delegate scanCompletionHandler:(void (^)(void))completionHandler;

- (void)addAfterInitialDocumentScanAction:(void (^)(void))action;

- (NSUInteger)metadataUpdateVersionNumber;
- (void)addAfterMetadataUpdateAction:(void (^)(void))action;

// Allow external objects to synchronize with our operations.
- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void))block;
- (void)afterAsynchronousFileAccessFinishes:(void (^)(void))block;

// Added the ability to pass in a baseName which will be substitute in for the files name in to toURL. We use this for handling localized names when restoring sample documents. If you don't want the name changed when adding an item, either pass in nil for the baseName or call the alternate method that doesn't take a baseName. Pass in nil for scope to add to the default scope.
- (void)addDocumentWithScope:(OFSDocumentStoreScope *)scope inFolderNamed:(NSString *)folderName baseName:(NSString *)baseName fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
- (void)addDocumentWithScope:(OFSDocumentStoreScope *)scope inFolderNamed:(NSString *)folderName fromURL:(NSURL *)fromURL option:(OFSDocumentStoreAddOption)option completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;
- (void)moveDocumentFromURL:(NSURL *)fromURL toScope:(OFSDocumentStoreScope *)scope inFolderNamed:(NSString *)folderName completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;    // similar to -addDocumentWithScope only this performs a coordinated move

// The caller should ensure this method is invoked on a thread that won't cause deadload with any registered NSFilePresenters and that will synchronize with other document I/O (see -[UIDocument performAsynchronousFileAccessUsingBlock:])
- (void)renameFileItem:(OFSDocumentStoreFileItem *)fileItem baseName:(NSString *)baseName fileType:(NSString *)fileType completionQueue:(NSOperationQueue *)completionQueue handler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)makeGroupWithFileItems:(NSSet *)fileItems completionHandler:(void (^)(OFSDocumentStoreGroupItem *group, NSError *error))completionHandler;
- (void)moveItems:(NSSet *)fileItems toFolderNamed:(NSString *)folderName completionHandler:(void (^)(OFSDocumentStoreGroupItem *group, NSError *error))completionHandler;
#endif

// Call this method on the main thread to asynchronously move a file to the cloud. The completionHandler will be executed on the main thread sometime after this method returns.
- (void)moveItemsAtURLs:(NSSet *)urls toCloudFolderInScope:(OFSDocumentStoreScope *)ubiquitousScope withName:(NSString *)folderNameOrNil completionHandler:(void (^)(NSDictionary *movedURLs, NSDictionary *errorURLs))completionHandler;

// This does not automatically call -rescanItems
- (void)deleteItem:(OFSDocumentStoreFileItem *)fileItem completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

@property(nonatomic,readonly) NSSet *fileItems; // All the file items, no matter if they are in a group
@property(nonatomic,readonly) NSSet *topLevelItems; // The top level file items (ungrouped) and any groups

@property(nonatomic,readonly) BOOL hasFinishedInitialMetdataQuery;

@property (nonatomic, readonly) NSArray *ubiquitousScopes;
- (OFSDocumentStoreScope *)defaultUbiquitousScope;

@property (nonatomic, readonly) OFSDocumentStoreScope *localScope;

- (void)scanItemsWithCompletionHandler:(void (^)(void))completionHandler;
- (void)startDeferringScanRequests;
- (void)stopDeferringScanRequests:(void (^)(void))completionHandler;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)migrateDocumentsInScope:(OFSDocumentStoreScope *)sourceScope toScope:(OFSDocumentStoreScope *)destinationScope byMoving:(BOOL)shouldMove completionHandler:(void (^)(NSDictionary *migratedURLs, NSDictionary *errorURLs))completionHandler;
#endif

- (BOOL)hasDocuments;
- (OFSDocumentStoreFileItem *)fileItemWithURL:(NSURL *)url;
- (OFSDocumentStoreFileItem *)fileItemNamed:(NSString *)documentName;

- (OFSDocumentStoreScope *)scopeForFileURL:(NSURL *)fileURL;

- (NSString *)folderNameForFileURL:(NSURL *)fileURL; // Given a URL to a document, return the filename of the containing folder (including the "folder" extension) or nil if it is not in such a folder (top level, in the inbox, etc).

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
@property(readonly,nonatomic) NSString *documentTypeForNewFiles;
- (NSURL *)urlForNewDocumentOfType:(NSString *)documentUTI;
- (NSURL *)urlForNewDocumentWithName:(NSString *)name ofType:(NSString *)documentUTI;
- (void)createNewDocument:(void (^)(OFSDocumentStoreFileItem *createdFileItem, NSError *error))handler;

- (void)moveFileItems:(NSSet *)fileItems toCloud:(BOOL)shouldBeInCloud completionHandler:(void (^)(OFSDocumentStoreFileItem *failingItem, NSError *errorOrNil))completionHandler;
+ (BOOL)isZipUTI:(NSString *)uti;
- (void)cloneInboxItem:(NSURL *)inboxURL completionHandler:(void (^)(OFSDocumentStoreFileItem *newFileItem, NSError *errorOrNil))completionHandler;
- (BOOL)deleteInbox:(NSError **)outError;

- (void)resolveConflictForFileURL:(NSURL *)fileURL keepingFileVersions:(NSArray *)keepFileVersions completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

#endif

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
