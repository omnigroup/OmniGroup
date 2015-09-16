// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController+InAppStore.h>

#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIInAppStoreViewController.h>
#import <Security/Security.h>

RCS_ID("$Id$");

static NSString *storeKeychainIdentifier = @"com.omnigroup.InAppPurchase.live";
static NSString *sandboxStoreKeychainIdentifier = @"com.omnigroup.InAppPurchase.sandbox";

@implementation OUIAppController (InAppStore)

- (BOOL)isPurchaseUnlocked:(NSString *)productIdentifier;
{
    return [self _isPurchasedProductInKeychain:productIdentifier];
}

+ (BOOL)inSandboxStore;
{
    static BOOL inSandboxStore;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *receiptName = [[[NSBundle mainBundle] appStoreReceiptURL] lastPathComponent];
        inSandboxStore = OFISEQUAL(receiptName, @"sandboxReceipt");
    });
    return inSandboxStore;
}

+ (NSString *)_keychainIdentifier;
{
    if ([self inSandboxStore])
        return sandboxStoreKeychainIdentifier;
    else
        return storeKeychainIdentifier;
}

+ (OFPreference *)vendorIDPreference;
{
    static OFPreference *vendorIDPreference;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        vendorIDPreference = [OFPreference preferenceForKey:@"OUIVendorID"];
    });
    return vendorIDPreference;
}

- (NSString *)vendorID;
{
    OFPreference *vendorIDPreference = [[self class] vendorIDPreference];

    if (![vendorIDPreference hasNonDefaultValue]) {
        NSString *newVendorID = [[NSUUID UUID] UUIDString];
        [vendorIDPreference setObjectValue:newVendorID];
    }

    NSString *vendorID = [vendorIDPreference objectValue];
    OBPOSTCONDITION(vendorID != nil);
    return vendorID;
}

- (BOOL)addPurchasedProductToKeychain:(NSString *)productIdentifier;
{
    NSDictionary *query = @{
        (__bridge id)kSecAttrGeneric : [[[self class] _keychainIdentifier] dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount : [productIdentifier dataUsingEncoding:NSUTF8StringEncoding],
    };

    NSDictionary *updateAttributes = @{
        (__bridge id)kSecValueData : [[self vendorID] dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    };

    OSStatus result = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)updateAttributes);
    if (result == errSecSuccess)
        return YES;

    if (result == errSecItemNotFound) {
        NSMutableDictionary *newAttributes = [updateAttributes mutableCopy];
        [newAttributes addEntriesFromDictionary:query];
        result = SecItemAdd((__bridge CFDictionaryRef)newAttributes, NULL);
        if (result == errSecSuccess)
            return YES;
    }

    return NO;
}

- (BOOL)_isPurchasedProductInKeychain:(NSString *)productIdentifier;
{
    NSDictionary *query = @{
        (__bridge id)kSecAttrGeneric : [[[self class] _keychainIdentifier] dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount : [productIdentifier dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitAll, // only one result
        (__bridge id)kSecReturnAttributes : (id)kCFBooleanTrue, // return the attributes previously set
        (__bridge id)kSecReturnData : (id)kCFBooleanTrue, // and the payload data
    };

    CFArrayRef matches = nil;
    OSStatus result = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&matches);
    if (result == errSecSuccess) {
        for (NSDictionary *item in (__bridge NSArray *)matches) {
            NSData *passwordData = [item objectForKey:(__bridge id)kSecValueData];
            NSString *keychainUUID = [[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding];
            
            return [keychainUUID isEqualToString:[self vendorID]];
        }
    }

    return NO;
}

- (void)_showInAppPurchases:(NSString *)productIdentifier viewController:(UIViewController *)viewController pushOntoNavigationStack:(BOOL)shouldPushOntoNavigationStack NS_EXTENSION_UNAVAILABLE_IOS("In-app purchases should be done in app, not in extensions");
{
    OBPRECONDITION(viewController != nil);

    if ([self isRunningRetailDemo]) {
        [self showFeatureDisabledForRetailDemoAlertFromViewController:viewController];
        return;
    }

    if (![[self inAppPurchaseIdentifiers] containsObject:productIdentifier])
        return;
    
    OUIInAppStoreViewController *storeViewController = [[OUIInAppStoreViewController alloc] initWithProductIdentifier:productIdentifier];

    if (shouldPushOntoNavigationStack) {
        UINavigationController *navigationController = OB_CHECKED_CAST(UINavigationController, viewController);
        [navigationController pushViewController:storeViewController animated:YES];
    } else {
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:storeViewController];
        navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
        navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        
        if (viewController.presentedViewController) {
            [viewController dismissViewControllerAnimated:YES completion:^{
                [viewController presentViewController:navigationController animated:YES completion:nil];
            }];
        }
        else {
            [viewController presentViewController:navigationController animated:YES completion:nil];
        }
    }
}

- (void)showInAppPurchases:(NSString *)productIdentifier viewController:(UIViewController *)viewController;
{
    [self _showInAppPurchases:productIdentifier viewController:viewController pushOntoNavigationStack:NO];
}

- (void)showInAppPurchases:(NSString *)productIdentifier navigationController:(UINavigationController *)navigationController;
{
    [self _showInAppPurchases:productIdentifier viewController:navigationController pushOntoNavigationStack:YES];
}

// for subclassers

- (BOOL)isEligibleForProUpgradeDiscount;
{
    OBRequestConcreteImplementation(self, _cmd);
    return NO;
}

- (NSString *)proUpgradePaidSKU;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (NSString *)proUpgradeDiscountSKU;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (NSURL *)proUpgradeMoreInfoURL;
{
    return nil;
}

- (NSString *)proUpgradeProductIdentifier;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (NSArray *)inAppPurchaseIdentifiers;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (NSString *)purchaseMenuItemTitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSString *)sheetTitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSURL *)descriptionURLForProductIdentifier:(NSString *)productIdentifier;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSArray *)pricingOptionSKUsForProductIdentifier:(NSString *)productIdentifier;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSString *)descriptionForPricingOptionSKU:(NSString *)pricingOptionSKU;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)validateEligibilityForPricingOptionSKU:(NSString *)pricingOptionSKU completion:(void (^)(BOOL isValidated))completionBlock;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)didUnlockInAppPurchase:(NSString *)productIdentifier;
{
}

@end
