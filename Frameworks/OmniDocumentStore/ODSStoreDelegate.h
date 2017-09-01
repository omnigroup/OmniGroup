// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class ODSStore, ODSScope, ODSFileItem, ODSFileItemEdit;

@protocol ODSStoreDelegate <NSObject>

// This must be thread-safe
- (Class)documentStore:(ODSStore *)store fileItemClassForURL:(NSURL *)fileURL;

- (NSString *)documentStoreBaseNameForNewFiles:(ODSStore *)store;
- (NSString *)documentStoreBaseNameForNewTemplateFiles:(ODSStore *)store;

// probably no one needs to override hte base OUIAppController version of the implementation of this method
- (BOOL)documentStore:(ODSStore *)store canViewFileTypeWithIdentifier:(NSString *)uti;

@optional

- (NSString *)documentStoreBaseNameForNewOtherFiles:(ODSStore *)store;

- (NSString *)documentStoreDocumentTypeForNewFiles:(ODSStore *)store;
- (NSString *)documentStoreDocumentTypeForNewTemplateFiles:(ODSStore *)store;
- (NSString *)documentStoreDocumentTypeForNewOtherFiles:(ODSStore *)store;

- (NSArray *)documentStoreEditableDocumentTypes:(ODSStore *)store;

- (void)documentStore:(ODSStore *)store addedFileItems:(NSSet *)addedFileItems;

- (void)documentStore:(ODSStore *)store fileItem:(ODSFileItem *)fileItem willMoveToURL:(NSURL *)newURL;
- (void)documentStore:(ODSStore *)store fileItemEdit:(ODSFileItemEdit *)fileItemEdit willCopyToURL:(NSURL *)newURL;
- (void)documentStore:(ODSStore *)store fileItemEdit:(ODSFileItemEdit *)fileItemEdit finishedCopyToURL:(NSURL *)destinationURL withFileItemEdit:(ODSFileItemEdit *)destinationFileItemEditOrNil;
- (void)documentStore:(ODSStore *)store willRemoveFileItemAtURL:(NSURL *)destinationURL;

- (ODSFileItem *)documentStore:(ODSStore *)store preferredFileItemForNextAutomaticDownload:(NSSet *)fileItems;

@end
