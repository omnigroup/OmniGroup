// Copyright 1999-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <AppKit/NSOutlineView.h>

#import <OmniAppKit/NSTableView-OAExtensions.h>
#import <AppKit/NSNibDeclarations.h> // For IBAction, IBOutlet

NS_ASSUME_NONNULL_BEGIN

@interface NSOutlineView (OAExtensions)

@property(nullable,nonatomic,readonly) id selectedItem;
@property(nonatomic,readonly) NSArray *selectedItems;

// Requires the parent(s) of the selected item to already be expanded. 
- (void)setSelectedItem:(nullable id)item;
- (void)setSelectedItem:(nullable id)item visibility:(OATableViewRowVisibility)visibility;
- (void)setSelectedItems:(nullable NSArray *)items;
- (void)setSelectedItems:(nullable NSArray *)items visibility:(OATableViewRowVisibility)visibility;

@property(nullable,nonatomic,readonly) id firstItem;

- (void)expandAllItemsAtLevel:(NSInteger)level;

- (void)expandItemAndChildren:(nullable id)item;
- (void)collapseItemAndChildren:(nullable id)item;

// Actions
- (IBAction)expandAll:(nullable id)sender;
- (IBAction)contractAll:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
