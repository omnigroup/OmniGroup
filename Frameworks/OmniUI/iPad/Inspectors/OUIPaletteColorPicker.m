// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIPaletteColorPicker.h>

#import <OmniUI/OUIPaletteTheme.h>
#import <OmniUI/OUIColorSwatchPicker.h>
#import <OmniUI/OUIInspectorSelectionValue.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorAppearance.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OUIPaletteColorPicker
{
    NSArray *_themeViews;
}

- (void)setThemes:(NSArray *)themes;
{
    if (OFISEQUAL(_themes, themes))
        return;
    _themes = [themes copy];
    
    if (self.isViewLoaded)
        [self _rebuildThemesViews];
}

#pragma mark - OUIColorPicker subclass

- (NSString *)identifier;
{
    return @"palette";
}

- (OUIColorPickerFidelity)fidelityForSelectionValue:(OUIInspectorSelectionValue *)selectionValue;
{
    OAColor *color = selectionValue.firstValue;

    // The palette color picker can exactly match 'no color' by not selecting any chits.
    if (!color)
        return OUIColorPickerFidelityExact;
    
    for (UIView *view in _themeViews) {
        if ([view isKindOfClass:[OUIColorSwatchPicker class]]) {
            OUIColorSwatchPicker *swatchPicker = (OUIColorSwatchPicker *)view;
            if ([swatchPicker hasMatchForColor:color])
                return OUIColorPickerFidelityExact;
        }
    }
    
    return OUIColorPickerFidelityZero;
}

- (void)setSelectionValue:(OUIInspectorSelectionValue *)selectionValue;
{
    [super setSelectionValue:selectionValue];
    [self scrollToSelectionValueAnimated:self.view.window != nil];
}

- (void)scrollToSelectionValueAnimated:(BOOL)animated;
{
    // Don't check every color, just the most important one.
    OAColor *color = self.selectionValue.firstValue;
    
    // Note the location of the first matching view, so we can scroll to it.
    CGRect rectToScrollTo = CGRectNull;
    
    for (UIView *themeView in _themeViews) {
        if ([themeView isKindOfClass:[OUIColorSwatchPicker class]]) {
            OUIColorSwatchPicker *swatchPicker = (OUIColorSwatchPicker *)themeView;
            [swatchPicker setSwatchSelectionColor:color];
            
            if (CGRectIsNull(rectToScrollTo) && [swatchPicker hasMatchForColor:color]) {
                rectToScrollTo = [self.view convertRect:swatchPicker.bounds fromView:swatchPicker];
                rectToScrollTo = CGRectInset(rectToScrollTo, 0, -32); // UIScrollView scrolls as little as needed; include some padding.
            }
        }
    }
    
    if (!CGRectIsNull(rectToScrollTo)) {
        [OB_CHECKED_CAST(UIScrollView, self.view) scrollRectToVisible:rectToScrollTo animated:animated];
    }
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    [self _rebuildThemesViews];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    UIScrollView *view = (UIScrollView *)self.view;
    [view flashScrollIndicators];
}

#pragma mark Receiving Control Events from Swatch Pickers

- (void)_colorSelectionChanged:(id)sender NS_EXTENSION_UNAVAILABLE_IOS("");
{
    OBASSERT([sender isKindOfClass:[OUIColorSwatchPicker class]]);
    [[UIApplication sharedApplication] sendAction:@selector(beginChangingColor) to:self.target from:self forEvent:nil];  // we need to send begin and end so self.target has a change to deal with undo groupings if it needs to
    
    OUIColorSwatchPicker *picker = (OUIColorSwatchPicker *)sender;
    self.selectionValue = [[OUIInspectorSelectionValue alloc] initWithValue:picker.selectedColor];
    
    [[UIApplication sharedApplication] sendAction:@selector(changeColor:) to:self.target from:self forEvent:nil];
    [[UIApplication sharedApplication] sendAction:@selector(endChangingColor) to:self.target from:self forEvent:nil];
}

#pragma mark -
#pragma mark Private

- (void)_rebuildThemesViews;
{
    if (!_themes)
        _themes = [[OUIPaletteTheme defaultThemes] copy];
    
    [_themeViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    _themeViews = nil;

    const CGFloat kLabelToPaletteSpacing = 5;
    const CGFloat kInterThemeSpacing = 12;
    
    UIFont *labelFont = [UIFont systemFontOfSize:[UIFont labelFontSize]];
    UIScrollView *view = (UIScrollView *)self.view;
    
    // Don't select every color, just the most important one.
    OAColor *singleSelectedColor = self.selectionValue.firstValue;
    
    CGRect viewBounds = view.bounds;
    viewBounds.size.width = 320;
    
    CGFloat xOffset = 8;
    CGFloat yOffset = CGRectGetMinY(view.bounds) + kInterThemeSpacing;
    NSMutableArray *themeViews = [NSMutableArray array];
    for (OUIPaletteTheme *theme in _themes) {
        {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
            label.text = theme.displayName;
            label.textColor = self.textColor;
            label.font = labelFont;
            label.opaque = NO;
            label.backgroundColor = nil;
            [label sizeToFit];
            
            CGRect labelFrame = label.frame;
            labelFrame.origin = CGPointMake(xOffset, yOffset);
            label.frame = labelFrame;
        
            yOffset = CGRectGetMaxY(labelFrame) + kLabelToPaletteSpacing;
            [themeViews addObject:label];
            [view addSubview:label];
        }
        
        {
            OUIColorSwatchPicker *swatchPicker = [[OUIColorSwatchPicker alloc] initWithFrame:CGRectMake(xOffset, yOffset, viewBounds.size.width - xOffset, 0)];
            [swatchPicker addTarget:self action:@selector(_colorSelectionChanged:) forControlEvents:UIControlEventValueChanged];
            swatchPicker.target = self;
            swatchPicker.wraps = YES;
            swatchPicker.colors = theme.colors;
            [swatchPicker sizeHeightToFit];
            [swatchPicker setSwatchSelectionColor:singleSelectedColor];

            yOffset = CGRectGetMaxY(swatchPicker.frame) + kInterThemeSpacing;
            [themeViews addObject:swatchPicker];
            [view addSubview:swatchPicker];
        }
    }

    view.contentSize = CGSizeMake(viewBounds.size.width, yOffset);
    
    _themeViews = [themeViews copy];
}

- (UIColor *)textColor
{
    if ([OUIInspectorAppearance inspectorAppearanceEnabled])
        return OUIInspectorAppearance.appearance.InspectorTextColor;
    
    return [OUIInspector labelTextColor];
}

#pragma mark <OUIColorValue>

-(OAColor *)color
{
    return  self.selectionValue.firstValue;
}

#pragma mark - OUIInspectorAppearance

- (void)themedAppearanceDidChange:(OUIThemedAppearance *)changedAppearance;
{
    [super themedAppearanceDidChange:changedAppearance];
    
    for (UIView *view in _themeViews) {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = OB_CHECKED_CAST(UILabel, view);
            if (label) {
                label.textColor = self.textColor;
            }
        }
    }
}

@end
