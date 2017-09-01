// Copyright 2017 Omni Development. Inc. All rights reserved.
//
// $Id$

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSURL (OUIExtensions)

/// Returns YES if the scheme of the receiver is likely to be registered by another app (and not an assigned scheme listed by IANA).
@property (nonatomic, readonly, getter = isProbablyAppScheme) BOOL probablyAppScheme;

@end

NS_ASSUME_NONNULL_END
