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

static NSString *storeKeychainIdentifierSuffix = @".InAppPurchase.live";
static NSString *sandboxStoreKeychainIdentifierSuffix = @".InAppPurchase.sandbox";

@implementation OUIAppController (InAppStore)

- (BOOL)isPurchaseUnlocked:(NSString *)productIdentifier;
{
    return [self _isPurchasedProductInKeychain:productIdentifier];
}

+ (BOOL)inSandboxStore;
{
#if TARGET_IPHONE_SIMULATOR
    return YES;
#else
    static BOOL inSandboxStore;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *receiptName = [[[NSBundle mainBundle] appStoreReceiptURL] lastPathComponent];
        inSandboxStore = OFISEQUAL(receiptName, @"sandboxReceipt");
    });
    return inSandboxStore;
#endif
}

+ (NSString *)_keychainIdentifier;
{
    static NSString *keychainIdentifier;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *storeSuffix;
        if ([self inSandboxStore])
            storeSuffix = sandboxStoreKeychainIdentifierSuffix;
        else
            storeSuffix = storeKeychainIdentifierSuffix;
        keychainIdentifier = [[[NSBundle mainBundle] bundleIdentifier] stringByAppendingString:storeSuffix];
    });
    return keychainIdentifier;
}

+ (NSString *)_serviceIdentifierForProductIdentifier:(NSString *)productIdentifier;
{
    return [NSString stringWithFormat:@"%@|%@", [self _keychainIdentifier], productIdentifier];
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

static NSMutableSet *_recordedPurchases(void) OB_HIDDEN;
static NSMutableSet *_recordedPurchases(void)
{
    static NSMutableSet *recordedPurchases = nil;
    static dispatch_once_t once = 0;
    
    dispatch_once(&once, ^{
        recordedPurchases = [[NSMutableSet alloc] init];
    });

    return recordedPurchases;
}

- (void)addPurchasedProductToKeychain:(NSString *)productIdentifier;
{
    // The customer has purchased something. We need to track it even if keychain access fails for some reason (e.g. a spurious instances of -34018 "client has neither application-identifier nor keychain-access-groups entitlements")
    [_recordedPurchases() addObject:productIdentifier];

    NSDictionary *query = @{
        (__bridge id)kSecAttrGeneric : [[self class] _keychainIdentifier],
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : [[self class] _serviceIdentifierForProductIdentifier:productIdentifier],
    };

    NSDictionary *updateAttributes = @{
        (__bridge id)kSecValueData : [[self vendorID] dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleAlwaysThisDeviceOnly,
    };

    OSStatus updateResult = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)updateAttributes);
    if (updateResult == errSecSuccess)
        return;

    if (updateResult != errSecItemNotFound) {
        NSLog(@"Unable to record purchase for next session: SecItemUpdate -> %@", @(updateResult));
        return;
    }

    NSMutableDictionary *newAttributes = [updateAttributes mutableCopy];
    [newAttributes addEntriesFromDictionary:query];
    OSStatus addResult = SecItemAdd((__bridge CFDictionaryRef)newAttributes, NULL);
    if (addResult == errSecSuccess)
        return;

    if (addResult != errSecDuplicateItem) {
        NSLog(@"Unable to record purchase for next session: SecItemUpdate -> %@, SecItemAdd -> %@", @(updateResult), @(addResult));
        return;
    }

    OSStatus deleteResult = SecItemDelete((__bridge CFDictionaryRef)query);
    addResult = SecItemAdd((__bridge CFDictionaryRef)newAttributes, NULL);
    if (addResult == errSecSuccess)
        return;

    NSLog(@"Unable to record purchase for next session: SecItemUpdate -> %@, SecItemDelete -> %@, SecItemAdd -> %@", @(updateResult), @(deleteResult), @(addResult));
}

- (BOOL)_isPurchasedProductInKeychain:(NSString *)productIdentifier;
{
    if ([_recordedPurchases() containsObject:productIdentifier])
        return YES;

    NSDictionary *query = @{
        (__bridge id)kSecAttrGeneric : [[self class] _keychainIdentifier],
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : [[self class] _serviceIdentifierForProductIdentifier:productIdentifier],
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
            
            if ([keychainUUID isEqualToString:[self vendorID]]) {
                [_recordedPurchases() addObject:productIdentifier]; // Save ourselves a keychain lookup next time
                return YES;
            } else {
                return NO;
            }
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
