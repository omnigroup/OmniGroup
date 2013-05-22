// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSDocumentStoreScope.h>

@interface OFSDocumentStoreScope ()

- (NSMutableSet *)_copyCurrentlyUsedFileNamesInFolderAtURL:(NSURL *)folderURL;

- (void)_fileItemContentsChanged:(OFSDocumentStoreFileItem *)fileItem;

@end

NSString *OFSDocumentStoreScopeFindAvailableName(NSSet *usedFileNames, NSString *baseName, NSString *extension, NSUInteger *ioCounter) OB_HIDDEN;
