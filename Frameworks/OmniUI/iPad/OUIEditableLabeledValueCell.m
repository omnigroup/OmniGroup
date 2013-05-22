// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIEditableLabeledValueCell.h>

RCS_ID("$Id$");

#define STANDARD_ROW_HEIGHT 44.0

@implementation OUIEditableLabeledValueCell

- (id)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
        
    [self labelChanged];
    return self;
}

@synthesize delegate = _delegate;
@synthesize target = _target;
@synthesize action = _action;
@synthesize valueField = _valueField;

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidChangeNotification object:_valueField];

    _valueField.delegate = nil;
    [_valueField release];
    [super dealloc];
}

- (NSString *)value;
{
    return self.valueField.text;
}

- (void)setValue:(NSString *)value;
{
    self.valueField.text = value;
}

- (void)labelChanged;
{
    [super labelChanged];
    
    CGRect valueRect = [self valueRectForString:@"Value" labelRect:[self labelRect]];
    
    if (!_valueField) {
        _valueField = [[UITextField alloc] initWithFrame:valueRect];
        _valueField.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
        _valueField.font = [[self class] valueFontForStyle:self.style];
        _valueField.adjustsFontSizeToFitWidth = YES;
        _valueField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        _valueField.minimumFontSize = 10.0;
        _valueField.placeholder = [super valuePlaceholder];
        _valueField.returnKeyType = UIReturnKeyDone;
        _valueField.delegate = self;
        [self addSubview:_valueField];
#if __IPHONE_3_2 >= __IPHONE_OS_VERSION_MAX_ALLOWED
        UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(beginEditingValue)];
        [self addGestureRecognizer:tapGestureRecognizer];
        [tapGestureRecognizer release];
#endif
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textFieldTextDidChange:) name:UITextFieldTextDidChangeNotification object:_valueField];
        
    } else {
        _valueField.frame = valueRect;
    }
}

- (NSString *)valuePlaceholder;
{
    return nil;
}

- (void)beginEditingValue;
{
    [self.valueField becomeFirstResponder];
}

#pragma mark -
#pragma mark Text Field Delegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField;
{
    if ([_delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldShouldBeginEditing:)]) {
        if (![_delegate editableLabeledValueCell:self textFieldShouldBeginEditing:textField])
            return NO;
    }

    UITableViewCell *cell = (UITableViewCell *)self.superview.superview;
    UITableView *tableView = (UITableView *)cell.superview;    
    NSIndexPath *path = [tableView indexPathForCell:cell];
    
    if (path)
	[tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionTop animated:YES];
 
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField;
{
    if ([_delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldDidBeginEditing:)]) {
        [_delegate editableLabeledValueCell:self textFieldDidBeginEditing:textField];
    }

    [self retain];
    [self setNeedsDisplay];
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField;
{
    if ([_delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldShouldEndEditing:)]) {
        if (![_delegate editableLabeledValueCell:self textFieldShouldEndEditing:textField])
            return NO;
    }

    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField; 
{
    if ([_delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldDidEndEditing:)]) {
        [_delegate editableLabeledValueCell:self textFieldDidEndEditing:textField];
    }

    [self.target performSelector:self.action withObject:self];
    [self setNeedsDisplay];
    [self autorelease];
}
            
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    if ([_delegate respondsToSelector:@selector(editableLabeledValueCell:textField:shouldChangeCharactersInRange:replacementString:)]) {
        if (![_delegate editableLabeledValueCell:self textField:textField shouldChangeCharactersInRange:range replacementString:string])
            return NO;
    }

    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField;           
{
    if ([_delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldShouldClear:)]) {
        if (![_delegate editableLabeledValueCell:self textFieldShouldClear:textField])
            return NO;
    }

    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField;           
{
    if ([_delegate respondsToSelector:@selector(editableLabeledValueCell:textFieldShouldReturn:)]) {
        if (![_delegate editableLabeledValueCell:self textFieldShouldReturn:textField])
            return NO;
    }

    [textField endEditing:YES];
    return NO;
}

- (void)_textFieldTextDidChange:(NSNotification *)note;
{
    if ([_delegate respondsToSelector:@selector(editableLabeledValueCellTextDidChange:)])
        [_delegate editableLabeledValueCellTextDidChange:self];
}

@end
