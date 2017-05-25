// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIChangePreferenceURLCommand.h>

#import <OmniFoundation/OFMultiValueDictionary.h>
#import <OmniFoundation/OFPreference.h>
@import OmniAppKit;

#if 0 && defined(DEBUG)
#define DEBUG_PREFERENCES(format, ...) NSLog(@"PREF: " format, ## __VA_ARGS__)
#else
#define DEBUG_PREFERENCES(format, ...)
#endif

RCS_ID("$Id$");

@implementation OUIChangePreferenceURLCommand

- (NSString *)confirmationMessage;
{
    NSString *titleFormat = NSLocalizedStringFromTableInBundle(@"You have tapped on a link which will change the following preferences:\n\n\"%@\"\n\nDo you wish to accept these changes?", @"OmniUI", OMNI_BUNDLE, @"alert message");
    return [NSString stringWithFormat:titleFormat, [self commandDescription]];
}

- (void)invoke;
{
    OFMultiValueDictionary *parameters = [[self.url query] parametersFromQueryString];
    NSLog(@"Changing preferences for URL <%@>: parameters=%@", [self.url absoluteString], parameters);
    OFPreferenceWrapper *preferences = [OFPreferenceWrapper sharedPreferenceWrapper];
    DEBUG_PREFERENCES(@"Using shared preferences object: %@", preferences);
    for (NSString *key in [parameters allKeys]) {
        DEBUG_PREFERENCES(@"Setting preference for key %@: %@", key, [preferences preferenceForKey:key]);
        id defaultValue = [[preferences preferenceForKey:key] defaultObjectValue];
        DEBUG_PREFERENCES(@"    with default value: %@", defaultValue);
        id oldValue = [preferences valueForKey:key];
        DEBUG_PREFERENCES(@"    and old value: %@", oldValue);
        NSString *stringValue = [parameters lastObjectForKey:key];
        DEBUG_PREFERENCES(@"    to string value: %@", stringValue);
        if ([stringValue isNull])
            stringValue = nil;
        
        id coercedValue = [OFPreference coerceStringValue:stringValue toTypeOfPropertyListValue:defaultValue];
        DEBUG_PREFERENCES(@"    using coerced value: %@", coercedValue);
        if (coercedValue == nil) {
            NSLog(@"Unable to update %@: failed to convert '%@' to the same type as '%@' (%@)", key, stringValue, defaultValue, [defaultValue class]);
            return;
        } else if ([coercedValue isNull]) {
            // Reset this preference
            [preferences removeObjectForKey:key];
        } else {
            // Set this preference
            [preferences setObject:coercedValue forKey:key];
        }
        id updatedValue = [preferences valueForKey:key];
        NSLog(@"... %@: %@ (%@) -> %@ (%@)", key, oldValue, [oldValue class], updatedValue, [updatedValue class]);

         UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Preference changed", @"OmniUI", OMNI_BUNDLE, @"alert title") message:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Changed the '%@' preference from '%@' to '%@'", @"OmniUI", OMNI_BUNDLE, @"alert message"), key, oldValue, updatedValue] preferredStyle:UIAlertControllerStyleAlert];

         [alertController addAction:[UIAlertAction actionWithTitle:OAOK() style:UIAlertActionStyleDefault handler:NULL]];

         [self.viewControllerForPresentation presentViewController:alertController animated:YES completion:NULL];
    }
}

@end
