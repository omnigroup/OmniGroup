// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIHSVColorPicker.h"

#import <OmniUI/OUIColorComponentSlider.h>
#import <OmniQuartz/OQColor.h>

RCS_ID("$Id$");

@implementation OUIHSVColorPicker

#pragma mark -
#pragma mark OUIComponentColorPicker

- (NSString *)identifier;
{
    return @"hsv";
}

- (OQColorSpace)colorSpace;
{
    return OQColorSpaceHSV;
}

- (NSArray *)makeComponentSliders;
{
    NSMutableArray *sliders = [NSMutableArray array];
    
    OUIColorComponentSlider *hue = [OUIColorComponentSlider slider];
    hue.range = 360;
    hue.formatString = NSLocalizedStringWithDefaultValue(@"<hue title+value>", @"OUIInspectors", OMNI_BUNDLE, @"Hue: %d°", @"title format for color component slider - hue angle in HSV model, degrees");
    hue.needsShading = YES; // We cannot due hue via linear interpolation in RGB space.
    [sliders addObject:hue];
    
    OUIColorComponentSlider *saturation = [OUIColorComponentSlider slider];
    saturation.range = 100;
    saturation.formatString = NSLocalizedStringWithDefaultValue(@"<saturation title+value>", @"OUIInspectors", OMNI_BUNDLE, @"Saturation: %d%%", @"title format for color component slider - saturation component in HSV model, 0-100");
    [sliders addObject:saturation];
    
    OUIColorComponentSlider *value = [OUIColorComponentSlider slider];
    value.range = 100;
    value.formatString = NSLocalizedStringWithDefaultValue(@"<brightness title+value>", @"OUIInspectors", OMNI_BUNDLE, @"Brightness: %d%%", @"title format for color component slider - value/brightness component in HSV model, 0-100");
    [sliders addObject:value];
    
    OUIColorComponentSlider *alpha = [OUIColorComponentSlider slider];
    alpha.range = 100;
    alpha.formatString = NSLocalizedStringWithDefaultValue(@"<alpha title+value>", @"OUIInspectors", OMNI_BUNDLE, @"Opacity: %d%%", @"title format for color component slider - alpha component, 0-100");
    alpha.representsAlpha = YES;
    [sliders addObject:alpha];
    
    return sliders;
}

- (void)extractComponents:(CGFloat *)components fromColor:(OQColor *)color;
{
    OSHSV hsv = [color toHSV];
    components[0] = hsv.h;
    components[1] = hsv.s;
    components[2] = hsv.v;
    components[3] = hsv.a;
}

- (OQColor *)makeColorWithComponents:(const CGFloat *)components;
{
    return [OQColor colorWithHue:components[0] saturation:components[1] brightness:components[2] alpha:components[3]];
}

static OQLinearRGBA _convertHSVAToRGBA(const CGFloat *input)
{
    OSHSV hsva;
    hsva.h = input[0];
    hsva.s = input[1];
    hsva.v = input[2];
    hsva.a = input[3];
    return OQHSVToRGB(hsva);
}

- (OUIComponentColorPickerConvertToRGB)rgbaComponentConverter;
{
    return _convertHSVAToRGBA;
}

@end
