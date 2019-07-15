// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIControl.h>

@class UILabel;
@class OAColor;
@class OUIColorComponentSliderKnobLayer;

@interface OUIColorComponentSlider : UIControl

+ (id)slider;

@property(nonatomic) CGFloat range;
@property(copy,nonatomic) NSString *formatString;
@property(nonatomic) BOOL representsAlpha;
@property(nonatomic) BOOL needsShading; // gets a gradient otherwise

@property(strong,nonatomic) OAColor *color;
@property(nonatomic) CGFloat value;

@property(nonatomic) CGFloat leftLuma;
@property(nonatomic) CGFloat rightLuma;

@property(readonly,nonatomic) BOOL inMiddleOfTouch;

- (void)updateBackgroundShadingUsingFunction:(CGFunctionRef)shadingFunction;
- (void)updateBackgroundShadingUsingGradient:(CGGradientRef)gradient;

@end
