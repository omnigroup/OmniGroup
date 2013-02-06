// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSDocumentStoreFileItem.h>

@interface OFSDocumentStoreFileItem (/*Internal*/)

- (void)_invalidateAfterWriter;

// Redeclare the properties from <OFSDocumentStoreItem> as writable so that scopes can update their file items.
@property(nonatomic) BOOL hasUnresolvedConflicts;
@property(nonatomic) BOOL isDownloaded;
@property(nonatomic) BOOL isDownloading;
@property(nonatomic) BOOL isUploaded;
@property(nonatomic) BOOL isUploading;
@property(nonatomic) double percentDownloaded;
@property(nonatomic) double percentUploaded;

@end
