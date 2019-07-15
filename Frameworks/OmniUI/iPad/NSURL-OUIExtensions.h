// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSURL.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSURL (OUIExtensions)

/// Returns YES if the scheme of the receiver is likely to be registered by another app (and not an assigned scheme listed by IANA).
@property (nonatomic, readonly, getter = isProbablyAppScheme) BOOL probablyAppScheme;

/// Returns YES if the receiver is likely to be previewable during a 3D Touch.
@property (nonatomic, readonly, getter = isProbablyPreviewable) BOOL probablyPreviewable;

@end

NS_ASSUME_NONNULL_END
