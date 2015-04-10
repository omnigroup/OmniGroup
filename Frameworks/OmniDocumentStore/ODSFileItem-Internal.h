// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSScope.h>

@interface ODSFileItemMotion ()
- initWithFileItem:(ODSFileItem *)fileItem destinationFolderURL:(NSURL *)destinationFolderURL;
@end

@interface ODSFileItemDeletion : NSObject
- initWithFileItem:(ODSFileItem *)fileItem;
@property(nonatomic,readonly) ODSFileItem *fileItem;
@property(nonatomic,readonly) NSURL *sourceFileURL;
@end
