// Copyright 2016 Omni Development. Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUIDocument/OUIServerAccountSetupViewController.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OUIValueCellType) {
    OUIValueCellTypePassword = 0,
    OUIValueCellTypePlaintext
};

@interface OUIServerAccountSetupViewController (Subclass)

/*!
 * @brief Override this to customize the behavior or appearance of rows in the tableView. For any cells which don't need customizing, call super's 
 * implementation.
 */
- (OUIEditableLabeledTableViewCell *)valueCellOfType:(OUIValueCellType)type forTableView:(UITableView *)tableView;

/*!
 * @brief The value text of a specific cell in the table view.
 * @discussion This tableView's cells have values and labels. Subclasses should call this to get information when the contents or behavior of one row depends on the user-entered value of another row.
 * @param section A section of the ServerAccountSections.
 * @param row The row of the section. If the section is ServerAccountCredentialsSection, then a row from the ServerAccountCredentialRows.
 */
- (nullable NSString *)textAtSection:(NSUInteger)section andRow:(NSUInteger)row;

/*!
 * After cell text is changed, this should be called to update caches. This is already 
 * handled when the user edits text directly. Code that changes the text by some other 
 * means should call this explicitly.
 */
- (void)editableLabeledValueCellTextDidChange:(OUIEditableLabeledValueCell *)cell;

@end

NS_ASSUME_NONNULL_END
