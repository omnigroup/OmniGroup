// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSDocumentStoreItem.h>

#import <OmniFileStore/OFSDocumentStoreScope.h>
#import <Foundation/NSFilePresenter.h>

@class OFSDocumentStoreScope;

extern NSString * const OFSDocumentStoreFileItemFileURLBinding;
extern NSString * const OFSDocumentStoreFileItemSelectedBinding;
extern NSString * const OFSDocumentStoreFileItemDownloadRequestedBinding;

extern NSString * const OFSDocumentStoreFileItemContentsChangedNotification;
extern NSString * const OFSDocumentStoreFileItemFinishedDownloadingNotification;
extern NSString * const OFSDocumentStoreFileItemInfoKey;

@interface OFSDocumentStoreFileItem : OFSDocumentStoreItem <NSFilePresenter, OFSDocumentStoreItem>

+ (NSString *)displayNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
+ (NSString *)editingNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;
+ (NSString *)exportingNameForFileURL:(NSURL *)fileURL fileType:(NSString *)fileType;

- initWithScope:(OFSDocumentStoreScope *)scope fileURL:(NSURL *)fileURL date:(NSDate *)date;

@property(readonly,nonatomic) NSURL *fileURL;
@property(readonly,copy,nonatomic) NSString *fileType;

@property(readonly) NSData *emailData; // packages cannot currently be emailed, so this allows subclasses to return a different content for email
@property(readonly) NSString *emailFilename;

@property(readonly,nonatomic) NSString *editingName;
@property(readonly,nonatomic) NSString *name;
@property(readonly,nonatomic) NSString *exportingName;
@property(copy,nonatomic) NSDate *date;

- (BOOL)requestDownload:(NSError **)outError;
@property(readonly,assign,nonatomic) BOOL downloadRequested;

@property(nonatomic,readonly,getter=isBeingDeleted) BOOL beingDeleted; // YES when this file item has received -accommodatePresentedItemDeletionWithCompletionHandler:.

@property(assign,nonatomic) BOOL selected;
@property(assign,nonatomic) BOOL draggingSource;

- (NSComparisonResult)compare:(OFSDocumentStoreFileItem *)otherItem;

@end
