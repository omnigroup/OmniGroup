// Copyright 2010-2011 The Omni Group.  All rights reserved.
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

#ifdef NS_BLOCKS_AVAILABLE
void OUITableViewFinishedReactingToSelectionWithPredicate(UITableView *tableView, OUITableViewCellSelectionType type, BOOL (^predicate)(NSIndexPath *indexPath))
{
    NSIndexPath *indexPath = [tableView indexPathForSelectedRow];
    OBASSERT(indexPath);
    
    // Clear the selection
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // Update the checkmarks on all the visible cells.    
    for (UITableViewCell *cell in [tableView visibleCells]) {
        NSIndexPath *indexPath = [tableView indexPathForCell:cell];
        OBASSERT(indexPath);
        OUITableViewCellShowSelection(cell, type, predicate(indexPath));
    }
}
#endif


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

BOOL OUITableViewAdjustContainingViewToExactlyFitContents(UITableView *tableView, CGFloat maximumHeight)
{
    // Make sure it has the correct data first.
    [tableView reloadData];

    CGSize tableViewContentSize = tableView.contentSize;
    CGRect tableViewFrame = tableView.frame;
    CGFloat delta = tableViewContentSize.height - CGRectGetHeight(tableViewFrame); // assuming no scaling here
    
    UIView *container = tableView.superview;
    if (!container)
        container = tableView; // Bare tableview.
    
    CGRect frame = container.frame;
    frame.size.height += delta;
    
    BOOL fits = YES;
    if (maximumHeight > 0 && frame.size.height > maximumHeight) {
        frame.size.height = maximumHeight;
        fits = NO;
    }
    
    container.frame = frame;
    
    tableView.scrollEnabled = !fits;
    return fits;
}
