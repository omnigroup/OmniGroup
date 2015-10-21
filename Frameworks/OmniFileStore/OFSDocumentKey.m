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
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFileStore/Errors.h>

#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
#import <CommonCrypto/CommonRandom.h>
#endif

RCS_ID("$Id$");

OB_REQUIRE_ARC

/* Our key store data blob is a plist: an array of dictionaries with the following keys */

#define KeyDerivationMethodKey              @"method"   /* How to derive the document key; see below */

/* Static method: the document key is simply stored in cleartext. Insecure obviously but useful for testing. */
#define KeyDerivationStatic                 @"static"
#define StaticKeyKey                        @"key"

/* Use PBKDF2 to derive a wrapping key, which is then used to wrap a random key using the RFC3394 aes128-wrap / AES-WRAP algorithm. The wrapped key is then stored. */
#define KeyDerivationMethodPassword         @"password"
#define PBKDFAlgKey                         @"algorithm"
#define PBKDFAlgPBKDF2_WRAP_AES             @"PBKDF2; aes128-wrap"
#define PBKDFRoundsKey                      @"rounds"
#define PBKDFSaltKey                        @"salt"
#define PBKDFPRFKey                         @"prf"
#define DocumentKeyKey                      @"key"

/* Store the document key in the iOS Keychain */
#define KeyDerivationAppleKeychain          @"keychain"
#define KeychainPersistentIdentifier        @"item"

/* Values for PRF */
#define PBKDFPRFSHA1                        "sha1"
#define PBKDFPRFSHA256                      "sha256"
#define PBKDFPRFSHA512                      "sha512"

/* We could use the derived key to simply wrap the bulk encryption keys themselves instead of having an intermediate document key, but that would make it difficult for the user to change their password without re-writing every encrypted file in the wrapper. This way we can simply wrap the same document key with a new password-derived key. It also leaves open the possibility of using keys on smartcards, phone TPMs, or whatever, to decrypt the document key, possibly with asymmetric crypto for least-authority background operation, and all that fun stuff. */

static NSError *wrapCCError(CCCryptorStatus cerr, NSString *op)
{
    /* CCCryptorStatus is actually in the Carbon OSStatus error domain */
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:op forKey:@"function"];
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:userInfo];
}
/* Security.framework errors are also OSStatus error codes */
#define wrapSecError(e,o) wrapCCError(e,o)

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

#pragma mark Key management

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
#define unsupportedError(e, t) unsupportedError_(e, __LINE__, t)

static const struct { CFStringRef name; CCPseudoRandomAlgorithm value; } prfNames[] = {
    { CFSTR(PBKDFPRFSHA1),   kCCPRFHmacAlgSHA1   },
    { CFSTR(PBKDFPRFSHA256), kCCPRFHmacAlgSHA256 },
    { CFSTR(PBKDFPRFSHA512), kCCPRFHmacAlgSHA512 },
};

static BOOL derive(uint8_t derivedKey[kCCKeySizeAES128], NSString *password, NSData *salt, CCPseudoRandomAlgorithm prf, unsigned int rounds, NSError **outError)
{
    /* TODO: A stringprep profile might be more appropriate here than simple NFC. Is there one that's been defined for unicode passwords? */
    NSData *passBytes = [[password precomposedStringWithCanonicalMapping] dataUsingEncoding:NSUTF8StringEncoding];
    if (!passBytes) {
        // Password itself was probably nil. Error out instead of crashing, though.
        if (outError)
            *outError = [NSError errorWithDomain:OFSErrorDomain
                                            code:OFSEncryptionNeedAuth
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Missing password" }];
        return NO;
    }
    
    /* Note: Asking PBKDF2 for an output size that's longer than its PRF size can (depending on downstream details) increase the difficulty for the legitimate user without increasing the difficulty for an attacker, because the portions of the result can be computed in parallel. That's not a problem right here since AES128 < SHA1-160, but it's something to keep in mind. */

    CCCryptorStatus cerr = CCKeyDerivationPBKDF(kCCPBKDF2, [passBytes bytes], [passBytes length],
                                               [salt bytes], [salt length],
                                               prf, rounds,
                                               derivedKey, kCCKeySizeAES128);

    if (cerr) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCKeyDerivationPBKDF");
        return NO;
    }

    return YES;
}

#if TARGET_OS_IPHONE
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

static BOOL deriveFromPassword(NSDictionary *docInfo, NSString *password, uint8_t *localKey, size_t localKeyLength, NSError **outError)
{
    /* Retrieve all our parameters from the dictionary */
    NSString *alg = [docInfo objectForKey:PBKDFAlgKey];
    if (![alg isEqualToString:PBKDFAlgPBKDF2_WRAP_AES])
        return unsupportedError(outError, alg);
    
    unsigned pbkdfRounds = [docInfo unsignedIntForKey:PBKDFRoundsKey];
    if (!pbkdfRounds)
        return unsupportedError(outError, [docInfo objectForKey:PBKDFRoundsKey]);
    
    NSData *salt = [docInfo objectForKey:PBKDFSaltKey];
    if (![salt isKindOfClass:[NSData class]])
        return unsupportedError(outError, NSStringFromClass([salt class]));
    
    id prfString = [docInfo objectForKey:PBKDFPRFKey defaultObject:@"sha1"];
    CCPseudoRandomAlgorithm prf = 0;
    for (int i = 0; i < (int)(sizeof(prfNames)/sizeof(prfNames[0])); i++) {
        if ([prfString isEqualToString:(__bridge NSString *)(prfNames[i].name)]) {
            prf = prfNames[i].value;
            break;
        }
    }
    if (prf == 0)
        return unsupportedError(outError, ([NSString stringWithFormat:@"%@ = %@", PBKDFPRFKey, prfString]));
    
    NSData *wrappedKey = [docInfo objectForKey:DocumentKeyKey];
    if (!wrappedKey || ( [wrappedKey length] % 8 != 0 ) || CCSymmetricUnwrappedSize(kCCWRAPAES, [wrappedKey length]) != localKeyLength)
        return unsupportedError(outError, @"wrappedKey");
    
    /* Derive the key-wrapping-key from the user's password */
    uint8_t wrappingKey[kCCKeySizeAES128];
    if (!derive(wrappingKey, password, salt, prf, pbkdfRounds, outError)) {
        return NO;
    }
    
    /* Unwrap the document key using the key-wrapping-key */
    size_t unrapt = localKeyLength;
    CCCryptorStatus cerr = CCSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen,
                                                wrappingKey, kCCKeySizeAES128,
                                                [wrappedKey bytes], [wrappedKey length],
                                                localKey, &unrapt);
    memset(wrappingKey, 0, sizeof(wrappingKey));
    if (cerr) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCSymmetricKeyUnwrap");
        return NO;
    } else {
        return YES;
    }
    
    /* Note that RFC3394-style key wrapping does effectively include a check field --- if we pass an incorrect wrapping key, or the wrapped key is bogus or something, it should fail. (This is tested by OFUnitTests/OFCryptoTest.m) */
}

@implementation OFSDocumentKey

- initWithData:(NSData *)storeData error:(NSError **)outError;
{
    self = [super init];
    
    NSMutableDictionary *byMethod = [NSMutableDictionary dictionary];

    if (storeData != nil) {
        NSError *error = NULL;
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
        
        if (![docInfo isKindOfClass:[NSArray class]]) {
            if (outError) {
                OFSError(outError, OFSEncryptionBadFormat, @"Could not decrypt file", @"Could not read encryption header");
            }
            return nil;
        }
        
        [docInfo enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop){
            [byMethod setObject:obj forKey:[obj objectForKey:KeyDerivationMethodKey]];
        }];
    }
    
    derivations = byMethod;
    valid = NO;
    
    return self;
}

- (NSData *)data;
{
    /* Return an NSData blob with the information we'll need to recover the document key in the future. The caller will presumably store this blob in the underlying file manager or somewhere related, and hand it back to us via -initWithFileManager:keyStore:error:. */
    return [NSPropertyListSerialization dataWithPropertyList:[derivations allValues] format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
}

@synthesize valid = valid;

- (BOOL)hasPassword;
{
    return [derivations objectForKey:KeyDerivationMethodPassword]? YES : NO;
}

- (BOOL)hasKeychainItem;
{
    return [derivations objectForKey:KeyDerivationAppleKeychain]? YES : NO;
}

- (BOOL)deriveWithOptions:(unsigned)opts password:(NSString *)password error:(NSError **)outError;
{
    NSDictionary *method;
    
    method = [derivations objectForKey:KeyDerivationStatic];
    if (method) {
        NSData *derivedKey = [method objectForKey:StaticKeyKey];
        _Static_assert(sizeof(_key) == kCCKeySizeAES128, "we don't support variable key sizes yet");
        if ([derivedKey length] == kCCKeySizeAES128) {
            [derivedKey getBytes:_key length:kCCKeySizeAES128];
            return YES;
        }
        return unsupportedError(outError, @"[staticKey length]");
    }
    
    if (password != nil && (method = [derivations objectForKey:KeyDerivationMethodPassword]) != nil) {
        /* TODO: Fall through to trying keychain method if password is wrong? */
        return deriveFromPassword(method, password, _key, sizeof(_key), outError);
    }
    
#if TARGET_OS_IPHONE
    method = [derivations objectForKey:KeyDerivationAppleKeychain];
    if (method) {
        return retrieveFromKeychain(method, _key, sizeof(_key), kSecUseAuthenticationUIAllow, outError);
    }
#endif
    
    /* Unknown derivation/storage method */
    return unsupportedError(outError, @"methods");
}

- (void)reset;  // Sets the document key to a new, randomly generated value. This is only a useful operation when you're creating a new document--- any existing items will become inaccessible.
{
    _Static_assert(sizeof(_key) == kCCKeySizeAES128, "we don't support variable key sizes yet");
    memset(_key, 0, sizeof(_key));
    [derivations removeAllObjects];
    
    NSError *e = NULL;
    if (!randomBytes(_key, kCCKeySizeAES128, &e)) {
        [NSException raise:NSGenericException
                    format:@"Failure generating random data: %@", [e description]];
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

- (BOOL)setPassword:(NSString *)password error:(NSError **)outError;
{
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
    
    uint8_t passwordDerivedWrappingKey[kCCKeySizeAES128];
    if (!derive(passwordDerivedWrappingKey, password, salt, kCCPRFHmacAlgSHA1, calibratedRoundCount, outError)) {
        return NO;
    }
    
    // Next, re-wrap our document key with the new password-derived key
    
    NSMutableData *wrappedKey = [NSMutableData data];
    size_t rapt = CCSymmetricWrappedSize(kCCWRAPAES, kCCKeySizeAES128);
    [wrappedKey setLength:rapt];
    CCCryptorStatus cerr = CCSymmetricKeyWrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen,
                                              passwordDerivedWrappingKey, kCCKeySizeAES128,
                                              _key, sizeof(_key),
                                              [wrappedKey mutableBytes], &rapt);
    if (cerr) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCSymmetricKeyWrap");
        return NO;
    }
    
    [kminfo setObject:wrappedKey forKey:DocumentKeyKey];
    [kminfo setObject:salt forKey:PBKDFSaltKey];
    
    [derivations setObject:[kminfo copy] forKey:KeyDerivationMethodPassword];
    
    return YES;
}

#if TARGET_OS_IPHONE
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

- (NSData *)wrapFileKey:(const uint8_t *)fileKeyInfo length:(size_t)fileKeyInfoLength error:(NSError **)outError;
{
    /* AESWRAP is only defined for multiples of 64 bits, but CCSymmetricKeyWrap() "handles" this by silently truncating and indicating success in that case; check here so we fail before writing out an unusable blob. (RFC5649 defines a variation on AESWRAP that handles other byte lengths, but CCSymmetricKeyWrap/Unwrap() doesn't implement it, nor is its API flexible enough for us to implement RFC5649 on top of Apple's RFC3394 implementation.) */
    if (fileKeyInfoLength < 16 || (fileKeyInfoLength % 8 != 0)) {
        if (outError)
            *outError = wrapCCError(kCCParamError, @"CCSymmetricKeyWrap");
        return nil;
    }
    
    size_t blobSize = CCSymmetricWrappedSize(kCCWRAPAES, fileKeyInfoLength);
    
    NSMutableData *result = [NSMutableData dataWithLength:2 + blobSize];
    
    /* The first two bytes of the key data are the diversification index. We don't support key rollover yet, so this is always 0. */
    OSWriteBigInt16([result mutableBytes], 0, 0);
    
    /* Wrap the document key using the key-wrapping-key */
    size_t rapt = blobSize;
    _Static_assert(sizeof(_key) == kCCKeySizeAES128, "unexpected key length");
    CCCryptorStatus cerr = CCSymmetricKeyWrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen,
                                              _key, kCCKeySizeAES128,
                                              fileKeyInfo, fileKeyInfoLength,
                                              [result mutableBytes]+2, &rapt);
    if (cerr) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCSymmetricKeyWrap");
        return nil;
    }
    
    return result;
}

- (ssize_t)unwrapFileKey:(const uint8_t *)wrappedFileKeyInfo length:(size_t)wrappedFileKeyInfoLen into:(uint8_t *)buffer length:(size_t)unwrappedKeyBufferLength error:(NSError **)outError;
{
    /* The first two bytes of the key data are the diversification index. We don't support key rollover yet, so this is always 0. */
    if (wrappedFileKeyInfoLen < 2 || OSReadBigInt16(wrappedFileKeyInfo, 0) != 0) {
        unsupportedError(outError, @"short key index");
        return -1;
    }
    
    const uint8_t *wrappedBlob = wrappedFileKeyInfo + 2;
    size_t wrappedBlobLength = wrappedFileKeyInfoLen - 2;
    
    /* AESWRAP key wrapping is only defined for multiples of 64 bits, and CCSymmetricKeyUnwrap() does not check this, so we check it here. */
    if (wrappedBlobLength < 16 || wrappedBlobLength % 8 != 0) {
        if (outError)
            *outError = wrapCCError(kCCParamError, @"CCSymmetricKeyUnwrap");
        return -1;
    }
    
    /* Unwrap the file key using the document key */
    size_t blobSize = CCSymmetricUnwrappedSize(kCCWRAPAES, wrappedBlobLength);
    if (blobSize > unwrappedKeyBufferLength) {
        if (outError)
            *outError = wrapCCError(kCCBufferTooSmall, @"CCSymmetricKeyUnwrap");
        return -1;
    }
    size_t unrapt = blobSize;
    _Static_assert(sizeof(_key) == kCCKeySizeAES128, "unexpected key length");
    CCCryptorStatus cerr = CCSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen,
                                                _key, kCCKeySizeAES128,
                                                wrappedBlob, wrappedBlobLength,
                                                buffer, &unrapt);
    /* (Note that despite the pointer giving the appearance of an inout parameter for rawKeyLen, CCSymmetricKeyUnwrap() does not update it (see RADAR 18206798 / 15949620). I'm treating the value of unrapt as undefined after the call, just in case Apple decides to randomly change the semantics of this function.) */
    if (cerr) {
        /* Note that, contrary to documentation, the only failure code CCSymmetricKeyUnwrap() returns is -1, which makes no sense as an error code */
        if (cerr == -1)
            cerr = kCCDecodeError;
        if (outError)
            *outError = wrapCCError(cerr, @"CCSymmetricKeyUnwrap");
        return -1;
    }
    
    /* Note that RFC3394-style key wrapping does effectively include a check field --- if we pass an incorrect wrapping key, or the wrapped key is bogus or something, it should fail. */
    
    return blobSize;
}

@end


