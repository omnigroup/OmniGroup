// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAbstractFontInspectorSlice.h>
#import <OmniFoundation/OFExtent.h>

@class OAFontDescriptor;
@class OUIInspectorTextWell, OUIInspectorStepperButton, OUIFontInspectorPane;

@interface OUIFontSizeInspectorSlice : OUIAbstractFontInspectorSlice

@property(nonatomic,strong) IBOutlet UILabel *fontSizeLabel;
@property(nonatomic,strong) IBOutlet UIView *fontSizeControl;
@property(nonatomic,strong) IBOutlet OUIInspectorStepperButton *fontSizeDecreaseStepperButton;
@property(nonatomic,strong) IBOutlet OUIInspectorStepperButton *fontSizeIncreaseStepperButton;

- (IBAction)increaseFontSize:(id)sender;
- (IBAction)decreaseFontSize:(id)sender;

- (UIView *)makeFontSizeControlWithFrame:(CGRect)frame; // Return a new view w/o adding it to the view heirarchy
- (void)updateFontSizeControl:(UIView *)fontSizeControl forFontSizes:(NSArray *)fontSizes extent:(OFExtent)fontSizeExtent;
- (void)updateFontSizeControl:(UIView *)fontSizeControl withText:(NSString *)text;

@property (nonatomic, strong) NSString *fontSizePointsString;

@end
