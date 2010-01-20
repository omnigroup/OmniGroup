// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSDAVFileManager-Reachability.h"

#import <SystemConfiguration/SCNetworkReachability.h>

RCS_ID("$Id$");

@implementation OFSDAVFileManager (Reachability)

#if 0
static void networkInterfaceWatcherCallback(SCDynamicStoreRef store, CFArrayRef keys, void *info)
{
#ifdef DEBUG
    NSLog(@"Network configuration has changed");
#endif
}
#endif

+ (BOOL)_checkReachability;
{
#if 0
    do {
        NSArray *watchedRegexps = [NSArray arrayWithObject:@"State:/Network/Global/.*"];
        SCDynamicStoreRef store; // our connection to the system configuration daemon
        SCDynamicStoreContext callbackContext;
        CFRunLoopSourceRef loopSource;

        // We don't do any retain/release stuff here since we will always deallocate the dynamic store connection before we deallocate ourselves.
        memset(&callbackContext, 0, sizeof(callbackContext));
        callbackContext.version = 0;
        callbackContext.info = self;
        callbackContext.retain = NULL;
        callbackContext.release = NULL;
        callbackContext.copyDescription = NULL;

        NSLog(@"%s:%d", __FILE__, __LINE__);
        store = SCDynamicStoreCreate(NULL, CFSTR("OFSDAVFileManager"), networkInterfaceWatcherCallback, &callbackContext);
        if (!store) {
            NSLog(@"SCDynamicStoreCreate -> NULL");
            break;
        }
        
        NSLog(@"%s:%d", __FILE__, __LINE__);
        if (!SCDynamicStoreSetNotificationKeys(store, NULL, (CFArrayRef)watchedRegexps)) {
            NSLog(@"SCDynamicStoreSetNotificationKeys failed");
            break;
        }
        
        
        NSLog(@"%s:%d", __FILE__, __LINE__);
        if (!(loopSource = SCDynamicStoreCreateRunLoopSource(NULL, store, 0))) {
            NSLog(@"SCDynamicStoreCreateRunLoopSource failed");
            break;
        }
        
        NSLog(@"%s:%d", __FILE__, __LINE__);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), loopSource, kCFRunLoopCommonModes);

    
        NSLog(@"%s:%d", __FILE__, __LINE__);
        CFArrayRef keys = SCDynamicStoreCopyKeyList(store, CFSTR(".*"));
        if (!keys) {
            NSLog(@"SCDynamicStoreCopyKeyList failed");
        } else {
            NSLog(@"keys = %@", keys);
        }
        
#if 1
#define SCKey_GlobalIPv4State CFSTR("State:/Network/Global/IPv4")
#define SCKey_GlobalIPv4State_hasUsefulRoute CFSTR("Router")
        CFDictionaryRef ipv4state = SCDynamicStoreCopyValue(store, SCKey_GlobalIPv4State);
        if (!ipv4state) {
            NSLog(@"SCDynamicStoreCopyValue failed");
            // Dude, we don't have any knowledge of IPv4 at all!
            // (This normally indicates a machine with no network interfaces, eg. a laptop, or a desktop machine that is not plugged in / dialed up / talking to an AirtPort / whatever)
            return NO;
        } else {
            BOOL reachable;
            // TODO: Check whether ipv4state is, in fact, a CFDictionary?
            NSLog(@"ipv4state = %@", ipv4state);
            if (!CFDictionaryContainsKey(ipv4state, SCKey_GlobalIPv4State_hasUsefulRoute))
                reachable = NO;  // We have some ipv4 state, but it doesn't look useful
            else
                reachable = YES;  // Might as well give it a try.
            
            // TODO: Should we furthermore try to call SCNetworkCheckReachabilityByName() if we have a router? (Probably not: even if everything is working, it might take a while for that call to return, and we don't want to hang the app for the duration. The fetcher tool can call that.)
            
            CFRelease(ipv4state);
            return reachable;
        }
#endif
    } while (0);

    if (0) {
        CFStringRef serviceID = NULL;
        CFDictionaryRef userOptions = NULL;
        if (SCNetworkConnectionCopyUserPreferences(NULL /*selectionOptions*/, & serviceID, &userOptions)) {
            NSLog(@"serviceID = %@", serviceID);
            NSLog(@"userOptions = %@", userOptions);
        } else {
            NSLog(@"SCNetworkConnectionCopyUserPreferences failed");
        }
        
        NSArray *interfaces = (NSArray *)SCNetworkInterfaceCopyAll();
        NSLog(@"interfaces = %@", interfaces);
        
        id interface = [interfaces lastObject];
        if (interface) {
            
        }
    }
#endif
    return NO;
}

@end
