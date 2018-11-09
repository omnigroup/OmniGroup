// Copyright 2017-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSAppearance-OAExtensions.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation NSAppearance (OAExtensions)

- (BOOL)OA_isDarkAppearance;
{
    if (@available(macOS 10.14, *)) {
        NSString *matchingAppearanceName = [self bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        if (matchingAppearanceName != nil && [matchingAppearanceName isEqualToString:NSAppearanceNameDarkAqua]) {
            return YES;
        } else {
            return NO;
        }
    } else {
        return [self.name isEqualToString:NSAppearanceNameVibrantDark];
    }
}

+ (void)withAppearance:(NSAppearance *)overrideAppearance performActions:(void (^ NS_NOESCAPE)(void))actions;
{
    NSAppearance *previousAppearance = self.currentAppearance;
    
    @try {
        self.currentAppearance = overrideAppearance;
        actions();
    } @finally {
        self.currentAppearance = previousAppearance;
    }
}

@end

NS_ASSUME_NONNULL_END
