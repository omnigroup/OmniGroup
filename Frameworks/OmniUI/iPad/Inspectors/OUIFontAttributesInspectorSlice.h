// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorSlice.h>

@class OUIInspectorSegmentedControl, OUIInspectorSegmentedControlButton;

typedef enum {
    OUIFontAttributeButtonTypeBold,
    OUIFontAttributeButtonTypeItalic,
    OUIFontAttributeButtonTypeUnderline,
    OUIFontAttributeButtonTypeStrikethrough,
} OUIFontAttributeButtonType;

@interface OUIFontAttributesInspectorSlice : OUIInspectorSlice
{
@private
    OUIInspectorSegmentedControl *_fontAttributeSegmentedControl;
    OUIInspectorSegmentedControlButton *_boldFontAttributeButton;
    OUIInspectorSegmentedControlButton *_italicFontAttributeButton;
    OUIInspectorSegmentedControlButton *_underlineFontAttributeButton;
    OUIInspectorSegmentedControlButton *_strikethroughFontAttributeButton;

    BOOL _showStrikethrough;
}

//@property(retain) IBOutlet OUIInspectorSegmentedControl *fontAttributeSegmentedControl;

- (OUIInspectorSegmentedControlButton *)fontAttributeButtonForType:(OUIFontAttributeButtonType)type; // Useful when overriding -updateFontAttributeButtons
- (void)updateFontAttributeButtonsWithFontDescriptors:(NSArray *)fontDescriptors;

@property BOOL showStrikethrough;

@end
