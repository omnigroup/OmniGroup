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

#import <OmniFoundation/OFObject.h>

@class OFSDocumentStore;

extern NSString * const OFSFilteredDocumentStoreTopLevelItemsBinding;

@interface OFSDocumentStoreFilter : OFObject

- (id)initWithDocumentStore:(OFSDocumentStore *)docStore;

@property(nonatomic,readonly) OFSDocumentStore *documentStore;
// only good for properties that cannot change at this point.
@property(nonatomic,retain) NSPredicate *filterPredicate;

@property(nonatomic,readonly) NSSet *filteredTopLevelItems;

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
