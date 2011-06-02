// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorInspectorPane.h>

#import <OmniUI/OUIColorPicker.h>
#import <OmniUI/OUIColorValue.h>
#import <OmniUI/OUIInspectorSegmentedControl.h>
#import <OmniUI/OUIInspectorSegmentedControlButton.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIColorInspectorPaneParentSlice.h>

RCS_ID("$Id$");

@implementation OUIColorInspectorPane

- (void)dealloc;
{
    [_colorTypeSegmentedControl release];
    [_shadowDivider release];
    [_currentColorPicker release];
    [_paletteColorPicker release];
    [_hsvColorPicker release];
    [_rgbColorPicker release];
    [_grayColorPicker release];
    [_noneColorPicker release];
    [super dealloc];
}

@synthesize colorTypeSegmentedControl = _colorTypeSegmentedControl;
@synthesize shadowDivider = _shadowDivider;

@synthesize noneColorPicker = _noneColorPicker;
@synthesize paletteColorPicker = _paletteColorPicker;
@synthesize hsvColorPicker = _hsvColorPicker;
@synthesize rgbColorPicker = _rgbColorPicker;
@synthesize grayColorPicker = _grayColorPicker;

@synthesize disableAutoPickingPanes;

- (void)_setSelectedColorTypeIndex:(NSInteger)colorTypeIndex;
{
    if (colorTypeIndex != (NSInteger)_colorTypeIndex) {
        _colorTypeIndex = colorTypeIndex;
        
        if (self.visibility == OUIViewControllerVisibilityVisible)
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIColorTypeChangeNotification object:self];
    }
    
    [_colorTypeSegmentedControl setSelectedSegmentIndex:_colorTypeIndex];
    
    OUIInspectorSegmentedControlButton *segment = [_colorTypeSegmentedControl segmentAtIndex:_colorTypeIndex];
    OUIColorPicker *colorPicker = segment.representedObject;
    if (colorPicker == _currentColorPicker)
        return;
    
    OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *slice = (OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *)self.parentSlice;
    
    if (_currentColorPicker) {
        [self removeChildViewController:_currentColorPicker animated:NO];
        [_currentColorPicker.view removeFromSuperview];
    }
    
    [_currentColorPicker release];
    _currentColorPicker = [colorPicker retain];
    
    if (_currentColorPicker) {
        _currentColorPicker.selectionValue = slice.selectionValue;
        
        // leaves the inspector at the same height if we somehow get no selection, which we shouldn't
        const CGFloat kSpaceBetweenSegmentedControllAndColorPicker = 8;
        
        CGRect typeFrame = _colorTypeSegmentedControl.frame;
        
        // Keep only the height of the picker's view
        UIView *pickerView = _currentColorPicker.view;
        
        UIView *view = self.view;
        CGRect frame = view.frame;

        CGFloat yOffset = CGRectGetMaxY(typeFrame) + kSpaceBetweenSegmentedControllAndColorPicker - CGRectGetMinY(frame);
        CGRect segmentedControlAndPaddingFrame, pickerFrame;
        CGRectDivide(view.frame, &segmentedControlAndPaddingFrame, &pickerFrame, yOffset, CGRectMinYEdge);
        
        pickerView.frame = pickerFrame;
        [view insertSubview:pickerView belowSubview:self.shadowDivider];
        [view layoutIfNeeded];

        [self addChildViewController:_currentColorPicker animated:NO];
    }
    
    [_shadowDivider setHidden:(_currentColorPicker != _paletteColorPicker)];
}

- (NSString *)selectedColorPickerIdentifier;
{
    if (_colorTypeIndex == NSNotFound)
        return nil;
    return [[[_colorTypeSegmentedControl segmentAtIndex:_colorTypeIndex] representedObject] identifier];
}

- (void)setSelectedColorPickerIdentifier:(NSString *)identifier;
{
    NSUInteger pickerIndex = NSNotFound;
    NSUInteger segmentIndex = [_colorTypeSegmentedControl segmentCount];
    while (segmentIndex--) {
        if (OFISEQUAL(identifier, [[[_colorTypeSegmentedControl segmentAtIndex:segmentIndex] representedObject] identifier])) {
            pickerIndex = segmentIndex;
            break;
        }
    }
    
    if (pickerIndex != NSNotFound) {
        _colorTypeIndex = pickerIndex;
        if ([self isViewLoaded]) {
            [self _setSelectedColorTypeIndex:_colorTypeIndex];
        }
    }
}

- (IBAction)colorTypeSegmentedControlSelectionChanged:(id)sender;
{
    OUIColorPicker *oldPicker = [[_currentColorPicker retain] autorelease];
    
    [self _setSelectedColorTypeIndex:[_colorTypeSegmentedControl selectedSegmentIndex]];
    
    if (oldPicker != _currentColorPicker) {
        [oldPicker wasDeselectedInColorInspectorPane:self];
        [_currentColorPicker wasSelectedInColorInspectorPane:self];
    }
}

#pragma mark -
#pragma mark OUIInspectorPane subclass

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *slice = (OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *)self.parentSlice;
    
    _currentColorPicker.selectionValue = slice.selectionValue;
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    // Let callers assign their own title
    if ([NSString isEmptyString:self.title])
        self.title = NSLocalizedStringFromTableInBundle(@"Color", @"OUIInspectors", OMNI_BUNDLE, @"color inspector title");
    
    OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *slice = (OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *)self.parentSlice;
    OBASSERT(slice);
    if (slice.allowsNone)
        [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorNoneSegment.png" representedObject:_noneColorPicker];
    
    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorPaletteSegment.png" representedObject:_paletteColorPicker];
    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorHSVSegment.png" representedObject:_hsvColorPicker];
    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorRGBSegment.png" representedObject:_rgbColorPicker];
    [_colorTypeSegmentedControl addSegmentWithImageNamed:@"OUIColorInspectorGraySegment.png" representedObject:_grayColorPicker];
    
    _colorTypeSegmentedControl.selectedSegment = [_colorTypeSegmentedControl segmentAtIndex:_colorTypeIndex];
    [self _setSelectedColorTypeIndex:_colorTypeIndex];
}

- (void)viewWillAppear:(BOOL)animated;
{
    if (!disableAutoPickingPanes) {
        // Default to the higest fidelity color picker, prefering earlier pickers. So, if the palette picker has an exact match, it will get used.
        OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *slice = (OUIInspectorSlice <OUIColorInspectorPaneParentSlice> *)self.parentSlice;
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
        
        [self _setSelectedColorTypeIndex:bestPickerIndex];
    }

    // Do this after possibly swapping child view controllers. This allows us to remove the old before it gets send -viewWillAppear:, which would hit an assertion (rightly).
    [super viewWillAppear:animated];
}

#pragma mark -
#pragma mark NSObject (OUIColorSwatch)

- (void)changeColor:(id <OUIColorValue>)colorValue;
{
    // The responder chain doesn't leap back up the nav controller stack.
    [self.parentSlice changeColor:colorValue];
}

@end
