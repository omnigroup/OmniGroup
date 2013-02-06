// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCredentials.h>

#import <Security/Security.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <Foundation/NSURLCredential.h>
#import <Foundation/NSOperation.h>

#import "OFCredentials-Internal.h"

RCS_ID("$Id$")

void _OFLogSecError(const char *caller, const char *function, OSStatus err)
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // No SecCopyErrorMessageString on iOS, sadly.
    NSLog(@"%s: %s returned %"PRI_OSStatus"", caller, function, err);
#else
    CFStringRef errorMessage = SecCopyErrorMessageString(err, NULL/*reserved*/);
    NSLog(@"%s: %s returned \"%@\" (%"PRI_OSStatus")", caller, function, errorMessage, err);
    if (errorMessage)
        CFRelease(errorMessage);
#endif
}

NSURLCredential *_OFCredentialFromUserAndPassword(NSString *user, NSString *password)
{
    if (![NSString isEmptyString:user] && ![NSString isEmptyString:password]) {
        // We'd like to use NSURLCredentialPersistenceNone to force NSURLConnection to always ask us for credentials, but if we do then it doesn't ask us early enough to avoid a 401 on each round trip. The downside to persistent credentials is that some versions of iOS would not call our authenticaion challenge NSURLConnection delegate method when there were any cached credentials, but per-session at least will ask again on the next launch of the app.
        NSURLCredential *result = [NSURLCredential credentialWithUser:user password:password persistence:NSURLCredentialPersistenceForSession];
        return result;
    }
    
    return nil;
}

NSString *OFMakeServiceIdentifier(NSURL *originalURL, NSString *username, NSString *realm)
{
    OBPRECONDITION(originalURL);
    OBPRECONDITION(![NSString isEmptyString:username]);
    OBPRECONDITION(![NSString isEmptyString:realm]);
    
    // Normalize the URL string to not have a trailing slash.
    NSString *urlString = [originalURL absoluteString];
    if ([urlString hasSuffix:@"/"])
        urlString = [urlString stringByRemovingSuffix:@"/"];
    
    return [NSString stringWithFormat:@"%@|%@|%@", urlString, username, realm];
}

static NSString * const OFTrustedSyncHostPreference = @"OFTrustedHosts";

NSString * const OFCertificateTrustUpdatedNotification = @"OFCertificateTrustUpdatedNotification";

/*
 TODO: Use one mechanism provided by Security.framework to store certificate trust.
 
 On the Mac, we have SecTrustSettingsSetTrustSettings() and friends, but this isn't on iOS at all.
 On iOS we have SecTrustCopyExceptions() and SecTrustSetExceptions(), but these aren't available on the Mac until 10.8.
 
 We could maybe add a hybrid API here, but it would be nicer to wait until we require 10.8 and then have API built around SecTrustSetExceptions().
 
 */
static NSMutableSet *SessionTrustedHosts = nil;

BOOL OFIsTrustedHost(NSString *host)
{
    if ([SessionTrustedHosts member:host] || [[[OFPreference preferenceForKey:OFTrustedSyncHostPreference] arrayValue] containsObject:host])
        return YES;
    
    // Useful for test cases run vs local web server
    if (getenv("OFAutomaticallyTrustAllHosts"))
        return YES;
    
    return NO;
}

void OFAddTrustedHost(NSString *host, OFHostTrustDuration duration)
{
    BOOL changed = NO;
    
    switch (duration) {
        case OFHostTrustDurationSession:
            if (!SessionTrustedHosts)
                SessionTrustedHosts = [[NSMutableSet alloc] init];
            if (![SessionTrustedHosts member:host]) {
                [SessionTrustedHosts addObject:host];
                changed = YES;
            }
            break;
        case OFHostTrustDurationAlways: {
            OFPreference *pref = [OFPreference preferenceForKey:OFTrustedSyncHostPreference];
            if (![[pref arrayValue] containsObject:host]) {
                NSMutableArray *hosts = [[pref arrayValue] mutableCopy];
                if (!hosts)
                    hosts = [[NSMutableArray alloc] init];
                
                [hosts addObject:host];
                [pref setArrayValue:hosts];
                [hosts release];
                changed = YES;
            }
            break;
        }
        default:
            OBASSERT_NOT_REACHED("Unknown host trust duration");
            break;
    }
    
    if (changed) {
        [[NSUserDefaults standardUserDefaults] synchronize]; // useful for commandline tools that might exit w/o doing this.
        
        // We can get called on a background queue used by NSURLConnection.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [[NSNotificationCenter defaultCenter] postNotificationName:OFCertificateTrustUpdatedNotification object:nil];
        }];
    }
}

void OFRemoveTrustedHost(NSString *host)
{
    BOOL changed = NO;
    
    if ([SessionTrustedHosts member:host]) {
        [SessionTrustedHosts removeObject:host];
        changed = YES;
    }
    
    OFPreference *pref = [OFPreference preferenceForKey:OFTrustedSyncHostPreference];
    if ([[pref arrayValue] containsObject:host]) {
        NSMutableArray *hosts = [[pref arrayValue] mutableCopy];
        [hosts removeObject:host];
        [pref setArrayValue:hosts];
        [hosts release];
        changed = YES;
    }
    
    if (changed) {
        [[NSUserDefaults standardUserDefaults] synchronize]; // useful for commandline tools that might exit w/o doing this.
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [[NSNotificationCenter defaultCenter] postNotificationName:OFCertificateTrustUpdatedNotification object:nil];
        }];
    }
}
