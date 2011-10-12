// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OUIDocumentStore;

@protocol OUIDocumentStoreDelegate <NSObject>

// This must be thread-safe
- (Class)documentStore:(OUIDocumentStore *)store fileItemClassForURL:(NSURL *)fileURL;

// This must be thread-safe
- (BOOL)documentStore:(OUIDocumentStore *)store shouldIncludeFileItemWithFileType:(NSString *)fileType;

- (NSString *)documentStoreBaseNameForNewFiles:(OUIDocumentStore *)store;

- (void)createNewDocumentAtURL:(NSURL *)url completionHandler:(void (^)(NSURL *url, NSError *error))completionHandler;

@optional

- (NSString *)documentStoreDocumentTypeForNewFiles:(OUIDocumentStore *)store;
- (NSArray *)documentStoreEditableDocumentTypes:(OUIDocumentStore *)store;

- (void)documentStore:(OUIDocumentStore *)store scannedFileItems:(NSSet *)fileItems;

@end
