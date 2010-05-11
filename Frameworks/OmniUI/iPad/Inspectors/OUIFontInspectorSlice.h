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

@class OUIInspectorTextWell, OUIInspectorStepperButton;

@interface OUIFontInspectorSlice : OUIInspectorSlice
{
@private
    OUIInspectorTextWell *_fontFamilyTextWell;
    OUIInspectorTextWell *_fontFaceTextWell;
    OUIInspectorStepperButton *_fontSizeDecreaseStepperButton;
    OUIInspectorStepperButton *_fontSizeIncreaseStepperButton;
    OUIInspectorTextWell *_fontSizeTextWell;
}

@property(retain) IBOutlet OUIInspectorTextWell *fontFamilyTextWell;
@property(retain) IBOutlet OUIInspectorTextWell *fontFaceTextWell;
@property(retain) IBOutlet OUIInspectorStepperButton *fontSizeDecreaseStepperButton;
@property(retain) IBOutlet OUIInspectorStepperButton *fontSizeIncreaseStepperButton;
@property(retain) IBOutlet OUIInspectorTextWell *fontSizeTextWell;

- (IBAction)increaseFontSize:(id)sender;
- (IBAction)decreaseFontSize:(id)sender;
- (IBAction)fontSizeTextWellAction:(OUIInspectorTextWell *)sender;

@end


#import <OmniUI/OUIInspectorDetailSlice.h>
@interface OUIFontInspectorDetailSlice : OUIInspectorDetailSlice <UITableViewDataSource, UITableViewDelegate>
{
@private
    BOOL _showFamilies;
    NSArray *_sections;
    
    NSArray *_fonts;
    NSArray *_fontNames;
    NSSet *_selectedFonts;
}

+ (NSSet *)recommendedFontFamilyNames;

@property(assign,nonatomic) BOOL showFamilies;

@end
