// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSItem.h>

extern NSString * const ODSFileItemRelativePathBinding;
extern NSString * const ODSFolderItemChildItemsBinding;

@interface ODSFolderItem : ODSItem <ODSItem>

@property(nonatomic,copy) NSString *relativePath;
@property(nonatomic,copy) NSSet *childItems;
@property(nonatomic,readonly) NSArray *childItemsSortedByName;

- (NSSet *)childrenContainingItems:(NSSet *)items;
- (ODSFolderItem *)parentFolderOfItem:(ODSItem *)item;
- (ODSItem *)itemWithRelativePath:(NSString *)relativePath;
- (ODSItem *)childItemWithFilename:(NSString *)filename;

@end
