// Copyright 2010-2012 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorButton.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIInspector.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIInspectorButton
{
    UIImage *_image;
}

static UIImage *_backgroundImage(NSString *name)
{
    UIImage *image = [UIImage imageNamed:name];
    CGSize size = image.size;

    // Should be exactly the height we expect and an odd width (making it easy to calculate the inner stretchable bit).
    OBASSERT(size.width == floor(size.width));
    OBASSERT(size.height == kOUIInspectorWellHeight);
    
    CGFloat capWidth = floor(size.width/2);
    OBASSERT(size.width == capWidth * 2 + 1);
    
    return [image stretchableImageWithLeftCapWidth:capWidth topCapHeight:0];
}

static id _commonInit(OUIInspectorButton *self)
{
    self.opaque = NO;
    self.backgroundColor = nil;
    self.clearsContextBeforeDrawing = YES;
    
    self.adjustsImageWhenHighlighted = NO;
    self.adjustsImageWhenDisabled = YES;
    
    [self setBackgroundImage:_backgroundImage(@"OUIInspectorButton-Normal.png") forState:UIControlStateNormal];
    [self setBackgroundImage:_backgroundImage(@"OUIInspectorButton-Selected.png") forState:UIControlStateSelected];
    [self setBackgroundImage:_backgroundImage(@"OUIInspectorButton-Highlighted.png") forState:UIControlStateHighlighted];

    [self setTitleColor:[OUIInspector labelTextColor] forState:UIControlStateNormal];
    [self setTitleColor:[OUIInspector disabledLabelTextColor] forState:UIControlStateDisabled];
    [self setTitleShadowColor:OUIShadowColor(OUIShadowTypeDarkContentOnLightBackground) forState:UIControlStateNormal];
    
    self.titleLabel.shadowOffset = OUIShadowOffset(OUIShadowTypeDarkContentOnLightBackground);

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
    [_image release];
    [super dealloc];
}

@synthesize image = _image;
- (void)setImage:(UIImage *)image;
{
    if (_image == image)
        return;
    [_image release];
    _image = [image retain];
    
    [self setImage:(image ? OUIMakeShadowedImage(image, OUIShadowTypeDarkContentOnLightBackground) : nil) forState:UIControlStateNormal];
}

#pragma mark - UIView (OUIExtensions)

- (UIEdgeInsets)borderEdgeInsets;
{
    return UIEdgeInsetsMake(0/*top*/, 0/*left*/, 2/*bottom*/, 0/*right*/);
}

#pragma mark - UIView subclass

- (CGSize)sizeThatFits:(CGSize)size;
{
    return CGSizeMake(size.width, kOUIInspectorWellHeight);
}

#ifdef OMNI_ASSERTIONS_ON
- (void)layoutSubviews;
{
    OBASSERT(CGRectEqualToRect(self.bounds, CGRectZero) || self.bounds.size.height == kOUIInspectorWellHeight);
    [super layoutSubviews];
}
#endif

@end
