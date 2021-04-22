// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUINumericFieldTableCell.h>
#import <OmniFoundation/OmniFoundation.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OUINumericFieldTableCellValueKey = @"value";

@interface OUINumericFieldTableCell () <UITextFieldDelegate>
@property (retain, nonatomic) IBOutlet UIButton *incrementButton;
@property (retain, nonatomic) IBOutlet UIButton *decrementButton;
@property (retain, nonatomic, readwrite) IBOutlet UILabel *editingUnitsLabel;
@property (retain, nonatomic) IBOutlet NSLayoutConstraint *valueTextFieldMinimumWidthConstraint;

- (IBAction)decrement:(id)sender;
- (IBAction)increment:(id)sender;

@end

@implementation OUINumericFieldTableCell
{
    BOOL _isEditing;
    BOOL _supportsDynamicType;
}

+ (instancetype)numericFieldTableCell;
{
    NSArray *topLevelObjects = [[UINib nibWithNibName:NSStringFromClass([OUINumericFieldTableCell class]) bundle:OMNI_BUNDLE] instantiateWithOwner:nil options:nil];
    OBASSERT(topLevelObjects != nil);
    OBASSERT(topLevelObjects.count == 1);
    OBASSERT([topLevelObjects.lastObject isKindOfClass:[OUINumericFieldTableCell class]]);
    return topLevelObjects.lastObject;
}

static id _commonInit(OUINumericFieldTableCell *self)
{
    self->_minimumValue = NSIntegerMin;
    self->_maximumValue = NSIntegerMax;
    self->_stepValue = 1;
    
    return self;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier;
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) == nil) {
        return nil;
    }
    return _commonInit(self);
}

- initWithFrame:(CGRect)frame;
{
    if ((self = [super initWithFrame:frame]) == nil) {
        return nil;
    }
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if ((self = [super initWithCoder:coder]) == nil) {
        return nil;
    }
    return _commonInit(self);
}

- (void)awakeFromNib;
{
    [super awakeFromNib];
    
    // setting the accessibilty label so that Wee-Stepper-Plus and Wee-Stepper-Minus aren't used for the button's accessibiltyLabels.
    self.incrementButton.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Increment", @"OmniUI", OMNI_BUNDLE, @"increment button accessibility label");
    self.decrementButton.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Decrement", @"OmniUI", OMNI_BUNDLE, @"increment button accessibility label");
    
    [self _updateFonts];
}

- (void)prepareForReuse;
{
    [super prepareForReuse];
    
    [self _updateFonts];
}

#pragma mark UITextFieldDelegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField;
{
    self.valueTextField.text = [NSString stringWithFormat:@"%ld", self.value];
    self.editingUnitsLabel.text = [self _unitsSuffix];
    [UIView animateWithDuration:0.2 animations:^{
        self.valueTextFieldMinimumWidthConstraint.priority = UILayoutPriorityDefaultHigh;
        self.editingUnitsLabel.alpha = 1.0;
        self.incrementButton.alpha = 0.0;
        self.decrementButton.alpha = 0.0;
        [self setNeedsLayout];
    }];
    _isEditing = YES;
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField;
{
    [self _constrainAndSetUserSuppliedValue:[self.valueTextField.text integerValue]];
    [UIView animateWithDuration:0.2 animations:^{
        self.valueTextFieldMinimumWidthConstraint.priority = 1;
        self.editingUnitsLabel.alpha = 0.0;
        self.incrementButton.alpha = 1.0;
        self.decrementButton.alpha = 1.0;
        [self setNeedsLayout];
    }];
    _isEditing = NO;
    [self _updateDisplay]; // ensures that units are added back to the string in case the value was unchanged
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    static NSCharacterSet *nonDigits;
    if (nonDigits == nil) {
        nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    }
    
    NSRange nonDigitRange = [string rangeOfCharacterFromSet:nonDigits];
    return nonDigitRange.location == NSNotFound; // only OK if there are no non-digits
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
    OBPRECONDITION(textField == self.valueTextField);
    [textField endEditing:YES];
    return NO;
}

#pragma mark - Public API

- (BOOL)supportsDynamicType;
{
    return _supportsDynamicType;
}

- (void)setSupportsDynamicType:(BOOL)flag;
{
    if (_supportsDynamicType != flag) {
        _supportsDynamicType = flag;
        [self _updateFonts];
    }
}

- (void)setLabelText:(nullable NSString *)labelText;
{
    if ([labelText isEqualToString:_labelText])
        return;
    
    _labelText = [labelText copy];
    
    [self _updateDisplay];
}

- (void)setUnitsSuffixStringSingular:(nullable NSString *)unitsSuffixStringSingular;
{
    if ([unitsSuffixStringSingular isEqualToString:_unitsSuffixStringSingular])
        return;
    
    _unitsSuffixStringSingular = [unitsSuffixStringSingular copy];
    
    [self _updateDisplay];
}

- (void)setUnitsSuffixStringPlural:(nullable NSString *)unitsSuffixStringPlural;
{
    if ([unitsSuffixStringPlural isEqualToString:_unitsSuffixStringPlural])
        return;
    
    _unitsSuffixStringPlural = [unitsSuffixStringPlural copy];
    
    [self _updateDisplay];
}

- (void)setValue:(NSInteger)value;
{
    // Input from the user should be set via _constrainAndSetUserSuppliedValue: rather than directly through this method
    _value = value;
    [self _updateDisplay];
}

- (void)setMinimumValue:(NSInteger)minimumValue;
{
    _minimumValue = minimumValue;
    [self _updateDisplay];
}

- (void)setMaximumValue:(NSInteger)maximumValue;
{
    _maximumValue = maximumValue;
    [self _updateDisplay];
}

- (void)setStepValue:(NSUInteger)stepValue;
{
    if (stepValue < 1) {
        stepValue = 1;
    }
    _stepValue = stepValue;
}

#pragma mark - Private API

- (void)didMoveToSuperview;
{
    // Workaround for rdar://35175843 (safeAreaInsets are not propagated to child view controllers under simple conditions) in iOS 11. When this view is added to its parent view (a stack view controller in our inspectors), its frame isn't updated immediately (that waits until the next layout pass) but its safe area insets are. That means that its safe area insets are calculated while it still has a provisional minimal width (based on our -loadView method's invocation of -sizeToFit), so its left inset gets set just fine but its right inset does not. We work around this by ensuring our horizontal edges match up with our parent view before it propagates its safe area insets to us.
 
    if (self.superview != nil) {
        CGRect superviewBounds = self.superview.bounds;
        CGRect oldFrame = self.frame;
        CGRect newFrame = (CGRect){.origin.x = superviewBounds.origin.x, .origin.y = oldFrame.origin.y, .size.width = superviewBounds.size.width, .size.height = oldFrame.size.height};
        self.frame = newFrame;
    }

    [super didMoveToSuperview];
}

- (IBAction)decrement:(id)sender {
    OBASSERT(_stepValue != 0);
    [self _constrainAndSetUserSuppliedValue:self.value - _stepValue];
}

- (IBAction)increment:(id)sender {
    OBASSERT(_stepValue != 0);
    [self _constrainAndSetUserSuppliedValue:self.value + _stepValue];
}

- (void)_constrainAndSetUserSuppliedValue:(NSInteger)value;
{
    NSInteger constrainedValue = CLAMP(value, self.minimumValue, self.maximumValue);
    self.value = constrainedValue;
}

- (NSArray *)_subviewsWeCareAboutWhenSizingToFit;
{
    NSMutableArray *subviews = [NSMutableArray array];
    [subviews addObjects:self.label, nil];
    [subviews addObjects:self.valueTextField, nil];
    [subviews addObjects:self.incrementButton, nil];
    [subviews addObjects:self.decrementButton, nil];
    [subviews addObjects:self.editingUnitsLabel, nil];
    return subviews;
}

- (NSString *)_unitsSuffix;
{
    NSString *suffixString = nil;
    if (self.value == 1) {
        suffixString = self.unitsSuffixStringSingular;
    } else {
        suffixString = self.unitsSuffixStringPlural;
    }
    if (suffixString == nil)
        suffixString = @"";
    
    return suffixString;
}

- (void)_updateDisplay;
{
    self.label.text = self.labelText;
    if (!_isEditing) {
        // We don't want to append the units to the string if we're editing.
        self.valueTextField.text = [NSString stringWithFormat:@"%ld %@", self.value, [self _unitsSuffix]];
    }
    self.editingUnitsLabel.text = [self _unitsSuffix];

    self.incrementButton.enabled = (self.value < self.maximumValue);
    self.decrementButton.enabled = (self.value > self.minimumValue);
}

- (void)_updateFonts;
{
    UIFont *font = _supportsDynamicType ? [UIFont preferredFontForTextStyle:UIFontTextStyleBody] : [UIFont systemFontOfSize:17.0];
    
    self.label.font = font;
    self.valueTextField.font = font;
    self.editingUnitsLabel.font = font;
}

#pragma mark - UIView subclass

- (CGSize)sizeThatFits:(CGSize)size;
{
    CGRect contentsRect = CGRectZero;
    for (UIView *subview in self._subviewsWeCareAboutWhenSizingToFit) {
        CGRect subviewFrame = subview.frame;
        if (!CGRectIsEmpty(subviewFrame)) {
            if (CGRectIsEmpty(contentsRect)) {
                contentsRect = subviewFrame;
            } else {
                contentsRect = CGRectUnion(contentsRect, subviewFrame);
            }
        }
    }
    return contentsRect.size;
}

@end

NS_ASSUME_NONNULL_END

