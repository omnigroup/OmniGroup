// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIColorPicker.h>
#import <OmniUI/OUIColorValue.h>
#import <OmniAppKit/OAColor.h>

/*
 A color picker that uses one or more floating point components to build its color.
 */

typedef OALinearRGBA (*OUIComponentColorPickerConvertToRGB)(const CGFloat *input);
                                                    
@interface OUIComponentColorPicker : OUIColorPicker <OUIColorValue>
{
@private
    NSArray *_componentSliders;
}

// Required subclass methods
- (OAColorSpace)colorSpace;
- (NSArray *)makeComponentSliders;
- (void)extractComponents:(CGFloat *)components fromColor:(OAColor *)color; // The count of the result of -makeComponentSliders determines the size of 'components'.
- (OAColor *)makeColorWithComponents:(const CGFloat *)components;
- (OUIComponentColorPickerConvertToRGB)rgbaComponentConverter;

@end
