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

@class OFSDocumentStore, OFSDocumentStoreScope, OFSDocumentStoreFileItem;

@protocol OFSDocumentStoreDelegate <NSObject>

// This must be thread-safe
- (Class)documentStore:(OFSDocumentStore *)store fileItemClassForURL:(NSURL *)fileURL;

- (NSString *)documentStoreBaseNameForNewFiles:(OFSDocumentStore *)store;

- (void)createNewDocumentAtURL:(NSURL *)url completionHandler:(void (^)(NSURL *url, NSError *error))completionHandler;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// probably no one needs to override hte base OUIAppController version of the implementation of this method
- (BOOL)documentStore:(OFSDocumentStore *)store canViewFileTypeWithIdentifier:(NSString *)uti;
#endif
@optional

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSString *)documentStoreDocumentTypeForNewFiles:(OFSDocumentStore *)store;
- (NSArray *)documentStoreEditableDocumentTypes:(OFSDocumentStore *)store;
#endif

- (void)documentStore:(OFSDocumentStore *)store scannedFileItems:(NSSet *)fileItems;

- (void)documentStore:(OFSDocumentStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;
- (void)documentStore:(OFSDocumentStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate didCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate;

- (void)documentStore:(OFSDocumentStore *)store fileItem:(OFSDocumentStoreFileItem *)fileItem didGainVersion:(NSFileVersion *)fileVersion;

#if OFS_AUTOMATICALLY_DOWNLOAD_SMALL_UBIQUITOUS_FILE_ITEMS
- (OFSDocumentStoreFileItem *)documentStore:(OFSDocumentStore *)store preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;
#endif

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
