// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
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

static NSString *keychainIdentifier = @"com.omnigroup.InAppPurchase";

@implementation OUIAppController (InAppStore)

- (BOOL)isPurchaseUnlocked:(NSString *)productIdentifier;
{
    return [self _isPurchasedProductInKeychain:productIdentifier];
}

- (NSString *)vendorID;
{
    static OFPreference *vendorIDPreference;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        vendorIDPreference = [OFPreference preferenceForKey:@"OUIVendorID"];
    });

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
        (__bridge id)kSecAttrGeneric : [keychainIdentifier dataUsingEncoding:NSUTF8StringEncoding],
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
        (__bridge id)kSecAttrGeneric : [keychainIdentifier dataUsingEncoding:NSUTF8StringEncoding],
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


- (void)removePurchasedProductFromKeychain:(NSString *)productIdentifier;
{
    NSDictionary *query = @{
        (__bridge id)kSecAttrGeneric : [keychainIdentifier dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount : [productIdentifier dataUsingEncoding:NSUTF8StringEncoding],
    };

    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    if (status != errSecSuccess) {
        UIAlertView *keychainResetFailedAlert = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Couldn't Re-Lock %@", [self sheetTitleForInAppStoreProductIdentifier:productIdentifier]] message:[NSString stringWithFormat:@"Keychain error: %ld", (long)status] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
        [keychainResetFailedAlert show];
    } else {
        UIAlertView *keychainResetSuccessAlert = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Re-Locked %@", [self sheetTitleForInAppStoreProductIdentifier:productIdentifier]] message:[NSString stringWithFormat:@"%@ is now re-locked", [self sheetTitleForInAppStoreProductIdentifier:productIdentifier]] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
        [keychainResetSuccessAlert show];
    }
}

- (void)_showInAppPurchases:(NSString *)productIdentifier viewController:(UIViewController *)viewController pushOntoNavigationStack:(BOOL)shouldPushOntoNavigationStack;
{
    OBPRECONDITION(viewController != nil);
    
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

- (NSArray *)inAppPurchaseIdentifiers;
{
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

- (NSURL *)purchasedDescriptionURLForProductIdentifier:(NSString *)productIdentifier;
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
