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

#import <OmniFileStore/OFSDocumentStoreScope.h>

@class OFSDocumentStore;

@protocol OFSDocumentStoreDelegate <NSObject>

// This must be thread-safe
- (Class)documentStore:(OFSDocumentStore *)store fileItemClassForURL:(NSURL *)fileURL;

// This must be thread-safe
- (BOOL)documentStore:(OFSDocumentStore *)store shouldIncludeFileItemWithFileType:(NSString *)fileType;

- (NSString *)documentStoreBaseNameForNewFiles:(OFSDocumentStore *)store;

- (void)createNewDocumentAtURL:(NSURL *)url completionHandler:(void (^)(NSURL *url, NSError *error))completionHandler;

@optional

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSString *)documentStoreDocumentTypeForNewFiles:(OFSDocumentStore *)store;
- (OFSDocumentStoreScope)documentStore:(OFSDocumentStore *)store scopeForNewDocumentAtURL:(NSURL *)fileURL;

- (NSArray *)documentStoreEditableDocumentTypes:(OFSDocumentStore *)store;
#endif

- (void)documentStore:(OFSDocumentStore *)store scannedFileItems:(NSSet *)fileItems;

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
