// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorInspectorPane.h>

#import <OmniUI/OUIColorInspectorSlice.h>
#import <OmniUI/OUIColorPicker.h>
#import <OmniUI/OUIColorValue.h>
#import <OmniUI/OUIInspectorSegmentedControl.h>
#import <OmniUI/OUIInspectorSegmentedControlButton.h>
#import <OmniUI/OUIInspector.h>

RCS_ID("$Id$");

@implementation OUIColorInspectorPane

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

- (void)_setSelectedColorTypeIndex:(NSInteger)colorTypeIndex notify:(BOOL)notify;
{
    if (colorTypeIndex != (NSInteger)_colorTypeIndex) {
        _colorTypeIndex = colorTypeIndex;
        if (notify)
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIColorTypeChangeNotification object:self];
    }
    
    [_colorTypeSegmentedControl setSelectedSegmentIndex:_colorTypeIndex];
    
    OUIInspectorSegmentedControlButton *segment = [_colorTypeSegmentedControl segmentAtIndex:_colorTypeIndex];
    OUIColorPicker *colorPicker = segment.representedObject;
    if (colorPicker == _currentColorPicker)
        return;
    
    OUIColorInspectorSlice *slice = (OUIColorInspectorSlice *)self.parentSlice;
    
    if (notify)
        [_currentColorPicker viewWillDisappear:NO];
    [_currentColorPicker.view removeFromSuperview];
    [_currentColorPicker release];
    if (notify)
        [_currentColorPicker viewDidDisappear:NO];

    _currentColorPicker = [colorPicker retain];
    _currentColorPicker.selectionValue = slice.selectionValue;
    if (notify)
        [_currentColorPicker viewWillAppear:NO];

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
        
        if (notify)
            [_currentColorPicker viewDidAppear:NO];
    }
}

- (NSUInteger)selectedColorPickerIndex;
{
    return _colorTypeIndex;
}

- (void)setSelectedColorPickerIndex:(NSUInteger)segmentIndex;
{
    _colorTypeIndex = segmentIndex;
    if ([self isViewLoaded]) {
        [self _setSelectedColorTypeIndex:segmentIndex notify:NO];
    }
}

- (IBAction)colorTypeSegmentedControlSelectionChanged:(id)sender;
{
    [self _setSelectedColorTypeIndex:[_colorTypeSegmentedControl selectedSegmentIndex] notify:YES];
}

#pragma mark -
#pragma mark OUIInspectorPane subclass

- (void)updateInterfaceFromInspectedObjects;
{
    OUIColorInspectorSlice *slice = (OUIColorInspectorSlice *)self.parentSlice;
    
    _currentColorPicker.selectionValue = slice.selectionValue;
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
    
    _colorTypeSegmentedControl.selectedSegment = [_colorTypeSegmentedControl segmentAtIndex:_colorTypeIndex];
    [self _setSelectedColorTypeIndex:_colorTypeIndex notify:NO]; // We'll forward the view controller methods.
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    
    // Default to the higest fidelity color picker, prefering earlier pickers. So, if the palette picker has an exact match, it will get used.
    OUIColorInspectorSlice *slice = (OUIColorInspectorSlice *)self.parentSlice;
    OUIInspectorSelectionValue *selectionValue = slice.selectionValue;
    
    OUIColorPickerFidelity bestFidelity = OUIColorPickerFidelityZero;
    NSUInteger bestPickerIndex = NSNotFound;
    NSUInteger pickerCount = [_colorTypeSegmentedControl segmentCount];
    for (NSUInteger pickerIndex = 0; pickerIndex < pickerCount; pickerIndex++) {
        OUIColorPicker *picker = [[_colorTypeSegmentedControl segmentAtIndex:pickerIndex] representedObject];
        OUIColorPickerFidelity fidelity = [picker fidelityForSelectionValue:selectionValue];
        
        if (bestPickerIndex == NSNotFound || fidelity > bestFidelity) {
            bestPickerIndex = pickerIndex;
            bestFidelity = fidelity;
        }
    }

    [self _setSelectedColorTypeIndex:bestPickerIndex notify:NO];
    
    [_currentColorPicker viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    [_currentColorPicker viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated;
{
    [super viewWillDisappear:animated];
    [_currentColorPicker viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];
    [_currentColorPicker viewDidDisappear:animated];
}

#pragma mark -
#pragma mark NSObject (OUIColorSwatch)

- (void)changeColor:(id <OUIColorValue>)colorValue;
{
    // The responder chain doesn't leap back up the nav controller stack.
    [self.parentSlice changeColor:colorValue];
    
    [self updateInterfaceFromInspectedObjects];
}

@end
