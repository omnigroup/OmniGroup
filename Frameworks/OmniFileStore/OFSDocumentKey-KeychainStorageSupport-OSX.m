// Copyright 2016-2017 Omni Development. Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFileStore/OFSDocumentKey-KeychainStorageSupport.h>

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSEncryptionConstants.h>

#import "OFSDocumentKey-Internal.h"
#import "OFSEncryption-Internal.h"

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#error Building OFSDocumentKey Mac Keychain support on an iOS platform
#endif

#define arraycount(a) (sizeof(a)/sizeof(a[0]))
#define CFDICT(keys, values) ({ _Static_assert(arraycount(keys) == arraycount(values), "dictionary key and value counts must be equal");  \
    CFDictionaryCreate(kCFAllocatorDefault, keys, values, arraycount(keys), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); })

/*
 Let's talk about symmetric keys.
 
 The ideal way to hang on to our OFSDocumentKey in the Keychain is to use an item of class kSecClassKey. This is what iOS does, and what early cuts at an OS X implementation did.
 
 "For a keychain item of class kSecClassKey, the primary key is the combination of kSecAttrApplicationLabel, kSecAttrApplicationTag, kSecAttrKeyType, kSecAttrKeySizeInBits, kSecAttrEffectiveKeySize, and the creator, start date and end date which are not exposed by SecItem yet." (Cribbed from StackOverflow, but this matches the contents of libsecurity_cdsa_utilities/lib/KeySchema.m4 in published Security-57337.20.44)
 
 Of these, the only ones we can really use to distinguish our keys are kSecAttrApplicationLabel and kSecAttrApplicationTag. Quoth the docs:
 
     kSecAttrApplicationLabel: "[....] This is different from the kSecAttrLabel (which is intended to be human-readable). This attribute is used to look up a key programmatically"
     kSecAttrApplicationTag: "Specifies a dictionary key whose value is a CFDataRef containing private tag data."
 
 However, on OSX, the Keychain Access app erroneously stores the user-editable "Comment" textbox contents under kSecAttrApplicationTag (RADAR 24579912; presumably it's supposed to be editing kSecAttrComment). So we can't use ApplicationTag or we'll get clobbered if the user edits that field. That leaves kSecAttrApplicationLabel – but we have a lot of trouble making a key and setting the label appropriately:
 
 * You can't add a symmetric key directly with SecItemAdd(), because Apple never bothered to implement that. (SecItemAdd() just works in terms of SecKeychainItemCreateFromContent() anyway, see below.) See RADAR 24575784
 * You can't fully create one with SecKeychainItemCreateFromContent(); this seems to just be an oversight in Schema::attributeInfo(), which is missing the attributes we need (all the key-specific attributes as well as ApplicationLabel (RADAR 24577556) and ApplicationTag (RADAR 24578456)).
 * You can't partially create one with SecKeychainItemCreateFromContent() and then add the missing attributes with SecItemUpdate or SecKeychainItemModifyContent, because the primary-key attributes you need to set in order to insert it into the keychain are not among those that SecKeychainItemCreateFromContent understands.
 * You can't create one with SecKeyCreateFromData(), then modify its attributes and *then* insert it into a keychain, because both of the attribute-modifying calls (SecItemUpdate or SecKeychainItemModifyContent) only work on items which are already inserted into the keychain (RADAR 11840882)
 * You can generate a *random* key with SecKeyGenerateSymmetric() (which also applies a random keylabel). With that reference, you can try to modify all of its attributes, including the keylabel and key data, using SecKeychainItemModifyAttributesAndData() – but despite that call succeeding, nothing seems to happen with the key's data. What's more, persisting the new random key in a keychain (by setting kSecUseKeychain, kSecAttrLabel, and kSecAttrApplicationLabel) doesn't seem to produce any visible results in Keychain Access, at least on 10.11.
 * You can't use 10.12's SecKeyCreateWithData(), since it only understands RSA and "ECSEC prime random" key types.
 
 As a result, we fall back on inserting the key into the Keychain not as kSecClassKey, but as kSecClassGenericPassword. This is suboptimal from a UX/Keychain Access perspective, but is more reliable (read: feasible) programmatically. The primary key for a generic password item is the combination of kSecAccountItemAttr and kSecServiceItemAttr (again according to Security-57337.20.44, this time in a comment in keychain_find.c).
 */

static NSString * const keychainAccountAttributeValue = @"OmniFileStore";

static inline void populateStatusError(NSError **outError, OSStatus status) {
    if (outError != NULL) {
        NSDictionary *userInfo = @{ NSUnderlyingErrorKey : [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil] };
        *outError = [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionStorageError userInfo:userInfo];
    }
}

static NSData *readFromKeychain(NSString *keyLabel, NSData *applicationLabel, NSError **outError);
static BOOL storeInKeychain(CFDataRef keymaterial, NSString *keyLabel, NSData *applicationLabel, NSString *displayName, NSError **outError);

/// Reads the current Keychain entry for the given label and compares its contents to the given keymaterial, returning YES iff the read succeeded and produced data identical to the argument.
static BOOL validateStorage(CFDataRef keymaterial, NSString *keyLabel, NSData *applicationLabel, NSError **outError) {
    NSString *description = NSLocalizedStringFromTableInBundle(@"Readback validation failed", @"OmniFileStore", OMNI_BUNDLE, @"readback error description");
    
    NSError *readError = nil;
    NSData *readData = readFromKeychain(keyLabel, applicationLabel, &readError);
    if (readData == nil) {
        if (outError != NULL) {
            NSDictionary *userInfo = @{ NSLocalizedDescriptionKey : description,
                                       NSUnderlyingErrorKey : readError,
                                        };
            *outError = [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionStorageError userInfo:userInfo];
        }
        return NO;
    }
    
    if (![readData isEqualToData:(__bridge NSData *)keymaterial]) {
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Key data differs from stored data", @"OmniFileStore", OMNI_BUNDLE, @"readback error failure reason");
        OFSError(outError, OFSEncryptionStorageError, description, reason);
        return NO;
    }
    
    return YES;
}

static BOOL storeInKeychain(CFDataRef keymaterial, NSString *keyLabel, NSData *applicationLabel, NSString *displayName, NSError **outError) {
    // Try updating an existing item first; if that's not found, we'll fall back to adding it new
    {
        const void *queryKeys[] = {
            kSecClass,
            
            kSecAttrAccount,
            kSecAttrService,
        };
        const void *queryValues[] = {
            kSecClassGenericPassword,
            
            (__bridge CFStringRef)keychainAccountAttributeValue,
            (__bridge CFStringRef)keyLabel,
        };
        CFDictionaryRef query = CFDICT(queryKeys, queryValues);
        
        const void *updateKeys[] = {
            kSecAttrLabel,
            kSecAttrGeneric,
            kSecValueData,
        };
        const void *updateValues[] = {
            (__bridge CFStringRef)displayName,
            (__bridge CFDataRef)applicationLabel,
            keymaterial,
        };
        CFDictionaryRef update = CFDICT(updateKeys, updateValues);
        
        OSStatus updateStatus = SecItemUpdate(query, update);
        CFRelease(query);
        CFRelease(update);
        
        if (updateStatus == noErr) {
            // Tentative success – validate what got stored
            return validateStorage(keymaterial, keyLabel, applicationLabel, outError);
        } else if (updateStatus == errSecItemNotFound) {
            // Nothing – fall through to the insert case
        } else {
            populateStatusError(outError, updateStatus);
            return NO;
        }
    }
    
    // Add a new item
    {
        const void *attrKeys[] = {
            kSecClass,
            
            kSecAttrAccount,
            kSecAttrService,
            kSecAttrGeneric,
            kSecAttrLabel,
            
            kSecValueData,
        };
        const void *attrValues[] = {
            kSecClassGenericPassword,
            
            (__bridge CFStringRef)keychainAccountAttributeValue,
            (__bridge CFStringRef)keyLabel,
            (__bridge CFDataRef)applicationLabel,
            (__bridge CFStringRef)displayName,
            
            keymaterial,
        };
        CFDictionaryRef attributes = CFDICT(attrKeys, attrValues);
        
        OSStatus addStatus = SecItemAdd(attributes, NULL);
        CFRelease(attributes);
        
        if (addStatus == noErr) {
            // Tentative success – validate what got stored
            return validateStorage(keymaterial, keyLabel, applicationLabel, outError);
        } else {
            populateStatusError(outError, addStatus);
            return NO;
        }
    }
}

static NSData *readFromKeychain(NSString *keyLabel, NSData *applicationLabel, NSError **outError) {
    // Unlike the iOS equivalent function, we cannot use SecItemCopyMatching here to get data (kSecReturnData) for multiple matching keys. This shouldn't be an issue, since we specify the full primary key for the item in the query; we should only get zero or one results.
    
    const void *queryKeys[] = {
        kSecClass,
        
        kSecAttrAccount,
        kSecAttrService,
        kSecAttrGeneric,
        
        kSecReturnData,
    };
    const void *queryValues[] = {
        kSecClassGenericPassword,
        
        (__bridge CFStringRef)keychainAccountAttributeValue,
        (__bridge CFStringRef)keyLabel,
        (__bridge CFDataRef)applicationLabel,
        
        kCFBooleanTrue,
    };
    CFDictionaryRef query = CFDICT(queryKeys, queryValues);
    
    CFDataRef resultData = NULL;
    OSStatus copyStatus = SecItemCopyMatching(query, (CFTypeRef *)(&resultData));
    CFRelease(query);
    
    if (copyStatus != noErr) {
        populateStatusError(outError, copyStatus);
        return nil;
    }
    
    return CFBridgingRelease(resultData);
}

@implementation OFSDocumentKey (Keychain)

- (BOOL)storeWithKeychainIdentifier:(NSString *)identifier displayName:(NSString *)displayName error:(NSError *__autoreleasing *)outError;
{
    if (!wk.len) {
        OFSError(outError, OFSEncryptionNeedAuth, NSLocalizedStringFromTableInBundle(@"No key available", @"OmniFileStore", OMNI_BUNDLE, @"missing encryption key error description"), @"");
        return NO;
    }
    
    CFDataRef material = CFDataCreate(kCFAllocatorDefault, wk.bytes, wk.len);
    BOOL success = storeInKeychain(material, identifier, [self applicationLabel], displayName, outError);
    CFRelease(material);
    return success;
}

- (BOOL)deriveWithKeychainIdentifier:(NSString *)identifier error:(NSError *__autoreleasing *)outError;
{
    NSData *rawData = readFromKeychain(identifier, [self applicationLabel], outError);
    if (rawData == nil) {
        return NO;
    }
    
    NSData *unwrapped = unwrapData(rawData.bytes, rawData.length, [passwordDerivation objectForKey:DocumentKeyKey], outError);
    if (unwrapped == nil) {
        return NO;
    }
    
    OFSKeySlots *keytable = [[OFSKeySlots alloc] initWithData:unwrapped error:outError];
    if (!keytable) {
        return NO;
    }
    
    wk.len = (uint16_t)rawData.length;
    [rawData getBytes:wk.bytes length:wk.len];
    slots = keytable;
    return YES;
}

@end
