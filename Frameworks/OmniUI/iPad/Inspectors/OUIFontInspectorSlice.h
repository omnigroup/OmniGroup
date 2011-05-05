// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorSlice.h>
#import <OmniFoundation/OFExtent.h>

@class OAFontDescriptor;
@class OUIInspectorTextWell, OUIInspectorStepperButton, OUIFontInspectorPane;

typedef struct {
    NSString *text;
    UIFont *font;
} OUIFontInspectorSliceFontDisplay;

@interface OUIFontInspectorSlice : OUIInspectorSlice
{
@private
    OUIInspectorTextWell *_fontFamilyTextWell;
    
    OUIInspectorStepperButton *_fontSizeDecreaseStepperButton;
    OUIInspectorStepperButton *_fontSizeIncreaseStepperButton;
    OUIInspectorTextWell *_fontSizeTextWell;
    
    OUIFontInspectorPane *_fontFacesPane;
}

@property(retain) IBOutlet OUIInspectorTextWell *fontFamilyTextWell;
@property(retain) IBOutlet OUIInspectorStepperButton *fontSizeDecreaseStepperButton;
@property(retain) IBOutlet OUIInspectorStepperButton *fontSizeIncreaseStepperButton;
@property(retain) IBOutlet OUIInspectorTextWell *fontSizeTextWell;

- (IBAction)increaseFontSize:(id)sender;
- (IBAction)decreaseFontSize:(id)sender;
- (IBAction)fontSizeTextWellAction:(OUIInspectorTextWell *)sender;

- (OUIFontInspectorSliceFontDisplay)fontNameDisplayForFontDescriptor:(OAFontDescriptor *)fontDescriptor;
- (OUIFontInspectorSliceFontDisplay)fontNameDisplayForFontDescriptors:(NSArray *)fontDescriptors;
- (void)updateFontSizeTextWellForFontSizes:(NSArray *)fontSizes extent:(OFExtent)fontSizeExtent;

@property(retain) IBOutlet OUIFontInspectorPane *fontFacesPane;
- (void)showFacesForFamilyBaseFont:(UIFont *)font; // Called from the family listing to display members of the family

@end
