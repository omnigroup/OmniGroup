// Copyright 2015 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDocumentStore/ODSScope.h>

@interface ODSExternalScope : ODSScope
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) void (^addDocumentBlock)(ODSFolderItem *folderItem, NSString *baseName, NSString *fileType, NSURL *fromURL, ODSStoreAddOption option, void (^completionHandler)(ODSFileItem *duplicateFileItem, NSError *error));
@property (nonatomic, copy) void (^itemsDidChangeBlock)(NSSet *items);
@property (nonatomic) BOOL allowDeletes;

- (void)addExternalFileItem:(ODSFileItem *)fileItem;

@end
