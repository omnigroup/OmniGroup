// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUISingleViewInspectorPane.h>

@class OUIInspectorSegmentedControl, OUIColorPicker;

// posts a change whenever the colorTypeSegmentedControl is changed via the UI
#define OUIColorTypeChangeNotification @"OUIColorTypeChangeNotification" 

@interface OUIColorInspectorPane : OUISingleViewInspectorPane
{
@private
    OUIInspectorSegmentedControl *_colorTypeSegmentedControl;
    UIView *_shadowDivider;
    OUIColorPicker *_currentColorPicker;
    
    OUIColorPicker *_noneColorPicker;
    OUIColorPicker *_paletteColorPicker;
    OUIColorPicker *_hsvColorPicker;
    OUIColorPicker *_rgbColorPicker;
    OUIColorPicker *_grayColorPicker;
    
    NSUInteger _colorTypeIndex;
    BOOL disableAutoPickingPanes;
}

@property(retain,nonatomic) IBOutlet OUIInspectorSegmentedControl *colorTypeSegmentedControl;
@property(retain,nonatomic) IBOutlet UIView *shadowDivider;

@property(copy,nonatomic) NSString *selectedColorPickerIdentifier;

@property(retain,nonatomic) IBOutlet OUIColorPicker *noneColorPicker;
@property(retain,nonatomic) IBOutlet OUIColorPicker *paletteColorPicker;
@property(retain,nonatomic) IBOutlet OUIColorPicker *hsvColorPicker;
@property(retain,nonatomic) IBOutlet OUIColorPicker *rgbColorPicker;
@property(retain,nonatomic) IBOutlet OUIColorPicker *grayColorPicker;

- (IBAction)colorTypeSegmentedControlSelectionChanged:(id)sender;
@property (nonatomic) BOOL disableAutoPickingPanes;  // OG remembers the previous choice

@end
