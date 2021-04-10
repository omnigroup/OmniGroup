// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIActionViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class OFXServerAccount;

@interface OUIServerAccountValidationViewController : OUIActionViewController

- initWithAccount:(OFXServerAccount *)account username:(NSString *)username password:(NSString *)password;

@end

NS_ASSUME_NONNULL_END

