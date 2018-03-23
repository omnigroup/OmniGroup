// Copyright 2010-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorComponentSlider.h>

#import <OmniUI/OUIInspectorWell.h>
#import <OmniUI/OUIDrawing.h>
#import <OmniAppKit/OAColor.h>
#import <OmniQuartz/OQDrawing.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@interface OUIColorComponentSliderKnobLayer : CALayer
{
@private
    OAColor *_color;
}
@property(strong,nonatomic) OAColor *color;
@end

@implementation OUIColorComponentSliderKnobLayer

static UIImage *_handleImage(void)
{
    UIImage *image = [UIImage imageNamed:@"OUIColorComponentSliderKnob.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    OBASSERT(image);
    return image;
}

static CGSize KnobSize;
static const CGFloat kKnobBorderThickness = 6;


+ (void)initialize;
{
    OBINITIALIZE;
    
    KnobSize = [_handleImage() size];
}

- (void)setColor:(OAColor *)color;
{
    _color = color;
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark CALayer subclass

- (void)drawInContext:(CGContextRef)ctx;
{
    CGRect bounds = self.bounds;
    OBASSERT(CGSizeEqualToSize(bounds.size, KnobSize));
    
    UIGraphicsPushContext(ctx);
    {
        // Swatch
            CGContextSaveGState(ctx);
            {
                if ([_color alphaComponent] < 1) {
                    CGPoint patternOffset = [self convertPoint:CGPointMake(1, 1) fromLayer:self.superlayer];
                    OUIDrawTransparentColorBackground(ctx, CGRectInset(bounds, kKnobBorderThickness, kKnobBorderThickness), CGSizeMake(patternOffset.x, patternOffset.y));
                }
                
                [_color set];
                CGContextFillRect(ctx, CGRectInset(bounds, kKnobBorderThickness, kKnobBorderThickness));
            }
            CGContextRestoreGState(ctx);
        
        // Overlay the cached knob
        [_handleImage() drawInRect:bounds];
    }
    UIGraphicsPopContext();
}

@end


@implementation OUIColorComponentSlider
{
    CGFloat _range;
    NSString *_formatString;
    UILabel *_label;
    BOOL _representsAlpha;
    BOOL _needsShading;
    
    CGFloat _value; // Our component's value
    OAColor *_color; // The full calculated color
    
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
{
    return [[self alloc] initWithFrame:CGRectZero];
}

static id _commonInit(OUIColorComponentSlider *self)
{
    self->_range = 100;
    self->_formatString = @"%d %%";
    self->_lastLabelAlignment = NSTextAlignmentCenter; // "Unknown"
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;
    
    self.clearsContextBeforeDrawing = YES;
    self.opaque = NO;
    self.backgroundColor = nil;
    self.layer.needsDisplayOnBoundsChange = YES;
    self.color = nil;

    [self setNeedsLayout];
    
    self->_knobLayer = [[OUIColorComponentSliderKnobLayer alloc] init];
    self->_knobLayer.needsDisplayOnBoundsChange = YES;
    self->_knobLayer.anchorPoint = CGPointZero; // don't want half pixels from setting the position (our width/height are odd).
    self->_knobLayer.contentsScale = _handleImage().scale;
    [self->_knobLayer setNeedsDisplay];

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
    if (_backgroundShadingFunction)
        CFRelease(_backgroundShadingFunction);
    if (_backgroundGradient)
        CFRelease(_backgroundGradient);
}

- (void)setRange:(CGFloat)range;
{
    if (_range == range)
        return;
    _range = range;
    [self setNeedsLayout];
}

- (void)setFormatString:(NSString *)formatString;
{
    if (OFISEQUAL(_formatString, formatString))
        return;
    _formatString = [formatString copy];
    [self setNeedsLayout];
}

- (void)setRepresentsAlpha:(BOOL)flag;
{
    if (_representsAlpha == flag)
        return;
    _representsAlpha = flag;
    [self setNeedsDisplay];
}

// We want the knob interior to show the calculated color
- (void)setColor:(OAColor *)color;
{
    if (color == nil) {
        // Sliders require a color (even if it's a transparent one). If you want no color, you have to go back to the No Color choice.
        color = [OAColor colorWithWhite:1.0 alpha:0.0];
    }

    if (OFISEQUAL(_color, color))
        return;
    
    _color = color;
    
    if (_representsAlpha == NO)
        // Our knob should display an opaque color unless we are the alpha slider
        color = [color colorWithAlphaComponent:1];
    
    _knobLayer.color = color;
}

// This cannot be named "alpha". Otherwise when it reaches zero, hit testing will trivially return NO as if we were hidden.
- (void)setValue:(CGFloat)value;
{
    if (_value == value)
        return;

    _value = value;
    
    [self setNeedsLayout];
}

- (void)setLeftLuma:(CGFloat)luma;
{
    if (_leftLuma == luma)
        return;
    _leftLuma = luma;
    [self setNeedsLayout];
}

- (void)setRightLuma:(CGFloat)luma;
{
    if (_rightLuma == luma)
        return;
    _rightLuma = luma;
    [self setNeedsLayout];
}

static CGFloat _valueToX(OUIColorComponentSlider *self, CGFloat value)
{
    if (value < 0)
        value = 0;
    else if (value > 1)
        value = 1;
    
    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds) - KnobSize.width;
    
    CGFloat x = value * width + ceil(KnobSize.width/2); // 1/2 knob size on each end

    return x;
}

static CGFloat _xToValue(OUIColorComponentSlider *self, CGFloat x)
{
    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds) - KnobSize.width;
    
    CGFloat value = (x - ceil(KnobSize.width/2)) / width; // 1/2 knob size on each end

    if (value < 0)
        value = 0;
    else if (value > 1)
        value = 1;

    return value;
}

- (void)updateBackgroundShadingUsingFunction:(CGFunctionRef)shadingFunction;
{
    OBPRECONDITION(_needsShading); // This will be more expensive, so don't call it needlessly.
    OBPRECONDITION(_backgroundGradient == NULL);
    
    if (_backgroundShadingFunction == shadingFunction)
        return;

    if (_backgroundShadingFunction) {
        CFRelease(_backgroundShadingFunction);
        _backgroundShadingFunction = NULL;
    }
  
    if (shadingFunction) {
        CFRetain(shadingFunction);        
        _backgroundShadingFunction = shadingFunction;
    }
    
    [self setNeedsDisplay];
}

- (void)updateBackgroundShadingUsingGradient:(CGGradientRef)gradient;
{
    OBPRECONDITION(_needsShading == NO);
    OBPRECONDITION(_backgroundShadingFunction == NULL);
    
    if (_backgroundGradient == gradient)
        return;
    
    if (_backgroundGradient) {
        CFRelease(_backgroundGradient);
        _backgroundGradient = NULL;
    }
    
    if (gradient) {
        CFRetain(gradient);        
        _backgroundGradient = gradient;
    }
    
    [self setNeedsDisplay];
    
}

#pragma mark -
#pragma mark UIControl subclass

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
{
    // Multi-touch should be off, so we should get only one begin/{end|cancel} cycle.
    OBPRECONDITION(!self.multipleTouchEnabled);
    OBPRECONDITION([[event touchesForView:self] count] <= 1);

    [self sendActionsForControlEvents:UIControlEventTouchDown];
    
    OBASSERT(_inMiddleOfTouch == NO);
    _inMiddleOfTouch = YES;
    
    [self _setValueFromDragTouch:touch];
    return YES; // we want contiuous tracking
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
{
    // Multi-touch should be off, so we should get only one begin/{end|cancel} cycle.
    OBPRECONDITION(!self.multipleTouchEnabled);
    OBPRECONDITION([[event touchesForView:self] count] <= 1);
    OBASSERT(_inMiddleOfTouch == YES);

    [self _setValueFromDragTouch:touch];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
{
    OBASSERT(_inMiddleOfTouch == YES);
    _inMiddleOfTouch = NO;

    [super endTrackingWithTouch:touch withEvent:event];

    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event;
{
    OBASSERT(_inMiddleOfTouch == YES);
    _inMiddleOfTouch = NO;

    [super cancelTrackingWithEvent:event];

    [self sendActionsForControlEvents:UIControlEventTouchCancel];
}

#pragma mark UIView subclass

- (CGSize)sizeThatFits:(CGSize)size;
{
    return CGSizeMake(size.width, 37);
}

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    OUIInspectorWellDraw(ctx, self.bounds,
                         OUIInspectorWellCornerTypeSmallRadius, OUIInspectorWellBorderTypeLight, NO/*innerShadow*/, NO/*outerShadow*/,
                         ^(CGRect interiorRect){
        // All the non-alpha channels should be opaque and don't need this checkerboard
        if ([self representsAlpha]) {
            OUIDrawTransparentColorBackground(ctx, CGRectInset(bounds, 1, 1), CGSizeMake(1,1));
        }
        
        if (self.enabled) {
            // Reserve 1/2 end cap size for the extremes on the slider and then extend the shading into those end areas
            CGFloat endCapSize = CGRectGetHeight(bounds);
            CGFloat reserve = endCapSize/2;
            
            CGPoint startPoint = CGPointMake(CGRectGetMinX(bounds) + reserve, CGRectGetMinY(bounds));
            CGPoint endPoint = CGPointMake(CGRectGetMaxX(bounds) - reserve, CGRectGetMinY(bounds));
            
            if (_backgroundGradient) {
                CGContextDrawLinearGradient(ctx, _backgroundGradient, startPoint, endPoint, kCGGradientDrawsBeforeStartLocation|kCGGradientDrawsAfterEndLocation);
            } else if (_backgroundShadingFunction) {
                CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
                CGShadingRef shading = CGShadingCreateAxial(colorSpace, startPoint, endPoint, _backgroundShadingFunction, YES, YES);
                CGColorSpaceRelease(colorSpace);
                CGContextDrawShading(ctx, shading);
                CGShadingRelease(shading);
            }
        }
    });
}

- (void)layoutSubviews;
{
    CGRect wellInnerRect = OUIInspectorWellInnerRect(self.bounds);
    _knobLayer.bounds = CGRectMake(0, 0, KnobSize.width, KnobSize.height);
    
    CGPoint position;
    position.x = floor(_valueToX(self, _value) - KnobSize.width/2);
    position.y = floor(CGRectGetMidY(wellInnerRect) - KnobSize.height/2);
    
    _knobLayer.position = position;
    
    if (_knobLayer.superlayer != self.layer)
        [self.layer addSublayer:_knobLayer];
    
    if (_formatString) {
        if (!_label) {
            _label = [[UILabel alloc] init];
            _label.font = [UIFont boldSystemFontOfSize:[UIFont systemFontSize]];
            _label.backgroundColor = nil;
            _label.opaque = NO;
            _label.clearsContextBeforeDrawing = YES;
        }
        
        NSString *labelString = [[NSString alloc] initWithFormat:_formatString, (int)rint(_range * _value)];
        _label.text = labelString;
        
        [_label sizeToFit];
        
        const CGFloat kLabelPadding = 8;
        
        CGRect bounds = self.bounds;
        CGRect labelFrame = _label.frame;
        
        CGFloat luma;
        
        // Pick a direction -- might want to just stay where we are in the middle.
        BOOL shouldGoLeft = _value > 0.55;
        BOOL shouldGoRight = _value < 0.45;
        
        // But if we've never picked, we have to pick at least once
        if (_lastLabelAlignment == NSTextAlignmentCenter && !shouldGoLeft && !shouldGoRight)
            shouldGoLeft = YES;
        
        if (shouldGoLeft) {
            labelFrame.origin.x = CGRectGetMinX(bounds) + kLabelPadding;
            _lastLabelAlignment = NSTextAlignmentLeft;
        } else if (shouldGoRight) {
            labelFrame.origin.x = CGRectGetMaxX(bounds) - labelFrame.size.width - kLabelPadding;
            _lastLabelAlignment = NSTextAlignmentRight;
        }
        labelFrame.origin.y = rint(CGRectGetMinY(bounds) + 0.5*(CGRectGetHeight(bounds) - CGRectGetHeight(labelFrame)));
        
        OBASSERT(_lastLabelAlignment == NSTextAlignmentLeft || _lastLabelAlignment == NSTextAlignmentRight);
        if (_lastLabelAlignment == NSTextAlignmentLeft) {
            // We ignore the supposed luma of the left side for alpha since it always fades to the light checkerboard
            if (_representsAlpha)
                luma = 255;
            else
                luma = _leftLuma;
        } else {
            luma = _rightLuma;
        }
        
        if (!self.enabled) {
            _label.textColor = [UIColor blackColor];
            _label.shadowColor = nil;
        } else if (luma < 0.5) {
            _label.textColor = [UIColor whiteColor];
            _label.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
        } else {
            _label.textColor = [UIColor blackColor];
            _label.shadowColor = [UIColor colorWithWhite:1 alpha:0.5];
        }
        
        _label.frame = labelFrame;
        if (_label.superview != self)
            [self addSubview:_label];
        
    } else {
        [_label removeFromSuperview];
    }
    
}

#pragma mark -
#pragma mark Private

- (void)_setValueFromDragTouch:(UITouch *)touch;
{
    CGPoint point = [touch locationInView:self];
    CGFloat value = _xToValue(self, point.x);
        
    if (value == _value)
        return;
    
    // User drag is driving this animation, but there will be a round trip between us and our color picker where it integrates our input into the color. W/o this structure, the checkerboard inside the alpha knob will jitter a bit as we drag.
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    {
        // Update our value
        self.value = _xToValue(self, point.x);
        
        // Inform the picker, inside the animation block and before our layout/display, as it will call back and set our knob's color
        [self sendActionsForControlEvents:UIControlEventValueChanged];

        // Finally, make sure everything gets displayed together.
        [self layoutIfNeeded];
        [_knobLayer displayIfNeeded];
    }
    [CATransaction commit];
}

@end
