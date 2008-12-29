// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSTableView-OAColumnConfigurationExtensions.h 68913 2005-10-03 19:36:19Z kc $

#import <AppKit/NSTableView.h>
#import <AppKit/NSNibDeclarations.h>


// Allows the user to add/remove columns at will via a context menu on the header view, like in iTunes and Final Cut.

@interface NSTableView (OAColumnConfigurationExtensions)

- (NSMenu *)columnsMenu;
    // Just a convenient accessor to [[self headerView] menu]. You might want to also stick it somewhere else (like in your menu bar).
- (NSArray *)inactiveTableColumns;
- (void)activateTableColumn:(NSTableColumn *)column;
- (void)deactivateTableColumn:(NSTableColumn *)column;
- (void)toggleTableColumn:(NSTableColumn *)column;
- (BOOL)isTableColumnActive:(NSTableColumn *)column;

@end


// These are all optional
@interface NSObject (OATableViewColumnConfigurationDataSource)

- (NSArray *)tableViewDefaultColumnIdentifiers:(NSTableView *)tableView;
    // Implementation of this method is required to enable the user-column-configuration feature. The rest are optional.
    // Put all allowed columns in your nib (or set them up programatically before setting your data source). If you don't want all the allowed columns to be visible by default, return a subset of them in this method.
    // To make this feature truly useful, you'll probably also want to setAutosaveTableColumns:YES.

- (NSString *)tableView:(NSTableView *)tableView menuStringForColumn:(NSTableColumn *)column;
    // Returns a more detailed description of the table column (possibly wider than the header cell of the column should be).
- (BOOL)tableView:(NSTableView *)tableView shouldAllowTogglingColumn:(NSTableColumn *)column;

- (BOOL)tableViewAllowsColumnAutosizing:(NSTableView *)tableView;
    // Return YES if you want the "Auto Size Column" and "Auto Size All Columns" menu items in the table header's context menu
    
    // If this return NO, the table column will not be present in the configuration menu (and thus cannot be disabled).
- (BOOL)tableView:(NSTableView *)tableView shouldAddMenuSeparatorAfterColumn:(NSTableColumn *)column;
    // Use to prettify your menu if you like.
- (void)tableView:(NSTableView *)tableView willActivateColumn:(NSTableColumn *)column;
- (void)tableView:(NSTableView *)tableView didActivateColumn:(NSTableColumn *)column;
- (void)tableView:(NSTableView *)tableView willDeactivateColumn:(NSTableColumn *)column;
- (void)tableView:(NSTableView *)tableView didDeactivateColumn:(NSTableColumn *)column;

@end
