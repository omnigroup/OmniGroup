// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorSlice.h>
#import <UIKit/UITableView.h>

@class OUIInspectorTextWell, OUIInspectorStepperButton, OUIFontInspectorDetailSlice, OUIInspectorSegmentedControl, OUIInspectorSegmentedControlButton;

@interface OUIFontInspectorSlice : OUIInspectorSlice
{
@private
    OUIInspectorTextWell *_fontFamilyTextWell;
    
    OUIInspectorSegmentedControl *_fontAttributeSegmentedControl;
    OUIInspectorSegmentedControlButton *_boldFontAttributeButton;
    OUIInspectorSegmentedControlButton *_italicFontAttributeButton;
    OUIInspectorSegmentedControlButton *_underlineFontAttributeButton;
    OUIInspectorSegmentedControlButton *_strikethroughFontAttributeButton;
    
    OUIInspectorStepperButton *_fontSizeDecreaseStepperButton;
    OUIInspectorStepperButton *_fontSizeIncreaseStepperButton;
    OUIInspectorTextWell *_fontSizeTextWell;
    
    BOOL _showStrikethrough;
    
    OUIFontInspectorDetailSlice *_fontFacesDetailSlice;
}

@property(retain) IBOutlet OUIInspectorTextWell *fontFamilyTextWell;
@property(retain) IBOutlet OUIInspectorSegmentedControl *fontAttributeSegmentedControl;
@property(retain) IBOutlet OUIInspectorStepperButton *fontSizeDecreaseStepperButton;
@property(retain) IBOutlet OUIInspectorStepperButton *fontSizeIncreaseStepperButton;
@property(retain) IBOutlet OUIInspectorTextWell *fontSizeTextWell;

- (IBAction)increaseFontSize:(id)sender;
- (IBAction)decreaseFontSize:(id)sender;
- (IBAction)fontSizeTextWellAction:(OUIInspectorTextWell *)sender;

// Called from the family listing to display members of the family
@property(retain) IBOutlet OUIFontInspectorDetailSlice *fontFacesDetailSlice;
- (void)showFacesForFamilyBaseFont:(UIFont *)font;

@property BOOL showStrikethrough;

@end
