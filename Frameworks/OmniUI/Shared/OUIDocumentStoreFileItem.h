// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIDocumentStoreItem.h>

#import <OmniUI/OUIDocumentStoreScope.h>
#import <Foundation/NSFilePresenter.h>

@class OUIDocument, OUIDocumentStore;

extern NSString * const OUIDocumentStoreFileItemFilePresenterURLBinding;
extern NSString * const OUIDocumentStoreFileItemSelectedBinding;

@interface OUIDocumentStoreFileItem : OUIDocumentStoreItem <NSFilePresenter, OUIDocumentStoreItem>

- initWithDocumentStore:(OUIDocumentStore *)documentStore fileURL:(NSURL *)fileURL date:(NSDate *)date;

@property(readonly,nonatomic) NSURL *fileURL;
@property(readonly,nonatomic) OUIDocumentStoreScope scope;

@property(readonly) NSData *emailData; // packages cannot currently be emailed, so this allows subclasses to return a different content for email
@property(readonly) NSString *emailFilename;

@property(readonly,nonatomic) NSString *editingName;
@property(readonly,nonatomic) NSString *name;
@property(copy,nonatomic) NSDate *date;

@property(assign,nonatomic) BOOL selected;
@property(assign,nonatomic) BOOL draggingSource;

- (NSComparisonResult)compare:(OUIDocumentStoreFileItem *)otherItem;

@end

