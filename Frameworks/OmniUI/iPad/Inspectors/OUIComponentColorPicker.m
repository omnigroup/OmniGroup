// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIComponentColorPicker.h>

#import <OmniUI/OUIColorComponentSlider.h>
#import <OmniUI/OUIInspectorSelectionValue.h>

RCS_ID("$Id$");

@interface OUIComponentColorPicker (/*Private*/)
- (void)_updateSliderValuesFromColor;
- (void)_componentSliderValueChanged:(OUIColorComponentSlider *)slider;
@end

@implementation OUIComponentColorPicker

// Required subclass methods
- (OAColorSpace)colorSpace;
{
    OBRequestConcreteImplementation(self, _cmd);
}
- (NSArray *)makeComponentSliders;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)extractComponents:(CGFloat *)components fromColor:(OAColor *)color;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (OAColor *)makeColorWithComponents:(const CGFloat *)components;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (OUIComponentColorPickerConvertToRGB)rgbaComponentConverter;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (OUIComponentColorPickerConvertToRGB)shadingRGBAComponentConverter;
{
    // Usually we want the same converter for all sliders
    return [self rgbaComponentConverter];
}

#pragma mark -
#pragma mark OUIColorPicker subclass

- (OUIColorPickerFidelity)fidelityForSelectionValue:(OUIInspectorSelectionValue *)selectionValue;
{
    OAColor *color = selectionValue.firstValue;
    if (!color)
        // Slider-based color pickers can't represent "no color"
        return OUIColorPickerFidelityZero;
        
    OAColorSpace colorSpace = [color colorSpace];
    if (colorSpace == OAColorSpacePattern || colorSpace == OAColorSpaceNamed) {
        OBASSERT_NOT_REACHED("We don't yet have pattern/named color pickers, if ever");
        return OUIColorPickerFidelityZero;
    }
    
    if (colorSpace == [self colorSpace])
        return OUIColorPickerFidelityExact;
    return OUIColorPickerFidelityApproximate;
}

- (void)setSelectionValue:(OUIInspectorSelectionValue *)selectionValue;
{
    [super setSelectionValue:selectionValue];
    
    BOOL animate = [self isViewLoaded];

    if (animate) {
        [UIView animateWithDuration:0.2 animations:^{
            [self update];
        }];
    } else {
        [self update];
    }
}

- (void)update {
    [self _updateSliderValuesFromColor];
    [self.view layoutIfNeeded];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)loadView;
{
    UIScrollView *view = [[UIScrollView alloc] initWithFrame:CGRectZero];
    view.alwaysBounceVertical = YES;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    
    OBASSERT(_componentSliders == nil);
    _componentSliders = [[self makeComponentSliders] copy];
    OBASSERT([_componentSliders count] > 0);
    
    for (OUIColorComponentSlider *slider in _componentSliders) {
        // Need the up/cancel variants so we find out about the end of the tracking and manage undo grouping
        [slider addTarget:self action:@selector(_componentSliderValueChanged:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(_beginChangingSliderValue:) forControlEvents:UIControlEventTouchDown];
        [slider addTarget:self action:@selector(_endChangingSliderValue:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    }
    
    [self _updateSliderValuesFromColor];
    [self setView:view];
}

#ifdef DEBUG_tom
- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];
    
    NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
}
#endif

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    const CGFloat kSpaceBeforeFirstSlider = 8;
    const CGFloat kSpaceBetweenSliders = 27;
    const CGFloat kEdgePadding = 8;
    const CGFloat kSpaceAfterLastSlider = 8;
    
    UIScrollView *scrollView = OB_CHECKED_CAST(UIScrollView, self.view);

    OUIColorComponentSlider *priorSlider = nil;
    for (OUIColorComponentSlider *slider in _componentSliders) {
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        [scrollView addSubview:slider];

        CGSize sliderSize = [slider sizeThatFits:CGSizeMake(scrollView.bounds.size.width - 2*kEdgePadding, 0)];
        NSArray *constraints = @[
             [slider.leftAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leftAnchor constant:kEdgePadding],
             [slider.widthAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-2 * kEdgePadding],
             [slider.rightAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.rightAnchor constant:-kEdgePadding],
             [slider.heightAnchor constraintEqualToConstant:sliderSize.height],
        ];
        
        if (priorSlider)
            constraints = [constraints arrayByAddingObject:[slider.topAnchor constraintEqualToAnchor:priorSlider.bottomAnchor constant:kSpaceBetweenSliders]];
        else
            constraints = [constraints arrayByAddingObject:[slider.topAnchor constraintEqualToAnchor:scrollView.safeAreaLayoutGuide.topAnchor constant:kSpaceBeforeFirstSlider]];
        
        [NSLayoutConstraint activateConstraints:constraints];
        
        priorSlider = slider;
    }
    
    OUIColorComponentSlider *lastSlider = [_componentSliders lastObject];
    [lastSlider.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:kSpaceAfterLastSlider].active = YES;
}

#pragma mark -
#pragma mark OUIColorValue

- (OAColor *)color;
{
    return self.selectionValue.firstValue;
}

#pragma mark -
#pragma mark Private

/*
 Make a CGFunction that takes N inputs where N-1 are constant and 1 varies from 0..1 (the domain input param).
 Output RGB via a function supplied by the concrete subclass by substituting the input into a specific channel of then N inputs.
 */

typedef struct {
    NSUInteger shadingComponentIndex; // The slot of the components we should put the varying 'in' parameter in.
    CGFloat *components; // The original components
    OUIComponentColorPickerConvertToRGB convertToRGB; // function to convert the resolved components to RGBA.
} BackgroundShadingInfo;

static void _backgroundShadingReleaseInfo(void *_info)
{
    BackgroundShadingInfo *info = _info;
    
    free(info->components);
    free(info);
}

static void _backgroundShadingEvaluate(void *_info, const CGFloat *in, CGFloat *out)
{
    BackgroundShadingInfo *info = _info;
    
    info->components[info->shadingComponentIndex] = *in;
    OALinearRGBA rgba = info->convertToRGB(info->components);
    
    out[0] = rgba.r;
    out[1] = rgba.g;
    out[2] = rgba.b;
    out[3] = rgba.a;
}



- (void)_updateSliderValuesFromColor;
{
    // The sliders need something to base edits on, so we need to give them a color even if there is multiple selection.
    OAColor *color = self.selectionValue.firstValue;
    if (color == nil) {
        // Sliders require a color as a reference point (even if it's a transparent one). White is a better default choice than Black because we want the saturation slider to show something meaningful.
        color = [OAColor colorWithWhite:1.0 alpha:0.0];
    }

    NSUInteger componentCount = [_componentSliders count];
    if (componentCount == 0)
        return;
    
    CGFloat *components;
    size_t componentsSize = sizeof(*components) * (2 * componentCount); // extra room for off by one errors.
    components = malloc(componentsSize);
    
    [self extractComponents:components fromColor:color];
    
    for (NSUInteger componentIndex = 0; componentIndex < componentCount; componentIndex++) {
        OUIColorComponentSlider *slider = [_componentSliders objectAtIndex:componentIndex];

        // Let all the sliders know the actual calculated color (to draw inside their knobs).
        // We might be getting called by switching the selected color picker. In this case, we might be the gray picker and the incoming color might be RGB. Convert to our colorspace.
        slider.color = [color colorUsingColorSpace:[self colorSpace]];
        
        // Don't update the slider(s) that the user is touching.
        if (slider.tracking)
            continue;
        
        [slider setValue:components[componentIndex]];
        
        if (slider.needsShading) {
            // Build the updated background shading. Make a new info and new copy of the input components for each (since each is going to modify a different channel).
            BackgroundShadingInfo *info = calloc(sizeof(*info), 1);
            info->shadingComponentIndex = componentIndex;
            
            info->components = malloc(componentsSize);
            memcpy(info->components, components, componentsSize);
            info->convertToRGB = [self shadingRGBAComponentConverter];
            
            // Build our luma values. We can muck with this slot since it will be interpolated by the shading build anyway.
            info->components[componentIndex] = 0;
            slider.leftLuma = OAGetRGBAColorLuma(info->convertToRGB(info->components));
            info->components[componentIndex] = 1;
            slider.rightLuma = OAGetRGBAColorLuma(info->convertToRGB(info->components));
            
            if ([slider representsAlpha]) {
                // don't force the channel to be opaque
            } else {
                NSUInteger alphaIndex = componentCount - 1;
                OBASSERT([[_componentSliders objectAtIndex:alphaIndex] representsAlpha]);
                info->components[alphaIndex] = 1; // ignore the current alpha and make this slider opaque
            }
            
            CGFloat domain[] = {0, 1}; // 0..1 input
            CGFloat range[] = {0, 1, 0, 1, 0, 1, 0, 1}; // rgba output
            
            CGFunctionCallbacks callbacks;
            memset(&callbacks, 0, sizeof(callbacks));
            callbacks.evaluate = _backgroundShadingEvaluate;
            callbacks.releaseInfo = _backgroundShadingReleaseInfo;
            
            CGFunctionRef shadingFunction = CGFunctionCreate(info, 1/*domain*/, domain, 4/*range*/, range, &callbacks);
            
            [slider updateBackgroundShadingUsingFunction:shadingFunction];
            
            CFRelease(shadingFunction);
        } else {
            // This component can be done with linear interpolation of the two end points in RGBA space.
            OUIComponentColorPickerConvertToRGB convertToRGB = [self rgbaComponentConverter];
            CGFloat *tmpComponents = malloc(componentsSize);
            memcpy(tmpComponents, components, componentsSize);

            // Build our luma values. We can muck with this slot since it will be interpolated by the shading build anyway.
            tmpComponents[componentIndex] = 0;
            slider.leftLuma = OAGetRGBAColorLuma(convertToRGB(tmpComponents));
            tmpComponents[componentIndex] = 1;
            slider.rightLuma = OAGetRGBAColorLuma(convertToRGB(tmpComponents));

            if ([slider representsAlpha]) {
                // don't force the channel to be opaque
            } else {
                NSUInteger alphaIndex = componentCount - 1;
                OBASSERT([[_componentSliders objectAtIndex:alphaIndex] representsAlpha]);
                tmpComponents[alphaIndex] = 1; // ignore the current alpha and make this slider opaque
            }

            OALinearRGBA ends[2];
            tmpComponents[componentIndex] = 0;
            ends[0] = convertToRGB(tmpComponents);
            
            tmpComponents[componentIndex] = 1;
            ends[1] = convertToRGB(tmpComponents);
                        
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, &ends[0].r, NULL, 2);
            CFRelease(colorSpace);
            
            free(tmpComponents);
            
            [slider updateBackgroundShadingUsingGradient:gradient];
            
            CFRelease(gradient);
        }
    }

    free(components);
}

- (void)_beginChangingSliderValue:(OUIColorComponentSlider *)slider NS_EXTENSION_UNAVAILABLE_IOS("");
{
    [[UIApplication sharedApplication] sendAction:@selector(beginChangingColor) to:self.target from:self forEvent:nil];
}

- (void)_endChangingSliderValue:(OUIColorComponentSlider *)slider NS_EXTENSION_UNAVAILABLE_IOS("");
{
    [[UIApplication sharedApplication] sendAction:@selector(endChangingColor) to:self.target from:self forEvent:nil];
}

- (void)_componentSliderValueChanged:(OUIColorComponentSlider *)slider NS_EXTENSION_UNAVAILABLE_IOS("");
{
    // The sliders need something to base edits on, so we need to give them a color even if there is multiple selection.
    OAColor *color = self.selectionValue.firstValue;
    NSUInteger componentCount = [_componentSliders count];
    if (!color || !componentCount)
        return;
    
    CGFloat *components = malloc(sizeof(*components) * (2 * componentCount)); // extra room for off by one errors.
    [self extractComponents:components fromColor:color];
    
    NSUInteger componentIndex = [_componentSliders indexOfObjectIdenticalTo:slider];
    //NSLog(@"changed component %d", componentIndex);
    
    components[componentIndex] = slider.value;
    
    // Store the color in ourselves since we are the <OUIColorValue> being sent
    OAColor *updatedColor = [self makeColorWithComponents:components];
    self.selectionValue = [[OUIInspectorSelectionValue alloc] initWithValue:updatedColor];
    free(components);
    
    if (![[UIApplication sharedApplication] sendAction:@selector(changeColor:) to:self.target from:self forEvent:nil])
        OBASSERT_NOT_REACHED("Showing a color picker, but not interested in the result?");
}

@end
