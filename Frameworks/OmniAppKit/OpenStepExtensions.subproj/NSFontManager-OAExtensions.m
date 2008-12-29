// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSFontManager-OAExtensions.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation NSFontManager (OAExtensions)

- (NSFont *)closestFontWithFamily:(NSString *)family traits:(NSFontTraitMask)traits size:(float)size;
{
    // According to the NSFontManager documentation, '5' is the weight for 'regular' fonts (1 is ultralight).
    return [self closestFontWithFamily:family traits:traits weight:5 size:size];
}

- (NSFont *)closestFontWithFamily:(NSString *)family traits:(NSFontTraitMask)traits weight:(int)weight size:(float)size;
{
    NSFont *font;

    font = [self fontWithFamily:family traits:traits weight:weight size:size];
    if (font && ([self traitsOfFont:font] & traits) == traits)
        return font;

    font = [self fontWithFamily:family traits:0 weight:weight size:size];
    if ([font isFixedPitch])
        return [self fontWithFamily:@"Courier" traits:traits weight:weight size:size];
    else
        return [self fontWithFamily:@"Helvetica" traits:traits weight:weight size:size];
}

@end
