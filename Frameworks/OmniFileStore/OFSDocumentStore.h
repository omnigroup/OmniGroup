// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSOperation;

@protocol OFSDocumentStoreDelegate;
@class OFSDocumentStoreFileItem, OFSDocumentStoreGroupItem, OFSDocumentStoreScope, OFSDocumentStoreLocalDirectoryScope;

@interface OFSDocumentStore : NSObject

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// The app controller is expected to call these when its foreground status changes (giving it more control over the timing of other the rescan).
- (void)applicationDidEnterBackground;
- (void)applicationWillEnterForegroundWithCompletionHandler:(void (^)(void))completionHandler;
#endif

- initWithDelegate:(id <OFSDocumentStoreDelegate>)delegate;

@property(nonatomic,readonly) NSArray *scopes;
- (void)addScope:(OFSDocumentStoreScope *)scope;
- (void)removeScope:(OFSDocumentStoreScope *)scope;

@property(nonatomic,readonly) OFSDocumentStoreScope *defaultUsableScope;

@property(nonatomic,readonly) NSSet *mergedFileItems; // All the file items from all scopes.

- (OFSDocumentStoreScope *)scopeForFileName:(NSString *)fileName inFolder:(NSString *)folder;

- (Class)fileItemClassForURL:(NSURL *)fileURL; // Defaults to asking the delegate. The URL may not exist yet!
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (BOOL)canViewFileTypeWithIdentifier:(NSString *)fileType;
- (OFSDocumentStoreFileItem *)preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;
#endif

- (void)addAfterInitialDocumentScanAction:(void (^)(void))action;

// Allow external objects to synchronize with our operations.
- (void)performAsynchronousFileAccessUsingBlock:(void (^)(void))block;
- (void)afterAsynchronousFileAccessFinishes:(void (^)(void))block;

- (void)moveDocumentFromURL:(NSURL *)fromURL toScope:(OFSDocumentStoreScope *)scope inFolderNamed:(NSString *)folderName completionHandler:(void (^)(OFSDocumentStoreFileItem *duplicateFileItem, NSError *error))completionHandler;    // similar to -addDocumentWithScope only this performs a coordinated move

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (void)makeGroupWithFileItems:(NSSet *)fileItems completionHandler:(void (^)(OFSDocumentStoreGroupItem *group, NSError *error))completionHandler;
- (void)moveItems:(NSSet *)fileItems toFolderNamed:(NSString *)folderName completionHandler:(void (^)(OFSDocumentStoreGroupItem *group, NSError *error))completionHandler;
#endif

// Call this method on the main thread to asynchronously move a file to the cloud. The completionHandler will be executed on the main thread sometime after this method returns.
- (void)moveItemsAtURLs:(NSSet *)urls toCloudFolderInScope:(OFSDocumentStoreScope *)ubiquitousScope withName:(NSString *)folderNameOrNil completionHandler:(void (^)(NSDictionary *movedURLs, NSDictionary *errorURLs))completionHandler;

- (void)scanItemsWithCompletionHandler:(void (^)(void))completionHandler;
- (void)startDeferringScanRequests;
- (void)stopDeferringScanRequests:(void (^)(void))completionHandler;

- (BOOL)hasDocuments;
- (OFSDocumentStoreFileItem *)fileItemWithURL:(NSURL *)url;
- (OFSDocumentStoreFileItem *)fileItemNamed:(NSString *)documentName;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
@property(readonly,nonatomic) NSString *documentTypeForNewFiles;
- (void)createNewDocumentInScope:(OFSDocumentStoreScope *)scope completionHandler:(void (^)(OFSDocumentStoreFileItem *createdFileItem, NSError *error))handler;

- (void)moveFileItems:(NSSet *)fileItems toCloud:(BOOL)shouldBeInCloud completionHandler:(void (^)(OFSDocumentStoreFileItem *failingItem, NSError *errorOrNil))completionHandler;
#endif

@end
