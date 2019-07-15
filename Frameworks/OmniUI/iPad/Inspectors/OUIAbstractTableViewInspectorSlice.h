// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSlice.h>

#import <UIKit/UITableView.h>

// This doesn't implement UITableViewDataSource or UITableViewDelegate, but assumes subclasses will.

@interface OUIAbstractTableViewInspectorSlice : OUIInspectorSlice
+ (NSString *)editActionButtonTitle;
+ (NSString *)doneActionButtonTitle;
+ (NSString *)tableViewLabelForLabel:(NSString *)label;
+ (void)updateHeaderButton:(UIButton *)button withTitle:(NSString *)title;
+ (UIButton *)headerActionButtonWithTitle:(NSString *)title section:(NSInteger)section;
+ (UIColor *)headerTextColor;
+ (UILabel *)headerLabelWithText:(NSString *)labelString;
+ (UIView *)sectionHeaderViewWithLabelText:(NSString *)labelString forTableView:(UITableView *)tableView;
+ (UIView *)sectionHeaderViewWithLabelText:(NSString *)labelString useDefaultActionButton:(BOOL)useDefaultActionButton target:(id)target section:(NSInteger)section forTableView:(UITableView *)tableView;
@property(strong,readonly,nonatomic) UITableView *tableView;
@property(nonatomic,retain) NSLayoutConstraint *heightConstraint;
- (UITableViewStyle)tableViewStyle; // The style to use when creating the table view
- (void)reloadTableAndResize;
@end
