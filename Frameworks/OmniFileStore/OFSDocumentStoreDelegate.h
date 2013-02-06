// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OFSDocumentStore, OFSDocumentStoreScope, OFSDocumentStoreFileItem;

@protocol OFSDocumentStoreDelegate <NSObject>

// This must be thread-safe
- (Class)documentStore:(OFSDocumentStore *)store fileItemClassForURL:(NSURL *)fileURL;

- (NSString *)documentStoreBaseNameForNewFiles:(OFSDocumentStore *)store;

- (void)createNewDocumentAtURL:(NSURL *)url completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// probably no one needs to override hte base OUIAppController version of the implementation of this method
- (BOOL)documentStore:(OFSDocumentStore *)store canViewFileTypeWithIdentifier:(NSString *)uti;
#endif
@optional

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSString *)documentStoreDocumentTypeForNewFiles:(OFSDocumentStore *)store;
- (NSArray *)documentStoreEditableDocumentTypes:(OFSDocumentStore *)store;
#endif

// TODO: Move this to the scope?
- (void)documentStore:(OFSDocumentStore *)store addedFileItems:(NSSet *)addedFileItems;

- (void)documentStore:(OFSDocumentStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)date didMoveToURL:(NSURL *)newURL;
- (void)documentStore:(OFSDocumentStore *)store fileWithURL:(NSURL *)oldURL andDate:(NSDate *)oldDate didCopyToURL:(NSURL *)newURL andDate:(NSDate *)newDate;

- (OFSDocumentStoreFileItem *)documentStore:(OFSDocumentStore *)store preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;

@end
