// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIColorInspectorPaneParentSlice.h>
#import <OmniUI/OUIColorPicker.h>

@class OAColor;
@class OUIInspectorSelectionValue;

@interface OUIAbstractColorInspectorSlice : OUIInspectorSlice <OUIColorInspectorPaneParentSlice, OUIColorPickerTarget>
{
@private
    OUIInspectorSelectionValue *_selectionValue;
    BOOL _allowsNone;
    OAColor *_defaultColor;
}

// Must be subclassed, in addition to -isAppropriateForInspectedObject:.
- (OAColor *)colorForObject:(id)object;
- (void)setColor:(OAColor *)color forObject:(id)object;

- (void)handleColorChange:(OAColor *)color; // Hook so that Graffle can handle mass changes a little differently

@end

