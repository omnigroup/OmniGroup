// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorTextWell.h>

#import <OmniUI/OUIInspectorWell.h>
#import <OmniUI/OUITextLayout.h>
#import <OmniUI/OUIEditableFrame.h>

#import <CoreText/CoreText.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/OmniBase.h>
#import <Foundation/Foundation.h>
#import <Foundation/NSAttributedString.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFExtent.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_EDITOR_FRAME_ENABLED
#endif

#ifdef DEBUG_EDITOR_FRAME_ENABLED
    #define DEBUG_EDITOR_FRAME(format, ...) NSLog(@"EDITOR: " format, ## __VA_ARGS__)
#else
    #define DEBUG_EDITOR_FRAME(format, ...)
#endif

@interface OUIInspectorTextWellEditor : OUIEditableFrame
@property(nonatomic,assign) CGRect clipRect;
@end
@implementation OUIInspectorTextWellEditor

@synthesize clipRect = _clipRect;
- (void)setClipRect:(CGRect)clipRect;
{
    if (CGRectEqualToRect(_clipRect, clipRect))
        return;
    _clipRect = clipRect;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    {
#ifdef DEBUG_EDITOR_FRAME_ENABLED
        // avoid clipping and just draw the rect that would be the clip
        CGContextAddRect(ctx, CGRectInset(_clipRect, 0.5, 0.5));
        [[UIColor blueColor] set];
        CGContextStrokePath(ctx);
#else
        CGContextAddRect(ctx, _clipRect);
        CGContextClip(ctx);
#endif
        
        [super drawRect:rect];
    }
    CGContextRestoreGState(ctx);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    UIView *hitView = [super hitTest:point withEvent:event];
    
    // We extent beyond what the user can see with our clipping rect hiding this. Don't let touches happen outside our unclipped area (unless they are some other view, like the text system autocorrection widgets).
    if (hitView == self && !CGRectContainsPoint(_clipRect, point))
        return nil;
    
    return hitView;
}

@end

@interface OUIInspectorTextWell (/*Private*/) <OUIEditableFrameDelegate>
@property(nonatomic,readonly) CTTextAlignment effectiveTextAlignment;
@property(readonly) OUIEditableFrame *editor; // returns nil unless editable is YES
- (NSAttributedString *)_defaultStyleFormattedText;
- (CGFloat)_calculateTextBaselineForLayout:(OUITextLayout *)layout inRect:(CGRect)textRect;
- (OUITextLayout *)_labelTextLayout;
- (OUITextLayout *)_valueTextLayoutForWidth:(CGFloat)valueWidth;
- (void)_drawAttributedString:(NSAttributedString *)attributedString inRect:(CGRect)textRect;
- (void)_drawTextLayout:(OUITextLayout *)layout xPosition:(CGFloat)xPosition baseline:(CGFloat)baseline;
- (void)_tappedTextWell:(id)sender;
- (void)_updateEditorFrame;
@end

@implementation OUIInspectorTextWell

static id _commonInit(OUIInspectorTextWell *self)
{
    self.clearsContextBeforeDrawing = YES;
    self.opaque = NO;
    self.backgroundColor = nil;
    self.textColor = [OUIInspector labelTextColor];
    
    // Same defaults as for UITextInputTraits
    self.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    self.autocorrectionType = UITextAutocorrectionTypeDefault;
#if defined(__IPHONE_5_0) && (__IPHONE_5_0 <= __IPHONE_OS_VERSION_MAX_ALLOWED)
    self.spellCheckingType = UITextSpellCheckingTypeDefault;
#endif
    self.keyboardType = UIKeyboardTypeDefault;
    
    self->_style = OUIInspectorTextWellStyleDefault;
    self->_textAlignment = UITextAlignmentCenter;
    
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
    _editor.delegate = nil;
    [_editor release];
    [_editorContainerView release];
    [_text release];
    [_textColor release];
    [_font release];
    [_label release];
    [_labelFont release];
    [_placeholderText release];
    [_labelTextLayout release];
    [_valueTextLayout release];
    [super dealloc];
}

+ (UIFont *)defaultLabelFont;
{
    return [UIFont boldSystemFontOfSize:[[self class] fontSize]];
}

+ (UIFont *)defaultFont;
{
    return [UIFont systemFontOfSize:[[self class] fontSize]];
}

@synthesize style = _style;
- (void)setStyle:(OUIInspectorTextWellStyle)style;
{
    if (_style == style)
        return;
    
    OBASSERT(!self.editing); // We won't reposition the field editor right now, but we could if needed
    _style = style;
    
    [_labelTextLayout release];
    _labelTextLayout = nil;
    
    [_valueTextLayout release];
    _valueTextLayout = nil;
    
    [self setNeedsDisplay];
    return;
}


@synthesize editable = _editable;
- (void)setEditable:(BOOL)editable;
{
    if (_editable == editable)
        return;
    
    if (!editable && _editor) {
        [_editor resignFirstResponder];
        [_editor removeFromSuperview];
        _editor.delegate = nil;
        [_editor release];
        _editor = nil;

        [_editorContainerView removeFromSuperview];
        [_editorContainerView release];
        _editorContainerView = nil;
    }
    
    _editable = editable;
    
    if (_editable)
        [self addTarget:self action:@selector(_tappedTextWell:) forControlEvents:UIControlEventTouchUpInside];
    else
        [self removeTarget:self action:@selector(_tappedTextWell:) forControlEvents:UIControlEventTouchUpInside];
}

- (BOOL)editing;
{
    return (_editor && _editorContainerView && _editor.superview == _editorContainerView);
}

static CTTextAlignment _ctAlignemntForAlignment(UITextAlignment align)
{    
    // UITextAlignment only has three options and they aren't identical values to the CT version... maybe our property should be a CTTextAlignment
    switch (align) {
        case UITextAlignmentRight:
            return kCTRightTextAlignment;
        case UITextAlignmentCenter:
            return kCTCenterTextAlignment;
        case UITextAlignmentLeft:
        default:
            return kCTLeftTextAlignment;
    }
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

static CTFontRef _copyFont(OUIInspectorTextWell *self, UIFont *font, TextType type)
{
    if (!font)
        font = _defaultFontForType(self, type);
    return CTFontCreateWithName((CFStringRef)[font fontName], [font pointSize], NULL);
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
    }
    if (outType)
        *outType = textType;
    return text;
}

- (NSAttributedString *)_attributedStringForEditingString:(NSString *)aString;
{
    // We don't want to edit the placeholder text, so don't use _getText().
    if (!aString)
        aString = @"";
    TextType textType = TextTypeValue;
    
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:aString attributes:nil];
    {
        CTFontRef font = _copyFont(self, _font, textType);
        _setAttr(attributedText, (id)kCTFontAttributeName, (id)font);
        CFRelease(font);
    }
    
    UIColor *textColor = textType == TextTypePlaceholder ? [OUIInspector disabledLabelTextColor] : [self textColor];
    _setAttr(attributedText, (id)kCTForegroundColorAttributeName, (id)[textColor CGColor]);
    
    OBASSERT(_editor); // use the paragraph style already set up when the editor was created
    CTParagraphStyleRef pgStyle = _editor.defaultCTParagraphStyle;
    if (pgStyle) {
        _setAttr(attributedText, (id)kCTParagraphStyleAttributeName, (id)pgStyle);
    }
    
    [attributedText autorelease];
    
    return attributedText;
}

- (NSString *)editingText;
{
    OBPRECONDITION(self.editing);
    return [_editor.attributedText string];
}

- (void)setEditingText:(NSString *)editingText;
{
    OBPRECONDITION(self.editing);

    _editor.attributedText = [self _attributedStringForEditingString:editingText];
}

@synthesize autocapitalizationType = _autocapitalizationType;
@synthesize autocorrectionType = _autocorrectionType;
#if defined(__IPHONE_5_0) && (__IPHONE_5_0 <= __IPHONE_OS_VERSION_MAX_ALLOWED)
@synthesize spellCheckingType = _spellCheckingType;
#endif
@synthesize keyboardType = _keyboardType;

- (CTTextAlignment)effectiveTextAlignment
{
    return _style == OUIInspectorTextWellStyleSeparateLabelAndText ? kCTRightTextAlignment : _ctAlignemntForAlignment(_textAlignment);
}

- (OUIEditableFrame *)editor;
{
    if (_editable && !_editor) {
        _editor = [[OUIInspectorTextWellEditor alloc] initWithFrame:CGRectZero];
        _editor.delegate = self;
        _editor.textColor = [self textColor];
        
        // Set up the default paragraph alignment for when the editor's text storage is empty. Also, when we make editing text, this will be used for the alignment.
        {
            CTTextAlignment align = self.effectiveTextAlignment;
            CTParagraphStyleSetting setting = {
                kCTParagraphStyleSpecifierAlignment, sizeof(align), &align
            };
            
            CTParagraphStyleRef pgStyle = CTParagraphStyleCreate(&setting, 1);
            _editor.defaultCTParagraphStyle = pgStyle;
            CFRelease(pgStyle);
        }
    }
    return _editor;
}

@synthesize textAlignment = _textAlignment;
- (void)setTextAlignment:(UITextAlignment)textAlignment;
{
    if (_textAlignment == textAlignment)
        return;
    
    _textAlignment = textAlignment;
    OBASSERT(!self.editing); // could need to mess with the editor's contents

    [self setNeedsDisplay];
}

- (NSString *)text;
{
    return _text;
}
- (void)setText:(NSString *)text;
{
    if (_text == text)
        return;

    [_text release];
    _text = [text copy];
    
    [_valueTextLayout release];
    _valueTextLayout = nil;

    [self setNeedsDisplay];
}

@synthesize textColor = _textColor;
- (void)setTextColor:(UIColor *)textColor;
{
    if (_textColor == textColor)
        return;
    [_textColor release];
    _textColor = [textColor retain];
    
    [_valueTextLayout release];
    _valueTextLayout = nil;

    [self setNeedsDisplay];
}

- (UIFont *)font;
{
    return _font;
}
- (void)setFont:(UIFont *)font;
{
    if (_font == font)
        return;

    [_font release];
    _font = [font retain];

    [_valueTextLayout release];
    _valueTextLayout = nil;

    [self setNeedsDisplay];
}

@synthesize label = _label;
- (void)setLabel:(NSString *)label;
{
    if (_label == label)
        return;
    
    [_label release];
    _label = [label copy];
    
    [_labelTextLayout release];
    _labelTextLayout = nil;
    
    [self setNeedsDisplay];
    
    OBASSERT(!self.editing); // Otherwise we'd need to adjust the space available to the field editor (via -setNeedsLayout) if we were using OUIInspectorTextWellStyleSeparateLabelAndText
}

@synthesize labelFont = _labelFont;
- (void)setLabelFont:(UIFont *)labelFont;
{
    if (_labelFont == labelFont)
        return;

    [_labelFont release];
    _labelFont = [labelFont retain];

    [_labelTextLayout release];
    _labelTextLayout = nil;

    [self setNeedsDisplay];
    
    OBASSERT(!self.editing); // Otherwise we'd need to adjust the space available to the field editor (via -setNeedsLayout) if we were using OUIInspectorTextWellStyleSeparateLabelAndText
}

@synthesize placeholderText = _placeholderText;
- (void)setPlaceholderText:(NSString *)placeholderText;
{
    if (OFISEQUAL(_placeholderText, placeholderText))
        return;
    
    [_placeholderText release];
    _placeholderText = [placeholderText copy];
    
    if ([NSString isEmptyString:_text]) {
        [_valueTextLayout release];
        _valueTextLayout = nil;
    }
    
    [self setNeedsDisplay];
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

#pragma mark -
#pragma mark UIView subclass

typedef struct {
    CGRect labelRect, valueRect;
} OUIInspectorTextWellLayout;

static OUIInspectorTextWellLayout _layout(OUIInspectorTextWell *self)
{
    OBPRECONDITION(self->_style == OUIInspectorTextWellStyleSeparateLabelAndText);
    
    OUIInspectorTextWellLayout layout;
    memset(&layout, 0, sizeof(layout));

    CGRect dummy;
    
    OUITextLayout *labelLayout = [self _labelTextLayout];
    CGFloat labelWidth = ceil(labelLayout.usedSize.width);
    
    CGRect contentsRect = self.contentsRect; // This will already have insets for the left/right margin.
    
    CGRectDivide(contentsRect, &layout.labelRect, &layout.valueRect, ceil(labelWidth), CGRectMinXEdge); // label
    CGRectDivide(layout.valueRect, &dummy, &layout.valueRect, 8, CGRectMinXEdge); // label-value margin
    
    return layout;
}

- (void)drawRect:(CGRect)rect;
{
    [super drawRect:rect]; // The background
        
    switch (_style) {
        case OUIInspectorTextWellStyleSeparateLabelAndText: {
            OUIInspectorTextWellLayout layout = _layout(self);
            
            CGFloat baseline = [self _calculateTextBaselineForLayout:[self _labelTextLayout] inRect:layout.labelRect];
                        
            [self _drawTextLayout:[self _labelTextLayout] xPosition:layout.labelRect.origin.x baseline:baseline];
            
            if (!self.editing || _shouldDisplayPlaceholderText)
                [self _drawTextLayout:[self _valueTextLayoutForWidth:layout.valueRect.size.width] xPosition:layout.valueRect.origin.x baseline:baseline];

            break;
        }
        case OUIInspectorTextWellStyleDefault:
            // Draw the text if we aren't editing. If we are, the text field subview will be drawing it.
            if (!self.editing) {
                // Center the text across the whole bounds, even if we have a nav arrow chopping off part of it. But if we are right or left aligned just use the contents rect (since we are probably trying to avoid a left/right view.
                CGRect drawRect;
                if (_textAlignment == UITextAlignmentCenter)
                    drawRect = self.bounds;
                else
                    drawRect = self.contentsRect;
                [self _drawAttributedString:[self _defaultStyleFormattedText] inRect:drawRect];
            }
            break;
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    UIView *hit = [super hitTest:point withEvent:event];
    
    if (hit == nil && self.editing)
        // Let the field editor have a chance. It may have subviews that are outside our bounds (for autocorrection).
        hit = [_editor hitTest:[self convertPoint:point toView:_editor] withEvent:event];

    return hit;
}

#pragma mark -
#pragma mark OUIEditableFrameDelegate

- (void)textViewContentsChanged:(OUIEditableFrame *)textView;
{
    BOOL flag = [NSString isEmptyString:[[textView attributedText] string]];
    
    if (flag != _shouldDisplayPlaceholderText) {
        _shouldDisplayPlaceholderText = flag;
        // if we have a text string set we are going to have to force layout again so that we can properly display the placeholder attributed string.
        if (_shouldDisplayPlaceholderText && _text && _text.length > 0) {
            [_valueTextLayout release];
            _valueTextLayout = nil;
        }
        [self setNeedsDisplay];
    }

    [self _updateEditorFrame];
    [self sendActionsForControlEvents:UIControlEventEditingChanged];
}

- (void)textViewSelectionChanged:(OUIEditableFrame *)textView;
{
    // Make sure the selection is on screen if the contents are too wide to all fit at the same time
    if (textView.window == nil) {
        // Not on screen yet -- just getting set up. Don't ask layout questions until the rest of the setup is done.
    } else {
        [self _updateEditorFrame];
    }
}

- (BOOL)textView:(OUIEditableFrame *)textView shouldInsertText:(NSString *)text;
{
    OBPRECONDITION(textView == _editor);
    
    if ([text containsString:@"\n"]) {
        // Hitting return; act like a field editor and end editing.
        
        // We don't have autocorrect on in at least some cases, but if we do, we have to do this after a delay. Otherwise, if there *is* an auto-correction widget up on the text editor, it will have already done its autocorrection and then when we tell it to end editing, it will do it again!
        // <bug:///72342> (Tapping return when autocomplete is up appends the substitution after your typed string)
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [_editor resignFirstResponder];
            
            // TODO: This means we'll end up sending both UIControlEventEditingDidEnd and UIControlEventEditingDidEndOnExit. Does UITextField?
            [self sendActionsForControlEvents:UIControlEventEditingDidEndOnExit];
        }];

        return NO;
    }
    return YES;
}

- (void)textViewDidEndEditing:(OUIEditableFrame *)textView;
{
    OBPRECONDITION(textView == _editor);
    NSString *text = [[_editor attributedText] string];
    _shouldDisplayPlaceholderText = NO;
    
    [_editor removeFromSuperview];
    _editor.delegate = nil;
    [_editor autorelease]; // Do NOT call -release here or we'll zombie if the editor is first responder in a popover when the popover is closed. They have a pointer to the view up the call stack from here.
    _editor = nil;
    
    [_editorContainerView removeFromSuperview];
    [_editorContainerView release];
    _editorContainerView = nil;
    
    // Let subclasses validate the text and provide a replacement. We should probably have a delegate with an optional -textWell:willCommitEditingText: too.
    text = [self willCommitEditingText:text];
    
    if (OFNOTEQUAL(text, _text)) {
        self.text = text;
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
    
    // start displaying again.
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark Private

- (NSAttributedString *)_defaultStyleFormattedText;
{
    OBPRECONDITION(_style == OUIInspectorTextWellStyleDefault);
    
    TextType textType;
    NSString *text = _getText(self, _text, &textType);

    NSMutableAttributedString *attrText = [[NSMutableAttributedString alloc] initWithString:text attributes:nil];
    {
        CTFontRef font = _copyFont(self, _font, textType);
        _setAttr(attrText, (id)kCTFontAttributeName, (id)font);
        CFRelease(font);
    }
    
    if (_label && textType != TextTypePlaceholder) {
        NSMutableAttributedString *attrFormat = [[NSMutableAttributedString alloc] initWithString:_label ? _label : @"" attributes:nil];
        CTFontRef font = _copyFont(self, _labelFont ? _labelFont : _font, TextTypeLabel);
        _setAttr(attrFormat, (id)kCTFontAttributeName, (id)font);
        CFRelease(font);
        
        // If there is a '%@', find it and put the text there. Otherwise, append the text.
        NSRange valueRange = [_label rangeOfString:@"%@"];
        if (valueRange.location == NSNotFound)
            valueRange = NSMakeRange([_label length], 0);
        [attrFormat replaceCharactersInRange:valueRange withAttributedString:attrText];
        
        [attrText release];
        attrText = attrFormat;
    }
    
    UIColor *textColor = textType == TextTypePlaceholder ? [OUIInspector disabledLabelTextColor] : [self textColor];
    _setAttr(attrText, (id)kCTForegroundColorAttributeName, (id)[textColor CGColor]);
    
    // Align the text horizontally and truncate instead of wrapping.
    {
        CTTextAlignment ctAlignment = self.effectiveTextAlignment;
        CTLineBreakMode lineBreak = kCTLineBreakByTruncatingTail;

        CTParagraphStyleSetting setting[] = {
            {kCTParagraphStyleSpecifierAlignment, sizeof(ctAlignment), &ctAlignment},
            {kCTParagraphStyleSpecifierLineBreakMode, sizeof(lineBreak), &lineBreak},
        };
        
        CTParagraphStyleRef pgStyle = CTParagraphStyleCreate(setting, sizeof(setting)/sizeof(*setting));
        _setAttr(attrText, (id)kCTParagraphStyleAttributeName, (id)pgStyle);
        CFRelease(pgStyle);
    }
    
    [attrText autorelease];
    
    return attrText;
}

- (OUITextLayout *)_labelTextLayout;
{
    OBPRECONDITION(_style == OUIInspectorTextWellStyleSeparateLabelAndText);
    OBPRECONDITION(![NSString isEmptyString:_label]);
    
    if (!_labelTextLayout) {
        NSMutableAttributedString *attrLabel = [[NSMutableAttributedString alloc] initWithString:_label ? _label : @"" attributes:nil];
        CTFontRef font = _copyFont(self, _labelFont ? _labelFont : _font, TextTypeLabel);
        _setAttr(attrLabel, (id)kCTFontAttributeName, (id)font);
        CFRelease(font);
        
        UIColor *textColor = [self textColor];
        _setAttr(attrLabel, (id)kCTForegroundColorAttributeName, (id)[textColor CGColor]);
        
        _labelTextLayout = [[OUITextLayout alloc] initWithAttributedString:attrLabel constraints:CGSizeMake(OUITextLayoutUnlimitedSize, OUITextLayoutUnlimitedSize)];
        [attrLabel autorelease];
    }
    
    return _labelTextLayout;
}

// We have to format this for a given width for right-alignment to work. An OUITextLayoutUnlimitedSize width will make the text layout use the minimum width possible.
- (OUITextLayout *)_valueTextLayoutForWidth:(CGFloat)valueWidth;
{
    OBPRECONDITION(_style == OUIInspectorTextWellStyleSeparateLabelAndText);
    
    if (_valueTextWidth != valueWidth) {
        [_valueTextLayout release];
        _valueTextLayout = nil;
    }
    
    if (!_valueTextLayout) {
        TextType textType;
        NSString *text = _getText(self, _text, &textType);
        if (_shouldDisplayPlaceholderText)
            textType = TextTypePlaceholder;

        NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:text attributes:nil];
        CTFontRef font = _copyFont(self, _font, textType);
        _setAttr(attrString, (id)kCTFontAttributeName, (id)font);
        CFRelease(font);
        
        UIColor *textColor = textType == TextTypePlaceholder ? [OUIInspector disabledLabelTextColor] : [self textColor];
        _setAttr(attrString, (id)kCTForegroundColorAttributeName, (id)[textColor CGColor]);
        
        // Right align and tail truncate the text
        {
            CTTextAlignment right = kCTRightTextAlignment;
            CTLineBreakMode lineBreak = kCTLineBreakByTruncatingTail;
            CTParagraphStyleSetting setting[] = {
                {kCTParagraphStyleSpecifierAlignment, sizeof(right), &right},
                {kCTParagraphStyleSpecifierLineBreakMode, sizeof(lineBreak), &lineBreak},
            };
            
            CTParagraphStyleRef pgStyle = CTParagraphStyleCreate(setting, sizeof(setting)/sizeof(*setting));
            _setAttr(attrString, (id)kCTParagraphStyleAttributeName, (id)pgStyle);
            CFRelease(pgStyle);
        }

        _valueTextLayout = [[OUITextLayout alloc] initWithAttributedString:attrString constraints:CGSizeMake(valueWidth, OUITextLayoutUnlimitedSize)];
        [attrString autorelease];

        _valueTextWidth = valueWidth;
    }
    
    return _valueTextLayout;
}

- (CGFloat)_calculateTextBaselineForLayout:(OUITextLayout *)layout inRect:(CGRect)textRect;
{
    CGSize usedSize = layout.usedSize;
    
    // We center the text vertically, but let the attributedString's paragraph style control horizontal alignment.
    textRect.origin.y += 0.5 * (CGRectGetHeight(textRect) - usedSize.height);
    textRect.origin.y = floor(textRect.origin.y);
    
    return CGRectGetMinY(textRect) + [layout firstLineAscent];
}

- (void)_drawAttributedString:(NSAttributedString *)attributedString inRect:(CGRect)textRect;
{
    OUITextLayout *layout = [[OUITextLayout alloc] initWithAttributedString:attributedString constraints:CGSizeMake(CGRectGetWidth(textRect), OUITextLayoutUnlimitedSize)];
    [self _drawTextLayout:layout xPosition:textRect.origin.x baseline:[self _calculateTextBaselineForLayout:layout inRect:textRect]];
    [layout release];
}

- (void)_drawTextLayout:(OUITextLayout *)layout xPosition:(CGFloat)xPosition baseline:(CGFloat)baseline;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect textRect;

    // figure out where the baseline was when we did this for the label text & align w/ the baseline for the value text.
    textRect.origin.y = baseline - [layout firstLineAscent];
    textRect.origin.x = xPosition;
    textRect.size.width = 0;
    textRect.size.height = 0;
    
    [layout drawFlippedInContext:ctx bounds:textRect];
}

- (void)_tappedTextWell:(id)sender;
{
    // Can tap the area above/below the text field. Don't restart editing if that happens.
    if (self.editing)
        return;
    
    // Move ourselves to the top of our peer subviews. Otherwise, text widgets can end up being clipped by peer views, see <bug:///72491> (Autocorrect/Kanji selection difficult in Column & Style Name fields entering Japanese with BT keyboard)
    [[self superview] bringSubviewToFront:self];
    
    // turn off display while editing.
    [self setNeedsDisplay];
        
    OUIEditableFrame *editor = self.editor; // creates if needed

    // Set this as the default instead of on the attributed string in case we start out with zero length text.
    UIFont *font = [self font] ? [self font] : [UIFont systemFontOfSize:[OUIInspectorTextWell fontSize]];
    if (font) {
        CTFontRef ctFont = CTFontCreateWithName((CFStringRef)font.fontName, font.pointSize, NULL);
        editor.defaultCTFont = ctFont;
        if (ctFont)
            CFRelease(ctFont);
    } else {
        editor.defaultCTFont = NULL;
    }

    _editorContainerView = [[UIView alloc] init];
    //_editorContainerView.clipsToBounds = YES; Can't do this since it lops off the UITextInput correction dingus.
    
    TextType textType;
    _getText(self, _text, &textType);
    _shouldDisplayPlaceholderText = (textType == TextTypePlaceholder);
    editor.autocapitalizationType = self.autocapitalizationType;
    editor.autocorrectionType = self.autocorrectionType;
#if defined(__IPHONE_5_0) && (__IPHONE_5_0 <= __IPHONE_OS_VERSION_MAX_ALLOWED)
    editor.spellCheckingType = self.spellCheckingType;
#endif
    editor.keyboardType = self.keyboardType;
    editor.opaque = NO;
    editor.backgroundColor = nil;
    
    editor.attributedText = [self _attributedStringForEditingString:_text];
    
    [_editorContainerView addSubview:editor];
    [self addSubview:_editorContainerView];
    
    [self _updateEditorFrame];
    
    [editor becomeFirstResponder];

    [self sendActionsForControlEvents:UIControlEventEditingDidBegin];
}

- (void)_updateEditorFrame;
{
    OBPRECONDITION(_editor);
    
    // Hacky constants...
    static const CGFloat kEditorInsetX = 3; // Give room to avoid clipping the insertion point at the extreme left/right edge.
    static const CGFloat kEditorInsetY = 2; // The top/bottom also need a little extra since the insertion point goes above/below the glyphs.

    // Position/size our containing clip view
    {
        CGRect valueRect;
        if (_style == OUIInspectorTextWellStyleSeparateLabelAndText) {
            OUIInspectorTextWellLayout layout = _layout(self);
            valueRect = layout.valueRect;
        } else {
            valueRect = self.contentsRect;
        }
        
        _editorContainerView.frame = CGRectInset(valueRect, -kEditorInsetX, -kEditorInsetY);
        _editor.textInset = UIEdgeInsetsMake(kEditorInsetY/*top*/, kEditorInsetX/*left*/, kEditorInsetY/*bottom*/, kEditorInsetX/*right*/); // TODO: Assumes zero scale
    }
    
#ifdef DEBUG_EDITOR_FRAME_ENABLED
    _editorContainerView.layer.borderColor = [[UIColor colorWithRed:0.5 green:1 blue:0.5 alpha:0.75] CGColor];
    _editorContainerView.layer.borderWidth = 1;
    DEBUG_EDITOR_FRAME(@"_editorContainerView = %@", _editorContainerView);
    
    _editor.backgroundColor = [UIColor colorWithRed:1 green:0.5 blue:0.5 alpha:0.25];
    
    DEBUG_EDITOR_FRAME(@"_editor = %@", _editor);
#endif
    
    /*
     Position the editor w/in the clip view.

     Right alignment won't work if we use unlimited width layout size on the editor and if the editor frame isn't tightly packing the text. The issue is that 'unlimited' means OUIEditableFrame/OUITextLayout gives CoreText a huge width, lay out in that, and then layout again with the right width. Thus, the text will be right-aligned within the _used width_, but with only a single line this isn't apparent. So, we have to do the major positioning of the frame here with the guts possibly doing some fine positioning.
     But, tightly bounding the used size doesn't work EITHER since then the autocorrection dingus wants to only be as wide as the text view (so the corrections come up truncated since the dingus is too narrow).
     
     So: we set the layout size to unlimited, figure out how much size was used and then turn the limit back on and use at least the clip width.
     
     */
    _editor.textLayoutSize = CGSizeMake(OUITextLayoutUnlimitedSize, OUITextLayoutUnlimitedSize); // No real reason to limit the height, but we could if needed...
    CGSize usedSize = _editor.viewUsedSize;
    _editor.textLayoutSize = CGSizeMake(0, 0); // default of current width, infinite height
    DEBUG_EDITOR_FRAME(@"usedSize = %@", NSStringFromCGSize(usedSize));
    
    CGRect clipBounds = _editorContainerView.bounds;
    
    CGRect editorFrame;
    editorFrame.origin.x = clipBounds.origin.x;
    editorFrame.origin.y = floor(CGRectGetMinY(clipBounds) + 0.5 * (CGRectGetHeight(clipBounds) - usedSize.height));
    editorFrame.size.width = MAX(clipBounds.size.width, ceil(usedSize.width));
    editorFrame.size.height = ceil(usedSize.height);
    
    // Provisionally assign the nominal frame (w/o the offset) so the rect conversions below give us something predictable.
    _editor.frame = editorFrame;

    // Shift the frame so that the first selection rect will be in view. If it is too big to all fit, we may want to prefer the left/right edge based on the text direction at the first point (or whatever).
    // Also, try to keep the same offset if possible, but if the text has gotten shorter (deleting text), we may want to readjust to make sure we are showing as much of the editor as possible.
    
    if (editorFrame.size.width > clipBounds.size.width) {
        CGRect selectionRect = [_editorContainerView convertRect:[_editor firstRectForRange:[_editor selectedTextRange]] fromView:_editor];
        OBASSERT(!CGRectIsNull(selectionRect));
        DEBUG_EDITOR_FRAME(@"selectionRect = %@", NSStringFromCGRect(selectionRect));
        
        CGFloat leftOffset = CGRectGetMinX(selectionRect) - (CGRectGetMinX(clipBounds) + kEditorInsetX); // aligns left edge of selection with left edge of frame
        CGFloat rightOffset = MAX(0, CGRectGetMaxX(selectionRect) - (CGRectGetMaxX(clipBounds) - kEditorInsetX)); // aligns right edge of selection with right edge of frame
        DEBUG_EDITOR_FRAME(@"leftOffset %f, rightOffset %f", leftOffset, rightOffset);
        
        // We should only shift the editor to the left -- if you move the cursor to the visually right-most position in the editor should just have bounds.origin.x = 0.
        OBASSERT(leftOffset >= 0);
        OBASSERT(rightOffset >= 0);
        
        if (CGRectGetMaxX(editorFrame) - _editorXOffset < CGRectGetMaxX(clipBounds)) {
            // We're wider than our clip area, but our right edge is leaving some clip area uncovered by our editor. Maybe the user deleted some text at the end after having scrolled over.
            _editorXOffset = rightOffset;
        }
        
        OFExtent allowedOffsetExtent = OFExtentFromLocations(leftOffset, rightOffset);
        DEBUG_EDITOR_FRAME(@"allowedOffsetExtent %@", OFExtentToString(allowedOffsetExtent));
        
        // Shift as little as possible
        _editorXOffset = OFExtentClampValue(allowedOffsetExtent, _editorXOffset);
        OBASSERT(_editorXOffset >= 0);
    } else {
        // The entire view will fit. The normal text alignment will handle it.
        _editorXOffset = 0;
    }
    DEBUG_EDITOR_FRAME(@"_editorXOffset = %f", _editorXOffset);

    editorFrame.origin.x = round(editorFrame.origin.x - _editorXOffset);
    DEBUG_EDITOR_FRAME(@"editorFrame = %@", NSStringFromCGRect(editorFrame));

    _editor.frame = editorFrame;
    _editor.clipRect = [_editor convertRect:clipBounds fromView:_editorContainerView];
    DEBUG_EDITOR_FRAME(@"_editor.clipRect = %@", NSStringFromCGRect(_editor.clipRect));
}

@end
