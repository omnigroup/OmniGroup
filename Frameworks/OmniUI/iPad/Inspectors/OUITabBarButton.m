// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUITabBarButton.h"

RCS_ID("$Id$");

@implementation OUITabBarButton

+ (instancetype)tabBarButton;
{
    return [self buttonWithType:UIButtonTypeCustom];
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
    [self updateTitleColors];
}

- (void)setSelected:(BOOL)selected;
{
    [super setSelected:selected];
    [self setNeedsLayout];
}

- (void)tintColorDidChange;
{
    [super tintColorDidChange];
    [self updateTitleColors];
}

- (void)updateTitleColors;
{
    [self setTitleColor:self.tintColor forState:UIControlStateNormal];
    [self setTitleColor:[self.tintColor colorWithAlphaComponent:0.2] forState:UIControlStateHighlighted];

    [self setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
    [self setTitleColor:[UIColor blackColor] forState:(UIControlStateSelected | UIControlStateHighlighted)];

    [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
}

@end
