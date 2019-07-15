// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@import UIKit;

NS_ASSUME_NONNULL_BEGIN

@interface UIResponder (OUIExtensions)

// Alternative to -[UIApplication firstResponder] that can be called from code which hasn't been marked extension unsafe, but is never compiled into an extension.
@property (class, nonatomic, nullable, readonly) UIResponder *firstResponder NS_SWIFT_NAME(firstResponder) /* NS_EXTENSION_UNAVAILABLE_IOS("") */;

// Determines if `self` is in the chain anywhere between `firstResponder` and `responder`.
- (BOOL)isInActiveResponderChainPrecedingResponder:(UIResponder *)responder;

@end

NS_ASSUME_NONNULL_END
