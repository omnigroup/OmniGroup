// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIViewController.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniUI/OUIAppController.h>

NS_ASSUME_NONNULL_BEGIN

@class OFXAgentActivity, OFXServerAccount;

/*
 Shows a list of available account types and navigates to an account editor
 */

@interface OUIAddCloudAccountViewController : UIViewController <OUIDisabledDemoFeatureAlerter>

- (instancetype)initWithAgentActivity:(OFXAgentActivity *)agentActivity usageMode:(OFXServerAccountUsageMode)usageModeToCreate;

@property (copy, nullable, nonatomic) void (^finished)(OFXServerAccount * _Nullable newAccountOrNil);

@end

NS_ASSUME_NONNULL_END
