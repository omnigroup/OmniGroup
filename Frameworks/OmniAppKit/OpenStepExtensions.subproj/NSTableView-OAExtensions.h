// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSTableView.h>
#import <AppKit/NSNibDeclarations.h>

typedef NS_ENUM(NSInteger, OATableViewRowVisibility) {
    OATableViewRowVisibilityLeaveUnchanged,
    OATableViewRowVisibilityScrollToVisible,
    OATableViewRowVisibilityScrollToMiddleIfNotVisible
};

#import <OmniAppKit/OAFindControllerTargetProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTableView (OAExtensions) <OAFindControllerTarget>

- (NSRect)rectOfSelectedRows;
    // Returns the rectangle enclosing all of the selected rows or NSZeroRect if there are no selected items
- (void)scrollSelectedRowsToVisibility:(OATableViewRowVisibility)visibility;
    // Calls -rectOfSelectedRows and then scrolls it to visible.

- (nullable NSFont *)font;
- (void)setFont:(NSFont *)font;

// Actions
- (IBAction)copy:(nullable id)sender; // If you support dragging out, you'll automatically support copy.
- (IBAction)delete:(nullable id)sender; // Data source must support -tableView:deleteRowsAtIndexes:.
- (IBAction)cut:(nullable id)sender; // cut == copy + delete
- (IBAction)paste:(nullable id)sender; // Data source must support -tableView:addItemsFromPasteboard:.
- (IBAction)duplicate:(nullable id)sender; // duplicate == copy + paste (without using the general pasteboard)

@end

@protocol OAExtendedTableViewDataSource <NSTableViewDataSource>

@optional

// Searching
- (BOOL)tableView:(NSTableView *)tableView itemAtRow:(NSInteger)row matchesPattern:(id <OAFindPattern>)pattern;
    // Implement this if you want find support.

// Content editing actions
- (BOOL)tableView:(NSTableView *)tableView addItemsFromPasteboard:(NSPasteboard *)pasteboard;
    // Called by paste & duplicate. Return NO to disallow, YES if successful.
- (void)tableView:(NSTableView *)tableView deleteRowsAtIndexes:(NSIndexSet *)rowIndexes;
    // Called by -delete:, keyboard delete keys, and drag-to-trash. 'rows' is an array of NSNumbers containing row indices.

// Drag image control
- (NSArray *)tableViewColumnIdentifiersForDragImage:(NSTableView *)tableView;
    // If you have a table similar to a Finder list view, where one or more columns contain a representation of the object associated with each row, and additional columns contain supplemental information (like sizes and mod dates), implement this method to specify which column(s) should be part of the dragged image. (Because you want to show the user that you're dragging a file, not a file and a date and a byte count.)
- (BOOL)tableView:(NSTableView *)tableView shouldShowDragImageForRow:(NSInteger)row;
    // If you'd like to support dragging of multiple-row selections, but want to control which of the selected rows is valid for dragging, implement this method in addition to -tableView:writeRows:toPasteboard:. If none of the selected rows are valid, return NO in -tableView:writeRows:toPasteboard:. If some of them are, write the valid ones to the pasteboard and return YES in -tableView:writeRows:toPasteboard:, and implement this method to return NO for the invalid ones. This prevents them from being drawn as part of the drag image, so that the items the user appears to be dragging are in sync with the items she's actually dragging.

// Additional editing actions
- (void)tableView:(NSTableView *)tableView insertNewline:(id)sender;
    // You may want to edit the currently selected item or insert a new item when Return is pressed.
- (BOOL)tableViewShouldEditNextItemWhenEditingEnds:(NSTableView *)tableView;
    // Normally tables like to move you to the next row when you hit return after editing a cell, but that's not always desirable.

// Context menus
- (NSMenu *)tableView:(NSTableView *)tableView contextMenuForRow:(NSInteger)row column:(NSInteger)column;

@end

NS_ASSUME_NONNULL_END
