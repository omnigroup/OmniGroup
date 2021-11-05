// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSUserDefaults-OFExtensions.h>

#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h> // For group container identifier utility
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/NSProcessInfo-OFExtensions.h> // For .isSandboxed

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
        if (NSProcessInfo.processInfo.isSandboxed) {
            NSString *containingApplicationBundleIdentifier = NSBundle.containingApplicationBundleIdentifier;
            wrapper = [OFPreferenceWrapper preferenceWrapperWithGroupIdentifier:containingApplicationBundleIdentifier];
        } else {
            // Apps which aren't sandboxed don't have a group identifier, so we'll just leave this in the app's default preferences
            wrapper = [OFPreferenceWrapper sharedPreferenceWrapper];
        }
    } else {
        // Registration to a preference wrapper for an app group named for the shared container.
        // Useful for non-isolated sharing (e.g. any store variant) of user defaults between any variant application and any variant app extensions.
        // This will be prefixed appropriately for the platform (e.g. `WithGroupIdentifier`).
        wrapper = [OFPreferenceWrapper preferenceWrapperWithGroupIdentifier:itemName];
    }

    [wrapper registerDefaults:description options:OFPreferenceRegistrationOptionNone];
}

// OFBundleMigrationTarget protocol

static NSUserDefaults *_sourceUserDefault(NSString *sourceMarker)
{
    if ([sourceMarker isEqualToString:OFUserDefaultsRegistrationItemName]) {
        return [NSUserDefaults standardUserDefaults];
    } else if ([sourceMarker isEqualToString:OFContainingApplicationBundleIdentifierRegistrationItemName]) {
        NSString *containingApplicationBundleIdentifier = NSBundle.containingApplicationBundleIdentifier;
        NSString *groupContainerApplicationBundleIdentifier = [[NSFileManager defaultManager] groupContainerIdentifierForBaseIdentifier:containingApplicationBundleIdentifier];
        return [[[NSUserDefaults alloc] initWithSuiteName:groupContainerApplicationBundleIdentifier] autorelease];
    } else {
        NSString *groupContainerForBaseIdentifier = [[NSFileManager defaultManager] groupContainerIdentifierForBaseIdentifier:sourceMarker];
        return [[[NSUserDefaults alloc] initWithSuiteName:groupContainerForBaseIdentifier] autorelease];
    }
}

static OFPreferenceWrapper * _Nullable _destinationPreferenceWrapper(NSString *destinationMarker)
{
    if ([destinationMarker isEqualToString:OFUserDefaultsRegistrationItemName]) {
        return [OFPreferenceWrapper sharedPreferenceWrapper];
    } else if ([destinationMarker isEqualToString:OFContainingApplicationBundleIdentifierRegistrationItemName]) {
        if (NSProcessInfo.processInfo.isSandboxed) {
            NSString *containingApplicationBundleIdentifier = NSBundle.containingApplicationBundleIdentifier;
            return [OFPreferenceWrapper preferenceWrapperWithGroupIdentifier:containingApplicationBundleIdentifier];
        } else {
            // Apps which aren't sandboxed don't have a group identifier, so we'll just leave this where it is
            return nil;
        }
    } else {
        return [OFPreferenceWrapper preferenceWrapperWithGroupIdentifier:destinationMarker];
    }
}

+ (void)migrateItems:(NSArray <NSDictionary <NSString *, NSString *> *> *)items bundle:(NSBundle *)bundle;
{
    // App Extensions can not access standard user defaults and should not attempt to perform migrations in case that's the migration's source/destination.
    OBPRECONDITION(!OFIsRunningInAppExtension());
    if (OFIsRunningInAppExtension()) {
        return;
    }

    for (NSDictionary *item in items) {
        NSString *sourceMarker = item[OFUserDefaultsMigrationSourceKey];
        NSString *destinationMarker = item[OFUserDefaultsMigrationDestinationKey];
        if ([NSString isEmptyString:sourceMarker] || [NSString isEmptyString:destinationMarker]) {
            OBASSERT_NOT_REACHED("Item: %@ failed to register a source and/or destination for the migration", item);
            continue;
        }

        NSArray <NSString *> *migrationKeys = item[OFUserDefaultsMigrationKeysKey];
        if ([migrationKeys count] == 0) {
            continue;
        }

        NSUserDefaults *sourceUserDefaults = _sourceUserDefault(sourceMarker);
        OFPreferenceWrapper *destinationWrapper = _destinationPreferenceWrapper(destinationMarker);
        if (destinationWrapper == nil) {
            continue;
        }
        
        for (NSString *key in migrationKeys) {
            // Be sure to clear out a migration object if found in the source domain.
            // Otherwise, consider a case where an unwanted value resurfaces when: a migration is performed, reset to registrations in preference pane, re-run the migration finds the pre-migration value.
            id sourceObject = [sourceUserDefaults objectForKey:key];
            [sourceUserDefaults removeObjectForKey:key];

            OFPreference *destinationPreference = [destinationWrapper preferenceForKey:key];
            if ([destinationPreference hasNonDefaultValue]) {
                // Never perform a migration if the destination preference wrapper already has a non-default value for the key.
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
