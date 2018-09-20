// Copyright 2010-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorSwatchPicker.h>

#import "OUIColorSwatch.h"
#import <OmniUI/OUIInspectorSlice.h> // -showDetails:

#import <OmniAppKit/OAColor.h>

RCS_ID("$Id$");


// A few built-in palette preference keys (in OmniUI.defaults)
NSString * const OUIColorSwatchPickerTextBackgroundPalettePreferenceKey = @"OUIColorSwatchPickerTextBackgroundPalette";
NSString * const OUIColorSwatchPickerTextColorPalettePreferenceKey = @"OUIColorSwatchPickerTextColorPalette";

@implementation OUIColorSwatchPicker
{
    NSMutableArray *_colors;
    OAColor *_swatchSelectionColor;
    
    NSMutableArray *_colorSwatches;
    UIButton *_navigationButton;
}

static id _commonInit(OUIColorSwatchPicker *self)
{
    self.clearsContextBeforeDrawing = YES;
    self.opaque = NO;
    self.backgroundColor = nil;
    
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

- (void)setPalettePreferenceKey:(NSString *)key;
{
    if (OFISEQUAL(_palettePreferenceKey, key))
        return;
    _palettePreferenceKey = [key copy];
    
    if (![NSString isEmptyString:_palettePreferenceKey]) {
        NSArray *colorPalette = [[NSUserDefaults standardUserDefaults] arrayForKey:_palettePreferenceKey];
        NSMutableArray *colors = [NSMutableArray array];
        OBASSERT(colorPalette);
        for (NSString *colorString in colorPalette) {
            OAColor *color = [OAColor colorFromRGBAString:colorString];
            if (color)
                [colors addObject:color];
        }
        self.colors = colors;

    } else {
        // leave the colors alone
    }
}

// Setter doesn't currently save the list to preferences if we have a preference, only picked colors do and only if _updatesPaletteForSelectedColors is set.
- (void)setColors:(NSArray *)colors;
{
    if (OFISEQUAL(colors, _colors))
        return;
    
    if (colors != nil)
        _colors = [[NSMutableArray alloc] initWithArray:colors];
    else
        _colors = [[NSMutableArray alloc] init];
    
    [self setNeedsLayout];
}

- (OAColor *)color;
{
    if ([_colors count] > 0)
        return [_colors objectAtIndex:0];
    return nil;
}

- (void)setColor:(OAColor *)color;
{
    // empty array if color is nil...
    self.colors = [NSArray arrayWithObjects:color, nil];
}

@synthesize target = _weak_target;
- (void)setTarget:(id)target;
{
    OBPRECONDITION(!target || (_showsSingleSwatch && [target respondsToSelector:@selector(showDetails:)]) || (!_showsSingleSwatch && [target respondsToSelector:@selector(changeColor:)])); // Later we could make the action configurable too...
    
    _weak_target = target;
}

- (void)setShowsSingleSwatch:(BOOL)showsSingleSwatch;
{
    if (_showsSingleSwatch == showsSingleSwatch)
        return;
    _showsSingleSwatch = showsSingleSwatch;
    [self setNeedsLayout];
}

- (void)setWraps:(BOOL)wraps;
{
    if (_wraps == wraps)
        return;
    _wraps = wraps;
    [self setNeedsLayout];
}

- (void)setShowsNoneSwatch:(BOOL)showsNoneSwatch;
{
    if (_showsNoneSwatch == showsNoneSwatch)
        return;
    _showsNoneSwatch = showsNoneSwatch;
    [self setNeedsLayout];
}

- (void)setShowsNavigationSwatch:(BOOL)showsNavigationSwatch;
{
    if (_showsNavigationSwatch == showsNavigationSwatch)
        return;
    _showsNavigationSwatch = showsNavigationSwatch;
    [self setNeedsLayout];
}

- (void)sizeToFit;
{
    [self sizeHeightToFit];

    CGRect frame = self.frame;
    frame.size.width = _layoutWidth;
    self.frame = frame;
}

- (void)sizeHeightToFit;
{
    [self layoutIfNeeded];
    
    CGFloat height;
    
    OUIColorSwatch *swatch = [_colorSwatches lastObject];
    if (swatch)
        height = CGRectGetMaxY(swatch.frame) - CGRectGetMinY(self.bounds);
    else
        height = [OUIColorSwatch swatchSize].height; // zero height doesn't seem useful to anyone...
    
    CGRect frame = self.frame;
    frame.size.height = height;
    self.frame = frame;
}

// Compare in RGBA space so we don't have red selected in the HSV picker and then not selected in swatches
static BOOL _colorsMatch(OAColor *color1, OAColor *color2)
{
    if (color1 == color2)
        return YES; // handle the nil case
    
    return [[color1 colorUsingColorSpace:OAColorSpaceRGB] isEqual:[color2 colorUsingColorSpace:OAColorSpaceRGB]];
}

- (BOOL)hasMatchForColor:(OAColor *)color;
{
    for (OUIColorSwatch *swatch in _colorSwatches)
        if (_colorsMatch(swatch.color, color))
            return YES;
    return NO;
}

- (void)setSwatchSelectionColor:(OAColor *)color;
{
    if (OFISEQUAL(_swatchSelectionColor, color))
        return;

    _swatchSelectionColor = color;

    for (OUIColorSwatch *swatch in _colorSwatches) {
        swatch.selected = _colorsMatch(swatch.color, _swatchSelectionColor);
        //NSLog(@"%@: %@", swatch.selected ? @"SELECTED" : @"----", [swatch.color shortDescription]);
    }
}

- (BOOL)hasSelectedSwatch;
{
    for (OUIColorSwatch *swatch in _colorSwatches)
        if (swatch.selected)
            return YES;
    return NO;
}

- (void)addColor:(OAColor *)color replacingRecentlyAdded:(BOOL)replacingRecentlyAdded;
{
    //NSLog(@"_swatchSelectionColor = %@", _swatchSelectionColor);
    //NSLog(@"adding %@ to %@", color, [_colors arrayByPerformingSelector:@selector(shortDescription)]);
    
    if (replacingRecentlyAdded && [_colors count])
        [_colors replaceObjectAtIndex:0 withObject:color];
    else
        [_colors insertObject:color atIndex:0];
    
    [self layoutSubviews];
    
    if (_palettePreferenceKey) {
        [[NSUserDefaults standardUserDefaults] setObject:[_colors arrayByPerformingSelector:@selector(rgbaString)]
                                                  forKey:_palettePreferenceKey];
    }
}

#pragma mark -
#pragma mark UIView

static const CGFloat kSwatchSpacing = 2;

static void _configureSwatchView(OUIColorSwatchPicker *self, UIView *swatchView, CGPoint *offset, CGSize size)
{
    CGRect swatchFrame;
    swatchFrame.origin = *offset;
    swatchFrame.size = size;
    swatchView.frame = swatchFrame;
    if (swatchView.superview != self)
        [self addSubview:swatchView];
    
    offset->x = CGRectGetMaxX(swatchFrame) + kSwatchSpacing;
}

static OUIColorSwatch *_newSwatch(OUIColorSwatchPicker *self, OAColor *color, CGPoint *offset, CGSize size)
{
    OUIColorSwatch *swatch = [(OUIColorSwatch *)[OUIColorSwatch alloc] initWithColor:color];
    
    [swatch addTarget:self action:@selector(_swatchTouchUp:) forControlEvents:UIControlEventTouchUpInside];
    
    swatch.selected = _colorsMatch(color, self->_swatchSelectionColor);
    _configureSwatchView(self, swatch, offset, size);
    return swatch;
}

- (void)_swatchTouchUp:(OUIColorSwatch *)swatch NS_EXTENSION_UNAVAILABLE_IOS("");
{
    id target = _weak_target;
    
    if (_showsSingleSwatch || swatch == _navigationButton) {
        if (![[UIApplication sharedApplication] sendAction:@selector(showDetails:) to:target from:swatch forEvent:nil])
            NSLog(@"Unable to find target for -showDetails: on color swatch tap.");
    } else {
        [self sendActionsForControlEvents:UIControlEventTouchDown];
        _selectedColor = swatch.color;
        [self setSwatchSelectionColor:swatch.color];
        [self sendActionsForControlEvents:UIControlEventValueChanged];
        [self sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)layoutSubviews;
{
    // If we are going to only show a single color, it should be reserved for actually showing a color
    OBPRECONDITION(!_showsSingleSwatch || (!_showsNavigationSwatch || !_showsNoneSwatch));
    
    CGRect bounds = self.bounds;

    if (!_colorSwatches)
        _colorSwatches = [[NSMutableArray alloc] init];
    else {
        [_colorSwatches makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [_colorSwatches removeAllObjects];
    }
    
    // Figure out how many swatches will fit per line in this width.
    CGSize swatchSize = [OUIColorSwatch swatchSize];
    NSUInteger swatchsPerRow = floor((CGRectGetWidth(bounds) + kSwatchSpacing) / (swatchSize.width + kSwatchSpacing));
    
    // Normal color picking swatches
    CGPoint offset = bounds.origin;
    NSUInteger colorIndex, colorCount = [_colors count];
        
    if (_showsNoneSwatch) {
        OUIColorSwatch *swatch = _newSwatch(self, nil, &offset, swatchSize);
        [_colorSwatches addObject:swatch];
        swatch.selected = _colorsMatch(nil, _swatchSelectionColor);
        
        OBASSERT(swatchsPerRow >= 2); // not wrapping here.
    }
    
    _layoutWidth = 0;
    
    for (colorIndex = 0; colorIndex < colorCount; colorIndex++) {
        OAColor *color = [_colors objectAtIndex:colorIndex];
        
        if (_showsSingleSwatch)
            swatchSize = bounds.size; // Take up the whole area

        OUIColorSwatch *swatch = _newSwatch(self, color, &offset, swatchSize);
        [_colorSwatches addObject:swatch];
        
        if (CGRectGetMaxX(swatch.frame) > _layoutWidth) {
            _layoutWidth = CGRectGetMaxX(swatch.frame);
        }
        
        swatch.selected = _colorsMatch(color, _swatchSelectionColor);

        if (_showsSingleSwatch) {
            swatch.showNavigationArrow = YES;
            break;
        }
        
        NSUInteger swatchColumn = [_colorSwatches count]; // Not equal to colorIndex if _showsNoneSwatch is YES.
        
        if (!_wraps) {
            // Stop if we are only supposed to show one line and we just did the last one, or if we did the 2nd to last one and we want to show the extra navigation swatch.
            if ((swatchColumn == swatchsPerRow) || ((swatchColumn == swatchsPerRow - 1) && _showsNavigationSwatch)) {
                break;
            }
        }

        if ((swatchColumn % swatchsPerRow) == 0) {
            // Prepare for the next row
            offset.x = CGRectGetMinX(bounds);
            offset.y += swatchSize.height + kSwatchSpacing;
        }
    }
    
    // Remove any unused colors; they've fallen off the edge. Not bothering to archive the preference change here, if any. Pruning will happen when another color is added.
    if (colorIndex < colorCount) {
        NSUInteger removeFromIndex = colorIndex + 1;
        [_colors removeObjectsInRange:NSMakeRange(removeFromIndex, colorCount - removeFromIndex)];
        //NSLog(@"removed colors from %d, now %@", removeFromIndex, _colors);
    }
    
    // Detail navigation setup
    if (_showsSingleSwatch) {
        OUIColorSwatch *swatch = [_colorSwatches lastObject];
        [swatch addTarget:self action:@selector(_swatchTouchUp:) forControlEvents:UIControlEventTouchUpInside];
    } else if (_showsNavigationSwatch) {
        if (!_navigationButton)
            _navigationButton = [OUIColorSwatch navigateToColorPickerSwatch];
        _configureSwatchView(self, _navigationButton, &offset, swatchSize);
        [_navigationButton addTarget:self action:@selector(_swatchTouchUp:) forControlEvents:UIControlEventTouchUpInside];
    }
}

@end
