// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUICompletionMatchCell.h>

#import <CoreText/CoreText.h>
#import <OmniFoundation/OFIndexPath.h>
#import <OmniFoundation/OFCompletionMatch.h>

RCS_ID("$Id$");

static const CGFloat _CompletionCellMargin = 10.0f;

@interface OFCompletionMatchLabel : UIView {
  @private
    BOOL _highlighted;
    UIFont *_textFont;
    UIColor *_textColor;
    UIColor *_highlightedTextColor;
    NSAttributedString *_attributedString;
}

+ (BOOL)isSupportedOnCurrentOS;
+ (NSAttributedString *)attributedStringForCompletionMatch:(OFCompletionMatch *)completionMatch;

@property (nonatomic, getter=isHighlighted) BOOL highlighted;
@property (nonatomic, retain) UIFont *textFont;
@property (nonatomic, retain) UIColor *textColor;
@property (nonatomic, retain) UIColor *highlightedTextColor;

@property (nonatomic, copy) NSAttributedString *attributedString;

- (CTFontRef)newCTFontWithUIFont:(UIFont *)font;

@end

static void _SetAttributedStringAttribute(NSMutableAttributedString *attributedString, NSString *attributeName, id value);

#pragma mark -

@interface OUICompletionMatchCell ()

@property (nonatomic, readonly) OFCompletionMatchLabel *completionMatchLabel;

@end

@implementation OUICompletionMatchCell

- (id)initWithCompletionMatch:(OFCompletionMatch *)completionMatch reuseIdentifier:(NSString *)reuseIdentifier;
{
    return [self initWithStyle:UITableViewCellStyleDefault completionMatch:completionMatch reuseIdentifier:reuseIdentifier];
}

- (id)initWithStyle:(UITableViewCellStyle)style completionMatch:(OFCompletionMatch *)completionMatch reuseIdentifier:(NSString *)reuseIdentifier;
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self)
        return nil;
    
    self.textLabel.font = [UIFont boldSystemFontOfSize:15.0];
    _completionMatch = [completionMatch retain];

    return self;
}

- (void)dealloc;
{
    [_completionMatch release];
    [_completionMatchLabel release];
    [super dealloc];
}

- (OFCompletionMatch *)completionMatch;
{
    return _completionMatch;
}

- (void)setCompletionMatch:(OFCompletionMatch *)completionMatch;
{
    if (completionMatch == _completionMatch)
        return;
        
    [_completionMatch release];
    _completionMatch = [completionMatch retain];

    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)layoutSubviews;
{
    OFCompletionMatchLabel *completionMatchLabel = self.completionMatchLabel;

    // Layout the simple label so we can steal its frame
    self.textLabel.text = [_completionMatch string];

    // Ask super to layout it's subviews
    [super layoutSubviews];
    
    self.textLabel.hidden = YES;
    
    // Layout our own subviews
    if (completionMatchLabel) {
        completionMatchLabel.attributedString = [OFCompletionMatchLabel attributedStringForCompletionMatch:_completionMatch];
        completionMatchLabel.textFont = self.textLabel.font;
        completionMatchLabel.textColor = self.textLabel.textColor;
        completionMatchLabel.highlightedTextColor = self.textLabel.highlightedTextColor;

        completionMatchLabel.frame = self.textLabel.frame;
    }
}

#pragma mark -
#pragma mark Private

- (OFCompletionMatchLabel *)completionMatchLabel;
{
    if (_completionMatchLabel)
        return _completionMatchLabel;
        
    if (![OFCompletionMatchLabel isSupportedOnCurrentOS])
        return nil;

    _completionMatchLabel = [[OFCompletionMatchLabel alloc] initWithFrame:CGRectZero];
    
    [self.contentView addSubview:_completionMatchLabel];
    [self setNeedsLayout];

    return _completionMatchLabel;
}

@end

#pragma mark -

@implementation OFCompletionMatchLabel

+ (BOOL)isSupportedOnCurrentOS;
{
    return (NSClassFromString(@"NSAttributedString") != Nil && CTLineCreateWithAttributedString != NULL);
}

+ (NSAttributedString *)attributedStringForCompletionMatch:(OFCompletionMatch *)completionMatch;
{
    OBPRECONDITION(completionMatch);

    Class cls = NSClassFromString(@"NSMutableAttributedString");
    OBASSERT(cls);

    NSMutableAttributedString *attributedString = [[[cls alloc] initWithString:[completionMatch string]] autorelease];
    OFIndexPath *characterIndexPath = [completionMatch characterIndexPath];
    unsigned int indexCount = [characterIndexPath length];

    if (indexCount > 0) {
        NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:kCTUnderlineStyleSingle], (id)kCTUnderlineStyleAttributeName,
            nil
        ];

        NSUInteger indexes[indexCount];
        [characterIndexPath getIndexes:indexes];
        for (unsigned int indexIndex = 0; indexIndex < indexCount; indexIndex++) {
            unsigned int indexValue = indexes[indexIndex];
            NSRange range = NSMakeRange(indexValue, 1);
            [attributedString addAttributes:attributes range:range];
        }
    }
        
    return attributedString;
}

- (id)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
        
    self.backgroundColor = [UIColor whiteColor];
    self.opaque = YES;
    
    return self;
}

- (void)dealloc;
{
    [_textFont release];
    [_textColor release];
    [_highlightedTextColor release];
    [_attributedString release];

    [super dealloc];
}

@synthesize highlighted = _highlighted;

- (UIFont *)textFont;
{
    return _textFont;
}

- (void)setTextFont:(UIFont *)textFont;
{
    if (_textFont != textFont) {
        [_textFont release];
        _textFont = [textFont retain];

        [self setNeedsDisplay];
    }
}

- (UIColor *)textColor;
{
    return _textColor;
}

- (void)setTextColor:(UIColor *)textColor;
{
    if (_textColor != textColor) {
        [_textColor release];
        _textColor = [textColor retain];

        [self setNeedsDisplay];
    }
}

- (UIColor *)highlightedTextColor;
{
    return _highlightedTextColor;
}

- (void)setHighlightedTextColor:(UIColor *)highlightedTextColor;
{
    if (_highlightedTextColor != highlightedTextColor) {
        [_highlightedTextColor release];
        _highlightedTextColor = [highlightedTextColor retain];

        [self setNeedsDisplay];
    }
}

- (NSAttributedString *)attributedString;
{
    return _attributedString;
}

- (void)setAttributedString:(NSAttributedString *)attributedString;
{
    if (_attributedString != attributedString) {
        [_attributedString release];
        _attributedString = [attributedString retain];

        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)clipRect;
{
    // REVIEW It might be nice to build and cache these CTLine instances once, and invalidate as necessary.
    // However, in practice since our drawing is cached to our underlying layer, this probably isn't important.
    
    CTFontRef font = NULL;
    CTLineRef line = NULL;
    
    UIFont *textFont = self.textFont;
    if (!textFont)
        textFont = [UIFont systemFontOfSize:[UIFont labelFontSize]];
    font = [self newCTFontWithUIFont:textFont];
    OBASSERT(font);
    
    UIColor *textColor = [self isHighlighted] ? self.highlightedTextColor : self.textColor;
    if (!textColor) 
        textColor = [self isHighlighted] ? [UIColor whiteColor] : [UIColor blackColor];

    Class cls = NSClassFromString(@"NSMutableAttributedString");
    OBASSERT(cls);

    NSMutableAttributedString *displayString = [[self.attributedString mutableCopy] autorelease];
    _SetAttributedStringAttribute(displayString, (id)kCTForegroundColorAttributeName, (id)[textColor CGColor]);
    _SetAttributedStringAttribute(displayString, (id)kCTFontAttributeName, (id)font);

    line = CTLineCreateWithAttributedString((CFAttributedStringRef)displayString);
    OBASSERT(line);
    
    if (CTLineGetTypographicBounds(line, NULL, NULL, NULL) > CGRectGetWidth(self.bounds)) {        
        CTLineRef truncationToken = NULL;
        CTLineRef truncatedLine = NULL;

        NSMutableAttributedString *truncationString = [[[cls alloc] initWithString:@"…" attributes:nil] autorelease];
        _SetAttributedStringAttribute(truncationString, (id)kCTForegroundColorAttributeName,  (id)[textColor CGColor]);
        _SetAttributedStringAttribute(truncationString, (id)kCTFontAttributeName, (id)font);

        truncationToken = CTLineCreateWithAttributedString((CFAttributedStringRef)truncationString);
        OBASSERT(truncationToken);
        
        truncatedLine = CTLineCreateTruncatedLine(line, CGRectGetWidth(self.bounds), kCTLineTruncationMiddle, truncationToken);
        OBASSERT(truncatedLine);

        CFRelease(line);
        line = (CTLineRef)CFRetain(truncatedLine);

        CFRelease(truncationToken);
        CFRelease(truncatedLine);
    }

    CGContextRef context = UIGraphicsGetCurrentContext();
    
    if ([self isOpaque]) {
        [self.backgroundColor set];
        CGContextFillRect(context, self.bounds);
    }
    
    CGRect textRect = self.bounds;
    CGRect lineBounds = CGRectIntegral(CTLineGetImageBounds(line, context));
    CGPoint pt = CGPointZero;
    pt.y = ceil(0.5 * (CGRectGetHeight(textRect) - CGRectGetHeight(lineBounds) - CGRectGetMinY(lineBounds)) - 1);
    
    CGContextSaveGState(context);
    {
        CGContextSetTextPosition(context, 0, 0);
        CGContextTranslateCTM(context, pt.x + CGRectGetMinX(lineBounds), pt.y + CGRectGetMaxY(lineBounds));
        CGContextScaleCTM(context, 1, -1);
        CTLineDraw(line, context);
    }
    CGContextRestoreGState(context);

    if (font != NULL)
        CFRelease(font);
    CFRelease(line);
}

- (CTFontRef)newCTFontWithUIFont:(UIFont *)font;
{
    if (!font)
        font = [UIFont systemFontOfSize:[UIFont labelFontSize]];

    return CTFontCreateWithName((CFStringRef)[font fontName], [font pointSize], NULL);
}

@end

static void _SetAttributedStringAttribute(NSMutableAttributedString *attributedString, NSString *attributeName, id value)
{
    OBPRECONDITION(attributedString);
    OBPRECONDITION(attributeName);

    NSRange range = NSMakeRange(0, [attributedString length]);
    if (value)
        [attributedString addAttribute:attributeName value:value range:range];
    else
        [attributedString removeAttribute:attributeName range:range];
}
