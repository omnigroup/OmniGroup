// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorSlice.h>

@class OQColor;
@class OUIColorSwatchPicker, OUIInspectorSelectionValue;

@interface OUIAbstractColorInspectorSlice : OUIInspectorSlice
{
@private
    OUIColorSwatchPicker *_swatchPicker;
    OUIInspectorSelectionValue *_selectionValue;
    BOOL _hasAddedColorSinceShowingDetail;
    BOOL _inContinuousChange;
}

@property(nonatomic,readonly) OUIColorSwatchPicker *swatchPicker;

- (IBAction)changeColor:(id)sender;

@property(nonatomic,readonly) OUIInspectorSelectionValue *selectionValue;

// Must be subclassed, in addition to -isAppropriateForInspectedObject:.
- (NSSet *)getColorsFromObject:(id)object;
- (void)setColor:(OQColor *)color forObject:(id)object;
- (void)loadColorSwatchesForObject:(id)object;

@end

// Uses the OUIColorInspection to validate objects and get/set colors.
@interface OUIColorInspectorSlice : OUIAbstractColorInspectorSlice
@end
