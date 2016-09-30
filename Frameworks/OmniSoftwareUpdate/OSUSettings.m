// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUSettings.h"

#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniBase/OmniBase.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#endif

RCS_ID("$Id$");

/*
 We used to read/write these to a shared preferences domain. But, with the advent of sandboxing, Apple prefers that we not use the temporary entitlement to enable this (at least on the Mac). On iOS, the "shared preference domain" was never shared since it was written into our own container. The shared application group does allow us to share between applications from the same developer. If we write to an app domain that is the same as a group container identifier, NSUserDefaults will write to the group container.
 */

#define OSU_IDENTIFIER "com.omnigroup.OmniSoftwareUpdate"

static NSUserDefaults *OSUDefaults = nil;


// Define this as a constructor so that we get assertion failures immediately if something about our entitlements has gone wrong rather than at some point in the future at our next scheduled check.
static void _OSUSettingInitialize(void) __attribute__((constructor));
static void _OSUSettingInitialize(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @autoreleasepool { // Constructors are called outside of any autorelease pool
            
            // We have no good way of checking these entitlements on iOS, but still need them.
#if (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE) && defined(OMNI_ASSERTIONS_ON)
            // OmniGroupCrashCatcher links OmniSoftwareUpdate and inherits the containing app's sandbox settings. But, the signing entitlements we get back in this case don't list the parent entitlements. The parent app launching should have checked this (though I suppose it could be crashing since it didn't have the entitlement).
            if ([[NSProcessInfo processInfo] isSandboxed] && ![[[NSProcessInfo processInfo] processName] isEqual:@"OmniGroupCrashCatcher"]) {
                NSDictionary *entitlements = [[NSProcessInfo processInfo] codeSigningEntitlements];
                id value = [entitlements objectForKey:@"com.apple.security.temporary-exception.shared-preference.read-only"];
                if (value == nil)
                    value = [NSArray array];
                NSArray *preferenceDomains = [value isKindOfClass:[NSArray class]] ? value : [NSArray arrayWithObject:value];
                assert([preferenceDomains containsObject:@OSU_IDENTIFIER]);
            }
#endif
            
            NSString *containerIdentifier = [[NSFileManager defaultManager] groupContainerIdentifierForBaseIdentifier:@OSU_IDENTIFIER];
            OSUDefaults = [[NSUserDefaults alloc] initWithSuiteName:containerIdentifier];
        };
    });
}

id OSUSettingGetValueForKey(NSString *key)
{
    OBPRECONDITION(key);

    _OSUSettingInitialize();
    
    // If we are sanboxed, this should read from the group container, not directly from ~/Library/Preferences. If we aren't sandboxed, the two paths should be equivalent so we'll read the old cached values.
    id value = [OSUDefaults objectForKey:key];
    if (value) {
        return value;
    }
    
    // Might be a value in the old preferences domain; try reading that. If there is something there, immediately push it to the shared container (in case we later need to remove the preferences use entirely).
    value = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)key, CFSTR(OSU_IDENTIFIER)));
    if (value) {
        OSUSettingSetValueForKey(key, value);
    }
    
    return value;
}

void OSUSettingSetValueForKey(NSString *key, id value)
{
    OBPRECONDITION(key);
    
    if (!value) {
        OBASSERT_NOT_REACHED("If we allow nil values to mean 'remove this key', then we need to write a NSNull so that we don't start falling back to whatever was in the preferences domain.");
        return;
    }
    
    _OSUSettingInitialize();

    [OSUDefaults setObject:value forKey:key];
}
