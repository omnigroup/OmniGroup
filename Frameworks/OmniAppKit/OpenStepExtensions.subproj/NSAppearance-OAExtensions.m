// Copyright 2017-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSAppearance-OAExtensions.h>

RCS_ID("$Id$")

@implementation NSAppearance (OAExtensions)

- (BOOL)OA_isDarkAppearance;
{
    static NSSet *darkAppearanceNames = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableSet *names = [NSMutableSet setWithObject:NSAppearanceNameVibrantDark];
        
#if defined(MAC_OS_X_VERSION_10_14) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_14
        if (@available(macOS 10.14, *)) {
            [names addObjectsFromArray:@[
                                         NSAppearanceNameAccessibilityHighContrastVibrantDark,
                                         NSAppearanceNameDarkAqua,
                                         NSAppearanceNameAccessibilityHighContrastDarkAqua,
                                         ]];
        }
#endif
        
        darkAppearanceNames = [names copy];
    });

    return [darkAppearanceNames containsObject:self.name];
}

@end
