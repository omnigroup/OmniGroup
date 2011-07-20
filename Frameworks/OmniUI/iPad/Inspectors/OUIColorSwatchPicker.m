// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorSwatchPicker.h>

#import "OUIColorSwatch.h"

#import <OmniQuartz/OQColor.h>

RCS_ID("$Id$");


// A few built-in palette preference keys (in OmniUI.defaults)
NSString * const OUIColorSwatchPickerTextBackgroundPalettePreferenceKey = @"OUIColorSwatchPickerTextBackgroundPalette";
NSString * const OUIColorSwatchPickerTextColorPalettePreferenceKey = @"OUIColorSwatchPickerTextColorPalette";


@implementation OUIColorSwatchPicker

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

- (void)dealloc;
{
    [_palettePreferenceKey release];
    [_colors release];
    [_swatchSelectionColor release];
    [_colorSwatches release];
    [_navigationButton release];
    [super dealloc];
}

@synthesize palettePreferenceKey = _palettePreferenceKey;
- (void)setPalettePreferenceKey:(NSString *)key;
{
    if (OFISEQUAL(_palettePreferenceKey, key))
        return;
    [_palettePreferenceKey release];
    _palettePreferenceKey = [key copy];
    
    if (![NSString isEmptyString:_palettePreferenceKey]) {
        NSArray *colorPalette = [[NSUserDefaults standardUserDefaults] arrayForKey:_palettePreferenceKey];
        NSMutableArray *colors = [NSMutableArray array];
        OBASSERT(colorPalette);
        for (NSString *colorString in colorPalette) {
            OQColor *color = [OQColor colorFromRGBAString:colorString];
            if (color)
                [colors addObject:color];
        }
        self.colors = colors;

    } else {
        // leave the colors alone
    }
}

// Setter doesn't currently save the list to preferences if we have a preference, only picked colors do and only if _updatesPaletteForSelectedColors is set.
@synthesize colors = _colors;
- (void)setColors:(NSArray *)colors;
{
    if (OFISEQUAL(colors, _colors))
        return;
    [_colors release];
    _colors = [[NSMutableArray alloc] initWithArray:colors];
    [self setNeedsLayout];
}

- (OQColor *)color;
{
    if ([_colors count] > 0)
        return [_colors objectAtIndex:0];
    return nil;
}

- (void)setColor:(OQColor *)color;
{
    // empty array if color is nil...
    self.colors = [NSArray arrayWithObjects:color, nil];
}

@synthesize showsSingleSwatch = _showsSingleSwatch;
- (void)setShowsSingleSwatch:(BOOL)showsSingleSwatch;
{
    if (_showsSingleSwatch == showsSingleSwatch)
        return;
    _showsSingleSwatch = showsSingleSwatch;
    [self setNeedsLayout];
}

@synthesize wraps = _wraps;
- (void)setWraps:(BOOL)wraps;
{
    if (_wraps == wraps)
        return;
    _wraps = wraps;
    [self setNeedsLayout];
}

@synthesize showsNoneSwatch = _showsNoneSwatch;
- (void)setShowsNoneSwatch:(BOOL)showsNoneSwatch;
{
    if (_showsNoneSwatch == showsNoneSwatch)
        return;
    _showsNoneSwatch = showsNoneSwatch;
    [self setNeedsLayout];
}

@synthesize showsNavigationSwatch = _showsNavigationSwatch;
- (void)setShowsNavigationSwatch:(BOOL)showsNavigationSwatch;
{
    if (_showsNavigationSwatch == showsNavigationSwatch)
        return;
    _showsNavigationSwatch = showsNavigationSwatch;
    [self setNeedsLayout];
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
static BOOL _colorsMatch(OQColor *color1, OQColor *color2)
{
    if (color1 == color2)
        return YES; // handle the nil case
    
    return [[color1 colorUsingColorSpace:OQColorSpaceRGB] isEqual:[color2 colorUsingColorSpace:OQColorSpaceRGB]];
}

- (BOOL)hasMatchForColor:(OQColor *)color;
{
    for (OUIColorSwatch *swatch in _colorSwatches)
        if (_colorsMatch(swatch.color, _swatchSelectionColor))
            return YES;
    return NO;
}

- (void)setSwatchSelectionColor:(OQColor *)color;
{
    if (OFISEQUAL(_swatchSelectionColor, color))
        return;

    [_swatchSelectionColor release];
    _swatchSelectionColor = [color retain];

    for (OUIColorSwatch *swatch in _colorSwatches)
        swatch.selected = _colorsMatch(swatch.color, _swatchSelectionColor);
}

- (BOOL)hasSelectedSwatch;
{
    for (OUIColorSwatch *swatch in _colorSwatches)
        if (swatch.selected)
            return YES;
    return NO;
}

- (void)addColor:(OQColor *)color replacingRecentlyAdded:(BOOL)replacingRecentlyAdded;
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

static OUIColorSwatch *_newSwatch(OUIColorSwatchPicker *self, OQColor *color, CGPoint *offset, CGSize size)
{
    OUIColorSwatch *swatch = [(OUIColorSwatch *)[OUIColorSwatch alloc] initWithColor:color];
    swatch.selected = _colorsMatch(color, self->_swatchSelectionColor);
    _configureSwatchView(self, swatch, offset, size);
    return swatch;
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
        [swatch release];
        swatch.selected = _colorsMatch(nil, _swatchSelectionColor);
        
        OBASSERT(swatchsPerRow >= 2); // not wrapping here.
    }
    
    for (colorIndex = 0; colorIndex < colorCount; colorIndex++) {
        OQColor *color = [_colors objectAtIndex:colorIndex];
        
        if (_showsSingleSwatch)
            swatchSize = bounds.size; // Take up the whole area

        OUIColorSwatch *swatch = _newSwatch(self, color, &offset, swatchSize);
        [_colorSwatches addObject:swatch];
        [swatch release];
        
        swatch.selected = _colorsMatch(color, _swatchSelectionColor);

        if (_showsSingleSwatch) {
            swatch.singleSwatch = YES;
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
        [swatch addTarget:nil action:@selector(showDetails:) forControlEvents:UIControlEventTouchDown];
    } else if (_showsNavigationSwatch) {
        if (!_navigationButton)
            _navigationButton = [[OUIColorSwatch navigateToColorPickerButton] retain];
        _configureSwatchView(self, _navigationButton, &offset, swatchSize);
        [_navigationButton addTarget:nil action:@selector(showDetails:) forControlEvents:UIControlEventTouchDown];
    }
}

@end
