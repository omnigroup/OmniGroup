// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISingleViewInspectorPane.h>
#import <OmniUI/OUIColorPicker.h>

@class OUISegmentedControl;

// posts a change whenever the colorTypeSegmentedControl is changed via the UI
#define OUIColorTypeChangeNotification @"OUIColorTypeChangeNotification" 

@interface OUIColorInspectorPane : OUISingleViewInspectorPane <OUIColorPickerTarget>
{
@private
    OUISegmentedControl *_colorTypeSegmentedControl;
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

@property(weak,nonatomic) OUIInspectorSlice <OUIColorPickerTarget> *parentSlice; // Set by the parent slice, if any.
@property(strong,nonatomic) IBOutlet OUISegmentedControl *colorTypeSegmentedControl;
@property(strong,nonatomic) IBOutlet UIView *shadowDivider;

@property(copy,nonatomic) NSString *selectedColorPickerIdentifier;

@property(strong,nonatomic) IBOutlet OUIColorPicker *noneColorPicker;
@property(strong,nonatomic) IBOutlet OUIColorPicker *paletteColorPicker;
@property(strong,nonatomic) IBOutlet OUIColorPicker *hsvColorPicker;
@property(strong,nonatomic) IBOutlet OUIColorPicker *rgbColorPicker;
@property(strong,nonatomic) IBOutlet OUIColorPicker *grayColorPicker;

- (IBAction)colorTypeSegmentedControlSelectionChanged:(id)sender;
@property (nonatomic) BOOL disableAutoPickingPanes;  // OG remembers the previous choice

@end
