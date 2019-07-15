// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UITableView.h>
#import <OmniFoundation/OFExtent.h>
#import <OmniAppKit/OAColor.h>

@interface UITableView (OUIExtensions)
@property(readonly,nonatomic) UIEdgeInsets borderEdgeInsets; // Overridden from UIView(OUIExtensions)
@end

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
 More flexible version of OUITableViewFinishedReactingToSelection() which allows a block to specify whether a cell should be considered selected. Useful for cases where more than one cell can be selected (toggled on/off).
 */
#ifdef NS_BLOCKS_AVAILABLE
extern void OUITableViewFinishedReactingToSelectionWithPredicate(UITableView *tableView, OUITableViewCellSelectionType type, BOOL (^predicate)(NSIndexPath *indexPath));
#endif

/*
 Used for the initial setup of images in this case
 */
extern void OUITableViewCellShowSelection(UITableViewCell *tableViewCell, OUITableViewCellSelectionType type, BOOL selected);

// For cases where you want to set the cell to show no selecton/highlight color of its own and control it yourself.
typedef struct {
    OAHSV normal;
    OAHSV selected;
    OAHSV highlighted;
} OUITableViewCellBackgroundColors;
extern const OUITableViewCellBackgroundColors OUITableViewCellDefaultBackgroundColors;

extern OAColor *OUITableViewCellBackgroundColorForControlState(const OUITableViewCellBackgroundColors *colors, UIControlState state);
extern OAColor *OUITableViewCellBackgroundColorForCurrentState(const OUITableViewCellBackgroundColors *colors, UITableViewCell *cell);

// For use when embedding a table view in another scroll view. The containing scroll view should be the scrolling agent, not this table view. Assumes the table view has current contents.
extern void OUITableViewAdjustHeightToFitContents(UITableView *tableView);

/*
 Assumes the table view is height stretchable. Adjusts the tableView's superview so that the contents of the table view won't be scrollable. Assumes the table view has current contents.
 */
extern void OUITableViewAdjustContainingViewHeightToFitContents(UITableView *tableView);

