// Copyright 2010-2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class ODSStore, ODSScope, ODSFileItem;

@protocol ODSStoreDelegate <NSObject>

// This must be thread-safe
- (Class)documentStore:(ODSStore *)store fileItemClassForURL:(NSURL *)fileURL;

- (NSString *)documentStoreBaseNameForNewFiles:(ODSStore *)store;
- (NSString *)documentStoreBaseNameForNewTemplateFiles:(ODSStore *)store;

- (void)createdNewDocument:(ODSFileItem *)fileItem templateURL:(NSURL *)templateURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;

// probably no one needs to override hte base OUIAppController version of the implementation of this method
- (BOOL)documentStore:(ODSStore *)store canViewFileTypeWithIdentifier:(NSString *)uti;

@optional

- (void)createNewDocumentAtURL:(NSURL *)url templateURL:(NSURL *)templateURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;  // Deprecated - use the createdNewDocument:templateURL:completionHandler: version instead
- (void)createNewDocumentAtURL:(NSURL *)url completionHandler:(void (^)(NSError *errorOrNil))completionHandler; // Deprecated - use the createdNewDocument:templateURL:completionHandler: version instead

- (NSString *)documentStoreDocumentTypeForNewFiles:(ODSStore *)store;
- (NSString *)documentStoreDocumentTypeForNewTemplateFiles:(ODSStore *)store;
- (NSArray *)documentStoreEditableDocumentTypes:(ODSStore *)store;

- (void)documentStore:(ODSStore *)store addedFileItems:(NSSet *)addedFileItems;

- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date willMoveToURL:(NSURL *)newURL;
- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date finishedMoveToURL:(NSURL *)newURL successfully:(BOOL)successfully;
- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate willCopyToURL:(NSURL *)newURL;
- (void)documentStore:(ODSStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate finishedCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate successfully:(BOOL)successfully;

- (ODSFileItem *)documentStore:(ODSStore *)store preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;

@end
