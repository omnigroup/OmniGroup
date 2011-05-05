// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIToolbarButton.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIToolbarButton

+ (UIImage *)normalBackgroundImage;
{
    UIImage *image = [UIImage imageNamed:@"OUIToolbarButton-Black-Normal.png"];
    OBASSERT(image);
    return image;
}

+ (UIImage *)highlightedBackgroundImage;
{
    UIImage *image = [UIImage imageNamed:@"OUIToolbarButton-Black-Highlighted.png"];
    OBASSERT(image);
    return image;
}

@synthesize possibleTitles = _possibleTitles;

static id _commonInit(OUIToolbarButton *self)
{
    CGFloat xCap = [[self class] leftImageStretchCapForBackgroundType:OUIBarButtonItemBackgroundTypeBlack];

    self.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self setTitleShadowColor:[UIColor colorWithWhite:0 alpha:.5f] forState:UIControlStateNormal];
    self.contentEdgeInsets = UIEdgeInsetsMake(1, xCap, 0, xCap);
    
    [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    
    // set up default background images
    [self setNormalBackgroundImage:[[[self class] normalBackgroundImage] stretchableImageWithLeftCapWidth:xCap topCapHeight:0]];
    [self setHighlightedBackgroundImage:[[[self class] highlightedBackgroundImage] stretchableImageWithLeftCapWidth:xCap topCapHeight:0]];
    
    // UIPushButton, a private UIControl subclass used inside the official bar button items uses these settings. Sadly no public API way to get it.
    UIColor *shadowColor = [UIColor colorWithWhite:0 alpha:0.35];
    CGSize shadowOffset = CGSizeMake(0, -1);
    
    [self setTitleShadowColor:shadowColor forState:UIControlStateNormal];
    self.titleLabel.shadowOffset = shadowOffset;
    
    return self;
}

- initWithFrame:(CGRect)frame;
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
    [_possibleTitles release];
    [super dealloc];
}

+ (CGFloat)leftImageStretchCapForBackgroundType:(OUIBarButtonItemBackgroundType)backgroundType;
{
    switch (backgroundType) {
        case OUIBarButtonItemBackgroundTypeBack:
            return 20;
        case OUIBarButtonItemBackgroundTypeBlack:
        case OUIBarButtonItemBackgroundTypeRed:
        case OUIBarButtonItemBackgroundTypeBlue:
        case OUIBarButtonItemBackgroundTypeClear:
            return 9;
        case OUIBarButtonItemBackgroundTypeNone:
        default:
            return 0;
    }
}

- (void)configureForBackgroundType:(OUIBarButtonItemBackgroundType)backgroundType;
{
    NSString *normalImageName, *highlightedImageName;
    UIColor *disabledTextColor = nil;
    
    switch (backgroundType) {
        case OUIBarButtonItemBackgroundTypeRed:
            normalImageName = @"OUIToolbarButton-Red-Normal.png";
            highlightedImageName = @"OUIToolbarButton-Red-Highlighted.png";
            break;
        case OUIBarButtonItemBackgroundTypeBlue:
            normalImageName = @"OUIToolbarButton-Blue-Normal.png";
            highlightedImageName = @"OUIToolbarButton-Blue-Highlighted.png";
            disabledTextColor = [UIColor colorWithWhite:kOUIBarButtonItemDisabledTextGrayForColoredButtons alpha:1.0];
            break;
        case OUIBarButtonItemBackgroundTypeNone:
            normalImageName = nil;
            highlightedImageName = nil;
            break;
        case OUIBarButtonItemBackgroundTypeBack:
            normalImageName = @"OUIToolbarBackButton-Black-Normal.png";
            highlightedImageName = @"OUIToolbarBackButton-Black-Highlighted.png";
            break;
        case OUIBarButtonItemBackgroundTypeClear:
            normalImageName = @"OUIToolbarButton-Clear-Normal.png";
            highlightedImageName = @"OUIToolbarButton-Clear-Highlighted.png";
            break;
        case OUIBarButtonItemBackgroundTypeBlack:
        default:
            normalImageName = @"OUIToolbarButton-Black-Normal.png";
            highlightedImageName = @"OUIToolbarButton-Black-Highlighted.png";
            break;
    }
    
    CGFloat xCap = [[self class] leftImageStretchCapForBackgroundType:backgroundType];
    self.contentEdgeInsets = UIEdgeInsetsMake(1, xCap, 0, xCap);
    
    if (disabledTextColor)
        [self setTitleColor:disabledTextColor forState:UIControlStateDisabled];
    
    UIImage *normalImage = nil;
    if (normalImageName) {
        normalImage = [UIImage imageNamed:normalImageName];
        OBASSERT(normalImageName);
        if (xCap)
            normalImage = [normalImage stretchableImageWithLeftCapWidth:xCap topCapHeight:0];
    }
    [self setNormalBackgroundImage:normalImage];
    
    UIImage *highlightedImage = nil;
    if (highlightedImageName) {
        highlightedImage = [UIImage imageNamed:highlightedImageName];
        OBASSERT(highlightedImage);
        if (xCap)
            highlightedImage = [highlightedImage stretchableImageWithLeftCapWidth:xCap topCapHeight:0];
    }
    [self setHighlightedBackgroundImage:highlightedImage];
}

- (void)setNormalBackgroundImage:(UIImage *)image;
{
    // We require the caller to set the end caps and insets to avoid the end caps.
    OBPRECONDITION(!image || ([image leftCapWidth] > 0));
    
    [self setBackgroundImage:image forState:UIControlStateNormal];
}

- (void)setHighlightedBackgroundImage:(UIImage *)image;
{
    // We require the caller to set the end caps and insets to avoid the end caps.
    OBPRECONDITION(!image || ([image leftCapWidth] > 0));

    [self setBackgroundImage:image forState:UIControlStateHighlighted];
}

- (void)setPossibleTitles:(NSSet *)possibleTitles;
{
    if (OFISEQUAL(_possibleTitles, possibleTitles))
        return;
    
    [_possibleTitles release];
    _possibleTitles = [possibleTitles copy];
    
    // This is lame, but sufficient for now.
    OBASSERT([self superview] == nil);
    
    CGRect oldFrame = self.frame;
    NSString *oldTitle = [[[self titleForState:UIControlStateNormal] copy] autorelease];

    OBASSERT([NSString isEmptyString:oldTitle] || [possibleTitles member:oldTitle]);
    
    CGFloat maxWidth = 0;
    for (NSString *title in possibleTitles) {
        [self setTitle:title forState:UIControlStateNormal];
        [self sizeToFit];
        maxWidth = MAX(maxWidth, self.frame.size.width);
    }
    
    _maxWidth = maxWidth;
    
    [self setTitle:oldTitle forState:UIControlStateNormal];
    
    [self sizeToFit];
    self.frame = (CGRect){oldFrame.origin, self.frame.size};
}

#pragma mark -
#pragma mark UIView subclass

- (CGSize)sizeThatFits:(CGSize)size;
{
    CGSize fits = [super sizeThatFits:size];

    if (_possibleTitles && _maxWidth > 0) // only do this if we aren't in the middle of initializing it!
        fits.width = _maxWidth;
    
    return fits;
}

#if 0
- (void)drawRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    [super drawRect:rect];
    CGContextRestoreGState(ctx);
    
    [[UIColor colorWithRed:1 green:0 blue:0 alpha:0.5] set];
    UIRectFillUsingBlendMode(self.bounds, kCGBlendModeNormal);
}
#endif

@end
