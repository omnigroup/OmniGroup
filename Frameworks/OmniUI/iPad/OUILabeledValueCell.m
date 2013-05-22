// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUILabeledValueCell.h>

RCS_ID("$Id$");

@implementation OUILabeledValueCell

+ (UIFont *)labelFontForStyle:(OUILabeledValueCellStyle)style;
{
    switch (style) {
        case OUILabeledValueCellStyleDefault:
        case OUILabeledValueCellStyleSettings:
            return [UIFont boldSystemFontOfSize:[UIFont systemFontSize]];
            
        case OUILabeledValueCellStyleOmniFocusForiPhoneLegacy:
            return [UIFont systemFontOfSize:12];
    }    
    
    OBASSERT_NOT_REACHED("");
    return nil;
}

+ (UIFont *)valueFontForStyle:(OUILabeledValueCellStyle)style;
{
    switch (style) {
        case OUILabeledValueCellStyleDefault:
        case OUILabeledValueCellStyleSettings:
            return [UIFont systemFontOfSize:[UIFont systemFontSize]];
            
        case OUILabeledValueCellStyleOmniFocusForiPhoneLegacy:
            return [UIFont systemFontOfSize:14];
    }    
    
    OBASSERT_NOT_REACHED("");
    return nil;
}

+ (UIColor *)labelColorForStyle:(OUILabeledValueCellStyle)style isHighlighted:(BOOL)highlighted;
{
    switch (style) {
        case OUILabeledValueCellStyleDefault:
        case OUILabeledValueCellStyleSettings:
            return highlighted ? [UIColor whiteColor] : [UIColor blackColor];
            
        case OUILabeledValueCellStyleOmniFocusForiPhoneLegacy:
            return highlighted ? [UIColor colorWithRed:0.31 green:0.40 blue:0.56 alpha:1.0] : [UIColor blackColor];
    }    
    
    OBASSERT_NOT_REACHED("");
    return nil;
}

+ (UIColor *)valueColorForStyle:(OUILabeledValueCellStyle)style isHighlighted:(BOOL)highlighted;
{
    switch (style) {
        case OUILabeledValueCellStyleDefault:
        case OUILabeledValueCellStyleSettings:
            return highlighted ? [UIColor whiteColor] : [UIColor blackColor];
            
        case OUILabeledValueCellStyleOmniFocusForiPhoneLegacy:
            return highlighted ? [UIColor whiteColor] : [UIColor blackColor];
    }    
    
    OBASSERT_NOT_REACHED("");
    return nil;
}

- (id)initWithFrame:(CGRect)frame;
{
    return [self initWithFrame:frame style:OUILabeledValueCellStyleDefault];
}

- (id)initWithFrame:(CGRect)frame style:(OUILabeledValueCellStyle)style
{
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
    
    _style = style;
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.labelAlignment = (self.style == OUILabeledValueCellStyleOmniFocusForiPhoneLegacy) ? NSTextAlignmentRight : NSTextAlignmentLeft;
    return self;
}

- (void)dealloc
{
    [_label release];
    [_value release];
    [_emptyValueString release];
    [_valueImage release];
    [super dealloc];
}

@synthesize style = _style;

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
    return _label;
}

- (void)setLabel:(NSString *)label;
{
    if (_label == label)
        return;
    
    [_label release];
    _label = [label copy];
    
    [self labelChanged];
}

- (void)labelChanged;
{
    [self setNeedsDisplay];
}

@synthesize value = _value;
@synthesize valuePlaceholder = _emptyValueString;
@synthesize valueImage = _valueImage;

- (NSString *)valuePlaceholder;
{
    if (_emptyValueString)
        return _emptyValueString;
    
    return NSLocalizedStringFromTableInBundle(@"None", @"OmniUI", OMNI_BUNDLE, @"empty value cell placeholder");
}

#define LABEL_GAP 10.0

- (CGRect)labelRect;
{    
    // The 'default context' label for Japanese is wider than we normally need, so make this dynamically computed, but with a minimum size that works for most cases (for nice right-alignment of most labels).
    UIFont *labelFont = [[self class] labelFontForStyle:self.style];
    CGFloat constrainedWidth = (self.style == OUILabeledValueCellStyleOmniFocusForiPhoneLegacy) ? 90 : 1e9;
    CGSize labelSize = [self.label sizeWithFont:labelFont constrainedToSize:CGSizeMake(constrainedWidth, 1e9)];
    CGFloat labelWidth = 0.0;

    if (self.label)
        labelWidth = labelSize.width;

    if (!self.usesActualLabelWidth) {
        labelWidth = MAX(labelWidth, 60.0);
        labelWidth = MAX(labelWidth, _minimumLabelWidth);
    }
    
    CGRect labelRect = self.bounds;
    labelRect.origin.x += LABEL_GAP /* gap on left of label */;
    labelRect.size.width = labelWidth;
    labelRect.origin.y += (labelRect.size.height - labelSize.height) / 2.0;
    labelRect.size.height = labelSize.height;
    return labelRect;
}

- (CGRect)valueRectForString:(NSString *)valueString labelRect:(CGRect)labelRect;
{
    CGRect valueRect;
    valueRect.origin.x = CGRectGetMaxX(labelRect) + LABEL_GAP /* gap on right of label */;
    valueRect.size.width = CGRectGetMaxX(self.bounds) - valueRect.origin.x;
    
    if (_valueImage) {
        valueRect.size = _valueImage.size;
        valueRect.origin.y = CGRectGetMidY(self.bounds) - valueRect.size.height / 2.0;
        
        [_valueImage drawInRect:valueRect];
        valueRect.origin.x = CGRectGetMaxX(valueRect) + 10.0;
        valueRect.size.width = CGRectGetMaxX(self.bounds) - valueRect.origin.x;
    }

    valueRect.origin.y = CGRectGetMinY(self.bounds);
    valueRect.size.height = self.bounds.size.height;
    
    return valueRect;
}

- (BOOL)isHighlighted;
{
    return _isHighlighted;
}

- (void)setHighlighted:(BOOL)yn;
{
    _isHighlighted = yn;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect 
{
    [super drawRect:rect];
    
    UIColor *labelColor = [[self class] labelColorForStyle:self.style isHighlighted:_isHighlighted];
    [labelColor set];

    CGRect labelRect = [self labelRect];
    UIFont *labelFont = [[self class] labelFontForStyle:self.style];
    [self.label drawInRect:labelRect withFont:labelFont lineBreakMode:NSLineBreakByWordWrapping alignment:self.labelAlignment];
    
    NSString *value = _value; // Must access iVar here, don't want to pull value from subclass, which substitutes an editable field
    NSString *valueString = value ? value : [self valuePlaceholder];
    CGRect valueRect = [self valueRectForString:valueString labelRect:labelRect];

    UIColor *valueColor = (value != nil || _isHighlighted) ? [[self class] valueColorForStyle:self.style isHighlighted:_isHighlighted] : [UIColor grayColor];
    [valueColor set];

    UIFont *valueFont = [[self class] valueFontForStyle:self.style];
    [valueString drawInRect:valueRect withFont:valueFont lineBreakMode:NSLineBreakByTruncatingTail alignment:NSTextAlignmentLeft];
}

@end
