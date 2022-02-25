// Copyright 2015-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIActionInspectorSlice.h>
#import <OmniFoundation/OFExtent.h>

@class OAFontDescriptor;
@class OUIInspectorTextWell, OUIInspectorStepperButton, OUIFontInspectorPane;
@class UIFontPickerViewControllerConfiguration;

@interface OUIFontFamilyInspectorSlice : OUIActionInspectorSlice

@property(nonatomic,strong) IBOutlet OUIFontInspectorPane *fontFacesPane;

- (void)showFacesForFamilyBaseFont:(UIFont *)font; // Called from the family listing to display members of the family

- (UIFontPickerViewControllerConfiguration *)fontPickerConfiguration;

@end
