// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSPredicate, NSSet;
@class ODSStore, ODSStore, ODSScope, ODSFolderItem;

@interface ODSFilter : NSObject

- (instancetype)initWithStore:(ODSStore *)store;
- (instancetype)initWithTopLevelOfScope:(ODSScope *)scope;
- (instancetype)initWithFileItemsInScope:(ODSScope *)scope;
- (instancetype)initWithFolderItem:(ODSFolderItem *)folder;

@property (readonly) ODSScope *scope;

@property(nonatomic, strong) NSPredicate *filterPredicate;

@property(nonatomic,readonly) NSSet *filteredItems;

@end
