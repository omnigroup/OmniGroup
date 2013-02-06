// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUILabeledValueCell.h>

@protocol OUIEditableLabeledValueCellDelegate;

@interface OUIEditableLabeledValueCell : OUILabeledValueCell <UITextFieldDelegate>
{
@private
    id _delegate;
    id _target;
    SEL _action;
    UITextField *_valueField;
}

@property (nonatomic, assign) id <OUIEditableLabeledValueCellDelegate> delegate;
@property (nonatomic, assign) id target;
@property (nonatomic, assign) SEL action;
@property (nonatomic, readonly) UITextField *valueField;

- (void)beginEditingValue;

@end


@protocol OUIEditableLabeledValueCellDelegate
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
