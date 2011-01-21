// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UITableView-OUIExtensions.h>

#import <OmniUI/OUIImages.h>

RCS_ID("$Id$");

void OUITableViewFinishedReactingToSelection(UITableView *tableView, OUITableViewCellSelectionType type)
{
    NSIndexPath *indexPath = [tableView indexPathForSelectedRow];
    OBASSERT(indexPath);
    
    // Clear the selection
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // Update the checkmarks on all the visible cells
    UITableViewCell *selectedCell = [tableView cellForRowAtIndexPath:indexPath];
    OBASSERT(selectedCell); // We are presuming the user just touched this row; so it really should have been visible.
    
    for (UITableViewCell *cell in [tableView visibleCells])
        OUITableViewCellShowSelection(cell, type, cell == selectedCell);
}

void OUITableViewCellShowSelection(UITableViewCell *cell, OUITableViewCellSelectionType type, BOOL selected)
{
    switch (type) {
        case OUITableViewCellImageSelectionType:
            if (selected) {
                cell.imageView.image = OUITableViewItemSelectionImage(UIControlStateSelected);
                cell.imageView.highlightedImage = OUITableViewItemSelectionImage(UIControlStateHighlighted);
            } else {
                cell.imageView.image = OUITableViewItemSelectionImage(UIControlStateNormal);
                cell.imageView.highlightedImage = nil;
            }
            break;
        case OUITableViewCellAccessorySelectionType:
            cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            break;
        default:
            OBASSERT_NOT_REACHED("Unknown selection display type");
            break;
    }
}

void OUITableViewAdjustContainingViewToExactlyFitContents(UITableView *tableView)
{
    // Make sure it has the correct data first.
    [tableView reloadData];

    CGSize tableViewContentSize = tableView.contentSize;
    CGRect tableViewFrame = tableView.frame;
    CGFloat delta = tableViewContentSize.height - CGRectGetHeight(tableViewFrame); // assuming no scaling here
    
    UIView *container = tableView.superview;
    
    CGRect frame = container.frame;
    frame.size.height += delta;
    container.frame = frame;
    
    tableView.scrollEnabled = NO;
}

