// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIEditableLabeledValueCell.h>

#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

#define STANDARD_ROW_HEIGHT 44.0

@implementation OUIEditableLabeledValueCell
{
    UITextField *_valueField;
}

+ (Class)valueTextFieldClass;
{
    return [UITextField class];
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    
    // Lame, but we override the value field in OUILabeledValueCell
    self.valueHidden = YES;
    
    [self labelChanged];
    
    return self;
}

@synthesize delegate = _weak_delegate;
@synthesize valueChangedTarget = _weak_valueChangedTarget;

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidChangeNotification object:_valueField];

    _valueField.delegate = nil;
}

- (nullable NSString *)value;
{
    return self.valueField.text;
}

- (void)setValue:(nullable NSString *)value;
{
    self.valueField.text = value;
}

- (void)labelChanged;
{
    [super labelChanged];
    
    if (!_valueField) {
        Class cls = [[self class] valueTextFieldClass];
        OBASSERT(OBClassIsSubclassOfClass(cls, [UITextField class]));

        _valueField = [[cls alloc] initWithFrame:CGRectZero];
        _valueField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _valueField.font = [[self class] valueFont];
        _valueField.adjustsFontSizeToFitWidth = YES;
        _valueField.minimumFontSize = 10.0;
        _valueField.placeholder = [super valuePlaceholder];
        _valueField.returnKeyType = UIReturnKeyDone;
        _valueField.delegate = self;
        //_valueField.layer.borderColor = [[UIColor blueColor] CGColor];
        //_valueField.layer.borderWidth = 1;
        [self addSubview:_valueField];
        
        UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(beginEditingValue)];
        [self addGestureRecognizer:tapGestureRecognizer];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textFieldTextDidChange:) name:UITextFieldTextDidChangeNotification object:_valueField];
    }
}

- (nullable NSString *)valuePlaceholder;
{
    return nil;
}

- (void)beginEditingValue;
{
    [self.valueField becomeFirstResponder];
}

#pragma mark - UIView subclass

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    _valueField.frame = [self valueFrameInRect:self.bounds];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField NS_EXTENSION_UNAVAILABLE_IOS("");
{
    id <OUIEditableLabeledValueCellDelegate> delegate = _weak_delegate;
    
    textField.keyboardAppearance = [OUIAppController controller].defaultKeyboardAppearance;

    if ([delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldShouldBeginEditing:)]) {
        if (![delegate editableLabeledValueCell:self textFieldShouldBeginEditing:textField])
            return NO;
    }

    UITableViewCell *containingCell = [self containingTableViewCell];
    UITableView *containingTableView = [self containingTableView];
        
    NSIndexPath *path = [containingTableView indexPathForCell:containingCell];
    if (path)
	[containingTableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionTop animated:YES];
 
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField;
{
    id <OUIEditableLabeledValueCellDelegate> delegate = _weak_delegate;
    
    if ([delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldDidBeginEditing:)])
        [delegate editableLabeledValueCell:self textFieldDidBeginEditing:textField];

    OBStrongRetain(self);
    [self setNeedsDisplay];
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField;
{
    id <OUIEditableLabeledValueCellDelegate> delegate = _weak_delegate;

    if ([delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldShouldEndEditing:)] &&
        ![delegate editableLabeledValueCell:self textFieldShouldEndEditing:textField])
        return NO;

    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField; 
{
    id <OUIEditableLabeledValueCellDelegate> delegate = _weak_delegate;

    if ([delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldDidEndEditing:)])
        [delegate editableLabeledValueCell:self textFieldDidEndEditing:textField];

    if (_valueChangedAction)
        OBSendVoidMessageWithObject(self.valueChangedTarget, _valueChangedAction, self);

    [self setNeedsDisplay];
    OBAutorelease(self);
}
            
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    id <OUIEditableLabeledValueCellDelegate> delegate = _weak_delegate;

    if ([delegate respondsToSelector:@selector(editableLabeledValueCell:textField:shouldChangeCharactersInRange:replacementString:)] &&
        ![delegate editableLabeledValueCell:self textField:textField shouldChangeCharactersInRange:range replacementString:string])
        return NO;

    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField;           
{
    id <OUIEditableLabeledValueCellDelegate> delegate = _weak_delegate;

    if ([delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldShouldClear:)] &&
        ![delegate editableLabeledValueCell:self textFieldShouldClear:textField])
        return NO;

    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField;           
{
    id <OUIEditableLabeledValueCellDelegate> delegate = _weak_delegate;

    if ([delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldShouldReturn:)] &&
        ![delegate editableLabeledValueCell:self textFieldShouldReturn:textField])
        return NO;

    [textField endEditing:YES];
    return NO;
}

- (void)_textFieldTextDidChange:(NSNotification *)note;
{
    id <OUIEditableLabeledValueCellDelegate> delegate = _weak_delegate;

    if ([delegate respondsToSelector:@selector(editableLabeledValueCellTextDidChange:)])
        [delegate editableLabeledValueCellTextDidChange:self];
}

@end

NS_ASSUME_NONNULL_END

