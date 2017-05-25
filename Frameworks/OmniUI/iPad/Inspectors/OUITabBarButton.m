// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
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
    button.showButtonImage = YES;
    button.showButtonTitle = YES;
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
    self.showButtonImage = _isVerticalTabButton;
    self.showButtonTitle = YES;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
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
    if (self.appearanceDelegate != nil && [self.appearanceDelegate respondsToSelector:@selector(selectedTabTintColor)] && self.selected) {
        tintColor = [self.appearanceDelegate selectedTabTintColor];
    }
    
    // Don't adjust the image when the tab is selected.
    // -updateTitleColors uses the same title color for UIControlStateSelected and UIControlStateHighlighted, we should behave the same way.
    //
    // For the record, I would have expected that we darken in response to taps (even when selected).
    // However, a sample application shows that when a button is selected, the UIControlStateHighlighted titleColor is ignored.
    // The UIControlStateNormal titleColor is used instead when the button is selected.
    // We could workaround this, but the tediousness of doing so and comparison with a stock tab-based application (which doesn't highlight the selected tab) suggest this is correct for a tabbed interface on iOS.
    self.adjustsImageWhenHighlighted = !self.selected;

    self.imageView.tintColor = tintColor;
}

- (void)updateTitleColors;
{
    UIColor *selectedTitleColor;
    UIColor *disabledTitleColor;
    if (self.appearanceDelegate != nil) {
        if ([self.appearanceDelegate respondsToSelector:@selector(selectedTabTintColor)]) {
            selectedTitleColor = self.appearanceDelegate.selectedTabTintColor;
        }
        if ([self.appearanceDelegate respondsToSelector:@selector(disabledTabTintColor)]) {
            disabledTitleColor = self.appearanceDelegate.disabledTabTintColor;
        }
    } else {
        selectedTitleColor = [UIColor blackColor];
        disabledTitleColor = [UIColor lightGrayColor];
    }
    
    [self setTitleColor:self.tintColor forState:UIControlStateNormal];

    [self setTitleColor:selectedTitleColor forState:UIControlStateSelected];
    [self setTitleColor:selectedTitleColor forState:(UIControlStateSelected | UIControlStateHighlighted)];

    [self setTitleColor:disabledTitleColor forState:UIControlStateDisabled];
}

- (CGRect)titleRectForContentRect:(CGRect)contentRect;
{
    // N.B. We'll need to adjust this logic once we allow for indicators to indicate tab content
    if (_isVerticalTabButton) {
        CGRect titleRect = [super titleRectForContentRect:contentRect];
        titleRect.origin.x = self.bounds.origin.x;
        titleRect.size.width = [self _xOffsetDividingTitleAndImage];
        return titleRect;
    }
    
    // only adjust our image origin.x if label overlaps the image and we are showing an image.
    CGRect titleRect = [super titleRectForContentRect:CGRectInset(contentRect, 4, 0)];
    CGRect imageRect = [self imageRectForContentRect:contentRect];

    if (self.showButtonImage && CGRectIntersectsRect(titleRect, imageRect)) {
        titleRect.origin.x = MAX(contentRect.origin.x, titleRect.origin.x - imageRect.size.width);
        if (CGRectGetMaxX(titleRect) > CGRectGetMinX(imageRect) - 10) {
            titleRect.size.width = CGRectGetMinX(imageRect) - 10;
        }
    }

    return titleRect;
}

- (CGRect)imageRectForContentRect:(CGRect)contentRect;
{
    if (! self.showButtonImage) {
        // No images for horizontal buttons
        return CGRectZero;
    }
    
    CGRect imageRect = [super imageRectForContentRect:contentRect];
    CGSize imageSize = [[self imageForState:UIControlStateNormal] size];

    if (self.showButtonImage) {
        imageRect = (CGRect){
            .origin = (CGPoint){
                .x = [self _xOffsetDividingTitleAndImage],
                .y = ceilf((CGRectGetHeight(contentRect) - imageSize.height) / 2.0),
            },
            .size = imageSize,
        };
    }
    
    return imageRect;
}

- (CGFloat)_xOffsetDividingTitleAndImage;
{
    CGSize imageSize = [[self imageForState:UIControlStateNormal] size];
    if (self.showButtonTitle)
        return CGRectGetWidth([self bounds]) - imageSize.width - 10;
    else
        return (CGRectGetWidth([self bounds])/2.0) - (imageSize.width/2.0);
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
