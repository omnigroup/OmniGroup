// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISpecialURLActionSheet.h>

#import <OmniFoundation/OFMultiValueDictionary.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$")

#if 0 && defined(DEBUG)
#define DEBUG_PREFERENCES(format, ...) NSLog(@"PREF: " format, ## __VA_ARGS__)
#else
#define DEBUG_PREFERENCES(format, ...)
#endif

@interface OUISpecialURLActionSheetDelegate : NSObject <UIActionSheetDelegate>
{
    NSURL *_url;
    OUISpecialURLHandler _handler;
}

- (id)initWithURL:(NSURL *)url handler:(OUISpecialURLHandler)urlHandler;

@end

OUISpecialURLHandler OUIChangePreferenceURLHandler = ^(NSURL *url) {
    OFMultiValueDictionary *parameters = [[url query] parametersFromQueryString];
    NSLog(@"Changing preferences for URL <%@>: parameters=%@", [url absoluteString], parameters);
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
            return NO;
        } else if ([coercedValue isNull]) {
            // Reset this preference
            [preferences removeObjectForKey:key];
        } else {
            // Set this preference
            [preferences setObject:coercedValue forKey:key];
        }
        id updatedValue = [preferences valueForKey:key];
        NSLog(@"... %@: %@ (%@) -> %@ (%@)", key, oldValue, [oldValue class], updatedValue, [updatedValue class]);
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Preference changed", @"OmniUI", OMNI_BUNDLE, @"alert title") message:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Changed the '%@' preference from '%@' to '%@'", @"OmniUI", OMNI_BUNDLE, @"alert message"), key, oldValue, updatedValue] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease];
        [alert show];
    }
    return YES;
};

@implementation OUISpecialURLActionSheet

- (id)initWithURL:(NSURL *)url titleFormat:(NSString *)titleFormat handler:(OUISpecialURLHandler)urlHandler;
{
    // Ask the user if they really want to run this command.  Anyone on the web could build one of these URLs.
    NSString *commandDescription = [url query];
    NSString *title = [NSString stringWithFormat:titleFormat, commandDescription];
    
    OUISpecialURLActionSheetDelegate *delegate = [[[OUISpecialURLActionSheetDelegate alloc] initWithURL:url handler:urlHandler] autorelease]; // retained; releases self in button press
    objc_msgSend(delegate, @selector(retain));
    return [self initWithTitle:title delegate:delegate cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title") destructiveButtonTitle:nil otherButtonTitles:NSLocalizedStringFromTableInBundle(@"Accept", @"OmniUI", OMNI_BUNDLE, @"alert button title"), nil];
}

@end

@implementation OUISpecialURLActionSheetDelegate

- (id)initWithURL:(NSURL *)url handler:(OUISpecialURLHandler)urlHandler;
{
    if (!(self = [super init]))
        return nil;
    _url = [url copy];
    _handler = [urlHandler copy];
    return self;
}

- (void)dealloc;
{
    [_url release];
    [_handler release];
    [super dealloc];
}

- (void)actionSheet:(UIActionSheet *)actionSheet willDismissWithButtonIndex:(NSInteger)buttonIndex;
{
    // NOTE: This simple approach works fine for current needs, but we may want to move to something more robust like OmniFocus's DebugURLAlert.m, which handles parsing of arguments and turning them into selectors.
    
    // We're left retained by our caller
    [self autorelease];
    
    BOOL cancelled = (buttonIndex != 0);
    
    if (cancelled)
        return;

    BOOL handled = _handler(_url);
        
    if (!handled) {
        NSString *title = NSLocalizedStringFromTableInBundle(@"Could not perform command", @"OmniUI", OMNI_BUNDLE, @"setting failure alert title");
        
        NSString *commandDescription = [_url query];
        NSString *messageFormat = NSLocalizedStringFromTableInBundle(@"“%@”\nwas not successful", @"OmniUI", OMNI_BUNDLE, @"setting failure alert message");
        NSString *message = [NSString stringWithFormat:messageFormat, commandDescription];
        
        NSString *okButtonLabel = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"OK button label");
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:okButtonLabel otherButtonTitles:nil] autorelease];
        [alert show];
    }
}

@end
