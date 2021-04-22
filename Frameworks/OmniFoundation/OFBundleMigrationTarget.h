// Copyright 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSString, NSDictionary, NSBundle;

NS_ASSUME_NONNULL_BEGIN

@protocol OFBundleMigrationTarget <NSObject>
+ (void)migrateItems:(NSArray <NSDictionary <NSString *, NSString *> *> *)items bundle:(NSBundle *)bundle;
@end

NS_ASSUME_NONNULL_END
