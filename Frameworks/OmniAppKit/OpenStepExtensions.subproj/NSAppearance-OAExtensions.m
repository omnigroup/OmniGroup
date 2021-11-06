// Copyright 2017-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSAppearance-OAExtensions.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

OBDEPRECATED_METHOD(+withAppearance:performActions:); // use -performAsCurrentDrawingAppearance: on NSAppearance directly (macOS 11 and up)

@implementation NSAppearance (OAExtensions)

- (BOOL)OA_isDarkAppearance;
{
    NSString *matchingAppearanceName = [self bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    if (matchingAppearanceName != nil && [matchingAppearanceName isEqualToString:NSAppearanceNameDarkAqua]) {
        return YES;
    } else {
        return NO;
    }
}


+ (void)withAppearance:(NSAppearance *)overrideAppearance performActions:(void (^ NS_NOESCAPE)(void))actions;
{
    if (@available(macOS 11, *)) {
        if (overrideAppearance) {
            [overrideAppearance performAsCurrentDrawingAppearance:actions];
        } else {
            actions();
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSAppearance *previousAppearance = self.currentAppearance;
        
        @try {
            self.currentAppearance = overrideAppearance;
            actions();
        } @finally {
            self.currentAppearance = previousAppearance;
        }
#pragma clang diagnostic pop
    }
}

@end

NS_ASSUME_NONNULL_END
