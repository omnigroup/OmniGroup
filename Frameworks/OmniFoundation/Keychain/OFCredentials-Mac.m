// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCredentials.h>

#import "OFCredentials-Internal.h"

RCS_ID("$Id$")

/*
 The Keychain Services support seems to be not terribly thread-friendly in OS X 10.8.x (at least).
 
 Others have hit this, including Chrome http://git.chromium.org/gitweb/?p=chromium/src/crypto.git;a=commitdiff;h=7f4b27b842b57c531ed0348d3951176ab9fc6438
 
 We could add our own Big Damn Lock, but that would leave us open to other code using Keychain w/o using our lock. Alternatively, we can dispatch to the main queue (assuming other Keychain-using code is also running on the main queue). In this case, we need to avoid having the main queue block waiting for a NSURLConnection (which would be a horrible thing to do anyway).
 
 */

static inline void main_sync(void (^block)(void))
{
    dispatch_queue_t mainQueue = dispatch_get_main_queue();
    if (dispatch_get_current_queue() == mainQueue)
        block(); // else we'll deadlock since dispatch_sync doesn't check for this
    else
        dispatch_sync(mainQueue, block);
}

NSURLCredential *OFReadCredentialsForServiceIdentifier(NSString *serviceIdentifier)
{
    OBPRECONDITION(![NSString isEmptyString:serviceIdentifier]);
    
    DEBUG_CREDENTIALS(@"read credentials for service identifier %@", serviceIdentifier);

    __block NSURLCredential *result = nil;
    
    main_sync(^{
        SecKeychainRef keychain = NULL; // default keychain
        
        NSData *serviceIdentifierData = [serviceIdentifier dataUsingEncoding:NSUTF8StringEncoding];
        
        SecKeychainItemRef itemRef = NULL;
        OSStatus err = SecKeychainFindGenericPassword(keychain,
                                                      (UInt32)[serviceIdentifierData length], [serviceIdentifierData bytes],
                                                      0, NULL, // username length and bytes -- we don't care
                                                      0, NULL, // password length and bytes -- we'll get these via SecKeychainItemCopyAttributesAndData()
                                                      &itemRef);
        if (err != noErr) {
            if (err != errSecItemNotFound)
                OFLogSecError("SecKeychainFindGenericPassword", err);
            DEBUG_CREDENTIALS(@"  returning nil credentials");
            return;
        }
        
        UInt32 passwordLength = 0;
        void *passwordBytes = NULL;
        
        UInt32 attributeTags[1] = {kSecAccountItemAttr};
        UInt32 attributeFormats[1] = {CSSM_DB_ATTRIBUTE_FORMAT_STRING};
        SecKeychainAttributeInfo attributeInfo = {
            .count = 1,
            .tag = attributeTags,
            .format = attributeFormats
        };
        SecKeychainAttributeList *attributes = NULL;
        err = SecKeychainItemCopyAttributesAndData(itemRef, &attributeInfo, NULL/*itemClass*/, &attributes, &passwordLength, &passwordBytes);
        
        if (err != noErr) {
            OFLogSecError("SecKeychainFindGenericPassword", err);
            CFRelease(itemRef);
            DEBUG_CREDENTIALS(@"  returning nil credentials");
            return;
        }
        
        OBASSERT(attributes->count == 1);
        OBASSERT(attributes->attr[0].tag == kSecAccountItemAttr);
        NSString *userName = [[[NSString alloc] initWithBytes:attributes->attr[0].data length:attributes->attr[0].length encoding:NSUTF8StringEncoding] autorelease];
        NSString *password = [[[NSString alloc] initWithBytes:passwordBytes length:passwordLength encoding:NSUTF8StringEncoding] autorelease];
        
        SecKeychainItemFreeAttributesAndData(attributes, passwordBytes);
        CFRelease(itemRef);
    
        result = [_OFCredentialFromUserAndPassword(userName, password) retain];
    });
    
    DEBUG_CREDENTIALS(@"  trying %@",  result);
    return [result autorelease];
}

void OFWriteCredentialsForServiceIdentifier(NSString *serviceIdentifier, NSString *userName, NSString *password)
{
    OBPRECONDITION(![NSString isEmptyString:serviceIdentifier]);
    OBPRECONDITION(![NSString isEmptyString:userName]);
    OBPRECONDITION(![NSString isEmptyString:password]);

    DEBUG_CREDENTIALS(@"writing credentials for userName:%@ password:%@ serviceIdentifier:%@", userName, password, serviceIdentifier);

    main_sync(^{
        SecKeychainRef keychain = NULL; // default keychain
        
        NSData *userNameData = [userName dataUsingEncoding:NSUTF8StringEncoding];
        NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
        NSData *serviceIdentifierData = [serviceIdentifier dataUsingEncoding:NSUTF8StringEncoding];
        
        SecKeychainItemRef itemRef = NULL;
        OSStatus err = SecKeychainFindGenericPassword(keychain,
                                                      (UInt32)[serviceIdentifierData length], [serviceIdentifierData bytes],
                                                      0, NULL, // username length and bytes -- we don't care
                                                      NULL, NULL, // password length and data
                                                      &itemRef);
        if (err == noErr) {
            err = SecKeychainItemModifyAttributesAndData(itemRef, NULL/*attributes*/,
                                                         (UInt32)[passwordData length], [passwordData bytes]);
            if (err != noErr)
                OFLogSecError("SecKeychainItemModifyAttributesAndData", err);
            CFRelease(itemRef);
        } else if (err == errSecItemNotFound) {
            // Add a new entry.
            OSStatus err = SecKeychainAddGenericPassword(keychain,
                                                         (UInt32)[serviceIdentifierData length], [serviceIdentifierData bytes],
                                                         (UInt32)[userNameData length], [userNameData bytes],
                                                         (UInt32)[passwordData length], [passwordData bytes],
                                                         NULL/*outItemRef*/);
            if (err != noErr)
                OFLogSecError("SecKeychainAddGenericPassword", err);
        } else
            OFLogSecError("SecKeychainFindGenericPassword", err);
    });
}

void OFDeleteCredentialsForServiceIdentifier(NSString *serviceIdentifier)
{
    OBPRECONDITION(![NSString isEmptyString:serviceIdentifier]);

    DEBUG_CREDENTIALS(@"delete credentials for protection space %@", serviceIdentifier);

    main_sync(^{
        SecKeychainRef keychain = NULL; // default keychain
        
        NSData *serviceIdentifierData = [serviceIdentifier dataUsingEncoding:NSUTF8StringEncoding];
        
        while (YES) {
            SecKeychainItemRef itemRef = NULL;
            OSStatus err = SecKeychainFindGenericPassword(keychain,
                                                          (UInt32)[serviceIdentifierData length], [serviceIdentifierData bytes],
                                                          0, NULL, // username length and bytes -- we don't care
                                                          NULL, NULL, // password length and data
                                                          &itemRef);
            if (err != noErr) {
                if (err != errSecItemNotFound)
                    OFLogSecError("SecKeychainFindGenericPassword", err);
                return;
            }
            
            DEBUG_CREDENTIALS(@"  deleting item %@", itemRef);
            err = SecKeychainItemDelete(itemRef);
            CFRelease(itemRef);
            if (err != noErr) {
                OFLogSecError("SecKeychainItemDelete", err);
                return;
            }
        }
    });
}

static void _OFAccessTrustedCertificateDataSet(void (^accessor)(NSMutableSet *))
{
    static NSMutableSet *trustedDatas;
    static dispatch_once_t onceToken;
    static dispatch_queue_t accessQueue;
    dispatch_once(&onceToken, ^{
        trustedDatas = [[NSMutableSet alloc] init];
        accessQueue = dispatch_queue_create("com.omnigroup.OmniFoundation.OFCredentials.TrustedCertificateDataAccess", DISPATCH_QUEUE_SERIAL);
    });
    
    dispatch_sync(accessQueue, ^{
        accessor(trustedDatas);
    });
}

void OFAddTrustForChallenge(NSURLAuthenticationChallenge *challenge, OFCertificateTrustDuration duration)
{
    OBPRECONDITION(duration == OFCertificateTrustDurationSession, @"For persistent trust, use SFCertificateTrustPanel.");
    
    NSData *data = _OFDataForLeafCertificateInChallenge(challenge);
    if (!data)
        return;
    
    _OFAccessTrustedCertificateDataSet(^(NSMutableSet *trustedCertificateDatas){
        [trustedCertificateDatas addObject:data];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:OFCertificateTrustUpdatedNotification object:nil];
        });
    });
}

BOOL OFHasTrustForChallenge(NSURLAuthenticationChallenge *challenge)
{
    NSData *data = _OFDataForLeafCertificateInChallenge(challenge);
    if (!data)
        return NO;
    
    __block BOOL trusted;
    _OFAccessTrustedCertificateDataSet(^(NSMutableSet *trustedCertificateDatas){
        trusted = ([trustedCertificateDatas member:data] != nil);
    });
    
    return trusted;
}

