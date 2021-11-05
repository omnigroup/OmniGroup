// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUILabeledValueCell.h>

NS_ASSUME_NONNULL_BEGIN

@protocol OUIEditableLabeledValueCellDelegate;

@interface OUIEditableLabeledValueCell : OUILabeledValueCell <UITextFieldDelegate>

@property (class, nonatomic, readonly) Class valueTextFieldClass;

@property (nonatomic, weak) id <OUIEditableLabeledValueCellDelegate> delegate;
@property (nonatomic, weak) id valueChangedTarget;
@property (nonatomic, assign) SEL valueChangedAction;
@property (nonatomic, readonly) UITextField *valueField;

- (void)beginEditingValue;

@end


@protocol OUIEditableLabeledValueCellDelegate <NSObject>
@optional

- (BOOL)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textFieldShouldBeginEditing:(UITextField *)textField;
- (void)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textFieldDidBeginEditing:(UITextField *)textField;
- (BOOL)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textFieldShouldEndEditing:(UITextField *)textField;
- (void)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textFieldDidEndEditing:(UITextField *)textField;

- (BOOL)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
- (void)editableLabeledValueCellTextDidChange:(OUIEditableLabeledValueCell *)cell;

- (BOOL)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textFieldShouldClear:(UITextField *)textField;
- (BOOL)editableLabeledValueCell:(OUIEditableLabeledValueCell *)cell textFieldShouldReturn:(UITextField *)textField;

@end

NS_ASSUME_NONNULL_END

