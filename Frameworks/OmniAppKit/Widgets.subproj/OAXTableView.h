// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSTableView.h>
#import <AppKit/NSNibDeclarations.h>

// This provides a context menu that allows the user to configured the list of displayed columns.

@class OATypeAheadSelectionHelper;

@interface OAXTableView : NSTableView
{
    NSMenu *columnsMenu;
}

// Configurable table columns
- (NSMenu *)columnsMenu;
    // Set by default as the context menu for the headerView, but you may also use it elsewhere (like in your menu bar).
- (NSArray *)inactiveTableColumns;
- (void)activateTableColumn:(NSTableColumn *)column;
- (void)deactivateTableColumn:(NSTableColumn *)column;
- (void)toggleTableColumn:(NSTableColumn *)column;
- (BOOL)isTableColumnActive:(NSTableColumn *)column;

@end


// These are all optional
@interface NSObject (OAXTableViewDataSource)

// Configurable columns
- (NSArray *)tableViewDefaultColumnIdentifiers:(OAXTableView *)tableView;
    // Put all allowed columns in your nib or before attaching your data source, and implement this if you want the default set to not include everything.
- (NSString *)tableView:(OAXTableView *)tableView menuStringForColumn:(NSTableColumn *)column;
    // Returns a more detailed description of the table column (possibly wider than the header cell of the column should be).
- (BOOL)tableView:(OAXTableView *)tableView shouldAllowTogglingColumn:(NSTableColumn *)column;
    // If this return NO, the table column will not be present in the configuration menu (and thus cannot be disabled).
- (BOOL)tableView:(OAXTableView *)tableView shouldAddMenuSeparatorAfterColumn:(NSTableColumn *)column;
    // Use to prettify your menu if you like.
- (void)tableView:(OAXTableView *)tableView willActivateColumn:(NSTableColumn *)column;
- (void)tableView:(OAXTableView *)tableView didActivateColumn:(NSTableColumn *)column;
- (void)tableView:(OAXTableView *)tableView willDeactivateColumn:(NSTableColumn *)column;
- (void)tableView:(OAXTableView *)tableView didDeactivateColumn:(NSTableColumn *)column;

// editing & Drag+drop additions
- (BOOL)tableViewShouldEditNextItemWhenEditingEnds:(OAXTableView *)tableView;
    // Normally tableViews like to move you to the next row when you hit return after editing a cell, but that's not always desirable.

// Context menus & tooltips
- (NSString *)tableView:(OAXTableView *)tableView tooltipForRow:(int)row column:(int)column;

@end
