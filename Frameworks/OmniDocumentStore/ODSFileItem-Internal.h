// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDocumentStore/ODSFileItem.h>

@interface ODSFileItem (/*Internal*/)
@end

@interface ODSFileItemMotion : NSObject

- initWithFileItem:(ODSFileItem *)fileItem destinationFolderURL:(NSURL *)destinationFolderURL;

@property(nonatomic,readonly) ODSFileItem *fileItem;
@property(nonatomic,readonly) NSURL *sourceFileURL;
@property(nonatomic,readonly) NSDate *sourceModificationDate;
@property(nonatomic,readonly) NSURL *destinationFileURL;

@end

@interface ODSFileItemDeletion : NSObject
- initWithFileItem:(ODSFileItem *)fileItem;
@property(nonatomic,readonly) ODSFileItem *fileItem;
@property(nonatomic,readonly) NSURL *sourceFileURL;
@end
