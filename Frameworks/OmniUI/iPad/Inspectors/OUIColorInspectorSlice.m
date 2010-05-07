// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSegmentedControl.h>
#import <OmniUI/OUIColorPicker.h>
#import <OmniUI/OUIInspectorSegmentedControlButton.h>
#import <OmniUI/OUIColorSwatchPicker.h>
#import <OmniUI/OUIColorValue.h>
#import <OmniUI/OUIInspectorSelectionValue.h>

#import <OmniFoundation/OFPreference.h>
#import <OmniQuartz/OQColor.h>

RCS_ID("$Id$");

@implementation OUIAbstractColorInspectorSlice

+ (NSString *)nibName;
{
    // Default to using the concrete xib for all subclasses instead of using our current class name.
    return @"OUIColorInspectorSlice";
}

- (void)dealloc;
{
    [_swatchPicker release];
    [_selectionValue release];
    [super dealloc];
}

@synthesize swatchPicker = _swatchPicker;
@synthesize selectionValue = _selectionValue;

- (NSSet *)getColorsFromObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (void)setColor:(OQColor *)color forObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)loadColorSwatchesForObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (IBAction)showDetails:(id)sender;
{
    _hasAddedColorSinceShowingDetail = NO;
    [super showDetails:sender];
}

- (void)updateInterfaceFromInspectedObjects;
{
    NSMutableArray *colors = [NSMutableArray array];
    NSSet *appropriateObjects = self.appropriateObjectsForInspection;
    
    // Get the appropriate color swatch
    [self loadColorSwatchesForObject:[appropriateObjects anyObject]];

    // Find a single color, obeying color spaces, that all the objects have.
    for (id object in appropriateObjects) {
        NSSet *objectColors = [self getColorsFromObject:object];
        if (objectColors)
            [colors addObjectsFromArray:[objectColors allObjects]];
    }

    OUIInspectorSelectionValue *selectionValue = [[OUIInspectorSelectionValue alloc] initWithValues:colors];

    // Compare the two colors in RGBA space, but keep the old single color's color space. This allow us to map to RGBA for text (where we store the RGBA in a CGColorRef for CoreText's benefit) but not lose the color space in our color picking UI, mapping all HSV colors with S or V of zero to black or white (and losing the H component).  See <bug://bugs/59912> (Hue slider jumps around)
    if (OFNOTEQUAL([selectionValue.dominantValue colorUsingColorSpace:OQColorSpaceRGB], [_selectionValue.uniqueValue colorUsingColorSpace:OQColorSpaceRGB])) {
        [_selectionValue release];
        _selectionValue = [selectionValue retain];
    } else
        [selectionValue release];

    // Don't check off swatches as selected unless there is only one color selected. Otherwise, we could have the main swatch list have one checkmark when there is really another selected color that just isn't in the list being shown.
    
    [_swatchPicker setSwatchSelectionColor:_selectionValue.uniqueValue];

    [super updateInterfaceFromInspectedObjects];
}

#pragma mark -
#pragma mark NSViewController

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    _swatchPicker.wraps = NO;
    _swatchPicker.showsNavigationSwatch = YES;
}

- (void)viewDidUnload;
{
    [_swatchPicker release];
    _swatchPicker = nil;
    [super viewDidUnload];
}

#pragma mark -
#pragma mark NSObject (OUIColorSwatch)

- (void)changeColor:(id <OUIColorValue>)colorValue;
{
    OQColor *color = colorValue.color;
    
    //NSLog(@"setting color %@, continuous %d", [colorValue.color shortDescription], colorValue.isContinuousColorChange);
    
    BOOL isContinuousChange = colorValue.isContinuousColorChange;
    
    OUIInspector *inspector = self.inspector;
    NSSet *appropriateObjects = self.appropriateObjectsForInspection;
    
    if (isContinuousChange && !_inContinuousChange) {
        //NSLog(@"will begin");
        _inContinuousChange = YES;
        [inspector willBeginChangingInspectedObjects];
    }
    
    [inspector beginChangeGroup];
    {
        for (id object in appropriateObjects)
            [self setColor:color forObject:object];
    }
    [inspector endChangeGroup];
    
    if (!isContinuousChange) {
        //NSLog(@"will end");
        _inContinuousChange = NO;
        [inspector didEndChangingInspectedObjects];
    }
    
    // Pre-populate our selected color before querying back from the objects. This will allow us to keep the original colorspace if the colors are equivalent enough.
    [_selectionValue release];
    _selectionValue = [[OUIInspectorSelectionValue alloc] initWithValue:color];
    
    [self updateInterfaceFromInspectedObjects];

    // Don't add more than one swatch to our top swatch list per journey into the detail pane.
    // In particular, if you scrub through the HSV sliders, we don't want to blow away all our colors.
    if (!_swatchPicker.hasSelectedSwatch) {
        [_swatchPicker addColor:color replacingRecentlyAdded:_hasAddedColorSinceShowingDetail];
        _hasAddedColorSinceShowingDetail = YES;
    }
}

@end

@implementation OUIColorInspectorSlice

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIColorInspection)];
}

- (NSSet *)getColorsFromObject:(id)object;
{
    return [(id <OUIColorInspection>)object colorsForInspectorSlice:self];
}

- (void)setColor:(OQColor *)color forObject:(id)object;
{
    [(id <OUIColorInspection>)object setColor:color fromInspectorSlice:self];
}

- (void)loadColorSwatchesForObject:(id)object;
{
    if (!object)
        return;
    
    NSString *preferenceKey = [(id <OUIColorInspection>)object preferenceKeyForInspectorSlice:self];
    self.swatchPicker.palettePreferenceKey = preferenceKey;
}

@end

@implementation OUIColorInspectorDetailSlice

- (void)dealloc;
{
    [_colorTypeSegmentedControl release];
    [_currentColorPicker release];
    [_paletteColorPicker release];
    [_hsvColorPicker release];
    [_rgbColorPicker release];
    [_grayColorPicker release];
    [super dealloc];
}

@synthesize colorTypeSegmentedControl = _colorTypeSegmentedControl;
@synthesize paletteColorPicker = _paletteColorPicker;
@synthesize hsvColorPicker = _hsvColorPicker;
@synthesize rgbColorPicker = _rgbColorPicker;
@synthesize grayColorPicker = _grayColorPicker;

- (NSUInteger)selectedColorPickerIndex;
{
    return _colorTypeSegmentedControl.selectedSegmentIndex;
}

- (void)setSelectedColorPickerIndex:(NSUInteger)segmentIndex;
{
    [_colorTypeSegmentedControl setSelectedSegmentIndex:segmentIndex];
    [self colorTypeSegmentedControlSelectionChanged:_colorTypeSegmentedControl];
}

- (IBAction)colorTypeSegmentedControlSelectionChanged:(id)sender;
{
    OUIInspectorSegmentedControlButton *segment = _colorTypeSegmentedControl.selectedSegment;
    OUIColorPicker *colorPicker = segment.representedObject;
    if (colorPicker == _currentColorPicker)
        return;
    
    OUIColorInspectorSlice *slice = (OUIColorInspectorSlice *)self.slice;

    [_currentColorPicker.view removeFromSuperview];
    [_currentColorPicker release];
    _currentColorPicker = [colorPicker retain];
    _currentColorPicker.selectionValue = slice.selectionValue;
    
    const CGFloat kSpaceBetweenSegmentedControllAndColorPicker = 8;
    
    // leaves the inspector at the same height if we somehow get no selection, which we shouldn't
    if (_currentColorPicker) {
        CGRect typeFrame = _colorTypeSegmentedControl.frame;
        
        // Keep only the height of the picker's view
        UIView *pickerView = _currentColorPicker.view;

        CGRect pickerFrame;
        pickerFrame.origin = CGPointMake(CGRectGetMinX(typeFrame), CGRectGetMaxY(typeFrame) + kSpaceBetweenSegmentedControllAndColorPicker);
        pickerFrame.size.width = CGRectGetWidth(typeFrame); // should span our bounds
        pickerFrame.size.height = [_currentColorPicker height];
        
        UIView *view = self.view;
        CGRect frame = view.frame;
        frame.size.height = CGRectGetMaxY(pickerFrame);
        view.frame = frame;
        [view layoutIfNeeded];
        
        self.contentSizeForViewInPopover = frame.size;
        
        [slice.inspector inspectorSizeChanged];

        pickerView.frame = pickerFrame;
        [self.view addSubview:pickerView];
        
        [_currentColorPicker becameCurrentColorPicker];
    }
}

#pragma mark -
#pragma mark OUIInspectorDetailSlice subclass

- (void)updateInterfaceFromInspectedObjects;
{
    OUIColorInspectorSlice *slice = (OUIColorInspectorSlice *)self.slice;
    
    _currentColorPicker.selectionValue = slice.selectionValue;
}

- (void)wasPushed;
{
    [super wasPushed];
    
    [_currentColorPicker becameCurrentColorPicker];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];

    // Let callers assign their own title
    if (![NSString isEmptyString:self.title])
        self.title = NSLocalizedStringFromTableInBundle(@"Color", @"OUIInspectors", OMNI_BUNDLE, @"color inspector title");
    
    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorPaletteSegment.png" representedObject:_paletteColorPicker];
    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorHSVSegment.png" representedObject:_hsvColorPicker];
    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorRGBSegment.png" representedObject:_rgbColorPicker];
    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorGraySegment.png" representedObject:_grayColorPicker];
    
    _colorTypeSegmentedControl.selectedSegment = _colorTypeSegmentedControl.firstSegment;
    [self colorTypeSegmentedControlSelectionChanged:nil];
}

#pragma mark -
#pragma mark NSObject (OUIColorSwatch)

- (void)changeColor:(id <OUIColorValue>)colorValue;
{
    // The responder chain doesn't leap back up the nav controller stack.
    [self.slice changeColor:colorValue];
}

@end
