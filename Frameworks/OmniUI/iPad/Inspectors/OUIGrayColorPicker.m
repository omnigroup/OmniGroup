// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIGrayColorPicker.h"

#import <OmniUI/OUIColorComponentSlider.h>
#import <OmniQuartz/OQColor.h>

RCS_ID("$Id$");

@implementation OUIGrayColorPicker

#pragma mark -
#pragma mark OUIComponentColorPicker

- (NSString *)identifier;
{
    return @"gray";
}

- (OQColorSpace)colorSpace;
{
    return OQColorSpaceWhite;
}

- (NSArray *)makeComponentSliders;
{
    NSMutableArray *sliders = [NSMutableArray array];
    
    OUIColorComponentSlider *white = [OUIColorComponentSlider slider];
    white.range = 100;
    white.formatString = NSLocalizedStringWithDefaultValue(@"<white title+value>", @"OUIInspectors", OMNI_BUNDLE, @"White: %d%%", @"title format for color component slider");
    [sliders addObject:white];
    
    OUIColorComponentSlider *alpha = [OUIColorComponentSlider slider];
    alpha.range = 100;
    alpha.formatString = NSLocalizedStringWithDefaultValue(@"<alpha title+value>", @"OUIInspectors", OMNI_BUNDLE, @"Opacity: %d%%", @"title format for color component slider");
    alpha.representsAlpha = YES;
    [sliders addObject:alpha];
    
    return sliders;
}

- (void)extractComponents:(CGFloat *)components fromColor:(OQColor *)color;
{
    components[0] = [color whiteComponent];
    components[1] = [color alphaComponent];
}

- (OQColor *)makeColorWithComponents:(const CGFloat *)components;
{
    return [OQColor colorWithWhite:components[0] alpha:components[1]];
}

static OQLinearRGBA _convertGrayToRGBA(const CGFloat *input)
{
    OQLinearRGBA rgba;
    CGFloat w = input[0];
    rgba.r = w;
    rgba.g = w;
    rgba.b = w;
    rgba.a = input[1];
    return rgba;
}

- (OUIComponentColorPickerConvertToRGB)rgbaComponentConverter;
{
    return _convertGrayToRGBA;
}

@end
