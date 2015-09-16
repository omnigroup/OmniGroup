// Copyright 2011-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>
#import <StoreKit/SKProductsRequest.h>

#import <OmniUI/OUIInAppStoreObserver.h>

/*!
 @discussion Currently, this view controller only supports products that contain exactly 2 IAPs. In practice, this view controller is only useful for a Standard to Pro upgrade purchase where the IAPs are 'Full Price Pro' and 'Discounted/Free Pro'.
 */
@interface OUIInAppStoreViewController : UIViewController <SKProductsRequestDelegate, OUIInAppStoreObserverDelegate>

- (nonnull instancetype)initWithProductIdentifier:(nonnull NSString *)aProductID NS_DESIGNATED_INITIALIZER NS_EXTENSION_UNAVAILABLE_IOS("In-app purchases should be done in app, not in extensions");
- (nonnull instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE NS_EXTENSION_UNAVAILABLE_IOS("In-app purchases should be done in app, not in extensions");
- (nullable instancetype)initWithCoder:(nonnull NSCoder *)aDecoder NS_UNAVAILABLE NS_EXTENSION_UNAVAILABLE_IOS("In-app purchases should be done in app, not in extensions");

#define OUIInAppStoreViewControllerUpgradeInstalledNotification @"OUIInAppStoreViewControllerUpgradeInstalled"

@end
