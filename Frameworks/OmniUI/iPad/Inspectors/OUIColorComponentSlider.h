// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIControl.h>

@class UILabel;
@class OQColor;
@class OUIColorComponentSliderKnobLayer;

@interface OUIColorComponentSlider : UIControl
{
@private
    CGFloat _range;
    NSString *_formatString;
    UILabel *_label;
    BOOL _representsAlpha;
    BOOL _needsShading;
    
    CGFloat _value; // Our component's value
    OQColor *_color; // The full calculated color
    
    NSTextAlignment _lastLabelAlignment;
    CGFloat _leftLuma;
    CGFloat _rightLuma;
    
    OUIColorComponentSliderKnobLayer *_knobLayer;

    // One of these should be set.
    CGFunctionRef _backgroundShadingFunction;
    CGGradientRef _backgroundGradient;
    
    BOOL _inMiddleOfTouch;
}

+ (id)slider;

@property(assign,nonatomic) CGFloat range;
@property(copy,nonatomic) NSString *formatString;
@property(assign,nonatomic) BOOL representsAlpha;
@property(assign,nonatomic) BOOL needsShading; // gets a gradient otherwise

@property(retain,nonatomic) OQColor *color;
@property(assign,nonatomic) CGFloat value;

@property(assign,nonatomic) CGFloat leftLuma;
@property(assign,nonatomic) CGFloat rightLuma;

@property(readonly) BOOL inMiddleOfTouch;

- (void)updateBackgroundShadingUsingFunction:(CGFunctionRef)shadingFunction;
- (void)updateBackgroundShadingUsingGradient:(CGGradientRef)gradient;

@end
