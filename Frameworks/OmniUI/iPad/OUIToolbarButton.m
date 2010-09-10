// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIToolbarButton.h>

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

static id _commonInit(OUIToolbarButton *self)
{
    self.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self setTitleShadowColor:[UIColor colorWithWhite:0 alpha:.5f] forState:UIControlStateNormal];
    self.titleEdgeInsets = UIEdgeInsetsMake(1, 8, 0, 8);
    
    [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    
    // set up default background images
    [self setNormalBackgroundImage:nil];
    [self setHighlightedBackgroundImage:nil];
    
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

static const CGFloat ButtonEndCapWidth = 4;

- (void)setNormalBackgroundImage:(UIImage *)image;
{
    if (!image)
        image = [[self class] normalBackgroundImage];
    [self setBackgroundImage:[image stretchableImageWithLeftCapWidth:ButtonEndCapWidth topCapHeight:0] forState:UIControlStateNormal];
}

- (void)setHighlightedBackgroundImage:(UIImage *)image;
{
    if (!image)
        image = [[self class] highlightedBackgroundImage];
    [self setBackgroundImage:[image stretchableImageWithLeftCapWidth:ButtonEndCapWidth topCapHeight:0] forState:UIControlStateHighlighted];
}

#pragma mark -
#pragma mark UIView subclass

- (CGSize)sizeThatFits:(CGSize)size;
{
    CGSize fits = [super sizeThatFits:size];
    
    UIImage *background = [[self class] normalBackgroundImage];
    CGSize backgroundSize = [background size];
    OBASSERT(backgroundSize.height == 44);
    OBASSERT(fits.height <= backgroundSize.height);
    
    // We want to be toolbar height sized and we expect our background images to be as well (since they are captured from a live toolbar item in the simulator).
    // Also, since UIToolbar shifts its buttons up/down by 1px based on the barStyle, this captures the movement of the background.
    // The superclass method doesn't return enough space for the string to draw w/o clipping, for some reason.
    return CGSizeMake(fits.width + 2*(ButtonEndCapWidth + 5), backgroundSize.height);
}

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    // UIToolbar draws its normal button items 1px higher if it is in black mode. We don't have a great spot to put this; ideally you'll set the bar style before adding any the items to it, or hopefully UIToolbar will tell them to layout if barStyle changes.
    
    UIToolbar *toolbar = nil;
    UIView *view = self.superview;
    while (view) {
        if ([view isKindOfClass:[UIToolbar class]]) {
            toolbar = (UIToolbar *)view;
            break;
        }
        view = view.superview;
    }
    
    UIBarStyle barStyle = toolbar.barStyle;
    
    if (barStyle == UIBarStyleBlack) {
        self.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 0);
    } else {
        // Otherwise the title is 1px too low (need to pull it up to match other buttons which have shadowing on).
        self.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 2, 0);
    }
}

@end
