// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSItem.h>

@interface ODSItem (/*Internal*/)

- (void)_invalidate;
- (void)_setParentFolder:(ODSFolderItem *)parentFolder;
- (void)_addMotions:(NSMutableArray *)motions toParentFolderURL:(NSURL *)destinationFolderURL isTopLevel:(BOOL)isTopLevel usedFolderNames:(NSMutableSet *)usedFolderNames ignoringFileItems:(NSSet *)ignoredFileItems;

@end
