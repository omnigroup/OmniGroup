// Copyright 1998-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSSliderCell-OAExtensions.h>
#import <OmniAppKit/NSCell-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")


@implementation NSSliderCell (OAExtensions)

- (void) applySettingsToCell: (NSCell *) cell;
{
    [super applySettingsToCell: cell];

    [(NSSliderCell *)cell setMinValue: [self minValue]];
    [(NSSliderCell *)cell setMaxValue: [self maxValue]];
    [(NSSliderCell *)cell setAltIncrementValue: [self altIncrementValue]];
    [(NSSliderCell *)cell setTitleCell: [self titleCell]];
    [(NSSliderCell *)cell setKnobThickness: [self knobThickness]];
    [(NSSliderCell *)cell setNumberOfTickMarks: [self numberOfTickMarks]];
    [(NSSliderCell *)cell setTickMarkPosition: [self tickMarkPosition]];
    [(NSSliderCell *)cell setAllowsTickMarkValuesOnly: [self allowsTickMarkValuesOnly]];
}

@end
