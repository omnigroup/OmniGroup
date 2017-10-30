// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIApplication-OUIExtensions.h>
#import <OmniUI/UIResponder-OUIExtensions.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation UIApplication (OUIExtensions)

- (nullable UIResponder *)firstResponder;
{
    return UIResponder.firstResponder;
}

@end

NS_ASSUME_NONNULL_END
