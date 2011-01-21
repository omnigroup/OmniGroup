// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorToggleButton.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniBase/OmniBase.h>
#import <OmniUI/OUIInspector.h>

RCS_ID("$Id$");

@implementation OUIInspectorToggleButton

static UIImage *NormalBackgroundImage = nil;
static UIImage *SelectedBackgroundImage = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    NormalBackgroundImage = [[[UIImage imageNamed:@"OUIToggleButtonNormal.png"] stretchableImageWithLeftCapWidth:6 topCapHeight:0] retain];
    SelectedBackgroundImage = [[[UIImage imageNamed:@"OUIToggleButtonSelected.png"] stretchableImageWithLeftCapWidth:6 topCapHeight:0] retain];
}

static id _commonInit(OUIInspectorToggleButton *self)
{
    self.opaque = NO;
    self.backgroundColor = nil;
    self.clearsContextBeforeDrawing = YES;
    
    self.adjustsImageWhenHighlighted = YES;
    self.adjustsImageWhenDisabled = YES;
    
    [self setBackgroundImage:NormalBackgroundImage forState:UIControlStateNormal];
    [self setBackgroundImage:SelectedBackgroundImage forState:UIControlStateSelected];

    [self setTitleColor:[OUIInspector labelTextColor] forState:UIControlStateNormal];
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
