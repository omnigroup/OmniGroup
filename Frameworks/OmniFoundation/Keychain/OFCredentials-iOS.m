// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCredentials.h>

#import "OFCredentials-Internal.h"

#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSRegularExpression-OFExtensions.h>
#import <OmniFoundation/NSData-OFSignature.h>
#import <OmniFoundation/NSData-OFEncoding.h>
#import <OmniFoundation/OFPreference.h>
#import <Foundation/NSURLCredential.h>
#import <Foundation/NSRegularExpression.h>

RCS_ID("$Id$")

// If a bad keychain entry is added (mistyped your password, or whatever) it can get cached and the NSURLRequest system will look it up and stall we can't replace it with NSURLCredentialStorage as far as we can tell.
// Instead, we'll store a service-based SecItem directly and return a per-session credential here (which they can't store).

static const UInt8 kKeychainIdentifier[] = "com.omnigroup.frameworks.OmniFoundation.OFCredentials";

static NSMutableDictionary *BasicQuery(void)
{
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [NSData dataWithBytes:kKeychainIdentifier length:strlen((const char *)kKeychainIdentifier)], kSecAttrGeneric, // look for our specific item
            kSecClassGenericPassword, kSecClass, // which is a generic item
            nil];
}

#if DEBUG_CREDENTIALS_DEFINED
static void OFLogMatchingCredentials(NSDictionary *query)
{
    // Some callers cannot add this to their query (see OFDeleteCredentialsForServiceIdentifier).
    NSMutableDictionary *searchQuery = [[query mutableCopy] autorelease];
    [searchQuery setObject:@(INT_MAX - 1) forKey:(id)kSecMatchLimit];
    
    // If neither kSecReturnAttributes nor kSecReturnData is set, the underlying SecItemCopyMatching() will return no results (since you didn't ask for anything).
    [searchQuery setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];
    
    NSLog(@"searching with %@", searchQuery);
    
    NSArray *items = nil;
    OSStatus err = SecItemCopyMatching((CFDictionaryRef)searchQuery, (CFTypeRef *)&items);
    if (err == noErr) {
        for (NSDictionary *item in items)
            NSLog(@"item = %@", item);
    } else if (err == errSecItemNotFound) {
        NSLog(@"No credentials found");
    } else
        OFLogSecError("SecItemCopyMatching", err);
    
    if (items)
        CFRelease(items);
}

static void OFLogAllCredentials(void)
{    
    OFLogMatchingCredentials(BasicQuery());
}
#endif

NSURLCredential *OFReadCredentialsForServiceIdentifier(NSString *serviceIdentifier)
{    
    OBPRECONDITION(![NSString isEmptyString:serviceIdentifier]);

    DEBUG_CREDENTIALS(@"read credentials for service identifier %@", serviceIdentifier);
    
    NSMutableDictionary *query = BasicQuery();
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [query setObject:(id)kSecMatchLimitAll forKey:(id)kSecMatchLimit]; // all results
#else
    [query setObject:@10000 forKey:(id)kSecMatchLimit]; // kSecMatchLimitAll, though documented to work, returnes errSecParam on the Mac.
#endif
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes]; // return the attributes previously set
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData]; // and the payload data
    [query setObject:serviceIdentifier forKey:(id)kSecAttrService]; // look for just our service
    
    DEBUG_CREDENTIALS(@"  using query %@", query);

    NSArray *items = nil;
    OSStatus err = SecItemCopyMatching((CFDictionaryRef)query, (CFTypeRef *)&items);
    if (err == noErr) {
        for (NSDictionary *item in items) {
            NSString *service = [item objectForKey:(id)kSecAttrService];
            NSString *expectedService = serviceIdentifier;
            
            if (OFNOTEQUAL(service, expectedService)) {
                DEBUG_CREDENTIALS(@"expected service %@, but got %@", expectedService, service);
                OBASSERT_NOT_REACHED("Item with incorrect service identifier returned");
                continue;
            }

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
            
            NSURLCredential *result = _OFCredentialFromUserAndPassword(user, password);
            DEBUG_CREDENTIALS(@"trying %@",  result);
            CFRelease(items);
            return result;
        }
        
    } else if (err != errSecItemNotFound) {
        OFLogSecError("SecItemCopyMatching", err);
    }
    if (items)
        CFRelease(items);
    
    return nil;
}

static const UInt8 legacyKeychainIdentifier[] = "com.omnigroup.frameworks.OmniUI";

static NSMutableDictionary *BasicLegacyQuery(void)
{
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [NSData dataWithBytes:legacyKeychainIdentifier length:strlen((const char *)legacyKeychainIdentifier)], kSecAttrGeneric, // look for our specific item
            kSecClassGenericPassword, kSecClass, // which is a generic item
            nil];
}

NSURLCredential *OFReadCredentialsForLegacyHostPattern(NSString *hostPattern, NSString *username)
{
    OBPRECONDITION(![NSString isEmptyString:hostPattern]);

    DEBUG_CREDENTIALS(@"read legacy credentials for host pattern /%@/ with user '%@'", hostPattern, username);

    NSError *expressionError;
    NSRegularExpression *hostExpression = [[[NSRegularExpression alloc] initWithPattern:hostPattern options:NSRegularExpressionAnchorsMatchLines error:&expressionError] autorelease];
    if (hostExpression == nil) {
        [expressionError log:@"Error creating host expression from pattern \"%@\"", hostPattern];
        return nil;
    }
    
    NSMutableDictionary *query = BasicLegacyQuery();
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [query setObject:(id)kSecMatchLimitAll forKey:(id)kSecMatchLimit]; // all results
#else
    [query setObject:@10000 forKey:(id)kSecMatchLimit]; // kSecMatchLimitAll, though documented to work, returnes errSecParam on the Mac.
#endif
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes]; // return the attributes previously set
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData]; // and the payload data
    
    DEBUG_CREDENTIALS(@"  using query %@", query);

    NSArray *items = nil;
    OSStatus err = SecItemCopyMatching((CFDictionaryRef)query, (CFTypeRef *)&items);
    if (err == noErr) {
        for (NSDictionary *item in items) {
            NSString *service = [item objectForKey:(id)kSecAttrService];
            // We used to store credentials using [NSString stringWithFormat:@"%@/%@", [protectionSpace host], [protectionSpace realm]].  When converting legacy accounts we no longer have those details, so we're looking for anything matching our legacy host pattern.
            
            if (![hostExpression hasMatchInString:service])
                continue;

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

            if (OFNOTEQUAL(user, username))
                continue; // This isn't the user we're looking for

            NSString *password = [[[NSString alloc] initWithData:[item objectForKey:(id)kSecValueData] encoding:NSUTF8StringEncoding] autorelease];
            
            NSURLCredential *result = _OFCredentialFromUserAndPassword(user, password);
            DEBUG_CREDENTIALS(@"trying %@",  result);
            CFRelease(items);
            return result;
        }
        
    } else if (err != errSecItemNotFound) {
        OFLogSecError("SecItemCopyMatching", err);
    }
    if (items)
        CFRelease(items);
    
    return nil;
}

void OFWriteCredentialsForServiceIdentifier(NSString *serviceIdentifier, NSString *userName, NSString *password)
{
    OBPRECONDITION(![NSString isEmptyString:serviceIdentifier]);
    OBPRECONDITION(![NSString isEmptyString:userName]);
    OBPRECONDITION(![NSString isEmptyString:password]);

    DEBUG_CREDENTIALS(@"writing credentials for userName:%@ password:%@ serviceIdentifier:%@", userName, password, serviceIdentifier);
    
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    [entry setObject:[NSData dataWithBytes:kKeychainIdentifier length:strlen((const char *)kKeychainIdentifier)] forKey:(id)kSecAttrGeneric]; // set our specific item
    [entry setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass]; // which is a generic item
    [entry setObject:userName forKey:(id)kSecAttrAccount]; // the user name and password we collected
    [entry setObject:[password dataUsingEncoding:NSUTF8StringEncoding] forKey:(id)kSecValueData];
    [entry setObject:serviceIdentifier forKey:(id)kSecAttrService];
    
    // TODO: Possibly apply kSecAttrAccessibleAfterFirstUnlock, or let the caller specify whether it should be applied. Need this if we are going to be able to access the item for background operations in iOS.
    
    DEBUG_CREDENTIALS(@"adding item: %@", entry);
    OSStatus err = SecItemAdd((CFDictionaryRef)entry, NULL);
    if (err != noErr) {
        if (err != errSecDuplicateItem) {
            OFLogSecError("SecItemAdd", err);
            return;
        }

        // Split the entry into a query and attributes to update.
        NSMutableDictionary *query = [[entry mutableCopy] autorelease];
        [query removeObjectForKey:kSecAttrAccount];
        [query removeObjectForKey:kSecValueData];
        
        NSDictionary *attributes = @{(id)kSecAttrAccount:entry[(id)kSecAttrAccount], (id)kSecValueData:entry[(id)kSecValueData]};
        
        err = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)attributes);
        if (err != noErr) {
            OFLogSecError("SecItemUpdate", err);
        }
    }
}

void OFDeleteAllCredentials(void)
{
    DEBUG_CREDENTIALS(@"delete all credentials");

    NSMutableDictionary *query = BasicQuery();
    OSStatus err = SecItemDelete((CFDictionaryRef)query);
    if (err != noErr && err != errSecItemNotFound)
        OFLogSecError("SecItemDelete", err);
}

void OFDeleteCredentialsForServiceIdentifier(NSString *serviceIdentifier)
{
    OBPRECONDITION(![NSString isEmptyString:serviceIdentifier]);
    
    DEBUG_CREDENTIALS(@"delete credentials for protection space %@", serviceIdentifier);
    
    NSMutableDictionary *query = BasicQuery();
    [query setObject:serviceIdentifier forKey:(id)kSecAttrService];

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // If neither kSecReturnAttributes nor kSecReturnData is set, the underlying SecItemCopyMatching() will return no results (since you didn't ask for anything).
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes]; // return the attributes previously set
#else
    // But on the Mac, if we specify kSecReturnAttributes, nothing gets deleted. Awesome.
#endif
    
    // We cannot pass kSecMatchLimit to SecItemDelete(). Inexplicably it causes errSecParam to be returned.
    //[query setObject:@10000 forKey:(id)kSecMatchLimit];

    DEBUG_CREDENTIALS(@"  using query %@", query);
#if DEBUG_CREDENTIALS_DEFINED
    DEBUG_CREDENTIALS(@"  before (matching)...");
    OFLogMatchingCredentials(query);
    DEBUG_CREDENTIALS(@"  before (all)...");
    OFLogAllCredentials();
#endif
    
    OSStatus err = SecItemDelete((CFDictionaryRef)query);
    if (err != noErr && err != errSecItemNotFound)
        OFLogSecError("SecItemDelete", err);
    
#if DEBUG_CREDENTIALS_DEFINED
    DEBUG_CREDENTIALS(@"  after (matching)...");
    OFLogMatchingCredentials(query);
    DEBUG_CREDENTIALS(@"  after (all)...");
    OFLogAllCredentials();
#endif
    
    OBASSERT(OFReadCredentialsForServiceIdentifier(serviceIdentifier) == nil);
    
    OBFinishPortingLater("Store trusted certificates for the same service identifier so we can remove them here");
#if 0
    // TODO: This could be more targetted. Might have multiple accounts on the same host.
    NSString *host = protectionSpace.host;
    if (OFIsTrustedHost(host)) {
        OFRemoveTrustedHost(host);
    }
#endif
}

static void _OFAccessCertificateTrustExceptions(void (^accessor)(NSMutableDictionary *, OFPreference *))
{
    static NSMutableDictionary *trustExceptions;
    static OFPreference *trustExceptionPreference;
    static dispatch_once_t onceToken;
    static dispatch_queue_t accessQueue;
    dispatch_once(&onceToken, ^{
        accessQueue = dispatch_queue_create("com.omnigroup.OmniFoundation.OFCredentials.CertifcateTrustExceptions", DISPATCH_QUEUE_SERIAL);

        trustExceptionPreference = [OFPreference preferenceForKey:@"OFCertificateTrustExceptions"];
        trustExceptions = [[NSMutableDictionary alloc] init];
    });
    
    dispatch_sync(accessQueue, ^{
        accessor(trustExceptions, trustExceptionPreference);
    });
}

static NSString *_OFTrustExceptionKeyForChallenge(NSURLAuthenticationChallenge *challenge)
{
    NSData *certificateData = _OFDataForLeafCertificateInChallenge(challenge);
    if (!certificateData) {
        OBASSERT_NOT_REACHED("Should not have even been called");
        return nil;
    }
    return [[certificateData sha1Signature] unadornedLowercaseHexString];
}

void OFAddTrustForChallenge(NSURLAuthenticationChallenge *challenge, OFCertificateTrustDuration duration)
{
    NSString *trustExceptionKey = _OFTrustExceptionKeyForChallenge(challenge);
    if (!trustExceptionKey)
        return;
    
    SecTrustRef trust = _OFTrustForChallenge(challenge);
    if (!trust) {
        OBASSERT_NOT_REACHED("Should have stopped before this.");
        return;
    }
    NSData *exceptionData = CFBridgingRelease(SecTrustCopyExceptions(trust));
    if (!exceptionData) {
        OBASSERT_NOT_REACHED("Unrecoverable trust failure?");
        return;
    }
    
    _OFAccessCertificateTrustExceptions(^(NSMutableDictionary *trustExceptions, OFPreference *trustExceptionsPreference){
        // Overwrite the session information always in case we had a previous trust exception stored there with only per-session storage.
        trustExceptions[trustExceptionKey] = exceptionData;
        
        if (duration == OFCertificateTrustDurationAlways) {
            NSMutableDictionary *exceptions = [NSMutableDictionary dictionaryWithDictionary:[trustExceptionsPreference dictionaryValue]];
            exceptions[trustExceptionKey] = exceptionData;
            [trustExceptionsPreference setDictionaryValue:exceptions]; // Will auto synchronize
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:OFCertificateTrustUpdatedNotification object:nil];
        });
    });
}

BOOL OFHasTrustForChallenge(NSURLAuthenticationChallenge *challenge)
{
    NSString *trustExceptionKey = _OFTrustExceptionKeyForChallenge(challenge);
    if (!trustExceptionKey)
        return NO;

    __block NSData *exceptionData;
    
    _OFAccessCertificateTrustExceptions(^(NSMutableDictionary *trustExceptions, OFPreference *trustExceptionsPreference){
        exceptionData = trustExceptions[trustExceptionKey];
        
        if (!exceptionData) {
            exceptionData = [trustExceptionsPreference dictionaryValue][trustExceptionKey];
            if (exceptionData && ![exceptionData isKindOfClass:[NSData class]]) {
                NSLog(@"Ignoring unexpected value of class %@ in trust exceptions", [exceptionData class]);
            }
        }
    });

    if (exceptionData == nil)
        return NO;
    
    // The exception might not solve the challenge problem we are hitting right now. For example, we might have OK'd an expiring certificate from foo.com, but if bar.com vends that certificate to us we don't want to automatically allow it.
    SecTrustRef trust = _OFTrustForChallenge(challenge);
    if (!trust) {
        OBASSERT_NOT_REACHED("Should have stopped before this.");
        return NO;
    }
    
    if (!SecTrustSetExceptions(trust, (CFDataRef)exceptionData)) {
        OBASSERT_NOT_REACHED("SecTrustSetExceptions failed."); // Maybe if the data is corrupted somehow?
        return NO;
    }

    SecTrustResultType evaluationResult = kSecTrustResultOtherError;
    OSStatus err = SecTrustEvaluate(trust, &evaluationResult); // NB: May block for long periods (eg OCSP verification, etc)
    if (err == noErr && evaluationResult == kSecTrustResultProceed)
        return YES;
    NSLog(@"err:%ld, evaluationResult:%ld", err, evaluationResult);
    return NO;
}
