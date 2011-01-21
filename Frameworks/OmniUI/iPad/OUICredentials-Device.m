// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUICredentials.h"

#import <Security/Security.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$")

#if !TARGET_IPHONE_SIMULATOR

// If a bad keychain entry is added (mistyped your password, or whatever) it can get cached and the NSURLRequest system will look it up and stall we can't replace it with NSURLCredentialStorage as far as we can tell.
// Instead, we'll store a service-based SecItem directly and return a per-session credential here (which they can't store).


static const UInt8 kKeychainIdentifier[] = "com.omnigroup.frameworks.OmniUI";
static NSString *_serviceForProtectionSpace(NSURLProtectionSpace *protectionSpace)
{
    // Adding kSecAttrServer or kSecAttrSecurityDomain results in errSecNotAvailable, presumably since only kSecClassInternetPassword has them.
    // Store the host/realm in the service so we can compare when doing the lookup and avoid passing server A's credentials to server B.
    return [NSString stringWithFormat:@"%@/%@", [protectionSpace host], [protectionSpace realm]];
}

static NSMutableDictionary *BasicQuery(void)
{
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [NSData dataWithBytes:kKeychainIdentifier length:strlen((const char *)kKeychainIdentifier)], kSecAttrGeneric, // look for our specific item
            kSecClassGenericPassword, kSecClass, // which is a generic item
            nil];
}

NSURLCredential *OUIReadCredentialsForProtectionSpace(NSURLProtectionSpace *protectionSpace)
{    
    NSMutableDictionary *query = BasicQuery();
    [query setObject:(id)kSecMatchLimitAll forKey:(id)kSecMatchLimit]; // all results
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes]; // return the attributes previously set
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData]; // and the payload data
    
    NSArray *items = nil;
    OSStatus err = SecItemCopyMatching((CFDictionaryRef)query, (CFTypeRef *)&items);
    if (err == noErr) {
        for (NSDictionary *item in items) {
            NSString *service = [item objectForKey:(id)kSecAttrService];
            NSString *expectedService = _serviceForProtectionSpace(protectionSpace);
//            NSLog(@"expected service %@", expectedService);
            
            // We only store one entry to hide it from the busted NSURLRequest goop.  But, we don't want to leak credentials to the wrong server.
            if (OFISEQUAL(service, expectedService)) {
                // We used to store a NSData for kSecAttrAccount, but it is documented to be a string. Make sure that if we get a data out we don't crash, but it likely won't work anyway.
                // When linked with a minimum OS < 4.2, this seemed to work, but under iOS 4.2+ it doesn't. At least that's the theory.
                id account = [item objectForKey:(id)kSecAttrAccount];
                NSString *user;
                if ([account isKindOfClass:[NSData class]]) {
                    user = [[[NSString alloc] initWithData:account encoding:NSUTF8StringEncoding] autorelease];
                } else if ([account isKindOfClass:[NSString class]]) {
                    user = account;
                } else {
                    user = @"";
                }
                
                NSString *password = [[[NSString alloc] initWithData:[item objectForKey:(id)kSecValueData] encoding:NSUTF8StringEncoding] autorelease];
                
                if (![NSString isEmptyString:user] && ![NSString isEmptyString:password]) {
                    NSURLCredential *result = [NSURLCredential credentialWithUser:user password:password persistence:NSURLCredentialPersistenceNone];
                    //NSLog(@"trying %@",  result);
                    CFRelease(item);
                    return result;
                }
            }
        }
        
    } else if (err != errSecItemNotFound) {
        NSLog(@"%s: SecItemCopyMatching -> %ld", __PRETTY_FUNCTION__, err);
        // fall through and try to recover by deleting all the matching entries and re-prompting.
    }
    if (items)
        CFRelease(items);
    
    return nil;
}

NSURLCredential *OUIReadCredentialsForChallenge(NSURLAuthenticationChallenge *challenge)
{
    //NSLog(@"find credentials for challenge %@, failure count = %ld", challenge, [challenge previousFailureCount]);
    
    // We only have one set of credentials.  The failure count can be 1 when we get called for the first time since the NSURLRequest system may have tried once.
    if ([challenge previousFailureCount] < 3) {
        NSURLCredential *result = OUIReadCredentialsForProtectionSpace([challenge protectionSpace]);
        if (result)
            return result;
    }
    
    // We hates it.  Too many tries or wrong server (or possibly no credentials).  Delete any entries matching our basic query (so an 'add' will work) and prompt the user.
    OUIDeleteCredentialsForProtectionSpace([challenge protectionSpace]);
    
    return nil;
}

void OUIWriteCredentialsForProtectionSpace(NSString *userName, NSString *password, NSURLProtectionSpace *protectionSpace)
{
    //NSLog(@"writing credentials for userName:%@ password:%@ protectionSpace:%@", userName, password, protectionSpace);
    
    // Do NOT store the entry in the keychain; if a bad entry gets in there, we can't get it out.
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    [entry setObject:[NSData dataWithBytes:kKeychainIdentifier length:strlen((const char *)kKeychainIdentifier)] forKey:(id)kSecAttrGeneric]; // set our specific item
    [entry setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass]; // which is a generic item
    [entry setObject:userName forKey:(id)kSecAttrAccount]; // the user name and password we collected
    [entry setObject:[password dataUsingEncoding:NSUTF8StringEncoding] forKey:(id)kSecValueData];
    [entry setObject:_serviceForProtectionSpace(protectionSpace) forKey:(id)kSecAttrService];
    
    //NSLog(@"adding item: %@", entry);
    OSErr err = SecItemAdd((CFDictionaryRef)entry, NULL);
    if (err != noErr)
        NSLog(@"%s: SecItemAdd -> %d", __PRETTY_FUNCTION__, err);
}

void OUIDeleteAllCredentials(void)
{
    NSMutableDictionary *query = BasicQuery();
    OSStatus err = SecItemDelete((CFDictionaryRef)query);
    if (err != noErr && err != errSecItemNotFound)
        NSLog(@"%s: SecItemDelete -> %ld", __PRETTY_FUNCTION__, err);
}

void OUIDeleteCredentialsForProtectionSpace(NSURLProtectionSpace *protectionSpace)
{
    NSMutableDictionary *query = BasicQuery();
    [query setObject:(id)_serviceForProtectionSpace(protectionSpace) forKey:(id)kSecAttrService];
    
    OSStatus err = SecItemDelete((CFDictionaryRef)query);
    if (err != noErr && err != errSecItemNotFound)
        NSLog(@"%s: SecItemDelete -> %ld", __PRETTY_FUNCTION__, err);
    
    if ([OFSDAVFileManager isTrustedHost:[protectionSpace host]]) {
        [OFSDAVFileManager removeTrustedHost:[protectionSpace host]];
        [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:[protectionSpace host]];
    }
}
#endif
