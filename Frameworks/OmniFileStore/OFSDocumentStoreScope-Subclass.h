// Copyright 2010-2012 The Omni Group. All rights reserved.
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

#define kOFSDocumentStoreFileItemDefault_HasUnresolvedConflicts (NO)
#define kOFSDocumentStoreFileItemDefault_IsDownloaded (YES)
#define kOFSDocumentStoreFileItemDefault_IsDownloading (NO)
#define kOFSDocumentStoreFileItemDefault_IsUploaded (YES)
#define kOFSDocumentStoreFileItemDefault_IsUploading (NO)
#define kOFSDocumentStoreFileItemDefault_PercentDownloaded (100)
#define kOFSDocumentStoreFileItemDefault_PercentUploaded (100)

@interface OFSDocumentStoreScope ()

@property(nonatomic,copy) NSSet *fileItems; // Redeclare this as writable for subclasses to fill out

- (void)fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;
- (void)fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate;

- (void)fileItemFinishedDownloading:(OFSDocumentStoreFileItem *)fileItem;

- (void)invalidateUnusedFileItems:(NSDictionary *)cacheKeyToFileItem;

// Subclasses must implement
- (void)updateFileItem:(OFSDocumentStoreFileItem *)fileItem withMetadata:(id)metadata modificationDate:(NSDate *)modificationDate;
- (NSMutableDictionary *)copyCurrentlyUsedFileNamesByFolderName; // NSMutableDictionary of folder name -> set of names, "" for the top-level folder
- (NSMutableSet *)copyCurrentlyUsedFileNamesInFolderNamed:(NSString *)folderName ignoringFileURL:(NSURL *)fileURLToIgnore;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)isRunningOnActionQueue;
#endif

@end
