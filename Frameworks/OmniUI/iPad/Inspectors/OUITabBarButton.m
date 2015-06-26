// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUITabBarButton.h"

RCS_ID("$Id$");

#import <OmniUI/OUITabBarAppearanceDelegate.h>

@interface OUITabBarButton () {
  @private
    BOOL _isVerticalTabButton;
}

@end

@implementation OUITabBarButton

+ (instancetype)tabBarButton;
{
    return [self buttonWithType:UIButtonTypeCustom];
}

+ (instancetype)verticalTabBarButton;
{
    OUITabBarButton *button = [self buttonWithType:UIButtonTypeCustom];
    button->_isVerticalTabButton = YES;
    
    return button;
}

+ (id)buttonWithType:(UIButtonType)buttonType;
{
    OBASSERT(buttonType == UIButtonTypeCustom);
    return [super buttonWithType:UIButtonTypeCustom];
}

- (id)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    
    [self OUITabBarButton_commonInit];
    
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    self = [super initWithCoder:coder];
    if (self == nil) {
        return nil;
    }
    
    [self OUITabBarButton_commonInit];

    return self;
}

- (void)OUITabBarButton_commonInit;
{
    [self appearanceDidChange];
}

- (void)setSelected:(BOOL)selected;
{
    [super setSelected:selected];
    [self updateImageViewTintColors];
    [self setNeedsLayout];
}

- (void)tintColorDidChange;
{
    [super tintColorDidChange];
    [self appearanceDidChange];
}

- (void)updateImageViewTintColors;
{
    UIColor *tintColor = nil;
    if (self.appearanceDelegate != nil && self.selected) {
        tintColor = [self.appearanceDelegate selectedTabTintColor];
    }

    self.imageView.tintColor = tintColor;
}

- (void)updateTitleColors;
{
    UIColor *selectedTitleColor;
    UIColor *disabledTitleColor;
    if (self.appearanceDelegate != nil) {
        selectedTitleColor = self.appearanceDelegate.selectedTabTintColor;
        disabledTitleColor = self.appearanceDelegate.disabledTabTintColor;
    } else {
        selectedTitleColor = [UIColor blackColor];
        disabledTitleColor = [UIColor lightGrayColor];
    }
    
    [self setTitleColor:self.tintColor forState:UIControlStateNormal];
    [self setTitleColor:[self.tintColor colorWithAlphaComponent:0.2] forState:UIControlStateHighlighted];

    [self setTitleColor:selectedTitleColor forState:UIControlStateSelected];
    [self setTitleColor:selectedTitleColor forState:(UIControlStateSelected | UIControlStateHighlighted)];

    [self setTitleColor:disabledTitleColor forState:UIControlStateDisabled];
}

- (CGRect)titleRectForContentRect:(CGRect)contentRect;
{
    CGRect titleRect = [super titleRectForContentRect:contentRect];

    // N.B. We'll need to adjust this logic once we allow for indicators to indicate tab content
    if (_isVerticalTabButton) {
        titleRect.origin.x = self.bounds.origin.x;
        titleRect.size.width = [self _xOffsetDividingTitleAndImage];
    }

    return titleRect;
}

- (CGRect)imageRectForContentRect:(CGRect)contentRect;
{
    if (!_isVerticalTabButton) {
        // No images for horizontal buttons
        return CGRectZero;
    }
    
    CGRect imageRect = [super imageRectForContentRect:contentRect];
    CGSize imageSize = [[self imageForState:UIControlStateNormal] size];
    
    if (_isVerticalTabButton) {
        imageRect = (CGRect){
            .origin = (CGPoint){
                .x = [self _xOffsetDividingTitleAndImage],
                .y = (CGRectGetHeight(contentRect) - imageSize.height) / 2.0,
            },
            .size = imageSize,
        };
    }
    
    return imageRect;
}

- (CGFloat)_xOffsetDividingTitleAndImage;
{
    CGSize imageSize = [[self imageForState:UIControlStateNormal] size];
    return CGRectGetWidth([self bounds]) - imageSize.width - 18.0;
}

#pragma mark Appearance

- (void)appearanceDidChange;
{
    [self updateTitleColors];
    [self updateImageViewTintColors];
}

@synthesize appearanceDelegate = _weak_appearanceDelegate;

- (id <OUITabBarAppearanceDelegate>)appearanceDelegate;
{
    return _weak_appearanceDelegate;
}

- (void)setAppearanceDelegate:(id<OUITabBarAppearanceDelegate>)appearanceDelegate;
{
    if (appearanceDelegate == _weak_appearanceDelegate) {
        return;
    }
    
    _weak_appearanceDelegate = appearanceDelegate;
    [self appearanceDidChange];
}


@end
