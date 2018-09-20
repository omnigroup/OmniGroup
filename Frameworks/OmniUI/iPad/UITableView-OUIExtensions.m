// Copyright 2010-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UITableView-OUIExtensions.h>

#import <OmniUI/OUIImages.h>
#import <OmniAppKit/OAColor.h>

RCS_ID("$Id$");

@implementation UITableView (OUIExtensions)

- (UIEdgeInsets)borderEdgeInsets;
{
    UIEdgeInsets insets = UIEdgeInsetsZero;
    UIEdgeInsets separatorInsets = self.separatorInset;
    insets.left = self.separatorInset.left;
    insets.right = (separatorInsets.right > 0.0f) ? separatorInsets.right : separatorInsets.left;
    return insets;
}

@end

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
    NSIndexPath *selectedIndexPath = [tableView indexPathForSelectedRow];
    if (selectedIndexPath) {
        // Clear the selection
        [tableView deselectRowAtIndexPath:selectedIndexPath animated:YES];
    }
    
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
                cell.accessibilityTraits = UIAccessibilityTraitSelected;
            } else {
                cell.imageView.image = OUITableViewItemSelectionImage(UIControlStateNormal);
                cell.imageView.highlightedImage = nil;
                cell.accessibilityTraits = UIAccessibilityTraitNone;
            }
            break;
        case OUITableViewCellAccessorySelectionType:
            cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            cell.accessibilityTraits = selected ? UIAccessibilityTraitSelected : UIAccessibilityTraitNone;
            break;
        default:
            OBASSERT_NOT_REACHED("Unknown selection display type");
            break;
    }
}

const OUITableViewCellBackgroundColors OUITableViewCellDefaultBackgroundColors = {
    .normal = ((OAHSV){0.0/360.0, 0.0, 1.0, 1.0}),
    .selected = ((OAHSV){216.0/360.0, 0.12, 1.0, 1.0}),
    .highlighted = ((OAHSV){216.0/360.0, 0.18, 1.0, 1.0})
};

// For cases where you want to set the cell to show no selecton/highlight color of its own and control it yourself.
OAColor *OUITableViewCellBackgroundColorForControlState(const OUITableViewCellBackgroundColors *colors, UIControlState state)
{
    switch (state) {
        case UIControlStateHighlighted:
            return [OAColor colorWithHue:colors->highlighted.h saturation:colors->highlighted.s brightness:colors->highlighted.v alpha:colors->highlighted.a];
        case UIControlStateSelected:
            return [OAColor colorWithHue:colors->selected.h saturation:colors->selected.s brightness:colors->selected.v alpha:colors->selected.a];
        default:
            OBASSERT_NOT_REACHED("Unknown control state");
            // fall through
        case UIControlStateNormal:
            return [OAColor colorWithHue:colors->normal.h saturation:colors->normal.s brightness:colors->normal.v alpha:colors->normal.a];
    }
}

OAColor *OUITableViewCellBackgroundColorForCurrentState(const OUITableViewCellBackgroundColors *colors, UITableViewCell *cell)
{
    // table view cells aren't controls... our use for this doesn't want both flags set
    UIControlState controlState = UIControlStateNormal;
    if (cell.highlighted)
        controlState = UIControlStateHighlighted;
    else if (cell.selected)
        controlState = UIControlStateSelected;

    return OUITableViewCellBackgroundColorForControlState(colors, controlState);
}

// Assumes the table view has current contents
void OUITableViewAdjustHeightToFitContents(UITableView *tableView)
{
    if (!tableView) {
        return;
    }
    OBPRECONDITION(tableView);
    OBPRECONDITION(tableView.autoresizingMask == 0);
    
    CGSize contentSize = tableView.contentSize;
    
    UIEdgeInsets contentInsets = tableView.contentInset;
    
    CGRect frame = tableView.frame;
    
    frame.size.height = contentSize.height + contentInsets.top + contentInsets.bottom;
    
    tableView.frame = frame;
    tableView.scrollEnabled = NO;
}

void OUITableViewAdjustContainingViewHeightToFitContents(UITableView *tableView)
{
    OBPRECONDITION(tableView);
    
    UIView *container = tableView.superview;
    if (!container) {
        // Bare table view
        OUITableViewAdjustHeightToFitContents(tableView);
        return;
    }
    OBASSERT(tableView.autoresizingMask == UIViewAutoresizingFlexibleHeight);

    CGSize tableViewContentSize = tableView.contentSize;
    OBASSERT(tableViewContentSize.height > 0); // No rows?
    
    CGRect tableViewFrame = tableView.frame;
    CGFloat delta = tableViewContentSize.height - CGRectGetHeight(tableViewFrame); // assuming no scaling here
    
    CGRect frame = container.frame;
    frame.size.height += delta;
    
    container.frame = frame;
    
    tableView.scrollEnabled = NO;
}
