// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
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
    OQColor *color = selectionValue.firstValue;

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
    
    // Don't check every color, just the most important one.
    OQColor *color = selectionValue.firstValue;
    
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
    
    if(!CGRectIsNull(rectToScrollTo))
    {
        BOOL animate = (self.view.window != nil);
        [(UIScrollView *)self.view scrollRectToVisible:rectToScrollTo animated:animate];
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
    OQColor *singleSelectedColor = self.selectionValue.firstValue;
    
    CGRect viewBounds = view.bounds;
    viewBounds.size.width = 320;
    
    CGFloat xOffset = 8;
    CGFloat yOffset = CGRectGetMinY(view.bounds) + kInterThemeSpacing;
    NSMutableArray *themeViews = [NSMutableArray array];
    for (OUIPaletteTheme *theme in _themes) {
        {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
            label.text = theme.displayName;
            label.textColor = [OUIInspector labelTextColor];
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

@end
