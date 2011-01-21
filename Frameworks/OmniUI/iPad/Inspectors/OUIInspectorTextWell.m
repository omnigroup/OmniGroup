// Copyright 2010-2011 The Omni Group.  All rights reserved.
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

#import "OUIParameters.h"

RCS_ID("$Id$");

@interface OUIInspectorTextWell (/*Private*/) <OUIEditableFrameDelegate>
@property(readonly) OUIEditableFrame *editor; // returns nil unless editable is YES
- (NSAttributedString *)_defaultStyleFormattedText;
- (OUITextLayout *)_labelTextLayout;
- (OUITextLayout *)_valueTextLayoutForWidth:(CGFloat)valueWidth;
- (void)_drawAttributedString:(NSAttributedString *)attributedString inRect:(CGRect)textRect;
- (void)_drawTextLayout:(OUITextLayout *)textLayout inRect:(CGRect)textRect;
- (void)_tappedTextWell:(id)sender;
@end

@implementation OUIInspectorTextWell

static id _commonInit(OUIInspectorTextWell *self)
{
    self.clearsContextBeforeDrawing = YES;
    self.opaque = NO;
    self.backgroundColor = nil;
    self.keyboardType = UIKeyboardTypeDefault;
    
    self->_style = OUIInspectorTextWellStyleDefault;
    
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
    [_text release];
    [_font release];
    [_label release];
    [_labelFont release];
    [_labelTextLayout release];
    [_valueTextLayout release];
    [super dealloc];
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
    }
    
    _editable = editable;
    
    if (_editable)
        [self addTarget:self action:@selector(_tappedTextWell:) forControlEvents:UIControlEventTouchUpInside];
    else
        [self removeTarget:self action:@selector(_tappedTextWell:) forControlEvents:UIControlEventTouchUpInside];
}

- (BOOL)editing;
{
    return (_editor.superview == self);
}

- (NSString *)editingText;
{
    OBPRECONDITION(self.editing);
    return [_editor.attributedText string];
}

- (void)setEditingText:(NSString *)editingText;
{
    OBPRECONDITION(self.editing);

    NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:editingText ? editingText : @"" attributes:nil];
    _editor.attributedText = attributedText;
    [attributedText release];
}

@synthesize keyboardType;

- (OUIEditableFrame *)editor;
{
    if (_editable && !_editor) {
        _editor = [[OUIEditableFrame alloc] initWithFrame:CGRectZero];
        _editor.delegate = self;
        _editor.textColor = [[self class] textColor];
    }
    return _editor;
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

- (NSString *)willCommitEditingText:(NSString *)editingText;
{
    return editingText;
}

static CTFontRef _copyFont(UIFont *font)
{
    if (!font)
        font = [UIFont systemFontOfSize:[UIFont labelFontSize]];
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
                        
            [self _drawTextLayout:[self _labelTextLayout] inRect:layout.labelRect];
            
            if (!self.editing)
                [self _drawTextLayout:[self _valueTextLayoutForWidth:layout.valueRect.size.width] inRect:layout.valueRect];
            
            break;
        }
        case OUIInspectorTextWellStyleDefault:
            // Draw the text if we aren't editing. If we are, the text field subview will be drawing it.
            if (!self.editing) {
                // Center the text across the whole bounds, even if we have a nav arrow chopping off part of it
                [self _drawAttributedString:[self _defaultStyleFormattedText] inRect:self.bounds];
            }
            break;
    }
}

#pragma mark -
#pragma mark OUIEditableFrameDelegate

- (BOOL)textView:(OUIEditableFrame *)textView shouldInsertText:(NSString *)text;
{
    OBPRECONDITION(textView == _editor);
    
    if ([text containsString:@"\n"]) {
        // Hitting return; act like a field editor.
        [_editor resignFirstResponder];
        return NO;
    }
    return YES;
}

- (void)textViewDidEndEditing:(OUIEditableFrame *)textView;
{
    OBPRECONDITION(textView == _editor);
    
    NSString *text = [[_editor attributedText] string];
    
    [_editor removeFromSuperview];
    _editor.delegate = nil;
    [_editor autorelease]; // Do NOT call -release here or we'll zombie if the editor is first responder in a popover when the popover is closed. They have a pointer to the view up the call stack from here.
    _editor = nil;
    
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
    
    // Add a customizable placeholder?  Only do this if we are doing a substring formatting replacement?
    NSString *text = [NSString isEmptyString:_text] ? @"–" : _text;
    
    NSMutableAttributedString *attrText = [[NSMutableAttributedString alloc] initWithString:text attributes:nil];
    {
        CTFontRef font = _copyFont(_font);
        _setAttr(attrText, (id)kCTFontAttributeName, (id)font);
        CFRelease(font);
    }
    
    if (_label) {
        NSMutableAttributedString *attrFormat = [[NSMutableAttributedString alloc] initWithString:_label ? _label : @"" attributes:nil];
        CTFontRef font = _copyFont(_labelFont ? _labelFont : _font);
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
    
    UIColor *textColor = [self textColor];
    
    _setAttr(attrText, (id)kCTForegroundColorAttributeName, (id)[textColor CGColor]);
    
    
    // Center the text horizontally.
    {
        CTTextAlignment centered = kCTCenterTextAlignment;
        CTParagraphStyleSetting setting = {
            kCTParagraphStyleSpecifierAlignment, sizeof(centered), &centered
        };
        
        CTParagraphStyleRef pgStyle = CTParagraphStyleCreate(&setting, 1);
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
        CTFontRef font = _copyFont(_labelFont ? _labelFont : _font);
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
        NSString *text = _text ? _text : @"";
        NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:text attributes:nil];
        CTFontRef font = _copyFont(_font);
        _setAttr(attrString, (id)kCTFontAttributeName, (id)font);
        CFRelease(font);
        
        UIColor *textColor = [self textColor];
        _setAttr(attrString, (id)kCTForegroundColorAttributeName, (id)[textColor CGColor]);
        
        // Right align the text
        {
            CTTextAlignment right = kCTRightTextAlignment;
            CTParagraphStyleSetting setting = {
                kCTParagraphStyleSpecifierAlignment, sizeof(right), &right
            };
            
            CTParagraphStyleRef pgStyle = CTParagraphStyleCreate(&setting, 1);
            _setAttr(attrString, (id)kCTParagraphStyleAttributeName, (id)pgStyle);
            CFRelease(pgStyle);
        }

        _valueTextLayout = [[OUITextLayout alloc] initWithAttributedString:attrString constraints:CGSizeMake(valueWidth, OUITextLayoutUnlimitedSize)];
        [attrString autorelease];

        _valueTextWidth = valueWidth;
    }
    
    return _valueTextLayout;
}

- (void)_drawAttributedString:(NSAttributedString *)attributedString inRect:(CGRect)textRect;
{
    OUITextLayout *layout = [[OUITextLayout alloc] initWithAttributedString:attributedString constraints:CGSizeMake(CGRectGetWidth(textRect), OUITextLayoutUnlimitedSize)];
    [self _drawTextLayout:layout inRect:textRect];
    [layout release];
}

- (void)_drawTextLayout:(OUITextLayout *)layout inRect:(CGRect)textRect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    CGSize usedSize = layout.usedSize;
        
    // We center the text vertically, but let the attributedString's parapgraph style control horizontal alignment.
    if (usedSize.height < CGRectGetHeight(textRect)) {
        textRect.origin.y += 0.5 * (CGRectGetHeight(textRect) - usedSize.height);
        textRect.origin.y = floor(textRect.origin.y);
    }
    
    [layout drawFlippedInContext:ctx bounds:textRect];
}

- (void)_tappedTextWell:(id)sender;
{
    // Can tap the area above/below the text field. Don't restart editing if that happens.
    if (self.editing)
        return;
    
    
    // turn off display while editing.
    [self setNeedsDisplay];
        
    OUIEditableFrame *editor = self.editor; // creates if needed

    // Set this as the default instead of on the attributed string in case we start out with zero length text.
    UIFont *font = self.font;
    if (font) {
        CTFontRef ctFont = CTFontCreateWithName((CFStringRef)font.fontName, font.pointSize, NULL);
        editor.defaultCTFont = ctFont;
        if (ctFont)
            CFRelease(ctFont);
    } else {
        editor.defaultCTFont = NULL;
    }
    
    editor.keyboardType = self.keyboardType;
    editor.opaque = NO;
    editor.backgroundColor = nil;
    
    // Align the text
    {
        CTTextAlignment align = _style == OUIInspectorTextWellStyleSeparateLabelAndText ? kCTRightTextAlignment : kCTCenterTextAlignment;
        CTParagraphStyleSetting setting = {
            kCTParagraphStyleSpecifierAlignment, sizeof(align), &align
        };
        
        CTParagraphStyleRef pgStyle = CTParagraphStyleCreate(&setting, 1);
        editor.defaultCTParagraphStyle = pgStyle;
        CFRelease(pgStyle);
    }
    
    NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:_text ? _text : @"" attributes:nil];
    editor.attributedText = attributedText;
    [attributedText release];
    
    CGRect valueRect;
    if (_style == OUIInspectorTextWellStyleSeparateLabelAndText) {
        OUIInspectorTextWellLayout layout = _layout(self);
        valueRect = layout.valueRect;
    } else {
        valueRect = self.contentsRect;
    }
    
    editor.textLayoutSize = CGSizeMake(CGRectGetWidth(valueRect), OUITextLayoutUnlimitedSize);
    
    CGSize usedSize = editor.viewUsedSize;
    CGRect editorFrame;
    
    editorFrame.origin.y = floor(CGRectGetMinY(valueRect) + 0.5 * (CGRectGetHeight(valueRect) - usedSize.height));
    editorFrame.origin.x = valueRect.origin.x;
    editorFrame.size.width = valueRect.size.width;
    editorFrame.size.height = ceil(usedSize.height);
    editor.frame = editorFrame;
    
    [self addSubview:editor];
    
    [editor becomeFirstResponder];
}

@end
