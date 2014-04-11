// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUICompletionMatchCell.h>

#import <OmniFoundation/OFIndexPath.h>
#import <OmniFoundation/OFCompletionMatch.h>

RCS_ID("$Id$");

@interface OFCompletionMatchLabel : UIView
+ (NSAttributedString *)attributedStringForCompletionMatch:(OFCompletionMatch *)completionMatch;

@property (nonatomic, getter=isHighlighted) BOOL highlighted;
@property (nonatomic, strong) UIFont *textFont;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, strong) UIColor *highlightedTextColor;

@property (nonatomic, copy) NSAttributedString *attributedString;

@end

static void _SetAttributedStringAttribute(NSMutableAttributedString *attributedString, NSString *attributeName, id value);

#pragma mark -

@interface OUICompletionMatchCell ()
@property(nonatomic,readonly) OFCompletionMatchLabel *completionMatchLabel;
@end

@implementation OUICompletionMatchCell
{
    OFCompletionMatch *_completionMatch;
    OFCompletionMatchLabel *_completionMatchLabel;
}

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
    _completionMatch = completionMatch;

    return self;
}

- (OFCompletionMatch *)completionMatch;
{
    return _completionMatch;
}

- (void)setCompletionMatch:(OFCompletionMatch *)completionMatch;
{
    if (completionMatch == _completionMatch)
        return;
        
    _completionMatch = completionMatch;

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
    completionMatchLabel.attributedString = [OFCompletionMatchLabel attributedStringForCompletionMatch:_completionMatch];
    completionMatchLabel.textFont = self.textLabel.font;
    completionMatchLabel.textColor = self.textLabel.textColor;
    completionMatchLabel.highlightedTextColor = self.textLabel.highlightedTextColor;

    completionMatchLabel.frame = self.textLabel.frame;
}

#pragma mark -
#pragma mark Private

- (OFCompletionMatchLabel *)completionMatchLabel;
{
    if (_completionMatchLabel)
        return _completionMatchLabel;
        
    _completionMatchLabel = [[OFCompletionMatchLabel alloc] initWithFrame:CGRectZero];
    
    [self.contentView addSubview:_completionMatchLabel];
    [self setNeedsLayout];

    return _completionMatchLabel;
}

@end

#pragma mark -

@implementation OFCompletionMatchLabel

+ (NSAttributedString *)attributedStringForCompletionMatch:(OFCompletionMatch *)completionMatch;
{
    OBPRECONDITION(completionMatch);

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:[completionMatch string]];
    OFIndexPath *characterIndexPath = [completionMatch characterIndexPath];
    unsigned long indexCount = [characterIndexPath length];

    if (indexCount > 0) {
        NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:NSUnderlineStyleSingle], (id)NSUnderlineStyleAttributeName,
            nil
        ];

        NSUInteger indexes[indexCount];
        [characterIndexPath getIndexes:indexes];
        for (unsigned int indexIndex = 0; indexIndex < indexCount; indexIndex++) {
            unsigned long indexValue = indexes[indexIndex];
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

- (void)setTextFont:(UIFont *)textFont;
{
    if (_textFont != textFont) {
        _textFont = textFont;
        [self setNeedsDisplay];
    }
}

- (void)setTextColor:(UIColor *)textColor;
{
    if (_textColor != textColor) {
        _textColor = textColor;
        [self setNeedsDisplay];
    }
}

- (void)setHighlightedTextColor:(UIColor *)highlightedTextColor;
{
    if (_highlightedTextColor != highlightedTextColor) {
        _highlightedTextColor = highlightedTextColor;
        [self setNeedsDisplay];
    }
}

- (void)setAttributedString:(NSAttributedString *)attributedString;
{
    if (_attributedString != attributedString) {
        _attributedString = attributedString;
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)clipRect;
{
    UIFont *font = self.textFont;
    if (!font)
        font = [UIFont systemFontOfSize:[UIFont labelFontSize]];
    
    UIColor *textColor = [self isHighlighted] ? self.highlightedTextColor : self.textColor;
    if (!textColor) 
        textColor = [self isHighlighted] ? [UIColor whiteColor] : [UIColor blackColor];

    NSMutableAttributedString *displayString = [self.attributedString mutableCopy];
    
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingMiddle;
    
    _SetAttributedStringAttribute(displayString, NSForegroundColorAttributeName, textColor);
    _SetAttributedStringAttribute(displayString, NSFontAttributeName, font);
    _SetAttributedStringAttribute(displayString, NSParagraphStyleAttributeName, paragraphStyle);
    
    NSStringDrawingContext *stringContext = [NSStringDrawingContext new];
    NSStringDrawingOptions options = 0;
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    if ([self isOpaque]) {
        [self.backgroundColor set];
        CGContextFillRect(context, self.bounds);
    }
    
    CGRect textBounds = [displayString boundingRectWithSize:self.bounds.size options:options context:stringContext];
    CGRect bounds = self.bounds;

    textBounds.origin.y = ceil(0.5 * (CGRectGetHeight(bounds) - CGRectGetHeight(textBounds)));
    
    [displayString drawWithRect:textBounds options:options context:stringContext];
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
