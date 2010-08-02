// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIInspectorTextWell.h"

#import "OUIInspectorWell.h"

#import <CoreText/CoreText.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/OmniBase.h>
#import <Foundation/Foundation.h>
#import <Foundation/NSAttributedString.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFNull.h>

RCS_ID("$Id$");

@interface OUIInspectorTextWell (/*Private*/)
- (void)_tappedTextWell:(id)sender;
@end

@implementation OUIInspectorTextWell

static CGGradientRef NormalGradient = NULL;
static CGGradientRef HighlightedGradient = NULL;

static BOOL _drawHighlighed(OUIInspectorTextWell *self)
{
    return !self.enabled || (self.highlighted && ([self allControlEvents] != 0));
}

+ (void)initialize;
{
    OBINITIALIZE;
        
    {
        UIColor *topColor = [UIColor colorWithHue:64.0/360.0 saturation:0.17 brightness:0.78 alpha:1.0];
        UIColor *bottomColor = [UIColor colorWithHue:60.0/360.0 saturation:0.10 brightness:0.94 alpha:1.0];
        NormalGradient = CGGradientCreateWithColors(NULL/*colorSpace*/, (CFArrayRef)[NSArray arrayWithObjects:(id)[topColor CGColor], (id)[bottomColor CGColor], nil], NULL);
    }
    
    {
        UIColor *topColor = [UIColor colorWithHue:64.0/360.0 saturation:0.17 brightness:0.48 alpha:1.0];
        UIColor *bottomColor = [UIColor colorWithHue:60.0/360.0 saturation:0.10 brightness:0.64 alpha:1.0];
        HighlightedGradient = CGGradientCreateWithColors(NULL/*colorSpace*/, (CFArrayRef)[NSArray arrayWithObjects:(id)[topColor CGColor], (id)[bottomColor CGColor], nil], NULL);
    }
    
}

+ (CGFloat)fontSize;
{
    return 18;
}

+ (UIFont *)italicFormatFont;
{
    return [UIFont fontWithName:@"HoeflerText-Italic" size:[self fontSize]];
}

+ (UIColor *)textColor;
{
    return [UIColor colorWithWhite:0.3 alpha:1];
}

+ (UIColor *)highlightedTextColor;
{
    return [UIColor colorWithWhite:0.2 alpha:1];
}

static id _commonInit(OUIInspectorTextWell *self)
{
    self.clearsContextBeforeDrawing = YES;
    self.opaque = NO;
    self.backgroundColor = nil;
    self.keyboardType = UIKeyboardTypeDefault;
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
    _textField.delegate = nil;
    [_textField release];
    [_text release];
    [_font release];
    [_formatString release];
    [_formatFont release];
    [super dealloc];
}

@synthesize rounded = _rounded;
- (void)setRounded:(BOOL)rounded;
{
    if (rounded == _rounded)
        return;
    _rounded = rounded;
    [self setNeedsDisplay];
}

@synthesize editable = _editable;
- (void)setEditable:(BOOL)editable;
{
    if (_editable == editable)
        return;
    
    if (!editable && _textField) {
        [_textField removeFromSuperview];
        _textField.delegate = nil;
        [_textField release];
        _textField = nil;
    }
    
    _editable = editable;
    
    if (_editable)
        [self addTarget:self action:@selector(_tappedTextWell:) forControlEvents:UIControlEventTouchUpInside];
    else
        [self removeTarget:self action:@selector(_tappedTextWell:) forControlEvents:UIControlEventTouchUpInside];
}

- (BOOL)editing;
{
    return (_textField.superview == self);
}

@synthesize keyboardType;

- (UITextField *)textField;
{
    if (_editable && !_textField) {
        _textField = [[UITextField alloc] initWithFrame:CGRectZero];
        [_textField setTextAlignment:UITextAlignmentCenter];
        [_textField setDelegate:self];
        
        _textField.font = self.font;
        _textField.textColor = [[self class] textColor];
        [_textField setKeyboardType:self.keyboardType];
    }
    return _textField;
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
    [self setNeedsDisplay];
}

- (NSString *)formatString;
{
    return _formatString;
}
- (void)setFormatString:(NSString *)formatString;
{
    if (_formatString == formatString)
        return;
    [_formatString release];
    _formatString = [formatString copy];
    [self setNeedsDisplay];
}

- (UIFont *)formatFont;
{
    return _formatFont;
}
- (void)setFormatFont:(UIFont *)formatFont;
{
    if (_formatFont == formatFont)
        return;
    [_formatFont release];
    _formatFont = [formatFont retain];
    [self setNeedsDisplay];
}

- (void)setNavigationTarget:(id)target action:(SEL)action;
{
    OBPRECONDITION(target);
    OBPRECONDITION(action);
    
    // We expect to only call this once during setup and to never turn it off.  We might support disabling a well, though.
    OBPRECONDITION(_showNavigationArrow == NO);
    
    _showNavigationArrow = YES;
    [self setNeedsDisplay];
    
    [self addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark -
#pragma mark UIControl subclass

- (void)setHighlighted:(BOOL)highlighted;
{
    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark UIView subclass

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

- (NSAttributedString *)formattedText;
{
    // Add a customizable placeholder?  Only do this if we are doing a substring formatting replacement?
    NSString *text = [NSString isEmptyString:_text] ? @"–" : _text;
    
    NSMutableAttributedString *attrText = [[NSMutableAttributedString alloc] initWithString:text attributes:nil];
    {
        CTFontRef font = _copyFont(_font);
        _setAttr(attrText, (id)kCTFontAttributeName, (id)font);
        CFRelease(font);
    }
    
    if (_formatString) {
        NSMutableAttributedString *attrFormat = [[NSMutableAttributedString alloc] initWithString:_formatString ? _formatString : @"" attributes:nil];
        CTFontRef font = _copyFont(_formatFont ? _formatFont : _font);
        _setAttr(attrFormat, (id)kCTFontAttributeName, (id)font);
        CFRelease(font);
        
        // Find the first '%@' and replace it with our value text
        NSRange valueRange = [_formatString rangeOfString:@"%@"];
        if (valueRange.location != NSNotFound)
            [attrFormat replaceCharactersInRange:valueRange withAttributedString:attrText];
        else
            OBASSERT_NOT_REACHED("No format specifier in format string");
        
        [attrText release];
        attrText = attrFormat;
    }
    
    UIColor *textColor = _drawHighlighed(self) ? [[self class] highlightedTextColor] : [[self class] textColor];
    
    _setAttr(attrText, (id)kCTForegroundColorAttributeName, (id)[textColor CGColor]);
    
    [attrText autorelease];
    
    return attrText;
}

// Need something to overide in graffle to draw some more complex text (2 "text"s)
// Could overide the attributed string creation instead... might do that anyway
- (void)drawTheText;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    CGRect textRect = self.bounds; // Center the text across the whole bounds, even if we have a nav arrow chopping off part of it
    
    NSAttributedString *attrText = [self formattedText];
    
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)attrText);
    
    CGContextSetTextPosition(ctx, 0, 0);
    
    CGRect lineBounds = CGRectIntegral(CTLineGetImageBounds(line, ctx));
    CGPoint pt;
    pt.x = ceil(0.5 * (CGRectGetWidth(textRect) - CGRectGetWidth(lineBounds)));
    pt.y = ceil(0.5 * (CGRectGetHeight(textRect) - CGRectGetHeight(lineBounds)));
    
    CGContextSaveGState(ctx);
    {
        CGContextTranslateCTM(ctx, pt.x + CGRectGetMinX(lineBounds), pt.y + CGRectGetMaxY(lineBounds));
        CGContextScaleCTM(ctx, 1, -1);
        CTLineDraw(line, ctx);
    }
    CGContextRestoreGState(ctx);
    CFRelease(line);
}

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    OUIInspectorWellDrawOuterShadow(ctx, bounds, _rounded);
    
    // Fill the gradient
    CGContextSaveGState(ctx);
    {
        OUIInspectorWellAddPath(ctx, bounds, _rounded);
        CGContextClip(ctx);
        
        CGGradientRef gradient = _drawHighlighed(self) ? HighlightedGradient : NormalGradient;
        CGContextDrawLinearGradient(ctx, gradient, bounds.origin, CGPointMake(bounds.origin.x, CGRectGetMaxY(bounds)), 0);
    }
    CGContextRestoreGState(ctx);
    
    OUIInspectorWellDrawBorderAndInnerShadow(ctx, bounds, _rounded);
        
    if (_showNavigationArrow) {
        UIImage *arrowImage = [UIImage imageNamed:@"OUINavigationArrow.png"];
        CGRect arrowRect, remainder;
        CGRectDivide(bounds, &arrowRect, &remainder, CGRectGetHeight(bounds), CGRectMaxXEdge);
        
        OQDrawImageCenteredInRect(ctx, [arrowImage CGImage], arrowRect);
    }
        
    // Draw the text if we aren't editing. If we are, the text field subview will be drawing it.
    if (!self.editing) {
        [self drawTheText];
    }
}

#pragma mark -
#pragma mark UITextFieldDelegate

// end editing when 'Return' is pressed
- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
    [textField endEditing:NO];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)aTextField
{
    NSString *text = [_textField text];
    
    [_textField removeFromSuperview];
    
    if (OFNOTEQUAL(text, _text)) {
        self.text = text;
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
    
    // start displaying again.
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark Private

- (void)_tappedTextWell:(id)sender;
{
    // Can tap the area above/below the text field. Don't restart editing if that happens.
    if (self.editing)
        return;
    
    
    // turn off display while editing.
    [self setNeedsDisplay];
    
    CGRect bounds = self.bounds;
    
    UITextField *textField = self.textField; // creates if needed
    textField.text = @"Wagfly";
    [textField sizeToFit];
    
    CGRect textFieldFrame = textField.frame;
    textFieldFrame.origin.y = floor(CGRectGetMinY(bounds) + 0.5 * (CGRectGetHeight(bounds) - CGRectGetHeight(textFieldFrame)));
    textFieldFrame.origin.x = bounds.origin.x;
    textFieldFrame.size.width = bounds.size.width;
    textField.frame = textFieldFrame;
    
    textField.text = _text;
    
    [self addSubview:textField];
    
    [textField becomeFirstResponder];
}

@end
