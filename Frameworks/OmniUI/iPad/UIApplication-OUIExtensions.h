// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIApplication.h>

@class UIResponder;

NS_ASSUME_NONNULL_BEGIN

@interface UIApplication (OUIExtensions)

@property (nonatomic, nullable, readonly) UIResponder *firstResponder;

@end

NS_ASSUME_NONNULL_END

