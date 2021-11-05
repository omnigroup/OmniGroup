// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorTextWell.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorWell.h>
#import <OmniUI/OUITextLayout.h>
#import <OmniUI/OUITextView.h>

#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/OmniBase.h>
#import <Foundation/Foundation.h>
#import <Foundation/NSAttributedString.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFExtent.h>

#import "OUIParameters.h"

@interface OUIInspectorTextWell () <UITextFieldDelegate>
@property(nonatomic,readonly) NSTextAlignment effectiveTextAlignment;
@end

@implementation OUIInspectorTextWell
{
    // While editing.
    UITextField *_textField;
    
    // When not editing these are shown. If we are using OUIInspectorTextWellStyleDefault, only _labelLabel is used. We use UITextField instances that are disabled instaed of UILabel so that the metrics match up exactly.
    UITextField *_labelLabel;
    UITextField *_valueLabel;
    
    // Used to show that we are the editing field when we have a custom keyboard and don't use _textField.
    UIView *_focusIndicatorView;

    id _objectValue;
    BOOL _textChangedWhileEditingOnCustomKeyboard;
}

static id _commonInit(OUIInspectorTextWell *self)
{
    self.clearsContextBeforeDrawing = YES;
    self.opaque = NO;
    self.backgroundColor = nil;
    
    // Same defaults as for UITextInputTraits
    self.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    self.autocorrectionType = UITextAutocorrectionTypeDefault;
    self.clearButtonMode = UITextFieldViewModeNever;
    self.spellCheckingType = UITextSpellCheckingTypeDefault;
    self.keyboardType = UIKeyboardTypeDefault;
    self.returnKeyType = UIReturnKeyDefault;
    
    self->_style = OUIInspectorTextWellStyleDefault;
    self->_textAlignment = NSTextAlignmentCenter;
    
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidChangeNotification object:_textField];
    _textField.delegate = nil;
}

+ (UIFont *)defaultLabelFont;
{
    return [OUIInspector labelFont];
}

+ (UIFont *)defaultFont;
{
    return [self defaultLabelFont]; // Our label font is actually the same as our normal font
}

- (void)setStyle:(OUIInspectorTextWellStyle)style;
{
    if (_style == style)
        return;
    
    OBASSERT(!self.editing); // We won't reposition the field editor right now, but we could if needed
    _style = style;
    
    [self _updateLabels];
    [self setNeedsLayout];
}


- (void)setEditable:(BOOL)editable;
{
    if (_editable == editable)
        return;
    
    if (!editable && [_textField isFirstResponder])
        [_textField endEditing:YES];
    
    _editable = editable;
    _textField.enabled = editable;
    
    if (_editable)
        [self addTarget:self action:@selector(_tappedTextWell:) forControlEvents:UIControlEventTouchUpInside];
    else
        [self removeTarget:self action:@selector(_tappedTextWell:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)setEnabled:(BOOL)enabled;
{
    [super setEnabled:enabled];
    
    [self _updateLabels];
    [self setNeedsLayout];
}

- (BOOL)editing;
{
    return [_textField isFirstResponder];
}

typedef enum {
    TextTypeValue,
    TextTypeLabel,
    TextTypePlaceholder,
} TextType;

static UIFont *_defaultFontForType(OUIInspectorTextWell *self, TextType type)
{
    if (type == TextTypeLabel)
        return [[self class] defaultLabelFont];
    
    OBASSERT(type == TextTypeValue || type == TextTypePlaceholder);
    return [[self class] defaultFont];
}

static UIFont *_getFont(OUIInspectorTextWell *self, UIFont *font, TextType type)
{
    if (!font)
        font = _defaultFontForType(self, type);
    return font;
}
static void _setAttr(NSMutableAttributedString *attrString, NSString *name, id value)
{
    OBPRECONDITION(attrString);
    OBPRECONDITION(name);
    
    NSRange range = NSMakeRange(0, [attrString length]);
    if (value)
        [attrString addAttribute:name value:value range:range];
    else
        [attrString removeAttribute:name range:range];
}

static NSString *_getText(OUIInspectorTextWell *self, NSString *text, TextType *outType)
{
    TextType textType = TextTypeValue;

    if ([NSString isEmptyString:text]) {
        text = self->_placeholderText;
        if ([NSString isEmptyString:text])
            text = @"";
        textType = TextTypePlaceholder;
    } else if (!self.enabled)
        textType = TextTypePlaceholder;
    
    if (outType)
        *outType = textType;
    return text;
}

- (NSAttributedString *)_attributedStringForEditingString:(NSString *)aString textType:(TextType)textType;
{
    // We don't want to edit the placeholder text, so don't use _getText().
    if (!aString)
        aString = @"";
    
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:aString attributes:nil];
    {
        UIFont *font = _getFont(self, _font, textType);
        if (font)
            _setAttr(attributedText, NSFontAttributeName, font);
    }
    
    UIColor *textColor = textType == TextTypePlaceholder ? self.disabledTextColor : [self textColor];
    _setAttr(attributedText, NSForegroundColorAttributeName, textColor);
    
    OBASSERT(_textField); // use the alignment already set up when the editor was created
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.alignment = _textField.textAlignment;
    _setAttr(attributedText, NSParagraphStyleAttributeName, paragraphStyle);
    
    return attributedText;
}

- (NSString *)editingText;
{
    OBPRECONDITION(self.editing);
    return [_textField.attributedText string];
}

- (void)setEditingText:(NSString *)editingText;
{
    OBPRECONDITION(self.editing);

    _textField.attributedText = [self _attributedStringForEditingString:editingText textType:TextTypeValue];
}

- (NSTextAlignment)effectiveTextAlignment
{
    return _style == OUIInspectorTextWellStyleSeparateLabelAndText ? NSTextAlignmentRight : _textAlignment;
}

- (UITextField *)editor;
{
    if (_editable && !_textField) {
        _textField = [[UITextField alloc] initWithFrame:CGRectZero];
        _textField.delegate = self;
        _textField.textColor = [self textColor];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textFieldDidChange:) name:UITextFieldTextDidChangeNotification object:_textField];

        // Set up the default paragraph alignment for when the editor's text is empty. Also, when we make editing text, this will be used for the alignment.
        _textField.textAlignment = self.effectiveTextAlignment;
        
        NSAttributedString *placeholder = [self _attributedStringForEditingString:_placeholderText textType:TextTypePlaceholder];
        _textField.attributedPlaceholder = placeholder;
    }
    return _textField;
}

- (void)setTextAlignment:(NSTextAlignment)textAlignment;
{
    if (_textAlignment == textAlignment)
        return;
    
    _textAlignment = textAlignment;
    OBASSERT(!self.editing); // could need to mess with the editor's contents

    [self setNeedsLayout];
}

- (void)setText:(NSString *)text;
{
    if (_text == text)
        return;

    _text = [text copy];
    
    [self _updateLabels];
    
    if (self.editing) {
        TextType textType;
        _getText(self, _text, &textType);
        self.editor.attributedText = [self _attributedStringForEditingString:_text textType:TextTypeValue];
    } else if (self.isFirstResponder) {
        _textChangedWhileEditingOnCustomKeyboard = YES;
    }
        
    [self setNeedsLayout];
}

- (id)objectValue;
{
    if (!_customKeyboard) {
        id objectValue;
        [_formatter getObjectValue:&objectValue forString:self.text errorDescription:NULL];
        _objectValue = objectValue;
    }
    return _objectValue;
}

- (void)setObjectValue:(id)objectValue;
{
    if (_objectValue == objectValue || (_objectValue && [objectValue isEqual:_objectValue]))
        return;

    _objectValue = objectValue;
    self.text = [_formatter stringForObjectValue:_objectValue];
}

@synthesize customKeyboardChangedText = _textChangedWhileEditingOnCustomKeyboard;

- (void)setSuffix:(NSString *)text;
{
    if (_suffix == text)
        return;
    
    _suffix = [text copy];
    
    [self _updateLabels];
    [self setNeedsLayout];
}

@synthesize textColor = _textColor;
- (UIColor *)textColor;
{
    if (_textColor)
        return _textColor;
        
    return [OUIInspector valueTextColor];
}

- (void)setTextColor:(UIColor *)textColor;
{
    if (_textColor == textColor)
        return;
    _textColor = textColor;
    
    [self _updateLabels];
    [self setNeedsLayout];
}

- (void)setFont:(UIFont *)font;
{
    if (_font == font)
        return;

    _font = font;

    [self _updateLabels];
    [self setNeedsLayout];
}

- (void)setLabel:(NSString *)label;
{
    if (_label == label)
        return;
    
    _label = [label copy];
    
    [self _updateLabels];
    [self setNeedsLayout];
    
    OBASSERT(!self.editing); // Otherwise we'd need to adjust the space available to the field editor (via -setNeedsLayout) if we were using OUIInspectorTextWellStyleSeparateLabelAndText
}

- (void)setLabelFont:(UIFont *)labelFont;
{
    if (_labelFont == labelFont)
        return;

    _labelFont = labelFont;

    [self _updateLabels];
    [self setNeedsLayout];
    
    OBASSERT(!self.editing); // Otherwise we'd need to adjust the space available to the field editor (via -setNeedsLayout) if we were using OUIInspectorTextWellStyleSeparateLabelAndText
}

@synthesize labelColor = _labelColor;
- (UIColor *)labelColor;
{
    if (_labelColor)
        return _labelColor;
    
    // Use a default based on our background style.
    if (self.backgroundType == OUIInspectorWellBackgroundTypeButton)
        return [UIColor labelColor];
    
    return self.textColor;
}

- (void)setLabelColor:(UIColor *)labelColor;
{
    if (_labelColor == labelColor)
        return;
    _labelColor = labelColor;
    
    [self _updateLabels];
    [self setNeedsLayout];
}

@synthesize disabledTextColor = _disabledTextColor;
- (UIColor *)disabledTextColor;
{
    if (_disabledTextColor)
        return _disabledTextColor;
    
    return [OUIInspector placeholderTextColor];
}

- (void)setDisabledTextColor:(UIColor *)disabledTextColor;
{
    if (_disabledTextColor == disabledTextColor)
        return;
    _disabledTextColor = disabledTextColor;
    
    [self _updateLabels];
    [self setNeedsLayout];
}

- (void)setPlaceholderText:(NSString *)placeholderText;
{
    if (OFISEQUAL(_placeholderText, placeholderText))
        return;
    
    _placeholderText = [placeholderText copy];
    _textField.placeholder = _placeholderText;
    [self _updateLabels];
    [self setNeedsLayout];
}

- (NSString *)willCommitEditingText:(NSString *)editingText;
{
    return editingText;
}

- (void)startEditing;
{
    [self becomeFirstResponder];
    [self _tappedTextWell:nil];
}

- (void)selectAll:(id)sender;
{
    if ([_textField isFirstResponder])
        [_textField selectAll:sender];
}

- (void)selectAll:(id)sender showingMenu:(BOOL)show;
{
    OBFinishPortingLater("<bug:///147848> (iOS-OmniOutliner Bug: Obey ‘showingMenu’ argument in -[OUIInspectorTextWell selectAll:showingMenu:])");
    if ([_textField isFirstResponder])
        [_textField selectAll:sender];
}

- (void)setHighlighted:(BOOL)highlighted;
{
    [super setHighlighted:highlighted];

    if (self.backgroundType == OUIInspectorWellBackgroundTypeButton) {
        self.textColor = [super textColor];
        self.labelColor = [super textColor];
        //The right view should highlight when we highlight
        OBASSERT([self.rightView respondsToSelector:@selector(setHighlighted:)] || self.rightView == nil);
        if ([self.rightView respondsToSelector:@selector(setHighlighted:)]) {
            [(UIControl *)self.rightView setHighlighted:highlighted];
        }
    }
}

#pragma mark - UIView subclass

-(CGSize)sizeThatFits:(CGSize)size;
{
    if (_style == OUIInspectorTextWellStyleDefault) {
        CGSize labelSize = [_labelLabel sizeThatFits:size];
        return CGSizeMake(labelSize.width + 16, self._standaloneValueRect.size.height); // only interested in adjusting the length right now
    } else {
#ifdef DEBUG
        NSLog(@"warning: not doing any calculations here!");
#endif
        return size;
    }
}

- (CGRect)_standaloneValueRect;
{
    OBPRECONDITION(_style == OUIInspectorTextWellStyleDefault);
    
    // Center the text across the whole bounds, even if we have a nav arrow chopping off part of it. But if we are right or left aligned just use the contents rect (since we are probably trying to avoid a left/right view.
    CGRect drawRect;
    if (_textAlignment == NSTextAlignmentCenter) {
        CGFloat leftRightInset = 0;
        
        // The left/right views are currently expected to have built-in padding.
        if (self.leftView) 
            leftRightInset = CGRectGetMaxX(self.leftView.frame);
        if (self.rightView) 
            leftRightInset = MAX(leftRightInset, CGRectGetMaxX(self.frame) - CGRectGetMinX(self.rightView.frame));
        
        UIEdgeInsets insets = UIEdgeInsetsMake(0, leftRightInset, 0, leftRightInset); // TODO: Assumes zero scale
        drawRect = UIEdgeInsetsInsetRect(OUIInspectorWellInnerRect(self.bounds), insets);
    } else
        drawRect = self.contentsRect;
    
    return drawRect;
}

- (void)_updateValueLabelFrameWithContentsRect:(CGRect)contentsRect labelFrame:(CGRect)labelFrame;
{
    CGRect valueFrame;
    CGRectDivide(contentsRect, &labelFrame, &valueFrame, labelFrame.size.width + 8, CGRectMinXEdge);
    UIView *rightView = self.rightView;
    if (rightView != nil) {
        valueFrame.size.width = CGRectGetMinX(rightView.frame) - CGRectGetMinX(valueFrame) - 8.0f /* padding between valueLabel and rightView */;
        valueFrame.size.width = MAX(valueFrame.size.width, 0.0f); // Don't go negative, at least
    }
    _valueLabel.frame = valueFrame;

    if (_focusIndicatorView) {
        valueFrame.size.width += 8;
        _focusIndicatorView.frame = CGRectInset(valueFrame, 0, 4);
    }
}

- (void)layoutSubviews;
{
    [super layoutSubviews];

    switch (_style) {
        case OUIInspectorTextWellStyleSeparateLabelAndText: {
            CGRect contentsRect = self.contentsRect; // This already avoids the left/right view and does any needed insets
            
            CGRect labelFrame = contentsRect;
            labelFrame.size.width = [_labelLabel sizeThatFits:contentsRect.size].width;
            _labelLabel.frame = labelFrame;
            
            OBASSERT((_textField == nil) || (_focusIndicatorView == nil));
            if (_textField) {
                if (CGRectEqualToRect(_valueLabel.frame, CGRectZero)) {
                    [self _updateValueLabelFrameWithContentsRect:contentsRect labelFrame:labelFrame];
                }
                [self _updateEditorFrame];
                _valueLabel.hidden = YES;
                if (!_textField.isEditing) {
                    [self startEditing];
                }
            } else {
                [self _updateValueLabelFrameWithContentsRect:contentsRect labelFrame:labelFrame];
                _valueLabel.hidden = NO;
            }
            break;
        }
        case OUIInspectorTextWellStyleDefault: {
            OBASSERT(_focusIndicatorView == nil, "Custom keyboard editing indicator not supported in the combined label/value case."); // not hard, but haven't needed it and so haven't tested it.
            CGRect rect = [self _standaloneValueRect];
            if (_textField) {
                _textField.frame = rect;
                _labelLabel.hidden = YES;
            } else {
                _labelLabel.frame = rect;
                _labelLabel.hidden = NO;
            }
            break;
        }
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    UIView *hit = [super hitTest:point withEvent:event];
    
    if (hit == nil && self.editing)
        // Let the field editor have a chance. It may have subviews that are outside our bounds (for autocorrection).
        hit = [_textField hitTest:[self convertPoint:point toView:_textField] withEvent:event];

    return hit;
}

#pragma mark - UITextFieldDelegate

- (void)_textFieldDidChange:(NSNotification *)note;
{
    OBPRECONDITION(note.object == _textField);
    
    [self sendActionsForControlEvents:UIControlEventEditingChanged];
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField NS_EXTENSION_UNAVAILABLE_IOS("");
{
    textField.keyboardAppearance = [OUIAppController controller].defaultKeyboardAppearance;
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField;              // called when 'return' key pressed. return NO to ignore.
{
    OBPRECONDITION(textField == _textField);
    
    // Hitting return; act like a field editor and end editing.
    
    // We don't have autocorrect on in at least some cases, but if we do, we have to do this after a delay. Otherwise, if there *is* an auto-correction widget up on the text editor, it will have already done its autocorrection and then when we tell it to end editing, it will do it again!
    // <bug:///72342> (Tapping return when autocomplete is up appends the substitution after your typed string)
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [_textField endEditing:YES];
        
        // TODO: This means we'll end up sending both UIControlEventEditingDidEnd and UIControlEventEditingDidEndOnExit. Does UITextField?
        [self sendActionsForControlEvents:UIControlEventEditingDidEndOnExit];
    }];

    return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _textField);
    NSString *text = [[_textField attributedText] string];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidChangeNotification object:_textField];
    [_textField removeFromSuperview];
    _textField.delegate = nil;
    
    // We need to keep the editor alive past our call frame. We'll zombie if the editor is first responder in a popover when the popover is closed. They have a pointer to the view up the call stack from here.
    OBRetainAutorelease(_textField); // Another -release will be generated by the assignment of nil to _editor
    _textField = nil;
    
    // Let subclasses and delegates validate the text and provide a replacement.
    text = [self willCommitEditingText:text];
    if ([_delegate respondsToSelector:@selector(textWell:willCommitEditingText:)])
        text = [_delegate textWell:self willCommitEditingText:text];

    if (OFNOTEQUAL(text, _text)) {
        self.text = text;
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
    
    [self sendActionsForControlEvents:UIControlEventEditingDidEnd];
    
    // start displaying again.
    [self setNeedsLayout];
}

- (NSAttributedString *)_defaultStyleFormattedText;
{
    OBPRECONDITION(_style == OUIInspectorTextWellStyleDefault);
    
    TextType textType;
    NSString *text = _getText(self, _text, &textType);

    NSMutableAttributedString *attrText = [[NSMutableAttributedString alloc] initWithString:text attributes:nil];
    {
        UIFont *font = _getFont(self, _font, textType);
        if (font)
            _setAttr(attrText, NSFontAttributeName, font);
    }
    
    if (_label && textType != TextTypePlaceholder) {
        NSMutableAttributedString *attrFormat = [[NSMutableAttributedString alloc] initWithString:_label ? _label : @"" attributes:nil];
        UIFont *font = _getFont(self, _labelFont ? _labelFont : _font, TextTypeLabel);
        if (font)
            _setAttr(attrFormat, NSFontAttributeName, font);
        
        // If there is a '%@', find it and put the text there. Otherwise, append the text.
        NSRange valueRange = [_label rangeOfString:@"%@"];
        if (valueRange.location == NSNotFound)
            valueRange = NSMakeRange([_label length], 0);
        [attrFormat replaceCharactersInRange:valueRange withAttributedString:attrText];
        
        attrText = attrFormat;
    }
    
    UIColor *textColor = textType == TextTypePlaceholder ? self.disabledTextColor : [self textColor];
    _setAttr(attrText, NSForegroundColorAttributeName, textColor);
    
    // Align the text horizontally and truncate instead of wrapping.
    {
        NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        paragraphStyle.alignment = self.effectiveTextAlignment;
        paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;

        _setAttr(attrText, NSParagraphStyleAttributeName, paragraphStyle);
    }
    
    return attrText;
}

- (void)_updateLabels;
{
    if (_style == OUIInspectorTextWellStyleSeparateLabelAndText) {
        // Label
        {
            NSMutableAttributedString *attrLabel = [[NSMutableAttributedString alloc] initWithString:_label ? _label : @"" attributes:nil];
            UIFont *font = _getFont(self, _labelFont ? _labelFont : _font, TextTypeLabel);
            if (font)
                _setAttr(attrLabel, NSFontAttributeName, font);
            
            UIColor *labelColor = self.enabled ? [self labelColor] : self.disabledTextColor;
            _setAttr(attrLabel, NSForegroundColorAttributeName, labelColor);
            
            if (!_labelLabel) {
                _labelLabel = [[UITextField alloc] init];
                _labelLabel.enabled = NO;
                [self addSubview:_labelLabel];
            }
            _labelLabel.attributedText = attrLabel;
        }
        
        // Value
        {
            TextType textType;
            NSString *text = _getText(self, _text, &textType);
            
            if (_suffix)
                text = [text stringByAppendingString:_suffix];
            
            NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:text attributes:nil];
            UIFont *font = _getFont(self, _font, textType);
            if (font)
                _setAttr(attrString, NSFontAttributeName, font);
            
            UIColor *textColor = textType == TextTypePlaceholder ? self.disabledTextColor : [OUIInspector valueTextColor];
            _setAttr(attrString, NSForegroundColorAttributeName, textColor);
            
            // Right align and tail truncate the text
            {
                NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle defaultParagraphStyle] mutableCopy];
                paragraphStyle.alignment = NSTextAlignmentRight;
                paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
                _setAttr(attrString, NSParagraphStyleAttributeName, paragraphStyle);
            }
            
            if (!_valueLabel) {
                _valueLabel = [[UITextField alloc] init];
                _valueLabel.enabled = NO;
                [self addSubview:_valueLabel];
            }
            _valueLabel.attributedText = attrString;
            _valueLabel.textColor = textColor;
            
            _valueLabel.hidden = NO;
        }
    } else {
        _valueLabel.hidden = YES;
        
        if (!_labelLabel) {
            _labelLabel = [[UITextField alloc] init];
            _labelLabel.enabled = NO;
            [self addSubview:_labelLabel];
        }

        _labelLabel.attributedText = [self _defaultStyleFormattedText];
    }
}

- (BOOL)canBecomeFirstResponder;
{
    return _customKeyboard && ![_customKeyboard shouldUseTextEditor];
}

- (UIView *)inputView;
{
    UIView *result = _customKeyboard.inputView;
    result.tintColor = self.tintColor;
    return result;
}

- (UIView *)inputAccessoryView;
{
    UIView *result = _customKeyboard.inputAccessoryView;
    result.tintColor = self.tintColor;
    return result;
}

- (BOOL)resignFirstResponder;
{
    if ([self isFirstResponder]) {
        if (_textChangedWhileEditingOnCustomKeyboard) {
            _textChangedWhileEditingOnCustomKeyboard = NO;
            [self sendActionsForControlEvents:UIControlEventValueChanged];
        }
        [_customKeyboard editInspectorTextWell:nil];
        
        [_focusIndicatorView removeFromSuperview];
        _focusIndicatorView = nil;
        
        _valueLabel.textColor = self.textColor;

        [self setNeedsLayout];
    }
    return [super resignFirstResponder];
}

- (BOOL)shouldDrawHighlighted;
{
    return [self isFirstResponder] || [super shouldDrawHighlighted];
}

- (void)_tappedTextWell:(id)sender;
{
    // Can tap the area above/below the text field. Don't restart editing if that happens.
    if (self.editing)
        return;
    
    // Move ourselves to the top of our peer subviews. Otherwise, text widgets can end up being clipped by peer views, see <bug:///72491> (Autocorrect/Kanji selection difficult in Column & Style Name fields entering Japanese with BT keyboard)
    [[self superview] bringSubviewToFront:self];
    [self.window endEditing:YES];
   
    // turn off display while editing.
    [self setNeedsLayout];
    
    if (_customKeyboard != nil && ![_customKeyboard shouldUseTextEditor]) {
        _textChangedWhileEditingOnCustomKeyboard = NO;
        [_customKeyboard editInspectorTextWell:self];
        [self becomeFirstResponder];
        
        _focusIndicatorView = [[UIView alloc] init];
        _focusIndicatorView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.04f];
        _focusIndicatorView.layer.cornerRadius = 4;
        [self insertSubview:_focusIndicatorView belowSubview:_valueLabel];
        
        _valueLabel.textColor = self.tintColor;
    } else {
        UITextField *editor = self.editor; // creates if needed

        // Set this as the default instead of on the attributed string in case we start out with zero length text.
        UIFont *font = [self font] ? [self font] : [UIFont systemFontOfSize:[OUIInspectorTextWell fontSize]];
        editor.font = font;
        
        TextType textType;
        _getText(self, _text, &textType);
        editor.autocapitalizationType = self.autocapitalizationType;
        editor.autocorrectionType = self.autocorrectionType;
        editor.clearButtonMode = self.clearButtonMode;
        editor.spellCheckingType = self.spellCheckingType;
        editor.keyboardType = self.keyboardType;
        editor.returnKeyType = self.returnKeyType;
        editor.opaque = NO;
        editor.backgroundColor = nil;
        editor.inputView = self.inputView;
        editor.inputAccessoryView = self.inputAccessoryView;
        
        editor.attributedText = [self _attributedStringForEditingString:_text textType:textType];
        [editor sizeToFit];
        
        [self addSubview:editor];
        
        [editor becomeFirstResponder];
    }

    [self sendActionsForControlEvents:UIControlEventEditingDidBegin];
}

- (void)_updateEditorFrame;
{
    OBPRECONDITION(_textField);

    CGRect valueRect;
    if (_style == OUIInspectorTextWellStyleSeparateLabelAndText) {
        valueRect = _valueLabel.frame;
    } else {
        valueRect = self.contentsRect;
    }
    
    _textField.frame = valueRect;
}

#pragma mark - UIAccessibility

- (BOOL)isAccessibilityElement;
{
    return YES;
}

- (NSString *)accessibilityLabel;
{
    return _label;
}

- (NSString *)accessibilityValue;
{
    if (self.editing)
        return _textField.accessibilityValue;

    NSString *text = _getText(self, _text, NULL);
    
    if (_suffix)
        text = [text stringByAppendingString:_suffix];
    return text;
}

@end
