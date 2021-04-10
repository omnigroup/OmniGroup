// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUILabeledValueCell.h>

#import <OmniUI/UIView-OUIExtensions.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

@implementation OUILabeledValueCell
{
    CGFloat _minimumLabelWidth;
    BOOL _usesActualLabelWidth;
    UITextField *_label; // Disabled UITextField so that we get the same metrics as the value w/o autolayout baseline alignment
    
    UITextField *_valueTextField;
    BOOL _isHighlighted;
}

+ (UIFont *)labelFont;
{
    return [UIFont boldSystemFontOfSize:[UIFont labelFontSize]];
}

+ (UIFont *)valueFont;
{
    return [UIFont systemFontOfSize:[UIFont labelFontSize]];
}

+ (UIColor *)labelColorForHighlighted:(BOOL)highlighted;
{
    return highlighted ? [UIColor whiteColor] : [UIColor blackColor];
}

+ (NSTextAlignment)labelTextAlignment;
{
    return NSTextAlignmentLeft;
}

+ (CGFloat)constrainedLabelWidth:(CGFloat)labelWidth;
{
    // The 'default context' label for Japanese is wider than we normally need, so make this dynamically computed, but with a minimum size that works for most cases (for nice right-alignment of most labels).
    return MAX(labelWidth, 60.0);
}

+ (UIColor *)valueColorForHighlighted:(BOOL)highlighted;
{
    return highlighted ? [UIColor whiteColor] : [UIColor blackColor];
}

- (id)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
    
    _label = [[UITextField alloc] initWithFrame:CGRectZero];
    _label.font = [[self class]  labelFont];
    _label.textAlignment = NSTextAlignmentLeft;
    _label.enabled = NO;
    //_label.layer.borderColor = [[UIColor redColor] CGColor];
    //_label.layer.borderWidth = 1;
    [self addSubview:_label];
    

    _valueTextField = [[UITextField alloc] initWithFrame:CGRectZero];
    _valueTextField.font = [[self class] valueFont];
    _valueTextField.textColor = [[self class] valueColorForHighlighted:NO];
    _valueTextField.enabled = NO;
    _valueTextField.placeholder = NSLocalizedStringFromTableInBundle(@"None", @"OmniUI", OMNI_BUNDLE, @"empty value cell placeholder");

    [self addSubview:_valueTextField];
    
    
    self.opaque = NO;

    return self;
}

- (CGFloat)minimumLabelWidth
{
    return _minimumLabelWidth;
}

- (void)setMinimumLabelWidth:(CGFloat)minWidth
{
    _minimumLabelWidth = minWidth;
    [self labelChanged];
}

- (BOOL)usesActualLabelWidth
{
    return _usesActualLabelWidth;
}

- (void)setUsesActualLabelWidth:(BOOL)usesActualLabelWidth
{
    _usesActualLabelWidth = usesActualLabelWidth;
    [self labelChanged];
}

- (NSString *)label;
{
    return _label.text;
}

- (void)setLabel:(NSString *)label;
{
    if (OFISEQUAL(_label.text, label))
        return;
    
    _label.text = label;

    [self labelChanged];
}

- (void)labelChanged;
{
    [self setNeedsLayout];
}

- (nullable NSString *)value;
{
    return _valueTextField.text;
}

- (void)setValue:(nullable NSString *)value;
{
    if (OFISEQUAL(self.value, value))
        return;
    
    _valueTextField.text = value;
    
    [self setNeedsLayout];
}

- (nullable NSString *)valuePlaceholder;
{
    return _valueTextField.placeholder;
}

- (void)setValuePlaceholder:(nullable NSString *)valuePlaceholder;
{
    if (!valuePlaceholder)
        valuePlaceholder = NSLocalizedStringFromTableInBundle(@"None", @"OmniUI", OMNI_BUNDLE, @"empty value cell placeholder");

    if (OFISEQUAL(self.valuePlaceholder, valuePlaceholder))
        return;
    
    _valueTextField.placeholder = valuePlaceholder;
    
    [self setNeedsLayout];
}

// TODO: Make this configurable and pass down the actual left separator value from the enclosing UITableViewCell
#define LABEL_GAP 15.0

- (CGRect)labelFrameInRect:(CGRect)bounds;
{
    // We take the height from our bounds and center the label w/in it. This is important since we do this for the value too, yielding consistent baselines.
    CGFloat labelWidth;
    if ([NSString isEmptyString:self.label])
        labelWidth = 0;
    else
        labelWidth = [_label sizeThatFits:bounds.size].width;
    
    if (!self.usesActualLabelWidth) {
        labelWidth = [[self class] constrainedLabelWidth:labelWidth];
        labelWidth = MAX(labelWidth, _minimumLabelWidth);
    }
    
    CGRect labelRect;
    labelRect.origin.x = CGRectGetMinX(bounds) + LABEL_GAP /* gap on left of label */;
    labelRect.size.width = labelWidth;
    labelRect.origin.y = CGRectGetMinY(bounds);
    labelRect.size.height = CGRectGetHeight(bounds);
    return labelRect;
}

- (CGRect)valueFrameInRect:(CGRect)bounds;
{
    CGRect labelRect = [self labelFrameInRect:bounds];
    
    CGRect valueRect;
    valueRect.origin.x = CGRectGetMaxX(labelRect) + LABEL_GAP /* gap on right of label */;
    valueRect.size.width = CGRectGetMaxX(bounds) - valueRect.origin.x - LABEL_GAP;
    
    valueRect.origin.y = CGRectGetMinY(labelRect);
    valueRect.size.height = labelRect.size.height;
    
    return valueRect;
}

- (BOOL)valueHidden;
{
    return _valueTextField.hidden;
}
- (void)setValueHidden:(BOOL)valueHidden;
{
    _valueTextField.hidden = valueHidden;
}

- (UITableView *)containingTableView;
{
    UITableView *tableView = (UITableView *)[self enclosingViewMatching:^BOOL(id object) {
        return [object isKindOfClass:[UITableView class]];
    }];
    OBASSERT(tableView);
    
    return tableView;
}

- (UITableViewCell *)containingTableViewCell;
{
    UITableViewCell *cell = (UITableViewCell *)[self enclosingViewMatching:^BOOL(id object) {
        return [object isKindOfClass:[UITableViewCell class]];
    }];
    OBASSERT(cell);
    
    return cell;
}

- (BOOL)isHighlighted;
{
    return _isHighlighted;
}

- (void)setHighlighted:(BOOL)yn;
{
    _isHighlighted = yn;
    
    _label.textColor = [[self class] labelColorForHighlighted:_isHighlighted];
}

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    CGRect bounds = self.bounds;
    _label.frame = [self labelFrameInRect:bounds];
    _valueTextField.frame = [self valueFrameInRect:bounds];
}

@end

NS_ASSUME_NONNULL_END
