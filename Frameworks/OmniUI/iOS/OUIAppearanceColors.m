// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppearanceColors.h>

RCS_ID("$Id$")

@implementation OUIAppearanceColors

// TODO: override to switch returned class based on global theme?
// + (instancetype)appearance;

@dynamic omniRedColor;
@dynamic omniOrangeColor;
@dynamic omniYellowColor;
@dynamic omniGreenColor;
@dynamic omniTealColor;
@dynamic omniBlueColor;
@dynamic omniPurpleColor;
@dynamic omniGraphiteColor;
@dynamic omniCremaColor;

@dynamic omniAlternateRedColor;
@dynamic omniAlternateYellowColor;

@dynamic omniNeutralDeemphasizedColor;
@dynamic omniNeutralPlaceholderColor;
@dynamic omniNeutralLightweightColor;

@dynamic omniDeleteColor;

@dynamic omniExplanotextColor;

@end

// Stub class to get correct plist lookup via +[OUIAppearanceColors appearance].
@implementation OUIAppearanceDefaultColors : OUIAppearanceColors
@end

// Stub class to get correct plist lookup via +[OUIAppearanceColors appearance].
@implementation OUIAppearanceDarkColors : OUIAppearanceColors
@end
