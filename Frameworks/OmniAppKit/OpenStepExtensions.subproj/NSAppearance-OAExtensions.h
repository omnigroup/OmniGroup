// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSAppearance.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSAppearance (OAExtensions)

@property (nonatomic, readonly) BOOL OA_isDarkAppearance;

+ (void)withAppearance:(NSAppearance *)overrideAppearance performActions:(void (^ NS_NOESCAPE)(void))actions NS_SWIFT_NAME(withAppearance(_:performActions:));

@end

NS_ASSUME_NONNULL_END
