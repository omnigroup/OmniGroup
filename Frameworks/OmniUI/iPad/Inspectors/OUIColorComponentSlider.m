// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorComponentSlider.h>

#import <OmniUI/OUIInspectorWell.h>
#import <OmniUI/OUIDrawing.h>
#import <OmniQuartz/OQColor.h>
#import <OmniQuartz/OQDrawing.h>

RCS_ID("$Id$");



@interface OUIColorComponentSliderKnobLayer : CALayer
{
@private
    OQColor *_color;
    BOOL _enabled;
    CGGradientRef KnobGradient;
    UIImage *KnobHandleImage;
}
@property(retain,nonatomic) OQColor *color;
@property(assign,nonatomic) BOOL enabled;
@end

@implementation OUIColorComponentSliderKnobLayer

static UIColor *BackgroundCheckerboardPatternColor = nil;

static const CGSize KnobSize = {35, 49};
static const CGFloat kKnobBorderThickness = 6;


+ (void)initialize;
{
    OBINITIALIZE;
}

- (void)dealloc;
{
    [_color release];
    CGGradientRelease(KnobGradient);
    [KnobHandleImage release];
    [super dealloc];
}

@synthesize color = _color;
- (void)setColor:(OQColor *)color;
{
    [_color autorelease];
    _color = [color retain];
    [self setNeedsDisplay];
}

@synthesize enabled = _enabled;
- (void)setEnabled:(BOOL)yn;
{
    if (yn == _enabled && KnobGradient != nil)
        return;
        
    _enabled = yn;
    
    CGGradientRelease(KnobGradient);
    [KnobHandleImage release];
    KnobHandleImage = nil;

    id translucentColor = NULL;
    id whiteColor = NULL;
    
    if (_enabled) {
        translucentColor = (id)[[UIColor colorWithWhite:1.0 alpha:0.85] CGColor];
        whiteColor = (id)[[UIColor colorWithWhite:1.0 alpha:1.0] CGColor];
    } else {
        translucentColor = (id)[[UIColor colorWithWhite:0.6 alpha:0.85] CGColor];
        whiteColor = (id)[[UIColor colorWithWhite:0.6 alpha:1.0] CGColor];
    }
    
    CGFloat locations[] = {0, 0.5, 0.5, 1.0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    KnobGradient = CGGradientCreateWithColors(colorSpace, (CFArrayRef)[NSArray arrayWithObjects:translucentColor, whiteColor, translucentColor, translucentColor, nil], locations);
    CFRelease(colorSpace);
    
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark CALayer subclass

static void _drawGripper(CGContextRef ctx, CGRect bounds, CGPoint pt)
{    
    CGContextSaveGState(ctx);
    {
        CGRect center = CGRectMake(pt.x,     pt.y, 1, 3);
        CGRect   left = CGRectMake(pt.x - 2, pt.y, 1, 3);
        CGRect  right = CGRectMake(pt.x + 2, pt.y, 1, 3);
        
        CGContextAddRect(ctx, center);
        CGContextAddRect(ctx, left);
        CGContextAddRect(ctx, right);

        CGContextClip(ctx);
        
        // RGB colors so the gradient works (giving it RGB color space)
        CGFloat dark = 0.45;
        CGFloat light = 0.7;
        CGColorRef darkColor = [[UIColor colorWithRed:dark green:dark blue:dark alpha:1] CGColor];
        CGColorRef lightColor = [[UIColor colorWithRed:light green:light blue:light alpha:1] CGColor];
                                 
        NSArray *colors = [NSArray arrayWithObjects:(id)darkColor, (id)lightColor, nil];
        
        
        CGGradientRef gradient = CGGradientCreateWithColors(NULL/*rgb*/, (CFArrayRef)colors, NULL);
        
        
        CGContextDrawLinearGradient(ctx, gradient,
                                    center.origin,
                                    CGPointMake(CGRectGetMaxX(center), CGRectGetMaxY(center)),
                                    kCGGradientDrawsBeforeStartLocation|kCGGradientDrawsAfterEndLocation);
        CFRelease(gradient);
    }
    CGContextRestoreGState(ctx);
}

- (void)drawInContext:(CGContextRef)ctx;
{
    CGRect bounds = self.bounds;
    OBASSERT(CGSizeEqualToSize(bounds.size, KnobSize));
    
    // We don't really want to rasterize this up to 4 times each time we drag a knob.
    if (!KnobHandleImage) {
        UIGraphicsBeginImageContext(KnobSize);
        {
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            
            CGContextClearRect(ctx, bounds);
            
            // Box-o-shine
            CGContextSaveGState(ctx);
            {
                OQAppendRoundedRect(ctx, CGRectInset(bounds, 1, 1), 1);
                OQAppendRoundedRect(ctx, CGRectInset(bounds, kKnobBorderThickness + 0.5, kKnobBorderThickness + 0.5), 4);
                CGContextEOClip(ctx);
                
                CGContextDrawLinearGradient(ctx, KnobGradient, bounds.origin, CGPointMake(bounds.origin.x, CGRectGetMaxY(bounds)), kCGGradientDrawsBeforeStartLocation|kCGGradientDrawsAfterEndLocation);
            }
            CGContextRestoreGState(ctx);
            
            // Border
            CGContextSaveGState(ctx);
            {
                // Drawing this w/o an inner shadow. I tried it and it distorts my perception of the picked color.
                OQAppendRoundedRect(ctx, CGRectInset(bounds, 0.5, 0.5), 1);
                OQAppendRoundedRect(ctx, CGRectInset(bounds, kKnobBorderThickness + 0.5, kKnobBorderThickness + 0.5), 4);
                OUIInspectorWellStrokePathWithBorderColor(ctx);
            }
            CGContextRestoreGState(ctx);
            
            // Gripper
            _drawGripper(ctx, bounds, CGPointMake(CGRectGetMidX(bounds) - 0.5, 2));
            _drawGripper(ctx, bounds, CGPointMake(CGRectGetMidX(bounds) - 0.5, CGRectGetMaxY(bounds) - 2 - 3));
            
            KnobHandleImage = [UIGraphicsGetImageFromCurrentImageContext() retain];
        }
        UIGraphicsEndImageContext();
    }
    
    UIGraphicsPushContext(ctx);
    {
        // Swatch
            CGContextSaveGState(ctx);
            {
                if ([_color alphaComponent] < 1 || !_enabled) {
                    CGPoint patternOffset = [self convertPoint:CGPointMake(1, 1) fromLayer:self.superlayer];
                    CGContextSetPatternPhase(ctx, CGSizeMake(patternOffset.x, patternOffset.y));
                    [BackgroundCheckerboardPatternColor set];
                    CGContextFillRect(ctx, CGRectInset(bounds, kKnobBorderThickness, kKnobBorderThickness));
                }
                
                if (_enabled) {
                    [_color set];
                    CGContextFillRect(ctx, CGRectInset(bounds, kKnobBorderThickness, kKnobBorderThickness));
                }
            }
            CGContextRestoreGState(ctx);
        
        // Overlay the cached knob
        [KnobHandleImage drawInRect:bounds];
    }
    UIGraphicsPopContext();
}

@end

@interface OUIColorComponentSlider (/*Private*/)
- (void)_setValueFromDragTouch:(UITouch *)touch;
@end

@implementation OUIColorComponentSlider

+ (void)initialize;
{
    OBINITIALIZE;
    
    UIImage *patternImage = [UIImage imageNamed:@"OUIColorOpacitySliderBackground.png"];
    BackgroundCheckerboardPatternColor = [[UIColor alloc] initWithPatternImage:patternImage];
}

+ (id)slider;
{
    return [[[self alloc] initWithFrame:CGRectZero] autorelease];
}

static id _commonInit(OUIColorComponentSlider *self)
{
    self->_range = 100;
    self->_formatString = @"%d %%";
    self->_lastLabelAlignment = UITextAlignmentCenter; // "Unknown"
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;
    
    self.clearsContextBeforeDrawing = YES;
    self.opaque = NO;
    self.backgroundColor = nil;
    self.layer.needsDisplayOnBoundsChange = YES;
    [self setNeedsLayout];
    
    self->_knobLayer = [[OUIColorComponentSliderKnobLayer alloc] init];
    self->_knobLayer.needsDisplayOnBoundsChange = YES;
    self->_knobLayer.anchorPoint = CGPointZero; // don't want half pixels from setting the position (our width/height are odd).
    [self->_knobLayer setNeedsDisplay];
    self->_knobLayer.enabled = YES;

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
    [_formatString release];
    [_label release];
    [_knobLayer release];
    [_color release];
    
    if (_backgroundShadingFunction)
        CFRelease(_backgroundShadingFunction);
    if (_backgroundGradient)
        CFRelease(_backgroundGradient);
    
    [super dealloc];
}

@synthesize range = _range;
- (void)setRange:(CGFloat)range;
{
    if (_range == range)
        return;
    _range = range;
    [self setNeedsLayout];
}

@synthesize formatString = _formatString;
- (void)setFormatString:(NSString *)formatString;
{
    if (OFISEQUAL(_formatString, formatString))
        return;
    [_formatString release];
    _formatString = [formatString copy];
    [self setNeedsLayout];
}

@synthesize representsAlpha = _representsAlpha;
- (void)setRepresentsAlpha:(BOOL)flag;
{
    if (_representsAlpha == flag)
        return;
    _representsAlpha = flag;
    [self setNeedsDisplay];
}

@synthesize needsShading = _needsShading;

// We want the knob interior to show the calculated color
@synthesize color = _color;
- (void)setColor:(OQColor *)color;
{
    if (OFISEQUAL(_color, color))
        return;
    
    [_color release];
    _color = [color retain];
    
    if (_representsAlpha == NO)
        // Our knob should display an opaque color unless we are the alpha slider
        color = [color colorWithAlphaComponent:1];
    
    _knobLayer.color = color;
}

// This cannot be named "alpha". Otherwise when it reaches zero, hit testing will trivially return NO as if we were hidden.
@synthesize value = _value;
- (void)setValue:(CGFloat)value;
{
    if (_value == value)
        return;

    _value = value;
    
    [self setNeedsLayout];
}

@synthesize leftLuma = _leftLuma;
- (void)setLeftLuma:(CGFloat)luma;
{
    if (_leftLuma == luma)
        return;
    _leftLuma = luma;
    [self setNeedsLayout];
}

@synthesize rightLuma = _rightLuma;
- (void)setRightLuma:(CGFloat)luma;
{
    if (_rightLuma == luma)
        return;
    _rightLuma = luma;
    [self setNeedsLayout];
}

@synthesize inMiddleOfTouch = _inMiddleOfTouch;

static CGFloat _valueToX(OUIColorComponentSlider *self, CGFloat value)
{
    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat endCapSize = CGRectGetHeight(bounds);
    CGFloat reserve = endCapSize/2;
    
    if (value < 0)
        value = 0;
    else if (value > 1)
        value = 1;
    
    CGFloat x = reserve + value * (width - 2*reserve); // 1/2 knob size on each end
    return x;
}

static CGFloat _xToValue(OUIColorComponentSlider *self, CGFloat x)
{
    CGRect bounds = self.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat endCapSize = CGRectGetHeight(bounds);
    CGFloat reserve = endCapSize/2;
    
    CGFloat value = (x - reserve) / (width - 2*reserve); // 1/2 knob size on each end

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
    
    // OmniGraffle uses a different undo strategy than OmniGraphSketcher, where this actually does help them avoid massive numbers of undo groups
    [[self undoManager] beginUndoGrouping];

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

    // OmniGraffle uses a different undo strategy than OmniGraphSketcher, where this actually does help them avoid massive numbers of undo groups
    [[self undoManager] endUndoGrouping];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event;
{
    OBASSERT(_inMiddleOfTouch == YES);
    _inMiddleOfTouch = NO;

    [super cancelTrackingWithEvent:event];

    // OmniGraffle uses a different undo strategy than OmniGraphSketcher, where this actually does help them avoid massive numbers of undo groups
    [[self undoManager] endUndoGrouping];
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
    
    OUIInspectorWellDrawOuterShadow(ctx, bounds, YES/*rounded*/);
    
    // Fill the background with the checkerboard, clipped to the bounding path.
    CGContextSaveGState(ctx);
    {
        OUIInspectorWellAddPath(ctx, bounds, YES/*rounded*/);
        CGContextClip(ctx);
        
        // All the non-alpha channels should be opaque and don't need this checkerboard
        if ([self representsAlpha]) {
            [BackgroundCheckerboardPatternColor set];
            CGContextSetPatternPhase(UIGraphicsGetCurrentContext(), CGSizeMake(1,1));
            UIRectFill(CGRectInset(self.bounds, 1, 1));
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
    }
    CGContextRestoreGState(ctx);
    
    OUIInspectorWellDrawBorderAndInnerShadow(ctx, bounds, YES/*rounded*/);
}

- (void)layoutSubviews;
{
    CGRect wellInnerRect = OUIInspectorWellInnerRect(self.bounds);
    _knobLayer.bounds = CGRectMake(0, 0, KnobSize.width, KnobSize.height);
    
    CGPoint position;
    position.x = ceil(_valueToX(self, _value) - KnobSize.width/2);
    position.y = ceil(CGRectGetMidY(wellInnerRect) - KnobSize.height/2);
    
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
        [labelString release];
        
        [_label sizeToFit];
        
        const CGFloat kLabelPadding = 8;
        
        CGRect bounds = self.bounds;
        CGRect labelFrame = _label.frame;
        
        CGFloat luma;
        
        // Pick a direction -- might want to just stay where we are in the middle.
        BOOL shouldGoLeft = _value > 0.55;
        BOOL shouldGoRight = _value < 0.45;
        
        // But if we've never picked, we have to pick at least once
        if (_lastLabelAlignment == UITextAlignmentCenter && !shouldGoLeft && !shouldGoRight)
            shouldGoLeft = YES;
        
        if (shouldGoLeft) {
            labelFrame.origin.x = CGRectGetMinX(bounds) + kLabelPadding;
            _lastLabelAlignment = UITextAlignmentLeft;
        } else if (shouldGoRight) {
            labelFrame.origin.x = CGRectGetMaxX(bounds) - labelFrame.size.width - kLabelPadding;
            _lastLabelAlignment = UITextAlignmentRight;
        }
        labelFrame.origin.y = rint(CGRectGetMinY(bounds) + 0.5*(CGRectGetHeight(bounds) - CGRectGetHeight(labelFrame)));
        
        OBASSERT(_lastLabelAlignment == UITextAlignmentLeft || _lastLabelAlignment == UITextAlignmentRight);
        if (_lastLabelAlignment == UITextAlignmentLeft) {
            // We ignore the supposed luma of the left side for alpha since it always fades to the dark checkerboard
            if (_representsAlpha)
                luma = 0;
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

- (void)setEnabled:(BOOL)yn;
{
    super.enabled = yn;
    
    _knobLayer.enabled = yn;
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
