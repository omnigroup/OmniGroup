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

@class OFSDocumentStore, OFSDocumentStoreScope;

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
- (OFSDocumentStoreScope *)documentStore:(OFSDocumentStore *)store scopeForNewDocumentAtURL:(NSURL *)fileURL;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSString *)documentStoreDocumentTypeForNewFiles:(OFSDocumentStore *)store;
- (NSArray *)documentStoreEditableDocumentTypes:(OFSDocumentStore *)store;
#endif

- (void)documentStore:(OFSDocumentStore *)store scannedFileItems:(NSSet *)fileItems;

- (void)documentStore:(OFSDocumentStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
