// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController+InAppStore.h>

#import <OmniUI/OUIInAppStoreViewController.h>

#import <Security/Security.h>


RCS_ID("$Id$");

static const UInt8 kKeychainIdentifier[] = "com.omnigroup.InAppPurchase";

@implementation OUIAppController (InAppStore)

- (BOOL)importIsUnlocked:(NSString *)productIdentifier;
{
    return [self readImportUnlockedFlagFromKeychain:productIdentifier];
}

- (NSString *)vendorID;
{
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString];
}

- (BOOL)addImportUnlockedFlagToKeychain:(NSString *)productIdentifier;
{
    NSData *unlockData = [productIdentifier dataUsingEncoding:NSUTF8StringEncoding];
    NSData *unlockValue = [[self vendorID] dataUsingEncoding:NSUTF8StringEncoding];
    
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSData dataWithBytes:kKeychainIdentifier length:strlen((const char *)kKeychainIdentifier)], (__bridge id)kSecAttrGeneric,
                           (__bridge id)kSecClassGenericPassword, (__bridge id)kSecClass,
                           unlockData, (__bridge id)kSecAttrAccount,
                           nil];
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       unlockValue, (__bridge id)kSecValueData,
                                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly, (__bridge id)kSecAttrAccessible,
                                       nil];
    
    OSStatus result = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    if (result == errSecItemNotFound) {
        [attributes setObject:[NSData dataWithBytes:kKeychainIdentifier length:strlen((const char *)kKeychainIdentifier)] forKey:(__bridge id)kSecAttrGeneric];
        [attributes setObject:(__bridge id)kSecClassGenericPassword forKey:(__bridge id)kSecClass];
        [attributes setObject:unlockData forKey:(__bridge id)kSecAttrAccount];
        result = SecItemAdd((__bridge CFDictionaryRef)attributes, NULL);
        if (result == errSecSuccess)
            return YES;
    }
    return NO;
}

- (BOOL)readImportUnlockedFlagFromKeychain:(NSString *)productIdentifier;
{
    BOOL isUnlocked = NO;
    
    NSData *unlockData = [productIdentifier dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSData dataWithBytes:kKeychainIdentifier length:strlen((const char *)kKeychainIdentifier)], (__bridge id)kSecAttrGeneric,
                           (__bridge id)kSecClassGenericPassword, (__bridge id)kSecClass,
                           unlockData, (__bridge id)kSecAttrAccount,
                           (__bridge id)kSecMatchLimitAll, (__bridge id)kSecMatchLimit, // only one result
                           (id)kCFBooleanTrue, (__bridge id)kSecReturnAttributes, // return the attributes previously set
                           (id)kCFBooleanTrue, (__bridge id)kSecReturnData, // and the payload data
                           nil];
    
    CFArrayRef matches = nil;
    OSStatus result = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&matches);
    if (result == errSecSuccess) {
        for (NSDictionary *item in (__bridge NSArray *)matches) {
            NSData *passwordData = [item objectForKey:(__bridge id)kSecValueData];
            NSString *keychainUUID = [[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding];
            
            isUnlocked = [keychainUUID isEqualToString:[self vendorID]];
        }
    }
    //    else if (result != errSecItemNotFound)
    //    {
    //        NSLog(@"%s: SecItemCopyMatching -> %ld", __PRETTY_FUNCTION__, result);
    //    }
    
    return isUnlocked;
}


- (void)deleteImportPurchasedFlag:(NSString *)productIdentifier;
{
    NSData *unlockData = [productIdentifier dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSData dataWithBytes:kKeychainIdentifier length:strlen((const char *)kKeychainIdentifier)], (__bridge id)kSecAttrGeneric,
                           (__bridge id)kSecClassGenericPassword, (__bridge id)kSecClass,
                           unlockData, (__bridge id)kSecAttrAccount,
                           nil];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    if (status != errSecSuccess) {
        UIAlertView *keychainResetFailedAlert = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Couldn't Re-Lock %@", [self sheetTitleForInAppStoreProductIdentifier:productIdentifier]] message:[NSString stringWithFormat:@"Keychain error: %ld", (long)status] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
        [keychainResetFailedAlert show];
    } else {
        UIAlertView *keychainResetSuccessAlert = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Re-Locked %@", [self sheetTitleForInAppStoreProductIdentifier:productIdentifier]] message:[NSString stringWithFormat:@"%@ is now re-locked", [self titleForInAppStoreProductIdentifier:productIdentifier]] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
        [keychainResetSuccessAlert show];
    }
}

- (void)showInAppPurchases:(NSString *)productIdentifier navigationController:(UINavigationController *)navigationController;
{
    if (![[self inAppPurchaseIdentifiers] containsObject:productIdentifier])
        return;
    
    OUIInAppStoreViewController *storeViewController =  [[OUIInAppStoreViewController alloc] initWithProductIdentifier:productIdentifier];
    if (navigationController) {
        [navigationController pushViewController:storeViewController animated:YES];
    } else {
        OBFinishPortingLater("The root view controller might not be right for everyone");
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:storeViewController];
        navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
        navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        
        UIViewController *viewController = self.window.rootViewController;
        [viewController presentViewController:navigationController animated:YES completion:nil];
    }
}


// for subclassers

- (NSArray *)inAppPurchaseIdentifiers;
{
    return nil;
}

- (NSString *)purchaseMenuItemTitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
{
    return nil;
}

- (NSString *)sheetTitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
{
    return nil;
}

- (NSString *)titleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
{
    return nil;
}

- (NSString *)subtitleForInAppStoreProductIdentifier:(NSString *)productIdentifier;
{
    return nil;
}

- (NSString *)descriptionForInAppStoreProductIdentifier:(NSString *)productIdentifier;
{
    return nil;
}

- (UIImage *)imageForInAppStoreProductIdentifier:(NSString *)productIdentifier;
{
    return nil;
}

- (void)didUnlockInAppPurchase:(NSString *)productIdentifier;
{
}

- (NSString *)documentUTIForInAppStoreProductIdentifier:(NSString *)productIdentifier;
{
    return nil;
}

@end
