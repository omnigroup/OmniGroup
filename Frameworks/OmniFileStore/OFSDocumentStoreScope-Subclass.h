// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

/*
 The API in this header should only be used when implementing subclasses of OFSDocumentStoreScope.
*/

#import <OmniFileStore/OFSDocumentStoreScope.h>

extern NSString *OFSDocumentStoreScopeCacheKeyForURL(NSURL *url);
extern NSDate *OFSDocumentStoreScopeModificationDateForFileURL(NSFileManager *fileManager, NSURL *fileURL);

#define kOFSDocumentStoreFileItemDefault_HasDownloadQueued (NO)
#define kOFSDocumentStoreFileItemDefault_IsDownloaded (YES)
#define kOFSDocumentStoreFileItemDefault_IsDownloading (NO)
#define kOFSDocumentStoreFileItemDefault_IsUploaded (YES)
#define kOFSDocumentStoreFileItemDefault_IsUploading (NO)
#define kOFSDocumentStoreFileItemDefault_PercentDownloaded (1.0)
#define kOFSDocumentStoreFileItemDefault_PercentUploaded (1.0)

@interface OFSDocumentStoreScope ()

@property(nonatomic,copy) NSSet *fileItems; // Redeclare this as writable for subclasses to fill out

- (void)fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;
- (void)fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate;

- (void)invalidateUnusedFileItems:(NSDictionary *)cacheKeyToFileItem;

// Called on the background queue. Default version does a filesystem-based move. In the case of a filesystem-based moved, the given filePresenter should be passed to the created NSFileCoordinator.
- (void)performMoveFromURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL filePresenter:(id <NSFilePresenter>)filePresenter completionHandler:(void (^)(NSURL *destinationURL, NSError *errorOrNil))completionHandler;

// Called on the main queue on a successful move. Default version just tells the file item.
- (void)completedMoveOfFileItem:(OFSDocumentStoreFileItem *)fileItem toURL:(NSURL *)destinationURL;

// Subclasses must implement
- (void)updateFileItem:(OFSDocumentStoreFileItem *)fileItem withMetadata:(id)metadata fileModificationDate:(NSDate *)fileModificationDate;
- (NSMutableSet *)copyCurrentlyUsedFileNamesInFolderAtURL:(NSURL *)folderURL ignoringFileURL:(NSURL *)fileURLToIgnore;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)isRunningOnActionQueue;
#endif

@end

#import <OmniFileStore/OFSDocumentStoreFileItem.h>
@interface OFSDocumentStoreFileItem ()

// For use by document store scope subclasses. For example, scopes might store a unique identifier for the file that helps when updating the set of active file items for move operations.
@property(nonatomic,copy) id scopeInfo;

// Redeclare the properties from <OFSDocumentStoreItem> as writable so that scopes can update their file items.
@property(nonatomic) BOOL hasDownloadQueued;
@property(nonatomic) BOOL isDownloaded;
@property(nonatomic) BOOL isDownloading;
@property(nonatomic) BOOL isUploaded;
@property(nonatomic) BOOL isUploading;
@property(nonatomic) double percentDownloaded;
@property(nonatomic) double percentUploaded;

- (void)didMoveToURL:(NSURL *)fileURL;

@end
