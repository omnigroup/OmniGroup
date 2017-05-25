// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentKey-KeychainStorageSupport.h>

#import "OFSDocumentKey-Internal.h"
#import "OFSEncryption-Internal.h"

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSEncryptionConstants.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>

RCS_ID("$Id$");

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#error Building OFSDocumentKey iOS Keychain support on a non-iOS platform
#endif

#define arraycount(a) (sizeof(a)/sizeof(a[0]))
#define CFDICT(keys, values) ({ _Static_assert(arraycount(keys) == arraycount(values), "dictionary key and value counts must be equal");  \
    CFDictionaryCreate(kCFAllocatorDefault, keys, values, arraycount(keys), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); })

static NSArray *retrieveFromKeychain(NSData *applicationLabel, NSError **outError)
{
    const void *keys[6] = { kSecMatchLimit, kSecAttrKeyClass, kSecAttrApplicationLabel, kSecClass, kSecReturnAttributes, kSecReturnRef };
    const void *vals[6] = { kSecMatchLimitAll, kSecAttrKeyClassSymmetric, (__bridge CFDataRef)applicationLabel, kSecClassKey, kCFBooleanTrue, kCFBooleanTrue };
    
    // See RADAR 24489395: in order to get results consistently, we need to ask for attributes, or we get nothing.
    
    CFDictionaryRef query = CFDICT(keys, vals);
    CFTypeRef result = NULL;
    OSStatus oserr = SecItemCopyMatching(query, &result);
    CFRelease(query);
    
    if (oserr != noErr) {
        if (oserr == errSecItemNotFound) {
            return [NSArray array];
        } else {
            if (outError) {
                *outError = ofsWrapSecError(oserr, @"SecItemCopyMatching", nil, nil);
            }
            return nil;
        }
    }
    
    /* Do the usual defensive checks against SecItemCopyMatching() bugginess */
    NSString *failure;
    if (!result || CFGetTypeID(result) != CFArrayGetTypeID()) {
        failure = @"not a CFArrayRef";
    } else {
        failure = nil;
        CFIndex resultCount = CFArrayGetCount(result);
        for (CFIndex resultIndex = 0; resultIndex < resultCount; resultIndex ++) {
            CFDictionaryRef item = CFArrayGetValueAtIndex(result, resultIndex);
            if (CFGetTypeID(item) != CFDictionaryGetTypeID()) {
                failure = @"not a CFDictionaryRef";
                break;
            }
            SecKeyRef keyItem = (SecKeyRef)CFDictionaryGetValue(item, kSecValueRef);
            if (keyItem) {
                if (CFGetTypeID(keyItem) != SecKeyGetTypeID()) {
                    failure = @"not a SecKeyRef";
                    break;
                }
            } else {
                // See RADAR 24489177: we ask for a key ref back, and we don't get one, but we do get the actual (supposedly secret?) contents of the key.
                CFDataRef keyData = (CFDataRef)CFDictionaryGetValue(item, kSecValueData);
                if (keyData) {
                    if (CFGetTypeID(keyData) != CFDataGetTypeID()) {
                        failure = @"not a CFDataRef";
                        break;
                    }
                } else {
                    failure = @"missing requested result key";
                }
            }
            CFTypeRef keyClass = CFDictionaryGetValue(item, kSecAttrKeyClass);
            if (!keyClass) {
                failure = @"not a symmetric key";
                break;
            }
#if 0
            /* This consistency check fails (RADAR 19804744), but it appears to be benign */
            if (!CFEqual(keyClass, kSecAttrKeyClassSymmetric)) {
                failure = @"not a symmetric key";
                break;
            }
#endif
        }
    }
    
    if (failure) {
        if (result)
            CFRelease(result);
        if (outError) {
            NSString *description =  NSLocalizedStringFromTableInBundle(@"Internal error updating keychain", @"OmniFileStore", OMNI_BUNDLE, @"error description");
            NSString *fullMessage = [NSString stringWithFormat:@"Invalid data retrieved from keychain due to API failure (%@)", failure];
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:(-25304)
                                        userInfo:@{ NSLocalizedDescriptionKey: description,
                                                    NSLocalizedFailureReasonErrorKey: fullMessage }];
        }
        
        return nil;
    }
    
    return CFBridgingRelease(result);
}

static BOOL storeInKeychain(CFDataRef keymaterial, CFDataRef applicationLabel, NSString *userVisibleLabel, NSError **outError)
{
    
#define NUM_LOOKUP_ITEMS 3
#define NUM_STORED_ITEMS 6
#define NUM_INITIAL_ITEMS 1
    const void *keys[NUM_LOOKUP_ITEMS + NUM_STORED_ITEMS + NUM_INITIAL_ITEMS] = {
        /* Search attributes */
        kSecAttrKeyClass, kSecClass, kSecAttrApplicationLabel,
        
        /* Storage attributes */
        kSecValueData,
        kSecAttrIsPermanent, kSecAttrCanWrap, kSecAttrCanUnwrap, kSecAttrSynchronizable,
        kSecAttrAccessible,
        
        /* Items to set but only when creating */
        kSecAttrLabel,
    };
    const void *vals[NUM_LOOKUP_ITEMS + NUM_STORED_ITEMS + NUM_INITIAL_ITEMS] = {
        kSecAttrKeyClassSymmetric, kSecClassKey, applicationLabel,
        
        keymaterial,
        kCFBooleanTrue, kCFBooleanTrue, kCFBooleanTrue, kCFBooleanFalse,
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        
        NULL,
    };
    
    {
        CFDictionaryRef query = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, NUM_LOOKUP_ITEMS, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionaryRef update = CFDictionaryCreate(kCFAllocatorDefault, keys + NUM_LOOKUP_ITEMS, vals + NUM_LOOKUP_ITEMS, NUM_STORED_ITEMS, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        OSStatus err = SecItemUpdate(query, update);
        CFRelease(query);
        CFRelease(update);
        
        if (err == errSecItemNotFound) {
            /* Huh. Try adding it, then. */
        } else if (err == errSecParam) {
            /* Keychain operations just fail sometimes for undocumented reasons and/or bugs. It's amazing how buggy this API is. */
        } else {
            /* Either success, or some failure other than errSecItemNotFound */
            if (err != noErr && outError != NULL) {
                *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:@{ @"function": @"SecItemUpdate" }];
            }
            return NO;
        }
    }
    
    {
        // Key label is documented to be a CFString, but it's actually a CFData. (RADAR 24496368)
        CFDataRef labelbytes = CFBridgingRetain([userVisibleLabel dataUsingEncoding:NSUTF8StringEncoding]);
        vals[NUM_LOOKUP_ITEMS+NUM_STORED_ITEMS] = labelbytes;
        
        CFDictionaryRef query = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, NUM_LOOKUP_ITEMS + NUM_STORED_ITEMS + NUM_INITIAL_ITEMS, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        OSStatus err = SecItemAdd(query, NULL);
        CFRelease(query);
        vals[NUM_LOOKUP_ITEMS+NUM_STORED_ITEMS] = NULL;
        CFRelease(labelbytes);
        if (err != noErr && outError != NULL) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:@{ @"function": @"SecItemAdd" }];
        }
        return (err == noErr)? YES : NO;
    }
}


static NSData *retrieveItemData(CFTypeRef item, CFTypeRef itemClass)
{
    /*
     Docs say: "By default, this function searches for items in the keychain. To instead provide your own set of items to be filtered by this search query, specify the search key kSecMatchItemList and provide as its value a CFArrayRef object".
     
     However, what you actually have to supply, at least on iOS 8.1 through 9.2, is kSecValueRef, and you also have to supply kSecAttrSynchronizable=Any or else it fails with paramErr.
     
     We can't be bugfix-compatible, unfortunately: if we pass the kSecMatchItemList key, it fails with paramErr.
     */
    const void *ks[4] = { kSecClass,     kSecValueRef, kSecAttrSynchronizable,         kSecReturnData   };
    const void *vs[4] = { itemClass,     item,         kSecAttrSynchronizableAny,      kCFBooleanTrue   };
    
    CFTypeRef result;
    OSStatus kerr;
    
    {
        CFDictionaryRef query = CFDICT(ks, vs);
        result = NULL;
        kerr = SecItemCopyMatching(query, &result);
        CFRelease(query);
    }
    
    if (kerr == errSecParam || kerr == errSecItemNotFound) {
        /* Try again, using the documented parameters */
        ks[1] = kSecMatchItemList;
        vs[1] = CFArrayCreate(kCFAllocatorDefault, &(vs[1]), 1, &kCFTypeArrayCallBacks);
        CFDictionaryRef query = CFDICT(ks, vs);
        CFRelease(vs[1]);
        vs[1] = NULL;
        result = NULL;
        kerr = SecItemCopyMatching(query, &result);
        CFRelease(query);
    }
    
    if (kerr != noErr || !result) {
        return nil;
    }
    
    /* SecItemCopyMatching() sometimes returns 1-item arrays when it's supposed to return a bare item */
    if (CFGetTypeID(result) == CFArrayGetTypeID()) {
        /* SecItemCopyMatching() sometimes returns other entries intermixed with the matching entry/entries (RADAR 10155924) */
        CFIndex count = CFArrayGetCount(result);
        if (count != 1) {
            NSLog(@"Complete garbage returned from SecItemCopyMatching? (array length = %ld)", (long)count);
            CFRelease(result);
            return nil;
        }
        CFTypeRef unwrapped = CFRetain(CFArrayGetValueAtIndex(result, 0));
        CFRelease(result);
        result = unwrapped;
    }
    
    if (CFGetTypeID(result) != CFDataGetTypeID()) {
        NSLog(@"Incorrect type returned from SecItemCopyMatching?");
        CFRelease(result);
        return nil;
    } else {
        return CFBridgingRelease(result);
    }
}

static BOOL deleteAllFromKeychain(NSError **outError)
{
    // This banks on OFSDocumentKey being the only user of stored symmetric keys.
    const void *keys[2] = { kSecAttrKeyClass, kSecClass, };
    const void *values[2] = { kSecAttrKeyClassSymmetric, kSecClassKey, };
    CFDictionaryRef query = CFDICT(keys, values);
    
    OSStatus err = SecItemDelete(query);
    if (err != noErr && outError != NULL) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
    }
    return (err == noErr);
}

#pragma mark -

@implementation OFSDocumentKey (Keychain)

static int whined = 0;

- (BOOL)deriveWithKeychainIdentifier:(NSString *)ident error:(NSError **)outError;
{
    NSData *appLabel = [self applicationLabel];
    
    NSArray *keys = retrieveFromKeychain(appLabel, outError);
    if (!keys)
        return NO;
    
    NSData *infoBlob = [passwordDerivation objectForKey:DocumentKeyKey];
    NSData *unwrapped = nil;
    NSData *rawData;
    
    for (NSDictionary *keyItem in keys) {
        // Verify the application label matches (i.e. this key is the one we want)
        if (appLabel) {
            NSData *itemLabel = [keyItem objectForKey:(__bridge id)kSecAttrApplicationLabel];
            if (itemLabel && ![appLabel isEqual:itemLabel])
                continue;
        }
        
        rawData = nil;
        
        SecKeyRef ref = (__bridge SecKeyRef)[keyItem objectForKey:(__bridge id)kSecValueRef];
        if (ref) {
            rawData = retrieveItemData(ref, kSecClassKey);
        } else {
            NSData *raw = [keyItem objectForKey:(__bridge id)kSecValueData];
            if (raw) {
                if (!whined) {
                    whined = 1;
                    NSLog(@"Working around RADAR 24489177");
                }
                rawData = raw;
            } else {
                /* Unusable entry?!? */
                if (!whined) {
                    whined = 1;
                    NSLog(@"Sidestepping RADAR 24489395");
                }
                continue;
            }
        }
        
        if (!rawData)
            continue;
        
        unwrapped = unwrapData(rawData.bytes, rawData.length, infoBlob, outError);
        if (unwrapped)
            break;
    }
    
    if (!unwrapped)
        return NO;
    
    OFSKeySlots *unwrappedSlots = [[OFSKeySlots alloc] initWithData:unwrapped error:outError];
    if (!unwrappedSlots) {
        return NO;
    }
    
    wk.len = (uint16_t)rawData.length;
    [rawData getBytes:wk.bytes length:wk.len];
    slots = unwrappedSlots;
    
    return YES;
}

- (BOOL)storeWithKeychainIdentifier:(NSString *)ident displayName:(NSString *)displayName error:(NSError **)outError;
{
    NSData *appTag = [self applicationLabel];
    
    if (!wk.len || !appTag) {
        if (outError)
            *outError = [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionNeedAuth userInfo:@{ NSLocalizedDescriptionKey: @"No key available." }];
        return NO;
    }
    
    // Key label is documented to be a CFString, but it's actually a CFData. (RADAR 24496368)
    NSData *identbytes = [ident dataUsingEncoding:NSUTF8StringEncoding];
    
    CFDataRef material = CFDataCreate(kCFAllocatorDefault, wk.bytes, wk.len);
    BOOL stored = storeInKeychain(material, (__bridge CFDataRef)appTag, displayName, outError);
    CFRelease(material);
    
    if (!stored) {
        return NO;
    }
    
    // Double-check that the key actually got inserted into the keychain in a way that it can be retrieved (remember, SecItem is terrible)
    NSArray *readback = retrieveFromKeychain(appTag, outError);
    if (!readback) {
        // TODO: Wrap the error?
        return NO;
    }
    
    NSLog(@"After insert, readback = %@", readback);
    
    BOOL found = NO;
    NSUInteger count = readback.count;
    for(NSUInteger i = 0; i < count; i++) {
        NSDictionary *item = [readback objectAtIndex:i];
        if (([[item objectForKey:(__bridge id)kSecAttrApplicationLabel] isEqual:ident] ||
             [[item objectForKey:(__bridge id)kSecAttrApplicationLabel] isEqual:identbytes]) &&
            [[item objectForKey:(__bridge id)kSecAttrApplicationTag] isEqual:appTag]) {
            found = YES;
            break;
        }
    }
    if (!found) {
        if (outError) {
            NSString *description =  NSLocalizedStringFromTableInBundle(@"Internal error updating keychain", @"OmniFileStore", OMNI_BUNDLE, @"error description");
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:errSecUnimplemented userInfo:@{ NSLocalizedDescriptionKey: description,
                                                                                                            NSLocalizedFailureReasonErrorKey: @"Inserted key not found in keychain." }];
        }
        return NO;
    }
    
    return YES;
}

+ (BOOL)deleteAllEntriesWithError:(NSError **)outError;
{
    return deleteAllFromKeychain(outError);
}

@end

