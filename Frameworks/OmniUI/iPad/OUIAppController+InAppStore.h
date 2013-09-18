// Copyright 2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIAppController.h>

@interface OUIAppController (InAppStore)

- (BOOL)importIsUnlocked:(NSString *)productIdentifier;
- (NSString *)vendorID;
- (BOOL)addImportUnlockedFlagToKeychain:(NSString *)productIdentifier;
- (BOOL)readImportUnlockedFlagFromKeychain:(NSString *)productIdentifier;
- (void)deleteImportPurchasedFlag:(NSString *)productIdentifier;
- (void)showInAppPurchases:(NSString *)productIdentifier navigationController:(UINavigationController *)navigationController;

// for subclassers
- (NSArray *)inAppPurchaseIdentifiers;
- (NSString *)purchaseMenuItemTitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
- (NSString *)sheetTitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
- (NSString *)titleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
- (NSString *)subtitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
- (NSString *)descriptionForInAppStoreProductIdentifier:(NSString *)productIdentifier;
- (UIImage *)imageForInAppStoreProductIdentifier:(NSString *)productIdentifier;
- (void)didUnlockInAppPurchase:(NSString *)productIdentifier;
- (NSString *)documentUTIForInAppStoreProductIdentifier:(NSString *)productIdentifier;

@end
