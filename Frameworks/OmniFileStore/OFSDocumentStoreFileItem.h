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

#import <OmniFileStore/OFSDocumentStoreItem.h>

#import <OmniFileStore/OFSDocumentStoreScope.h>
#import <Foundation/NSFilePresenter.h>

@class OUIDocument, OFSDocumentStore;

extern NSString * const OFSDocumentStoreFileItemFilePresenterURLBinding;
extern NSString * const OFSDocumentStoreFileItemSelectedBinding;

extern NSString * const OFSDocumentStoreFileItemContentsChangedNotification;
extern NSString * const OFSDocumentStoreFileItemFinishedDownloadingNotification;
extern NSString * const OFSDocumentStoreFileItemInfoKey;

@interface OFSDocumentStoreFileItem : OFSDocumentStoreItem <NSFilePresenter, OFSDocumentStoreItem, NSCopying>

- initWithDocumentStore:(OFSDocumentStore *)documentStore fileURL:(NSURL *)fileURL date:(NSDate *)date;

@property(readonly,nonatomic) NSURL *fileURL;
@property(readonly,copy,nonatomic) NSString *fileType;
@property(readonly,nonatomic) OFSDocumentStoreScope *scope;

@property(readonly) NSData *emailData; // packages cannot currently be emailed, so this allows subclasses to return a different content for email
@property(readonly) NSString *emailFilename;

@property(readonly,nonatomic) NSString *editingName;
@property(readonly,nonatomic) NSString *name;
@property(copy,nonatomic) NSDate *date;

@property(nonatomic,readonly,getter=isBeingDeleted) BOOL beingDeleted; // YES when this file item has received -accommodatePresentedItemDeletionWithCompletionHandler:.

@property(assign,nonatomic) BOOL selected;
@property(assign,nonatomic) BOOL draggingSource;

- (NSComparisonResult)compare:(OFSDocumentStoreFileItem *)otherItem;

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
