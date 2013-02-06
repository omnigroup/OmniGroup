// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSDocumentStoreItem.h>

extern NSString * const OFSDocumentStoreGroupItemFileItemsBinding;

@interface OFSDocumentStoreGroupItem : OFSDocumentStoreItem <OFSDocumentStoreItem>

@property(nonatomic,copy) NSString *name;
@property(nonatomic,readonly) NSDate *date; // derived from members

@property(nonatomic,copy) NSSet *fileItems;

@end
