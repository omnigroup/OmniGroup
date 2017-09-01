// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniUI/OUIAppController.h>

@class OFXServerAccount;

/*
 Shows a list of available account types and navigates to an account editor
 */

@interface OUIAddCloudAccountViewController : UIViewController <OUIDisabledDemoFeatureAlerter>

- (instancetype)initWithUsageMode:(OFXServerAccountUsageMode)usageModeToCreate;

@property (copy, nonatomic) void (^finished)(OFXServerAccount *newAccountOrNil);

@end
