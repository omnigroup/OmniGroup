// Copyright 2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIAppController.h>

@interface OUIAppController (InAppStore)

- (BOOL)isPurchaseUnlocked:(NSString *)productIdentifier;
- (NSString *)vendorID;
- (BOOL)addPurchasedProductToKeychain:(NSString *)productIdentifier;
- (void)removePurchasedProductFromKeychain:(NSString *)productIdentifier;

- (void)showInAppPurchases:(NSString *)productIdentifier viewController:(UIViewController *)viewController;
    // Present the In-App Purchase sheet from viewController.  If viewController is currently presenting another view controller, we call dismiss and then present the IAP sheet from within the completion handler.
- (void)showInAppPurchases:(NSString *)productIdentifier navigationController:(UINavigationController *)navigationController;
    // Push the In-App Purchase sheet into the current navigation controller. For this to look appropriate, the navigationController in question should be laid out with a width which matches what you would get with a presentation style of UIModalPresentationFormSheet.

// for subclassers
- (NSArray *)inAppPurchaseIdentifiers;
- (NSString *)purchaseMenuItemTitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
- (NSString *)sheetTitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
- (NSURL *)descriptionURLForProductIdentifier:(NSString *)productIdentifier;
- (NSURL *)purchasedDescriptionURLForProductIdentifier:(NSString *)productIdentifier;

- (NSArray *)pricingOptionSKUsForProductIdentifier:(NSString *)productIdentifier;
- (NSString *)descriptionForPricingOptionSKU:(NSString *)pricingOptionSKU;
- (void)validateEligibilityForPricingOptionSKU:(NSString *)pricingOptionSKU completion:(void (^)(BOOL isValidated))completionBlock;

- (void)didUnlockInAppPurchase:(NSString *)productIdentifier;

@end
