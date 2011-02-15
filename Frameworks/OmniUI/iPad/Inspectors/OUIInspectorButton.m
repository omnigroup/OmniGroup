// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorButton.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniBase/OmniBase.h>
#import <OmniUI/OUIInspector.h>

RCS_ID("$Id$");

@implementation OUIInspectorButton

static UIImage *_backgroundImage(NSString *name)
{
    UIImage *image = [UIImage imageNamed:name];
    OBASSERT(image);
    return [image stretchableImageWithLeftCapWidth:6 topCapHeight:0];
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

@end
