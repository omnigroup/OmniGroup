// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorSlice.h>

#import <UIKit/UITableView.h>

// This doesn't implement UITableViewDataSource or UITableViewDelegate, but assumes subclasses will.

@interface OUIAbstractTableViewInspectorSlice : OUIInspectorSlice
+ (UILabel *)headerLabelWiithText:(NSString *)labelString;
+ (UIView *)sectionHeaderViewWithLabelText:(NSString *)labelString forTableView:(UITableView *)tableView;
@property(strong,readonly,nonatomic) UITableView *tableView;
@property(nonatomic,retain) NSLayoutConstraint *heightConstraint;
- (UITableViewStyle)tableViewStyle; // The style to use when creating the table view
- (void)reloadTableAndResize;
@end
