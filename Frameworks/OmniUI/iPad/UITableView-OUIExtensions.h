// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UITableView.h>


typedef enum {
    OUITableViewCellAccessorySelectionType,
    OUITableViewCellImageSelectionType,
} OUITableViewCellSelectionType;

/*
 Need a better name for this, but this is used in a couple places where we have a table view where tapping a row updates a relationship and indicates selection with a checkmark in the image of the cells. We use our own images for this (since the UIKit ones are private...grrr) in this case since we *also* want the disclosure control and you can't have both types of accessories.
 
 The row is expected to still be selected in the table view.
 */
extern void OUITableViewFinishedReactingToSelection(UITableView *tableView, OUITableViewCellSelectionType type);

/*
 Used for the initial setup of images in this case
 */
extern void OUITableViewCellShowSelection(UITableViewCell *tableViewCell, OUITableViewCellSelectionType type, BOOL selected);

/*
 Assumes the table view is height stretchable. Adjusts the tableView's superview so that the contents of the table view won't be scrollable.
 */
extern void OUITableViewAdjustContainingViewToExactlyFitContents(UITableView *tableView);
