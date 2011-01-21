// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUISingleViewInspectorPane.h>

@class OUIInspectorSegmentedControl, OUIColorPicker;

// posts a change whenevrer the colorTypeSegmentedControl is changed via the UI
#define OUIColorTypeChangeNotification @"OUIColorTypeChangeNotification" 

@interface OUIColorInspectorPane : OUISingleViewInspectorPane
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
