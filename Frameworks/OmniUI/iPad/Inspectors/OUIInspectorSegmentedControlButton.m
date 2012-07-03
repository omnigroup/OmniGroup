// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSegmentedControlButton.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniBase/OmniBase.h>
#import <UIKit/UIImage.h>
#import <OmniUI/OUIInspector.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@interface OUIInspectorSegmentedControlButton (/*Private*/)
- (void)_updateBackgroundImages;
@end

@implementation OUIInspectorSegmentedControlButton
{
    OUIInspectorSegmentedControlButtonPosition _buttonPosition;
    UIImage *_image;
    id _representedObject;
    BOOL _dark;
}

typedef struct {
    NSString *normal;
    NSString *selected;
} ImageNames;

static const ImageNames BackgroundImageNames[] = {
    [OUIInspectorSegmentedControlButtonPositionLeft] = {@"OUISegmentLeftEndNormal.png", @"OUISegmentLeftEndSelected.png"},
    [OUIInspectorSegmentedControlButtonPositionRight] = {@"OUISegmentRightEndNormal.png", @"OUISegmentRightEndSelected.png"},
    [OUIInspectorSegmentedControlButtonPositionCenter] = {@"OUISegmentMiddleNormal.png", @"OUISegmentMiddleSelected.png"},
};

static const ImageNames DarkBackgroundImageNames[] = {
    [OUIInspectorSegmentedControlButtonPositionLeft] = {@"OUIDarkSegmentLeftEndNormal.png", @"OUIDarkSegmentLeftEndSelected.png"},
    [OUIInspectorSegmentedControlButtonPositionRight] = {@"OUIDarkSegmentRightEndNormal.png", @"OUIDarkSegmentRightEndSelected.png"},
    [OUIInspectorSegmentedControlButtonPositionCenter] = {@"OUIDarkSegmentMiddleNormal.png", @"OUIDarkSegmentMiddleSelected.png"},
};

static UIImage *_loadImage(NSString *imageName, OUIInspectorSegmentedControlButtonPosition position)
{
    UIImage *image = [UIImage imageNamed:imageName];
    OBASSERT(image);
    
    // These images are all even width. The amount of end-cap stretching needs to be based on whether this is left or right (the center images work either way).
    
    OBASSERT(image.size.width == 20);
    OBASSERT(image.size.height == kOUIInspectorWellHeight);

    // There are still some dark images that are not 20 wide
    // This code can go away when they are fixed
    if (image.size.width == 13) {
        UIEdgeInsets edgeInsets = (UIEdgeInsets){.left = 6, .right = 6};
        return [image resizableImageWithCapInsets:edgeInsets];
    }

    const CGFloat roundCapWidth = 12;
    const CGFloat flatCapWidth = 7;
    
    UIEdgeInsets edgeInsets;
    if (position == OUIInspectorSegmentedControlButtonPositionLeft)
        edgeInsets = (UIEdgeInsets){.left = roundCapWidth, .right = flatCapWidth};
    else
        edgeInsets = (UIEdgeInsets){.left = flatCapWidth, .right = roundCapWidth};
    
    return [image resizableImageWithCapInsets:edgeInsets];
}

static id _commonInit(OUIInspectorSegmentedControlButton *self)
{
    [self setTitleColor:[OUIInspector labelTextColor] forState:UIControlStateNormal];
    [self setTitleColor:[OUIInspector disabledLabelTextColor] forState:UIControlStateDisabled];
    [self setTitleShadowColor:OUIShadowColor(OUIShadowTypeDarkContentOnLightBackground) forState:UIControlStateNormal];
    self.titleLabel.shadowOffset = OUIShadowOffset(OUIShadowTypeDarkContentOnLightBackground);
    
    [self _updateBackgroundImages];
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
    [_image release];
    [_representedObject release];
    [super dealloc];
}

@synthesize buttonPosition = _buttonPosition;
- (void)setButtonPosition:(OUIInspectorSegmentedControlButtonPosition)buttonPosition;
{
    OBASSERT_NONNEGATIVE(buttonPosition);
    OBPRECONDITION(buttonPosition < _OUIInspectorSegmentedControlButtonPositionCount);
    if (buttonPosition >= _OUIInspectorSegmentedControlButtonPositionCount)
        buttonPosition = OUIInspectorSegmentedControlButtonPositionCenter;

    if (_buttonPosition == buttonPosition)
        return;
    _buttonPosition = buttonPosition;
    [self _updateBackgroundImages];
}

@synthesize image = _image;
- (void)setImage:(UIImage *)image;
{
    if (_image == image)
        return;
    [_image release];
    _image = [image retain];
    
    if ([self dark])
        [self setImage:(image ? OUIMakeShadowedImage(image, OUIShadowTypeLightContentOnDarkBackground) : nil) forState:UIControlStateNormal];
    else
        [self setImage:(image ? OUIMakeShadowedImage(image, OUIShadowTypeDarkContentOnLightBackground) : nil) forState:UIControlStateNormal];
}

@synthesize representedObject = _representedObject;

- (void)addTarget:(id)target action:(SEL)action;
{
    [super addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
}

@synthesize dark = _dark;

- (void)setDark:(BOOL)flag;
{
    _dark = flag;
    [self _updateBackgroundImages];
}

#pragma mark -
#pragma mark Private

- (void)_updateBackgroundImages;
{
    OUIInspectorSegmentedControlButtonPosition buttonPosition = _buttonPosition;
    OBASSERT_NONNEGATIVE(buttonPosition);
    OBASSERT(buttonPosition < _OUIInspectorSegmentedControlButtonPositionCount);
    if (buttonPosition >= _OUIInspectorSegmentedControlButtonPositionCount)
        buttonPosition = OUIInspectorSegmentedControlButtonPositionCenter;
    
    const ImageNames *backgroundImageNames = (_dark) ? &DarkBackgroundImageNames[buttonPosition] : &BackgroundImageNames[buttonPosition];
    [self setBackgroundImage:_loadImage(backgroundImageNames->normal, buttonPosition) forState:UIControlStateNormal];
    [self setBackgroundImage:_loadImage(backgroundImageNames->selected, buttonPosition) forState:UIControlStateSelected];
}

@end
