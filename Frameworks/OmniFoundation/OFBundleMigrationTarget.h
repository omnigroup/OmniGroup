// Copyright 2020 Omni Development, Inc. All rights reserved.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol OFBundleMigrationTarget <NSObject>
+ (void)migrateItems:(NSArray <NSDictionary <NSString *, NSString *> *> *)items bundle:(NSBundle *)bundle;
@end

NS_ASSUME_NONNULL_END
