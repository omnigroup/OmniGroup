// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@class NSString, NSBundle;

NS_ASSUME_NONNULL_BEGIN

@protocol OFBundleRegistryTarget
+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(id)description;
@end

NS_ASSUME_NONNULL_END

