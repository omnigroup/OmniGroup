// Copyright 2011-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIAppController.h>

@class OFPreference;

@interface OUIAppController (InAppStore)

- (BOOL)isPurchaseUnlocked:(NSString *)productIdentifier;

+ (BOOL)inSandboxStore;
+ (OFPreference *)vendorIDPreference;
- (NSString *)vendorID;

- (void)addPurchasedProductToKeychain:(NSString *)productIdentifier;

- (void)showInAppPurchases:(NSString *)productIdentifier viewController:(UIViewController *)viewController NS_EXTENSION_UNAVAILABLE_IOS("In-app purchases should be done in app, not in extensions");
    // Present the In-App Purchase sheet from viewController.  If viewController is currently presenting another view controller, we call dismiss and then present the IAP sheet from within the completion handler.
- (void)showInAppPurchases:(NSString *)productIdentifier navigationController:(UINavigationController *)navigationController NS_EXTENSION_UNAVAILABLE_IOS("In-app purchases should be done in app, not in extensions");
    // Push the In-App Purchase sheet into the current navigation controller. For this to look appropriate, the navigationController in question should be laid out with a width which matches what you would get with a presentation style of UIModalPresentationFormSheet.

// for subclassers
- (BOOL)isEligibleForProUpgradeDiscount;
- (NSString *)proUpgradePaidSKU;
- (NSString *)proUpgradeDiscountSKU;
- (NSURL *)proUpgradeMoreInfoURL;

- (NSString *)proUpgradeProductIdentifier;
- (NSArray *)inAppPurchaseIdentifiers;
- (NSString *)purchaseMenuItemTitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
- (NSString *)sheetTitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
- (NSURL *)descriptionURLForProductIdentifier:(NSString *)productIdentifier;

- (NSArray *)pricingOptionSKUsForProductIdentifier:(NSString *)productIdentifier;
- (NSString *)descriptionForPricingOptionSKU:(NSString *)pricingOptionSKU;
- (void)validateEligibilityForPricingOptionSKU:(NSString *)pricingOptionSKU completion:(void (^)(BOOL isValidated))completionBlock;

- (void)didUnlockInAppPurchase:(NSString *)productIdentifier;

@end
