// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSUserDefaults-OFExtensions.h>

#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/OFPreference.h>

NS_ASSUME_NONNULL_BEGIN

NSString * const OFUserDefaultsRegistrationItemName = @"defaultsDictionary";
NSString * const OFContainingApplicationBundleIdentifierRegistrationItemName = @"containingApplicationBundleIdentifier";

NSString * const OFUserDefaultsMigrationSourceKey = @"source";
NSString * const OFUserDefaultsMigrationDestinationKey = @"destination";
NSString * const OFUserDefaultsMigrationKeysKey = @"keys";

@implementation NSUserDefaults (OFExtensions)

// OFBundleRegistryTarget protocol

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description;
{
    OFPreferenceWrapper *wrapper;
    if ([itemName isEqualToString:OFUserDefaultsRegistrationItemName]) {
        // Registration to the preference wrapper backed by `standardUserDefaults`
        wrapper = [OFPreferenceWrapper sharedPreferenceWrapper];
    } else if ([itemName isEqualToString:OFContainingApplicationBundleIdentifierRegistrationItemName]) {
        // Registration to a preference wrapper for an app group named with the containing application's bundle identifier.
        // Useful for isolated sharing (e.g. per store variant) of user defaults between an application and its app extensions.
        // Application and app extensions need to declare the group to participate.
        // This will be prefixed appropriately for the platform (e.g. `WithGroupIdentifier`).
        NSString *containingApplicationBundleIdentifier = NSBundle.containingApplicationBundleIdentifier;
        wrapper = [OFPreferenceWrapper preferenceWrapperWithGroupIdentifier:containingApplicationBundleIdentifier];
    } else {
        // Registration to a preference wrapper for an app group named for the shared container.
        // Useful for non-isolated sharing (e.g. any store variant) of user defaults between any variant application and any variant app extensions.
        // This will be prefixed appropriately for the platform (e.g. `WithGroupIdentifier`).
        wrapper = [OFPreferenceWrapper preferenceWrapperWithGroupIdentifier:itemName];
    }

    [wrapper registerDefaults:description options:OFPreferenceRegistrationPreserveExistingRegistrations];
}

// OFBundleMigrationTarget protocol

+ (void)migrateItems:(NSArray <NSDictionary <NSString *, NSString *> *> *)items bundle:(NSBundle *)bundle;
{
    for (NSDictionary *item in items) {

        NSString *sourceKey = item[OFUserDefaultsMigrationSourceKey];
        (void)sourceKey;
        NSString *destinationKey = item[OFUserDefaultsMigrationDestinationKey];
        (void)destinationKey;
        NSArray <NSString *> *migrationKeys = item[OFUserDefaultsMigrationKeysKey];

        // <bug:///182130> (iOS-OmniFocus Feature: Write a migration for preferences moved from standard user defaults to "containingApplicationBundleIdentifier" suite): Whine and continue if anything is wrong so far.

        // <bug:///182130> (iOS-OmniFocus Feature: Write a migration for preferences moved from standard user defaults to "containingApplicationBundleIdentifier" suite): Don't arbitrarily choose source and destination. Actually look at the migration.

        NSUserDefaults *sourceUserDefaults = [NSUserDefaults standardUserDefaults];

        NSString *containingApplicationBundleIdentifier = NSBundle.containingApplicationBundleIdentifier;
        OFPreferenceWrapper *destinationWrapper = [OFPreferenceWrapper preferenceWrapperWithGroupIdentifier:containingApplicationBundleIdentifier];
        
        for (NSString *key in migrationKeys) {
            // Always clear out a migration object if found in the source domain
            id sourceObject = [sourceUserDefaults objectForKey:key];
            [sourceUserDefaults removeObjectForKey:key];

            OFPreference *destinationPreference = [destinationWrapper preferenceForKey:key];
            if ([destinationPreference hasNonDefaultValue]) {
                // No additional work needed for source key
                continue;
            }

            if (![sourceObject isEqual:[destinationPreference objectValue]]) {
                [destinationPreference setObjectValue:sourceObject];
            }
        }
    }
}

@end

NS_ASSUME_NONNULL_END
