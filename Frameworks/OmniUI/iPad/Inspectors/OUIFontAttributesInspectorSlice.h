// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorSlice.h>

@class OUISegmentedControl, OUISegmentedControlButton;

typedef enum {
    OUIFontAttributeButtonTypeBold,
    OUIFontAttributeButtonTypeItalic,
    OUIFontAttributeButtonTypeUnderline,
    OUIFontAttributeButtonTypeStrikethrough,
} OUIFontAttributeButtonType;

@interface OUIFontAttributesInspectorSlice : OUIInspectorSlice

- (OUISegmentedControlButton *)fontAttributeButtonForType:(OUIFontAttributeButtonType)type; // Useful when overriding -updateFontAttributeButtons
- (void)updateFontAttributeButtonsWithFontDescriptors:(NSArray *)fontDescriptors;

@property(nonatomic) BOOL showStrikethrough;
@property(nonatomic) BOOL useAdditionalOptions;

@end
