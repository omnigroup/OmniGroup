// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UITableView-OUIExtensions.h>

#import <OmniUI/OUIImages.h>
#import <OmniQuartz/OQColor.h>

RCS_ID("$Id$");

@implementation UITableView (OUIExtensions)

- (UIEdgeInsets)borderEdgeInsets;
{
    if (self.style == UITableViewStyleGrouped)
        // eye-ball the built in padding for the grouped look; to match our other controls.
        return UIEdgeInsetsMake(10/*top*/, 9/*left*/, 11/*bottom*/, 8/*right*/);
    
    return UIEdgeInsetsZero; // all the way to the edges
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
    .normal = ((OSHSV){0.0/360.0, 0.0, 1.0, 1.0}),
    .selected = ((OSHSV){216.0/360.0, 0.12, 1.0, 1.0}),
    .highlighted = ((OSHSV){216.0/360.0, 0.18, 1.0, 1.0})
};

// For cases where you want to set the cell to show no selecton/highlight color of its own and control it yourself.
OQColor *OUITableViewCellBackgroundColorForControlState(const OUITableViewCellBackgroundColors *colors, UIControlState state)
{
    switch (state) {
        case UIControlStateHighlighted:
            return [OQColor colorWithCalibratedHue:colors->highlighted.h saturation:colors->highlighted.s brightness:colors->highlighted.v alpha:colors->highlighted.a];
        case UIControlStateSelected:
            return [OQColor colorWithCalibratedHue:colors->selected.h saturation:colors->selected.s brightness:colors->selected.v alpha:colors->selected.a];
        default:
            OBASSERT_NOT_REACHED("Unknown control state");
            // fall through
        case UIControlStateNormal:
            return [OQColor colorWithCalibratedHue:colors->normal.h saturation:colors->normal.s brightness:colors->normal.v alpha:colors->normal.a];
    }
}

OQColor *OUITableViewCellBackgroundColorForCurrentState(const OUITableViewCellBackgroundColors *colors, UITableViewCell *cell)
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
    OBPRECONDITION(tableView);
    OBPRECONDITION(tableView.autoresizingMask == 0);
    
    CGSize contentSize = tableView.contentSize;
    OBASSERT(contentSize.height > 0); // No rows?
    
    CGRect frame = tableView.frame;
    
    // Seems to be a UIKit bug that tableView.contentSize is 1 pixel too high. This little hack will cover up the extra pixel of white that shows just under the last cell. This is only noticeable when the cell is selected (non-white). 
    frame.size.height = contentSize.height - 1;
    
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
