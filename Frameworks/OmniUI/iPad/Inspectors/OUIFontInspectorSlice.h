// Copyright 2010-2011, 2013 Omni Development, Inc. All rights reserved.
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

@interface OUIFontInspectorSliceFontDisplay : NSObject
@property(nonatomic,copy) NSString *text;
@property(nonatomic,strong) UIFont *font;
@end

@interface OUIFontInspectorSlice : OUIInspectorSlice

@property(nonatomic,strong) IBOutlet OUIInspectorTextWell *fontFamilyTextWell;
@property(nonatomic,strong) IBOutlet UILabel *fontSizeLabel;
@property(nonatomic,strong) IBOutlet OUIInspectorStepperButton *fontSizeDecreaseStepperButton;
@property(nonatomic,strong) IBOutlet OUIInspectorStepperButton *fontSizeIncreaseStepperButton;

- (IBAction)increaseFontSize:(id)sender;
- (IBAction)decreaseFontSize:(id)sender;

- (OUIFontInspectorSliceFontDisplay *)fontNameDisplayForFontDescriptor:(OAFontDescriptor *)fontDescriptor;
- (OUIFontInspectorSliceFontDisplay *)fontNameDisplayForFontDescriptors:(NSArray *)fontDescriptors;

- (UIView *)makeFontSizeControlWithFrame:(CGRect)frame; // Return a new view w/o adding it to the view heirarchy
- (void)updateFontSizeControl:(UIView *)fontSizeControl forFontSizes:(NSArray *)fontSizes extent:(OFExtent)fontSizeExtent;
- (void)updateFontSizeControl:(UIView *)fontSizeControl withText:(NSString *)text;

@property(nonatomic,strong) IBOutlet OUIFontInspectorPane *fontFacesPane;
- (void)showFacesForFamilyBaseFont:(UIFont *)font; // Called from the family listing to display members of the family

@end
