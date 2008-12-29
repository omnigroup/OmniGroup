// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAExtendedTableView.h 68913 2005-10-03 19:36:19Z kc $

#import <AppKit/NSTableView.h>

@interface OAExtendedTableView : NSTableView
{
    NSRange _dragColumnRange;
}

// API
- (NSRange)columnRangeForDragImage;
- (void)setColumnRangeForDragImage:(NSRange)newRange;
    // If you have a table similar to a Finder list view, where one or more columns contain a representation of the object associated with each row, and additional columns contain supplemental information (like sizes and mod dates), use these methods to specify which columns should be part of the dragged image. (Because you want to show the user that you're dragging a file, not a file and a date and a byte count.)
    
@end

@interface NSObject (OAExtendedTableViewDataSource)
- (BOOL)tableView:(OAExtendedTableView *)tv shouldShowDragImageForRow:(int)row;
    // If you'd like to support dragging of multiple-row selections, but want to control which of the selected rows is valid for dragging, implement this method in addition to -tableView:writeRows:toPasteboard:. If none of the selected rows are valid, return NO in -tableView:writeRows:toPasteboard:. If some of them are, write the valid ones to the pasteboard and return YES in -tableView:writeRows:toPasteboard:, and implement this method to return NO for the invalid ones. This prevents them from being drawn as part of the drag image, so that the items the user appears to be dragging are in sync with the items she's actually dragging. 
@end

@interface NSObject (DataCellExtraTableMethods)
- (void)modifyFieldEditor:(NSText *)fieldEditor forTableView:(OAExtendedTableView *)tableView column:(int)columnIndex row:(int)rowIndex;
@end
