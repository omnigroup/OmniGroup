// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIChangePreferencesActionSheet.h>

#import <OmniFoundation/OFMultiValueDictionary.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$")

@interface OUIChangePreferencesActionSheetDelegate : NSObject <UIActionSheetDelegate>
{
@private
    NSURL *_url;
}

- (id)initWithURL:(NSURL *)url;

@end

@implementation OUIChangePreferencesActionSheet

- (id)initWithChangePreferenceURL:(NSURL *)url;
{
    // Ask the user if they really want to load these preferences.  Anyone on the web could build one of these URLS
    NSString *commandDescription = [url query];
    NSString *titleFormat = NSLocalizedStringFromTableInBundle(@"You have tapped on a link which will change the following preferences:\n\n\"%@\"\n\nDo you wish to accept these changes?", @"OmniUI", OMNI_BUNDLE, @"alert message");
    NSString *title = [NSString stringWithFormat:titleFormat, commandDescription];

    OUIChangePreferencesActionSheetDelegate *delegate = [[[OUIChangePreferencesActionSheetDelegate alloc] initWithURL:url] autorelease]; // retained; releases self in button press
    objc_msgSend(delegate, @selector(retain));
    return [self initWithTitle:title delegate:delegate cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title") destructiveButtonTitle:nil otherButtonTitles:NSLocalizedStringFromTableInBundle(@"Accept", @"OmniUI", OMNI_BUNDLE, @"alert button title"), nil];
}

@end

@implementation OUIChangePreferencesActionSheetDelegate

- (id)initWithURL:(NSURL *)url;
{
    if (!(self = [super init]))
        return nil;
    _url = [url copy];
    return self;
}

- (void)dealloc;
{
    [_url release];
    [super dealloc];
}

- (void)actionSheet:(UIActionSheet *)actionSheet willDismissWithButtonIndex:(NSInteger)buttonIndex;
{
    // We're left retained by our caller
    [self autorelease];
    
    BOOL cancelled = (buttonIndex != 0);
    
    if (cancelled)
        return;

    OFMultiValueDictionary *parameters = [[_url query] parametersFromQueryString];
    NSLog(@"Changing preferences for URL <%@>: parameters=%@", [_url absoluteString], parameters);
    OFPreferenceWrapper *preferences = [OFPreferenceWrapper sharedPreferenceWrapper];
    for (NSString *key in [parameters allKeys]) {
        id defaultValue = [[preferences preferenceForKey:key] defaultObjectValue];
        id oldValue = [preferences valueForKey:key];
        NSString *stringValue = [parameters lastObjectForKey:key];
        if ([stringValue isNull])
            stringValue = nil;

        id coercedValue = [OFPreference coerceStringValue:stringValue toTypeOfPropertyListValue:defaultValue];
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
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Preference changed", @"OmniUI", OMNI_BUNDLE, @"alert title") message:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Changed the '%@' preference from '%@' to '%@'", @"OmniUI", OMNI_BUNDLE, @"alert message"), key, oldValue, updatedValue] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease];
        [alert show];
    }
}

@end
