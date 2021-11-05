// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIColorSwatchPicker.h>

RCS_ID("$Id$");

// OUIColorInspection
OBDEPRECATED_METHOD(-colorsForInspectorSlice:); // -> -colorForInspectorSlice:

@implementation OUIColorInspectorSlice

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIColorInspection)];
}

- (OAColor *)colorForObject:(id)object;
{
    return [(id <OUIColorInspection>)object colorForInspectorSlice:self];
}

- (void)setColor:(OAColor *)color forObject:(id)object;
{
    [(id <OUIColorInspection>)object setColor:color fromInspectorSlice:self];
}

- (void)loadColorSwatchesForObject:(id)object;
{
    if (!object)
        return;
    
    NSString *preferenceKey = [(id <OUIColorInspection>)object preferenceKeyForInspectorSlice:self];
    self.swatchPicker.palettePreferenceKey = preferenceKey;
}

@end

