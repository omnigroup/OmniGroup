// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorSlice.h>

@class OQColor;
@class OUIColorSwatchPicker, OUIInspectorSelectionValue;

@interface OUIAbstractColorInspectorSlice : OUIInspectorSlice
{
@private
    OUIColorSwatchPicker *_swatchPicker;
    OUIInspectorSelectionValue *_selectionValue;
    BOOL _hasAddedColorSinceShowingDetail;
    BOOL _inContinuousChange;
}

@property(retain) IBOutlet OUIColorSwatchPicker *swatchPicker;

- (IBAction)changeColor:(id)sender;

@property(readonly) OUIInspectorSelectionValue *selectionValue;

// Must be subclassed, in addition to -isAppropriateForInspectedObject:.
- (NSSet *)getColorsFromObject:(id)object;
- (void)setColor:(OQColor *)color forObject:(id)object;
- (void)loadColorSwatchesForObject:(id)object;

@end

// Uses the OUIColorInspection to validate objects and get/set colors.
@interface OUIColorInspectorSlice : OUIAbstractColorInspectorSlice
@end

#import <OmniUI/OUIInspectorDetailSlice.h>

@class OUIInspectorSegmentedControl, OUIColorPicker;

// posts a change whenevrer the colorTypeSegmentedControl is changed via the UI
#define OUIColorTypeChangeNotification @"OUIColorTypeChangeNotification" 

@interface OUIColorInspectorDetailSlice : OUIInspectorDetailSlice
{
@private
    OUIInspectorSegmentedControl *_colorTypeSegmentedControl;
    OUIColorPicker *_currentColorPicker;
    
    OUIColorPicker *_paletteColorPicker;
    OUIColorPicker *_hsvColorPicker;
    OUIColorPicker *_rgbColorPicker;
    OUIColorPicker *_grayColorPicker;
    
    NSUInteger _colorTypeIndex;
}

@property(retain,nonatomic) IBOutlet OUIInspectorSegmentedControl *colorTypeSegmentedControl;
@property(retain,nonatomic) IBOutlet OUIColorPicker *paletteColorPicker;
@property(retain,nonatomic) IBOutlet OUIColorPicker *hsvColorPicker;
@property(retain,nonatomic) IBOutlet OUIColorPicker *rgbColorPicker;
@property(retain,nonatomic) IBOutlet OUIColorPicker *grayColorPicker;

@property(assign) NSUInteger selectedColorPickerIndex;

- (IBAction)colorTypeSegmentedControlSelectionChanged:(id)sender;

@end
