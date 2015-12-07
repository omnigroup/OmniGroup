// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentKey.h>
#import <OmniFileStore/OFSSegmentedEncryption.h>

#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSEncryptionConstants.h>
#include <stdlib.h>

#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
#import <CommonCrypto/CommonRandom.h>
#endif

RCS_ID("$Id$");

OB_REQUIRE_ARC

struct skbuf {
    uint16_t len;
    uint8_t bytes[kCCKeySizeAES256];
};

static BOOL validateSlots(NSData *slots);
static BOOL traverseSlots(NSData *slots, BOOL (^cb)(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *start, size_t len));
static uint16_t chooseUnusedSlot(NSIndexSet *used);
static uint16_t derive(uint8_t derivedKey[kCCKeySizeAES256], NSString *password, NSData *salt, CCPseudoRandomAlgorithm prf, unsigned int rounds, NSError **outError);
static NSData *deriveFromPassword(NSDictionary *docInfo, NSString *password, struct skbuf *outWk, NSError **outError);

static NSError *wrapCarbonError(int cerr, NSString *op) __attribute__((cold));
#define wrapCCError(e, o) wrapCarbonError(e,o)   /* CCCryptorStatus is actually in the Carbon OSStatus error domain */
#define wrapSecError(e,o) wrapCarbonError(e,o)   /* Security.framework errors are also OSStatus error codes */
static BOOL unsupportedError_(NSError **outError, int lineno, NSString *badThing) __attribute__((cold));
#define unsupportedError(e, t) unsupportedError_(e, __LINE__, t)

static const char * const zeroes = "\0\0\0\0\0\0\0\0";

static BOOL randomBytes(uint8_t *buffer, size_t bufferLength, NSError **outError)
{
#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
    CCRNGStatus randomErr = CCRandomGenerateBytes(buffer, bufferLength);
    if (randomErr) {
        if (outError)
            *outError = wrapCCError(randomErr, @"CCRandomGenerateBytes");
        return NO;
    }
#else
    if (SecRandomCopyBytes(kSecRandomDefault, bufferLength, buffer) != 0) {
        /* Documentation says "check errno to find out the real error" but a look at the published source code shows that's not going to be very reliable */
        if (outError)
            *outError = wrapSecError(kCCRNGFailure, @"SecRandomCopyBytes");
        return NO;
    }
#endif
    
    return YES;
}

static NSError *wrapCarbonError(int cerr, NSString *op)
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:op forKey:@"function"];
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:userInfo];
}

static BOOL unsupportedError_(NSError **outError, int lineno, NSString *badThing)
{
    if (!badThing)
        badThing = @"(nil)";
    _OBError(outError, OFSErrorDomain, OFSEncryptionBadFormat, __FILE__, lineno,
             NSLocalizedDescriptionKey, @"Could not decrypt file",
             NSLocalizedFailureReasonErrorKey, @"Unrecognized settings in encryption header",
             @"detail", badThing,
             nil);
    return NO;
}

static const struct { CFStringRef name; CCPseudoRandomAlgorithm value; } prfNames[] = {
    { CFSTR(PBKDFPRFSHA1),   kCCPRFHmacAlgSHA1   },
    { CFSTR(PBKDFPRFSHA256), kCCPRFHmacAlgSHA256 },
    { CFSTR(PBKDFPRFSHA512), kCCPRFHmacAlgSHA512 },
};

#if 0 && TARGET_OS_IPHONE
static BOOL checkCanRetrieveFromKeychain(CFDataRef itemref, NSError **outError);

static BOOL retrieveFromKeychain(NSDictionary *docInfo, uint8_t *localKey, size_t localKeyLength, CFStringRef allowUI, NSError **outError)
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

@implementation OFSDocumentKey
{
    /* The contents of our saved blob */
    NSDictionary *passwordDerivation;
    
    /* Cached, shareable encryption worker */
    OFSSegmentEncryptWorker *reusableEncryptionWorker;

    /* The decrypted key slots. buf is nil if we are not unlocked/valid. */
    NSData *buf;
    
    /* We keep a copy of the wrapping key around so we can re-wrap after a rollover event */
    struct skbuf wk;

    NSInteger changeCount;
}

- initWithData:(NSData *)storeData error:(NSError **)outError;
{
    self = [super init];
    
    if (storeData != nil) {
        NSError * __autoreleasing error = NULL;
        NSArray *docInfo = [NSPropertyListSerialization propertyListWithData:storeData
                                                                     options:NSPropertyListImmutable
                                                                      format:NULL
                                                                       error:&error];
        if (!docInfo) {
            if (outError) {
                *outError = error;
                OFSError(outError, OFSEncryptionBadFormat, @"Could not decrypt file", @"Could not read encryption header");
            }
            return nil;
        }
        
        __block BOOL contentsLookReasonable = YES;
        
        if (![docInfo isKindOfClass:[NSArray class]]) {
            contentsLookReasonable = NO;
        }
        
        if (contentsLookReasonable) {
            [docInfo enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop){
                if (![obj isKindOfClass:[NSDictionary class]]) {
                    contentsLookReasonable = NO;
                    *stop = YES;
                    return;
                }
                
                NSString *method = [obj objectForKey:KeyDerivationMethodKey];
                if ([method isEqual:KeyDerivationMethodPassword] && !passwordDerivation) {
                    passwordDerivation = obj;
                } else {
                    // We might eventually want to mark ourselves as read-only if we have a passwordDerivation and also some derivations we don't understand.
                    // For now we just fail completely in that case.
                    contentsLookReasonable = NO;
                }
            }];
        }
        
        if (!contentsLookReasonable) {
            if (outError) {
                OFSError(outError, OFSEncryptionBadFormat, @"Could not decrypt file", @"Could not read encryption header");
            }
            return nil;
        }
    }
    
    return self;
}

- (NSData *)data;
{
    /* Return an NSData blob with the information we'll need to recover the document key in the future. The caller will presumably store this blob in the underlying file manager or somewhere related, and hand it back to us via -initWithData:error:. */
    NSArray *docInfo = [NSArray arrayWithObject:passwordDerivation];
    return [NSPropertyListSerialization dataWithPropertyList:docInfo format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
}

@synthesize changeCount = changeCount;
@dynamic valid, hasPassword;

- (BOOL)isValid;
{
    return (buf && buf.length)? YES : NO;
}

#pragma mark Passphrase handling and wrapping/unwrapping

- (BOOL)hasPassword;
{
    return (passwordDerivation != nil)? YES : NO;
}

- (BOOL)deriveWithPassword:(NSString *)password error:(NSError **)outError;
{
    NSData *derivedKey = deriveFromPassword(passwordDerivation, password, &wk, outError);
    if (derivedKey && wk.len) {
        
        if (!validateSlots(derivedKey)) {
            wk.len = 0;
            memset(wk.bytes, 0, sizeof(wk.bytes));
            buf = nil;
            
            OFSError(outError, OFSEncryptionBadFormat,
                     @"Could not decrypt file",
                     @"Could not read parse key slots");

            return NO;
        }
        
        buf = derivedKey;
        return YES;
    } else {
        return NO;
    }
}

static unsigned calibratedRoundCount = 1000000;
static unsigned const saltLength = 20;
static void calibrateRounds(void *dummy) {
    uint roundCount = CCCalibratePBKDF(kCCPBKDF2, 24, saltLength, kCCPRFHmacAlgSHA1, kCCKeySizeAES128, 750);
    if (roundCount > calibratedRoundCount)
        calibratedRoundCount = roundCount;
}
static dispatch_once_t calibrateRoundsOnce;

static uint16_t derive(uint8_t derivedKey[kCCKeySizeAES256], NSString *password, NSData *salt, CCPseudoRandomAlgorithm prf, unsigned int rounds, NSError **outError)
{
    /* TODO: A stringprep profile might be more appropriate here than simple NFC. Is there one that's been defined for unicode passwords? */
    NSData *passBytes = [[password precomposedStringWithCanonicalMapping] dataUsingEncoding:NSUTF8StringEncoding];
    if (!passBytes) {
        // Password itself was probably nil. Error out instead of crashing, though.
        if (outError)
            *outError = [NSError errorWithDomain:OFSErrorDomain
                                            code:OFSEncryptionNeedAuth
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Missing password" }];
        return 0;
    }
    
    /* Note: Asking PBKDF2 for an output size that's longer than its PRF size can (depending on downstream details) increase the difficulty for the legitimate user without increasing the difficulty for an attacker, because the portions of the result can be computed in parallel. That's not a problem right here since AES128 < SHA1-160, but it's something to keep in mind. */
    
    uint16_t outputLength;
    if (prf >= kCCPRFHmacAlgSHA256) {
        /* We rely on the ordering of the CCPseudoRandomAlgorithm constants here :( */
        outputLength = kCCKeySizeAES256;
    } else {
        outputLength = kCCKeySizeAES128;
    }
    
    CCCryptorStatus cerr = CCKeyDerivationPBKDF(kCCPBKDF2, [passBytes bytes], [passBytes length],
                                                [salt bytes], [salt length],
                                                prf, rounds,
                                                derivedKey, outputLength);
    
    if (cerr) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCKeyDerivationPBKDF");
        return 0;
    }
    
    return outputLength;
}

- (BOOL)setPassword:(NSString *)password error:(NSError **)outError;
{
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    NSMutableDictionary *kminfo = [NSMutableDictionary dictionary];
    
    [kminfo setObject:KeyDerivationMethodPassword forKey:KeyDerivationMethodKey];
    [kminfo setObject:PBKDFAlgPBKDF2_WRAP_AES forKey:PBKDFAlgKey];
    
    /* TODO: Choose a round count dynamically using CCCalibratePBKDF()? The problem is we don't know if we're on one of the user's faster machines or one of their slower machines, nor how much tolerance the user has for slow unlocking on their slower machines. On my current 2.4GHz i7, asking for a 1-second derive time results in a round count of roughly 2560000. */
    dispatch_once_f(&calibrateRoundsOnce, NULL, calibrateRounds);
    
    [kminfo setUnsignedIntValue:calibratedRoundCount forKey:PBKDFRoundsKey];
    
    NSMutableData *salt = [NSMutableData data];
    [salt setLength:saltLength];
    if (!randomBytes([salt mutableBytes], saltLength, outError))
        return NO;
    [kminfo setObject:salt forKey:PBKDFSaltKey];
    
    wk.len = derive(wk.bytes, password, salt, kCCPRFHmacAlgSHA1, calibratedRoundCount, outError);
    if (!wk.len) {
        return NO;
    }

    if (buf) {
        // Next, wrap our secrets with the new password-derived key
        NSData *wrappedKey = [self _rewrap];
        
        [kminfo setObject:wrappedKey forKey:DocumentKeyKey];
    }
    
    passwordDerivation = kminfo;
    changeCount ++;
    
    return YES;
}

- (NSData *)_rewrap;
{
    if (!buf || !wk.len)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    if (!validateSlots(buf))
        [NSException raise:NSInternalInconsistencyException
                    format:@"Inconsistent keyslot array"];
    
    NSData *toWrap = buf;
    size_t toWrapLength = [toWrap length];
    if (toWrapLength % 8 != 0) {
        // AESWRAP is only defined for multiples of half the underlying block size.
        // If necessary pad the end with 0s (the slot structure knows to ignore this).
        NSMutableData *padded = [toWrap mutableCopy];
        size_t more = ( (toWrapLength + 8) & ~ 0x07 ) - toWrapLength;
        [padded appendBytes:zeroes length:more];
        toWrap = padded;
        toWrapLength = [toWrap length];
    }
    
    NSMutableData *wrappedKey = [NSMutableData data];
    size_t rapt = CCSymmetricWrappedSize(kCCWRAPAES, toWrapLength);
    [wrappedKey setLength:rapt];
    CCCryptorStatus cerr = CCSymmetricKeyWrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen,
                                              wk.bytes, wk.len,
                                              [toWrap bytes], toWrapLength,
                                              [wrappedKey mutableBytes], &rapt);
    
    /* There's no reasonable situation in which CCSymmetricKeyWrap() fails here--- it should only happen if we have some serious bug elsewhere in OFSDocumentKey. So treat it as a fatal error. */
    if (cerr) {
        [NSException exceptionWithName:NSGenericException
                                reason:[NSString stringWithFormat:@"CCSymmetricKeyWrap returned %d", cerr]
                              userInfo:@{ @"klen": @(wk.len), @"twl": @(toWrapLength) }];
    }
    
    return wrappedKey;
}

static NSData *deriveFromPassword(NSDictionary *docInfo, NSString *password, struct skbuf *outWk, NSError **outError)
{
    /* Retrieve all our parameters from the dictionary */
    NSString *alg = [docInfo objectForKey:PBKDFAlgKey];
    if (![alg isEqualToString:PBKDFAlgPBKDF2_WRAP_AES]) {
        unsupportedError(outError, alg);
        return nil;
    }
    
    unsigned pbkdfRounds = [docInfo unsignedIntForKey:PBKDFRoundsKey];
    if (!pbkdfRounds) {
        unsupportedError(outError, [docInfo objectForKey:PBKDFRoundsKey]);
        return nil;
    }
    
    NSData *salt = [docInfo objectForKey:PBKDFSaltKey];
    if (![salt isKindOfClass:[NSData class]]) {
        unsupportedError(outError, NSStringFromClass([salt class]));
        return nil;
    }
    
    id prfString = [docInfo objectForKey:PBKDFPRFKey defaultObject:@"sha1"];
    CCPseudoRandomAlgorithm prf = 0;
    for (int i = 0; i < (int)(sizeof(prfNames)/sizeof(prfNames[0])); i++) {
        if ([prfString isEqualToString:(__bridge NSString *)(prfNames[i].name)]) {
            prf = prfNames[i].value;
            break;
        }
    }
    if (prf == 0) {
        OFSErrorWithInfo(outError, OFSEncryptionBadFormat,
                         @"Could not decrypt file", @"Unrecognized settings in encryption header",
                         PBKDFPRFKey, prfString, nil);
        return nil;
    }
    
    NSData *wrappedKey = [docInfo objectForKey:DocumentKeyKey];
    if (!wrappedKey || ( [wrappedKey length] % 8 != 0 )) { /* AESWRAP is only defined on certain lengths of input; Apple's implementation doesn't check */
        unsupportedError(outError, @"wrappedKey");
        return nil;
    }
    
    /* Derive the key-wrapping-key from the user's password */
    uint8_t wrappingKey[kCCKeySizeAES256];
    uint16_t wrappingKeyLength = derive(wrappingKey, password, salt, prf, pbkdfRounds, outError);
    if (!wrappingKeyLength) {
        return nil;
    }
    
    /* Unwrap the document key(s) using the key-wrapping-key */
    size_t wrappedKeyLength = [wrappedKey length];
    size_t localKeyLength = CCSymmetricUnwrappedSize(kCCWRAPAES, wrappedKeyLength);
    void *localKey = malloc(wrappedKeyLength);
    size_t unwrapt = localKeyLength;
    CCCryptorStatus cerr = CCSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen,
                                                wrappingKey, wrappingKeyLength,
                                                [wrappedKey bytes], wrappedKeyLength,
                                                localKey, &unwrapt);
    /* Note that RFC3394-style key wrapping does effectively include a check field --- if we pass an incorrect wrapping key, or the wrapped key is bogus or something, it should fail. (This is tested by OFUnitTests/OFCryptoTest.m) */
    NSData *retval;
    if (cerr) {
        free(localKey);
        if (outError)
            *outError = wrapCCError(cerr, @"CCSymmetricKeyUnwrap");
        retval = nil;
    } else {
        outWk->len = wrappingKeyLength;
        memcpy(outWk->bytes, wrappingKey, wrappingKeyLength);
        retval = [NSData dataWithBytesNoCopy:localKey length:localKeyLength freeWhenDone:YES];
    }
    
    memset(wrappingKey, 0, sizeof(wrappingKey));
    return retval;
}

#if 0 && TARGET_OS_IPHONE
- (BOOL)storeInKeychainWithAttributes:(NSDictionary *)attrs error:(NSError **)outError;
{
    NSData *existingKeyIdentifier = nil;
    OSStatus oserr;
    
    /* See if we already have a keychain item */
    existingKeyIdentifier = [[derivations objectForKey:KeyDerivationAppleKeychain] objectForKey:KeychainPersistentIdentifier];
    
    NSMutableDictionary *setting = attrs? [attrs mutableCopy] : [NSMutableDictionary dictionary];
    
    [setting setObject:(__bridge id)kSecClassKey forKey:(__bridge id)kSecClass];
    [setting setObject:(__bridge id)kSecAttrKeyClassSymmetric forKey:(__bridge id)kSecAttrKeyClass];
    [setting setObject:(__bridge id)kCFBooleanTrue forKey:(__bridge id)kSecAttrIsPermanent];
    [setting setObject:[NSData dataWithBytesNoCopy:_key length:sizeof(_key) freeWhenDone:NO] forKey:(__bridge id)kSecValueData];
    
    /* If we already have a keychain item reference, just update the keychain */
    if (existingKeyIdentifier) {
        NSDictionary *specifier = @{ (__bridge id)kSecMatchItemList: @[ existingKeyIdentifier ] };
        
        oserr = SecItemUpdate((__bridge CFDictionaryRef)specifier, (__bridge CFDictionaryRef)setting);
        
        if (oserr == noErr) {
            return YES; // Successfully updated--- our keychain identifier hasn't changed, so we don't need to update our info blob
        } else if (oserr == errSecUserCanceled) {
            if (outError)
                *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
            return NO;
        }
        
        /* Failed? Fall through to the insert case */
    }
    
    /* Otherwise, insert an item */
    
    [setting setObject:(__bridge id)kCFBooleanTrue forKey:(__bridge id)kSecReturnPersistentRef];
    
    if (![setting objectForKey:(__bridge id)kSecAttrLabel])
        [setting setObject:@"File encryption key" forKey:(__bridge id)kSecAttrLabel];
    
    CFTypeRef result = NULL;
    oserr = SecItemAdd((__bridge CFDictionaryRef)setting, &result);
    if (oserr != noErr) {
        if (outError)
            *outError = wrapSecError(oserr, @"SecItemAdd");
        return NO;
    }
    
    /* Verify that we can retrieve the keychain item using the persistent identifier we just got */
    BOOL roundtrip = checkCanRetrieveFromKeychain(result, outError);
    if (!roundtrip) {
        CFRelease(result);
        return NO;
    }

    NSDictionary *kminfo = @{
                             KeyDerivationMethodKey: KeyDerivationAppleKeychain,
                             KeychainPersistentIdentifier: (__bridge NSData *)result
                            };
    
    CFRelease(result);
    
    [derivations setObject:kminfo forKey:KeyDerivationAppleKeychain];
    
    return YES;
}
#endif

- (OFSSegmentEncryptWorker *)encryptionWorker;
{
    @synchronized(self) {
        if (!reusableEncryptionWorker)
            reusableEncryptionWorker = [[OFSSegmentEncryptWorker alloc] init];
        return reusableEncryptionWorker;
    }
}

#pragma mark Key slot managemennt

static BOOL validateSlots(NSData *slots)
{
    const unsigned char *buf = slots.bytes;
    size_t len = slots.length;
    size_t pos = 0;
    while (pos != len) {
        if (pos > len)
            return NO;
        enum OFSDocumentKeySlotType keytype = buf[pos];
        if (keytype == SlotTypeNone)
            break;
        if (pos + 4 > len)
            return NO;
        size_t slotlength = 4 * (unsigned)buf[pos+1];
        
        switch (keytype) {
            case SlotTypeActiveAESWRAP:
            case SlotTypeRetiredAESWRAP:
                if (slotlength < kCCKeySizeAES128 || slotlength > kCCKeySizeAES256)
                    return NO;
                break;
            default:
                break;
        }
        
        pos += 4 + slotlength;
    }
    
    while (pos < len) {
        if (buf[pos] != 0)
            return NO;
        pos ++;
    }
    
    return YES;
}

static BOOL traverseSlots(NSData *slots, BOOL (^cb)(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *start, size_t len))
{
    const unsigned char *buf = slots.bytes;
    size_t len = slots.length;
    size_t pos = 0;
    while (pos < len) {
        enum OFSDocumentKeySlotType keytype = buf[pos];
        if (keytype == SlotTypeNone)
            return NO;
        size_t slotlength = 4 * (unsigned)buf[pos+1];
        uint16_t slotid = OSReadBigInt16(buf, pos+2);
        BOOL callback_satisfied = cb(keytype, slotid, buf + pos + 4, slotlength);
        if (callback_satisfied)
            return YES;
        pos += 4 + slotlength;
    }
    if (pos != len) {
        abort(); // Should be impossible: our input is verified by validateSlots() first
    }
    return NO;
}

static uint16_t chooseUnusedSlot(NSIndexSet *used)
{
    uint16_t trial = (uint16_t)arc4random_uniform(16);
    if (![used containsIndex:trial])
        return trial;
    
    NSMutableIndexSet *unused = [NSMutableIndexSet indexSetWithIndexesInRange:(NSRange){0, 65535}];
    [unused removeIndexes:used];
    NSUInteger availableIndex = [unused firstIndex];
    if (availableIndex == NSNotFound) {
        [NSException raise:NSGenericException format:@"No unused key slots!"];
    }
    return (uint16_t)availableIndex;
}

- (void)discardKeysExceptSlots:(NSIndexSet *)keepThese retireCurrent:(BOOL)retire;
{
    if (keepThese && !buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    NSMutableIndexSet *usedSlots = [NSMutableIndexSet indexSet];
    NSMutableData *newBuffer = [NSMutableData data];
    __block BOOL seenActiveAESKey = NO;
    traverseSlots(buf, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength){
        BOOL copyThis = [keepThese containsIndex:sn] && ![usedSlots containsIndex:sn];
        if (retire && (tp == SlotTypeActiveAESWRAP)) {
            tp = SlotTypeRetiredAESWRAP;
            copyThis = YES;
        }
        // NSLog(@"In discardKeys: looking at slot %u, copy=%s", sn, copyThis?"YES":"NO");
        if (copyThis) {
            if (keylength % 4 != 0 || keylength > 4*255) {
                [NSException raise:NSInternalInconsistencyException
                            format:@"Invalid slot length %zu", keylength];
                return NO;
            }
            if (tp == SlotTypeActiveAESWRAP)
                seenActiveAESKey = YES;
            uint8_t slotheader[4];
            slotheader[0] = tp;
            slotheader[1] = (uint8_t)(keylength/4);
            OSWriteBigInt16(slotheader, 2, sn);
            [newBuffer appendBytes:slotheader length:4];
            [newBuffer appendBytes:keydata length:keylength];
        }
        [usedSlots addIndex:sn];
        return NO;
    });
    
    /* Make sure we have a key of type SlotTypeActiveAESWRAP */
    if (!seenActiveAESKey) {
        uint8_t newslot[4 + kCCKeySizeAES128];
        newslot[0] = SlotTypeActiveAESWRAP;
        newslot[1] = kCCKeySizeAES128 / 4;
        OSWriteBigInt16(newslot, 2, chooseUnusedSlot(usedSlots));
        
        NSError *e = NULL;
        if (!randomBytes(newslot+4, kCCKeySizeAES128, &e)) {
            [NSException raise:NSGenericException
                        format:@"Failure generating random data: %@", [e description]];
        }
        
        // NSLog(@"In discardKeys: added new key in slot %u", OSReadBigInt16(newslot, 2));
        [newBuffer replaceBytesInRange:(NSRange){0, 0} withBytes:newslot length:sizeof(newslot)];
    }
    
    if (buf && [buf isEqual:newBuffer]) {
        /* This can be a no-op if retire=NO and all keys are listed in keepThese */
        return;
    }
    
    buf = newBuffer;
    changeCount ++;
    
    if (passwordDerivation) {
        NSData *reWrapped = [self _rewrap];
        passwordDerivation = [passwordDerivation dictionaryWithObject:reWrapped forKey:DocumentKeyKey];
    }
}

#pragma mark File-subkey wrapping and unwrapping

- (NSData *)wrapFileKey:(const uint8_t *)fileKeyInfo length:(size_t)fileKeyInfoLength error:(NSError **)outError;
{
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    /* AESWRAP is only defined for multiples of 64 bits, but CCSymmetricKeyWrap() "handles" this by silently truncating and indicating success in that case; check here so we fail before writing out an unusable blob. (RFC5649 defines a variation on AESWRAP that handles other byte lengths, but CCSymmetricKeyWrap/Unwrap() doesn't implement it, nor is its API flexible enough for us to implement RFC5649 on top of Apple's RFC3394 implementation.) */
    if (fileKeyInfoLength < 16 || (fileKeyInfoLength % 8 != 0)) {
        if (outError)
            *outError = wrapCCError(kCCParamError, @"CCSymmetricKeyWrap");
        return nil;
    }
    
    __block NSMutableData *result = nil;
    __block CCCryptorStatus cerr = -2070; /* This value should never be read, but if it is, this is an "internal error" code */
    
    if (!traverseSlots(buf, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength){
        if (tp != SlotTypeActiveAESWRAP)
            return NO;
        
        size_t blobSize = CCSymmetricWrappedSize(kCCWRAPAES, fileKeyInfoLength);
        result = [NSMutableData dataWithLength:2 + blobSize];
        uint8_t *resultPtr = [result mutableBytes];
        
        /* The first two bytes of the key data are the diversification index. */
        OSWriteBigInt16(resultPtr, 0, sn);
        
        /* Wrap the document key using the key-wrapping-key */
        size_t rapt = blobSize;
        cerr = CCSymmetricKeyWrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen,
                                  keydata, keylength,
                                  fileKeyInfo, fileKeyInfoLength,
                                  resultPtr+2, &rapt);
        
        return YES;
    })) {
        /* No slot was acceptable to our callback. I don't expect this to happen in normal use. */
        if (outError)
            *outError = [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionNeedAuth userInfo:@{ NSLocalizedDescriptionKey: @"No active key slot" }];
        return nil;
    }
    
    if (cerr != kCCSuccess) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCSymmetricKeyWrap");
        return nil;
    }
    
    return result;
}

/* This is just CCSymmetricKeyUnwrap() with some error checking */
static inline NSError *do_AESUNWRAP(const uint8_t *keydata, size_t keylength, const uint8_t *wrappedBlob, size_t wrappedBlobLength, uint8_t *unwrappedKeyBuffer, size_t unwrappedKeyBufferLength, ssize_t *outputBufferUsed)
{
    /* AESWRAP key wrapping is only defined for multiples of 64 bits, and CCSymmetricKeyUnwrap() does not check this, so we check it here. */
    if (wrappedBlobLength < 16 || wrappedBlobLength % 8 != 0) {
        return wrapCCError(kCCParamError, @"CCSymmetricKeyUnwrap");
    }
    
    /* Unwrap the file key using the document key */
    size_t blobSize = CCSymmetricUnwrappedSize(kCCWRAPAES, wrappedBlobLength);
    if (blobSize > unwrappedKeyBufferLength) {
        return wrapCCError(kCCBufferTooSmall, @"CCSymmetricKeyUnwrap");
    }
    size_t unwrapt = blobSize;
    CCCryptorStatus cerr = CCSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen,
                                                keydata, keylength,
                                                wrappedBlob, wrappedBlobLength,
                                                unwrappedKeyBuffer, &unwrapt);
    /* (Note that despite the pointer giving the appearance of an in+out parameter for rawKeyLen, CCSymmetricKeyUnwrap() does not update it (see RADAR 18206798 / 15949620). I'm treating the value of unwrapt as undefined after the call, just in case Apple decides to randomly change the semantics of this function.) */
    if (cerr) {
        /* Note that, contrary to documentation, the only failure code CCSymmetricKeyUnwrap() returns is -1, which makes no sense as an error code */
        if (cerr == -1)
            cerr = kCCDecodeError;
        return wrapCCError(cerr, @"CCSymmetricKeyUnwrap");
    }
    
    /* Note that RFC3394-style key wrapping does effectively include a check field --- if we pass an incorrect wrapping key, or the wrapped key is bogus or something, it should fail. */
    
    *outputBufferUsed = blobSize;
    return nil;
}

- (ssize_t)unwrapFileKey:(const uint8_t *)wrappedFileKeyInfo length:(size_t)wrappedFileKeyInfoLen into:(uint8_t *)buffer length:(size_t)unwrappedKeyBufferLength error:(NSError **)outError;
{
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    /* The first two bytes of the key data are the diversification index. */
    if (wrappedFileKeyInfoLen < 2) {
        unsupportedError(outError, @"no key index");
        return -1;
    }
    uint16_t keyslot = OSReadBigInt16(wrappedFileKeyInfo, 0);
    
    __block NSError *localError = nil;
    __block ssize_t result = -1;
    if (!traverseSlots(buf, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength){
        if (sn != keyslot)
            return NO;
        if (tp == SlotTypeActiveAESWRAP || tp == SlotTypeRetiredAESWRAP) {
            /* We've found an AES key. Unwrap using it. */
            const uint8_t *wrappedBlob = wrappedFileKeyInfo + 2;
            size_t wrappedBlobLength = wrappedFileKeyInfoLen - 2;
            localError = do_AESUNWRAP(keydata, keylength, wrappedBlob, wrappedBlobLength, buffer, unwrappedKeyBufferLength, &result);
            return YES;
        } else if (tp == SlotTypeActiveAES_CTR_HMAC || tp == SlotTypeRetiredAES_CTR_HMAC) {
            /* We've found a directly stored AES+HMAC key set */
            if (unwrappedKeyBufferLength < keylength || wrappedFileKeyInfoLen > 2) {
                /* Inapplicable! */
                unsupportedError(&localError, @"invalid length");
                return YES;
            }
            memcpy(buffer, keydata, keylength);
            result = keylength;
            return YES;
        } else {
            /* We found an applicable slot, but don't know how to use it. This could be due to a future version using an algorithm we don't know about. */
            NSString *msg = [NSString stringWithFormat:@"Unknown key type (%d) for slot %u", tp, sn];
            localError = [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionNeedAuth userInfo:@{ NSLocalizedDescriptionKey: msg }];
            return YES;
        }
    })) {
        NSString *msg = [NSString stringWithFormat:@"No key in slot %u", keyslot];
        if (outError)
            *outError = [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionNeedAuth userInfo:@{ NSLocalizedDescriptionKey: msg }];
        return -1;
    }
    if (result < 0) {
        if (outError)
            *outError = localError;
        return -1;
    }
    
    OBASSERT(localError == nil);
    return result;
}

@end


