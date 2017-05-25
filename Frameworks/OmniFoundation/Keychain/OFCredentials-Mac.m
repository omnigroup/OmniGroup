// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCredentials.h>

#import <Foundation/NSURLCredential.h>

#import "OFCredentials-Internal.h"

RCS_ID("$Id$")

/*
 The Keychain Services support seems to be not terribly thread-friendly in OS X 10.8.x (at least).
 
 Others have hit this, including Chrome http://git.chromium.org/gitweb/?p=chromium/src/crypto.git;a=commitdiff;h=7f4b27b842b57c531ed0348d3951176ab9fc6438
 
 We could add our own Big Damn Lock, but that would leave us open to other code using Keychain w/o using our lock. Alternatively, we can dispatch to the main queue (assuming other Keychain-using code is also running on the main queue). In this case, we need to avoid having the main queue block waiting for a NSURLConnection (which would be a horrible thing to do anyway).
 
 */

static inline void main_sync(void (^block)(void))
{
    OFMainThreadPerformBlockSynchronously(block);
}

static SecKeychainItemRef _OFKeychainItemForServiceIdentifier(NSString *serviceIdentifier, NSError **outError)
{
    NSData *serviceIdentifierData = [serviceIdentifier dataUsingEncoding:NSUTF8StringEncoding];
    
    // 22011331: SecKeychainFindGenericPassword has inconsistent/incorrect nullability annotations
    // NOTE: If you pass a non-NULL password length parameter, then you must pass a non-NULL passwordBytes pointer too since it will get written. And, then you must free it, and maybe should zero it out first, and ... So for now disabling this warning until they fix the bad annotation.
    
    SecKeychainItemRef itemRef = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    OSStatus err = SecKeychainFindGenericPassword(NULL, // default keychain search list
                                                  (UInt32)[serviceIdentifierData length], [serviceIdentifierData bytes],
                                                  0, NULL, // username length and bytes -- we don't care
                                                  NULL, NULL, // password length and bytes -- we'll get these via SecKeychainItemCopyAttributesAndData()
                                                  &itemRef);
#pragma clang diagnostic pop
    if (err != errSecSuccess) {
        if (err == errSecItemNotFound) {
            if (outError)
                *outError = [NSError errorWithDomain:OFCredentialsErrorDomain code:OFCredentialsErrorNotFound userInfo:nil];
            DEBUG_CREDENTIALS(@"  returning nil credentials -- not found");
            return NULL;
        }
        OFSecError("SecKeychainFindGenericPassword", err, outError);
        DEBUG_CREDENTIALS(@"  returning nil credentials -- error in lookup");
        return NULL;
    }
    
    return itemRef;
}

NSURLCredential *OFReadCredentialsForServiceIdentifier(NSString *serviceIdentifier, NSError **outError)
{
    DEBUG_CREDENTIALS(@"read credentials for service identifier %@", serviceIdentifier);
    
    if ([NSString isEmptyString:serviceIdentifier]) {
        if (outError)
            *outError = [NSError errorWithDomain:OFCredentialsErrorDomain code:OFCredentialsErrorNotFound userInfo:nil];
        return nil;
    }
    
    __block NSURLCredential *result = nil;
    
    main_sync(^{
        SecKeychainItemRef itemRef = _OFKeychainItemForServiceIdentifier(serviceIdentifier, outError);
        if (!itemRef)
            return;
        
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
        OSStatus err = SecKeychainItemCopyAttributesAndData(itemRef, &attributeInfo, NULL/*itemClass*/, &attributes, &passwordLength, &passwordBytes);
        
        if (err != errSecSuccess) {
            OFSecError("SecKeychainItemCopyAttributesAndData", err, outError);
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

BOOL OFWriteCredentialsForServiceIdentifier(NSString *serviceIdentifier, NSString *userName, NSString *password, NSError **outError)
{
    OBPRECONDITION(![NSString isEmptyString:serviceIdentifier]);
    OBPRECONDITION(![NSString isEmptyString:userName]);
    OBPRECONDITION(![NSString isEmptyString:password]);

    DEBUG_CREDENTIALS(@"writing credentials for userName:%@ password:%@ serviceIdentifier:%@", userName, password, serviceIdentifier);

    __block BOOL success = NO;
    
    main_sync(^{
        SecKeychainRef keychain = NULL; // default keychain
        
        NSData *userNameData = [userName dataUsingEncoding:NSUTF8StringEncoding];
        NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
        NSData *serviceIdentifierData = [serviceIdentifier dataUsingEncoding:NSUTF8StringEncoding];
        
        // 22011331: SecKeychainFindGenericPassword has inconsistent/incorrect nullability annotations
        // NOTE: If you pass a non-NULL password length parameter, then you must pass a non-NULL passwordBytes pointer too since it will get written. And, then you must free it, and maybe should zero it out first, and ... So for now disabling this warning until they fix the bad annotation.
        
        SecKeychainItemRef itemRef = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
        OSStatus err = SecKeychainFindGenericPassword(keychain,
                                                      (UInt32)[serviceIdentifierData length], [serviceIdentifierData bytes],
                                                      0, NULL, // username length and bytes -- we don't care
                                                      NULL, NULL, // password length and data
                                                      &itemRef);
#pragma clang diagnostic pop
        if (err == errSecSuccess) {
            err = SecKeychainItemModifyAttributesAndData(itemRef, NULL/*attributes*/,
                                                         (UInt32)[passwordData length], [passwordData bytes]);
            if (err != errSecSuccess)
                OFSecError("SecKeychainItemModifyAttributesAndData", err, outError);
            else
                success = YES;
            CFRelease(itemRef);
        } else if (err == errSecItemNotFound) {
            // Add a new entry.
            err = SecKeychainAddGenericPassword(keychain,
                                                (UInt32)[serviceIdentifierData length], [serviceIdentifierData bytes],
                                                (UInt32)[userNameData length], [userNameData bytes],
                                                (UInt32)[passwordData length], [passwordData bytes],
                                                NULL/*outItemRef*/);
            if (err != errSecSuccess)
                OFSecError("SecKeychainAddGenericPassword", err, outError);
            else
                success = YES;
        } else
            OFSecError("SecKeychainFindGenericPassword", err, outError);
    });
    
    return success;
}

BOOL OFDeleteCredentialsForServiceIdentifier(NSString *serviceIdentifier, NSError * __autoreleasing *outError)
{
    OBPRECONDITION(![NSString isEmptyString:serviceIdentifier]);

    DEBUG_CREDENTIALS(@"delete credentials for protection space %@", serviceIdentifier);

    __block BOOL success = NO;
    
    main_sync(^{
        SecKeychainRef keychain = NULL; // default keychain
        
        NSData *serviceIdentifierData = [serviceIdentifier dataUsingEncoding:NSUTF8StringEncoding];
        
        while (YES) {
            // 22011331: SecKeychainFindGenericPassword has inconsistent/incorrect nullability annotations
            // NOTE: If you pass a non-NULL password length parameter, then you must pass a non-NULL passwordBytes pointer too since it will get written. And, then you must free it, and maybe should zero it out first, and ... So for now disabling this warning until they fix the bad annotation.

            SecKeychainItemRef itemRef = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
            OSStatus err = SecKeychainFindGenericPassword(keychain,
                                                          (UInt32)[serviceIdentifierData length], [serviceIdentifierData bytes],
                                                          0, NULL, // username length and bytes -- we don't care
                                                          NULL, NULL, // password length and data
                                                          &itemRef);
#pragma clang diagnostic pop
            if (err == errSecItemNotFound) {
                success = YES;
                break;
            }
            if (err != errSecSuccess) {
                OFSecError("SecKeychainFindGenericPassword", err, outError);
                return;
            }
            
            DEBUG_CREDENTIALS(@"  deleting item %@", itemRef);
            err = SecKeychainItemDelete(itemRef);
            CFRelease(itemRef);
            if (err != errSecSuccess) {
                OFSecError("SecKeychainItemDelete", err, outError);
                return;
            }
        }
    });
    
    return success;
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
    return OFAddTrustExceptionForTrust(_OFTrustForChallenge(challenge), duration);
}

void OFAddTrustExceptionForTrust(CFTypeRef trust_, OFCertificateTrustDuration duration)
{
    OBPRECONDITION(duration == OFCertificateTrustDurationSession, @"For persistent trust, use SFCertificateTrustPanel.");
    
    SecTrustRef trust = (SecTrustRef)trust_;

    NSData *data = _OFDataForLeafCertificateInTrust(trust);
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
    SecTrustRef trust = _OFTrustForChallenge(challenge);
    if (!trust) {
        OBASSERT_NOT_REACHED("Should have stopped before this.");
        return NO;
    }
    
    return OFHasTrustExceptionForTrust(trust);
}

BOOL OFHasTrustExceptionForTrust(CFTypeRef trust_)
{
    SecTrustRef trust = (SecTrustRef)trust_;

    NSData *data = _OFDataForLeafCertificateInTrust(trust);
    if (!data)
        return NO;
    
    __block BOOL trusted;
    _OFAccessTrustedCertificateDataSet(^(NSMutableSet *trustedCertificateDatas){
        trusted = ([trustedCertificateDatas member:data] != nil);
    });
    
    return trusted;
}

