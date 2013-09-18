// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

/*
 The API in this header should only be used when implementing subclasses of ODSScope.
*/

#import <OmniDocumentStore/ODSScope.h>

extern NSString *ODSScopeCacheKeyForURL(NSURL *url);
extern NSDate *ODSModificationDateForFileURL(NSFileManager *fileManager, NSURL *fileURL);

#define kODSFileItemDefault_HasDownloadQueued (NO)
#define kODSFileItemDefault_IsDownloaded (YES)
#define kODSFileItemDefault_IsDownloading (NO)
#define kODSFileItemDefault_IsUploaded (YES)
#define kODSFileItemDefault_IsUploading (NO)
#define kODSFileItemDefault_PercentDownloaded (1.0)
#define kODSFileItemDefault_PercentUploaded (1.0)

@interface ODSScope ()

- (void)setFileItems:(NSSet *)fileItems itemMoved:(BOOL)itemMoved;

- (void)fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date willMoveToURL:(NSURL *)newURL;
- (void)fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date finishedMoveToURL:(NSURL *)newURL successfully:(BOOL)successfully;
- (void)fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date willCopyToURL:(NSURL *)newURL;
- (void)fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date finishedCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate successfully:(BOOL)successfully;

- (void)invalidateUnusedFileItems:(NSDictionary *)cacheKeyToFileItem;

// Called on the background queue. Default version does a filesystem-based move. In the case of a filesystem-based moved, the given filePresenter should be passed to the created NSFileCoordinator.
- (BOOL)performMoveFromURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL filePresenter:(id <NSFilePresenter>)filePresenter error:(NSError **)outError;

// Called on the main queue on a successful move. Default version just tells the file item.
- (void)completedMoveOfFileItem:(ODSFileItem *)fileItem toURL:(NSURL *)destinationURL;

// Subclasses must implement
- (void)updateFileItem:(ODSFileItem *)fileItem withMetadata:(id)metadata fileModificationDate:(NSDate *)fileModificationDate;
- (NSMutableSet *)copyCurrentlyUsedFileNamesInFolderAtURL:(NSURL *)folderURL ignoringFileURL:(NSURL *)fileURLToIgnore;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)isRunningOnActionQueue;
#endif

@end

#import <OmniDocumentStore/ODSFileItem.h>
@interface ODSFileItem ()

// For use by document store scope subclasses. For example, scopes might store a unique identifier for the file that helps when updating the set of active file items for move operations.
@property(nonatomic,copy) id scopeInfo;

// Redeclare the properties from <ODSItem> as writable so that scopes can update their file items.
@property(nonatomic) BOOL hasDownloadQueued;
@property(nonatomic) BOOL isDownloaded;
@property(nonatomic) BOOL isDownloading;
@property(nonatomic) BOOL isUploaded;
@property(nonatomic) BOOL isUploading;
@property(nonatomic) uint64_t downloadedSize;
@property(nonatomic) uint64_t uploadedSize;

- (void)didMoveToURL:(NSURL *)fileURL;

@end
