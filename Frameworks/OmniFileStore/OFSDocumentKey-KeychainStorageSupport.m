// Copyright 2016 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSDocumentKey-KeychainStorageSupport.h"
#import "OFSEncryption-Internal.h"

RCS_ID("$Id$");

#define arraycount(a) (sizeof(a)/sizeof(a[0]))
#define CFDICT(keys, values) ({ _Static_assert(arraycount(keys) == arraycount(values), "dictionary key and value counts must be equal");  \
    CFDictionaryCreate(kCFAllocatorDefault, keys, values, arraycount(keys), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); })

NSArray *retrieveFromKeychain(NSData *applicationTag, NSError **outError)
{
    const void *keys[6] = { kSecMatchLimit, kSecAttrKeyClass, kSecAttrApplicationLabel, kSecClass, kSecReturnAttributes, kSecReturnRef };
    const void *vals[6] = { kSecMatchLimitAll, kSecAttrKeyClassSymmetric, (__bridge CFDataRef)applicationTag, kSecClassKey, kCFBooleanTrue, kCFBooleanTrue };
    
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

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
BOOL storeInKeychain(CFDataRef keymaterial, CFDataRef applicationLabel, NSString *userVisibleLabel, NSError **outError)
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

#else /* OSX */

/*
 (Cribbed from StackOverflow, but this matches the contents of libsecurity_cdsa_utilities/lib/KeySchema.m4 in published Security-57337.20.44) "For a keychain item of class kSecClassKey, the primary key is the combination of kSecAttrApplicationLabel, kSecAttrApplicationTag, kSecAttrKeyType, kSecAttrKeySizeInBits, kSecAttrEffectiveKeySize, and the creator, start date and end date which are not exposed by SecItem yet."
 
 Of these, the only ones we can really use to distinguish our keys are kSecAttrApplicationLabel and kSecAttrApplicationTag. Quoth the docs:
 
 kSecAttrApplicationLabel: "[....] This is different from the kSecAttrLabel (which is intended to be human-readable). This attribute is used to look up a key programmatically"
 
 kSecAttrApplicationTag: "Specifies a dictionary key whose value is a CFDataRef containing private tag data."
 
 However, on OSX, the Keychain Access app erroneously stores the user-editable "Comment" textbox contents under kSecAttrApplicationTag (RADAR 24579912; presumably it's supposed to be editing kSecAttrComment). So we can't use ApplicationTag or we'll get clobbered if the user edits that field. That leaves kSecAttrApplicationLabel.
 */

BOOL storeInKeychain(CFDataRef keymaterial, CFDataRef keylabel, NSString *displayName, NSError **outError)
{
    /* OSX is tricky.
     You can't add a symmetric key directly with SecItemAdd(), because Apple never bothered to implement that. (SecItemAdd() just works in terms of SecKeychainItemCreateFromContent() anyway, see below.) See RADAR 24575784
     You can't fully create one with SecKeychainItemCreateFromContent(); this seems to just be an oversight in Schema::attributeInfo(), which is missing the attributes we need (all the key-specific attributes as well as ApplicationLabel (RADAR 24577556) and ApplicationTag (RADAR 24578456)).
     You can't partially create one with SecKeychainItemCreateFromContent() and then add the missing attributes with SecItemUpdate or SecKeychainItemModifyContent, because the primary-key attributes you need to set in order to insert it into the keychain are not among those that SecKeychainItemCreateFromContent understands.
     You can't create one with SecKeyCreateFromData(), then modify its attributes and *then* insert it into a keychain, because both of the attribute-modifying calls (SecItemUpdate or SecKeychainItemModifyContent) only work on items which are already inserted into the keychain (RADAR 11840882)
     
     So, what we have to do is generate a *random* key with SecKeyGenerateSymmetric() (which also applies a random keylabel), and then modify all of its attributes, including the keylabel and key data, using SecKeychainItemModifyAttributesAndData().
     */
    
    OSStatus err;
    SecKeychainItemRef keyRef;
    BOOL creatingNewItem;
    
    /* First, check whether we already have a key with that keylabel */
    {
        const void *itkeys[] = { kSecClass, kSecAttrKeyClass, kSecMatchLimit, kSecReturnRef, kSecReturnAttributes, kSecAttrApplicationLabel };
        const void *itvals[] = { kSecClassKey, kSecAttrKeyClassSymmetric, kSecMatchLimitAll, kCFBooleanTrue, kCFBooleanTrue, keylabel };
        _Static_assert(arraycount(itkeys) == arraycount(itvals), "");
        CFDictionaryRef attrs = CFDICT(itkeys, itvals);
        CFArrayRef oot = NULL;
        err = SecItemCopyMatching(attrs, (CFTypeRef *)&oot);
        
        if (err == noErr) {
            /* Work around SecItemCopyMatching() bugs ... */
            if (CFGetTypeID(oot) != CFArrayGetTypeID()) {
                CFArrayRef wrappedInArray = CFArrayCreate(kCFAllocatorDefault, (const void **)&oot, 1, &kCFTypeArrayCallBacks);
                CFRelease(oot);
                oot = wrappedInArray;
            }
            
            keyRef = NULL;
            for (CFIndex i = 0; i < CFArrayGetCount(oot); i++) {
                CFDictionaryRef d = CFArrayGetValueAtIndex(oot, i);
                CFDataRef found_klbl = CFDictionaryGetValue(d, kSecAttrApplicationLabel);
                if (found_klbl != NULL && CFEqual(found_klbl, keylabel)) {
                    keyRef = (SecKeychainItemRef)CFRetain(CFDictionaryGetValue(d, kSecValueRef));
                    break;
                }
            }
            
            CFRelease(oot);
        } else if (err == errSecItemNotFound) {
            // Expected error, no key matching that label
            keyRef = NULL;
        } else {
            // Unexpected error
            CFStringRef msg = SecCopyErrorMessageString(err, NULL);
            NSLog(@"SecItemCopyMatching() returns --> %d %@", err, msg);
            CFRelease(msg);
            // But continue as if the item just wasn't found
            keyRef = NULL;
        }
    }
    
    if (keyRef != NULL) {
        creatingNewItem = NO;
    } else {
        creatingNewItem = YES;
        
        SecAccessRef initialAccess = NULL;
        NSString *descr = NSLocalizedStringFromTableInBundle(@"Sync Encryption Key", @"OmniFileStore", OMNI_BUNDLE, @"keychain item description - used in keychain access control prompt");
        err = SecAccessCreate((__bridge CFStringRef)descr, NULL /* "If NULL, defaults to (just) the application creating the item." */, &initialAccess);
        if (err != noErr) {
            NSLog(@"SecAccessCreate -> %d", (int)err);
        }
        
        SInt32 bitsize = 8 * (int)CFDataGetLength(keymaterial);
        CFNumberRef num = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitsize);
        const void *itkeys[] = {
            /* kSecUseKeychain, */ kSecAttrKeyType, kSecAttrKeySizeInBits, kSecAttrLabel,
            kSecAttrCanEncrypt, kSecAttrCanDecrypt, kSecAttrCanWrap, kSecAttrCanUnwrap,
            kSecAttrAccess,
            kSecAttrIsPermanent,
        };
        const void *itvals[] = {
            /* kcRef, */ kSecAttrKeyTypeAES, num, CFSTR("Temporary Keychain Entry"),
            kCFBooleanFalse, kCFBooleanFalse, kCFBooleanTrue, kCFBooleanTrue,
            initialAccess,
            kCFBooleanTrue,
        };
        CFDictionaryRef attrs = CFDICT(itkeys, itvals);
        CFRelease(num);
        
        keyRef = NULL;
        CFErrorRef errref = NULL;
        /// TODO WIML: It seems like SecKeyGenerateSymmetric() would return +1 ref count, but the compiler thinks otherwise.
        keyRef = (SecKeychainItemRef)CFRetain(SecKeyGenerateSymmetric(attrs, &errref));
        
        CFRelease(attrs);
        
        if (keyRef == NULL) {
            NSLog(@"SecKeyGenerateSymmetric failed: %@", errref);
            if (outError) {
                *outError = (__bridge NSError *)errref;
            }
            CFRelease(errref);
            return NO;
        }
        
        // Voodoo: make sure the created item has a keychain
        // tekl 2016.05.24: is this really necessary? can we get rid of this keychain fetch?
        SecKeychainRef referencedKeychain = NULL;
        err = SecKeychainItemCopyKeychain(keyRef, &referencedKeychain);
        if (err != errSecSuccess) {
            NSLog(@"SecKeychainItemCopyKeychain returned %d, indicating the created symmetric key has no backing keychain. Bravely continuing anyway…", err);
        }
        
        // Refetch the same thing
        {
            // tekl 2016.05.24: maybe we need to match all keys here and make sure we're getting only one thing back? probably would like to ensure it's the *right* thing, too
            const void *refetchKeys[] = { kSecClass, kSecAttrKeyClass, kSecMatchLimit, kSecReturnRef, kSecAttrLabel };
            const void *refetchVals[] = { kSecClassKey, kSecAttrKeyClassSymmetric, kSecMatchLimitOne, kCFBooleanTrue, CFSTR("Temporary Keychain Entry") };
            _Static_assert(arraycount(itkeys) == arraycount(itvals), "");
            CFDictionaryRef refetchAttrs = CFDICT(refetchKeys, refetchVals);

            CFTypeRef refetched = NULL;
            err = SecItemCopyMatching(refetchAttrs, &refetched);
            if (err == errSecSuccess) {
                CFRelease(keyRef);
                keyRef = (SecKeychainItemRef)refetched;
            }
        }
    }
    
    /* Okay, now we can update everything */
    {
        char dateBytes[15];
        SecKeychainAttribute attrs[5];
        int attrCount = 0;
        UInt32 yes = 1;
        CFDataRef displayBytes = NULL;
        
        attrs[attrCount++] = (SecKeychainAttribute){ kSecKeySensitive, sizeof(yes), &yes };
        attrs[attrCount++] = (SecKeychainAttribute){ kSecKeyExtractable, sizeof(yes), &yes };
        
        if (creatingNewItem) {
            time_t tnow = time(NULL);
            struct tm parts;
            gmtime_r(&tnow, &parts);
            strftime(dateBytes, sizeof(dateBytes), "%Y%m%d%H%M%S", &parts);
            attrs[attrCount++] = (SecKeychainAttribute){ kSecKeyStartDate, (UInt32)strlen(dateBytes), dateBytes };
            
            /* kSecKeyLabel maps to kSecAttrApplicationLabel */
            attrs[attrCount++] = (SecKeychainAttribute){ kSecKeyLabel, (UInt32)CFDataGetLength(keylabel), (void *)CFDataGetBytePtr(keylabel) };
            
            /* kSecKeyPrintName maps to kSecAttrLabel */
            displayBytes = CFBridgingRetain([displayName dataUsingEncoding:NSUTF8StringEncoding]);
            attrs[attrCount++] = (SecKeychainAttribute){ kSecKeyPrintName, (UInt32)CFDataGetLength(displayBytes), (void *)CFDataGetBytePtr(displayBytes) };
        }
        
        // tekl 2016.05.24: consider accepting the kSecAttrApplicationLabel that the thing generates for us, and storing a mapping from some other key to that generated label in preferences or similar
        SecKeychainAttributeList attrList = { .count = attrCount, .attr = attrs };
        err = SecKeychainItemModifyAttributesAndData(keyRef, &attrList, (UInt32)CFDataGetLength(keymaterial), (void *)CFDataGetBytePtr(keymaterial));
        if (displayBytes)
            CFRelease(displayBytes);
    }
    
    if (creatingNewItem && err != noErr) {
        // Remove the incomplete entry
        removeItemFromKeychain(keyRef);
    }
    
    CFRelease(keyRef); // We might have just modified the keylabel, which would make this key reference invalid.
    
    if (err != noErr) {
        CFStringRef msg = SecCopyErrorMessageString(err, NULL);
        NSLog(@"SecKeychainItemModifyAttributesAndData() returns --> %d %@", err, msg);
        
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:@{ NSLocalizedDescriptionKey: (__bridge id)msg,
                                                                                            @"function": @"SecKeychainItemModifyAttributesAndData" }];
        }
        
        CFRelease(msg);
        
        return NO;
    } else {
        return YES;
    }
}

OSStatus removeItemFromKeychain(SecKeychainItemRef keyRef)
{
    const void *kk[1] = { kSecValueRef };
    const void *vv[1] = { keyRef };
    CFDictionaryRef del = CFDICT(kk, vv);
    OSStatus result = SecItemDelete(del);
    CFRelease(del);
    return result;
}

#endif


#if 0
OSStatus removeDerivations(CFStringRef attrKey, NSData *attrValue)
{
    const void *keys[3] = { kSecClass, kSecAttrKeyClass, attrKey };
    const void *vals[3] = { kSecClassKey, kSecAttrKeyClassSymmetric, (__bridge CFDataRef)attrValue };
    
    CFDictionaryRef query = CFDICT(keys, vals);
    OSStatus err = SecItemDelete(query);
    CFRelease(query);
    
    return err;
}
#endif

NSData *retrieveItemData(CFTypeRef item, CFTypeRef itemClass)
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



#if 0 && TARGET_OS_IPHONE
static BOOL checkCanRetrieveFromKeychain(CFDataRef itemref, NSError **outError);

BOOL retrieveFromKeychain(NSDictionary *docInfo, uint8_t *localKey, size_t localKeyLength, CFStringRef allowUI, NSError **outError)
{
    NSData *itemref = [docInfo objectForKey:KeychainPersistentIdentifier];
    if (!itemref || ![itemref isKindOfClass:[NSData class]])
        return unsupportedError(outError, NSStringFromClass([itemref class]));
    
    const void *keys[4] = { kSecValuePersistentRef, kSecClass, kSecReturnData, kSecUseAuthenticationUI };
    const void *vals[4] = { (__bridge const void *)itemref, kSecClassKey, kCFBooleanTrue, allowUI };
    
    CFDictionaryRef query = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFTypeRef result = NULL;
    OSStatus oserr = SecItemCopyMatching(query, &result);
    CFRelease(query);
    
    if (oserr != noErr) {
        if (outError) {
            NSError *e;
            if (oserr == errSecUserCanceled) {
                *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
            } else {
                e = wrapSecError(oserr, @"SecItemCopyMatching");
                *outError = [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionNeedAuth userInfo:@{ NSUnderlyingErrorKey: e, OFSEncryptionNeedKeychain: @YES }];
            }
        }
        return NO;
    }
    
    if (CFGetTypeID(result) != CFDataGetTypeID() || (size_t)CFDataGetLength(result) != localKeyLength) {
        CFRelease(result);
        
        if (outError)
            *outError = [NSError errorWithDomain:OFErrorDomain code:OFKeyNotAvailable userInfo:@{ NSLocalizedFailureReasonErrorKey: @"Invalid data retrieved from keychain" }];
        
        return NO;
    }
    CFDataGetBytes(result, (CFRange){0, localKeyLength }, localKey);
    CFRelease(result);
    
    return YES;
}

static BOOL checkCanRetrieveFromKeychain(CFDataRef itemref, NSError **outError)
{
    const void *keys[3] = { kSecValuePersistentRef, kSecClass, kSecReturnAttributes };
    const void *vals[3] = { NULL, kSecClassKey, kCFBooleanTrue };
    vals[0] = itemref;
    
    CFDictionaryRef query = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFTypeRef result = NULL;
    OSStatus oserr = SecItemCopyMatching(query, &result);
    CFRelease(query);
    
    if (oserr != noErr) {
        if (outError) {
            *outError = wrapSecError(oserr, @"SecItemCopyMatching");
        }
        return NO;
    }
    
    NSString *failure;
    if (CFGetTypeID(result) != CFDictionaryGetTypeID()) {
        failure = @"API error";
    } else if (!CFEqual(CFDictionaryGetValue(result, kSecClass), kSecClassKey)) {
        failure = @"Wrong item class";
    } else if (!CFEqual(CFDictionaryGetValue(result, kSecAttrKeyClass), kSecAttrKeyClassSymmetric)) {
        failure = @"Wrong key class";
    } else {
        failure = nil;
    }
    
    CFRelease(result);
    
    if (failure) {
        if (outError) {
            NSString *fullMessage = [@"Invalid data retrieved from keychain: " stringByAppendingString:failure];
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:(-25304)
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Internal error updating keychain",
                                                    NSLocalizedFailureReasonErrorKey: fullMessage }];
        }
        
        return NO;
    }
    
    return YES;
}

#endif



