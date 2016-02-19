// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSDocumentKey.h>
#import <OmniFileStore/OFSSegmentedEncryptionWorker.h>

#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSEncryptionConstants.h>
#import <OmniFileStore/OFSEncryption-Internal.h>
#include <stdlib.h>

#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
#import <CommonCrypto/CommonRandom.h>
#endif

RCS_ID("$Id$");

OB_REQUIRE_ARC

#define MAX_SYMMETRIC_KEY_BYTES kCCKeySizeAES256
struct skbuf {
    uint16_t len;
    uint8_t bytes[MAX_SYMMETRIC_KEY_BYTES];
};

static BOOL validateSlots(NSData *slots);
static BOOL traverseSlots(NSData *slots, BOOL (^cb)(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *start, size_t len));
static uint16_t chooseUnusedSlot(NSIndexSet *used);
static uint16_t derive(uint8_t derivedKey[MAX_SYMMETRIC_KEY_BYTES], NSString *password, NSData *salt, CCPseudoRandomAlgorithm prf, unsigned int rounds, NSError **outError);
static NSData *deriveFromPassword(NSDictionary *docInfo, NSString *password, struct skbuf *outWk, NSError **outError);

#if 0 && !(defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE)
/* iOS doesn't have the concept of a keychain item ref */
static OSStatus removeItemFromKeychain(SecKeychainItemRef keyRef);
#endif

#define unsupportedError(e, t) ofsUnsupportedError_(e, __LINE__, t)

static const char * const zeroes = "\0\0\0\0\0\0\0\0";

static const struct { CFStringRef name; CCPseudoRandomAlgorithm value; } prfNames[] = {
    { CFSTR(PBKDFPRFSHA1),   kCCPRFHmacAlgSHA1   },
    { CFSTR(PBKDFPRFSHA256), kCCPRFHmacAlgSHA256 },
    { CFSTR(PBKDFPRFSHA512), kCCPRFHmacAlgSHA512 },
};

#define arraycount(a) (sizeof(a)/sizeof(a[0]))

@implementation OFSDocumentKey
{
    /* The contents of our saved blob */
    NSDictionary *passwordDerivation;
    
    /* Cached, shareable encryption worker */
    OFSSegmentEncryptWorker *reusableEncryptionWorker;

    /* The decrypted key slots. buf is nil if we are not unlocked/valid. */
    NSData *buf;
    
    /* Incremented when -data changes */
    NSInteger changeCount;
    
    /* We keep a copy of the wrapping key around so we can re-wrap after a rollover event */
    struct skbuf wk;
}

- initWithData:(NSData *)storeData error:(NSError **)outError;
{
    self = [super init];
    
    memset(&wk, 0, sizeof(wk));
    
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

/* Passphrase continuity: create a new document key with no keyslots, but the same authenticator (including the PBKDF2 salt, which allows stored authenticators on clients to continue working). */
- initWithAuthenticator:(OFSDocumentKey *)source error:(NSError **)outError;
{
    self = [super init];
    
    if (!(source.valid)) {
        unsupportedError(outError, @"source.valid = NO");
        return nil;
    }
    
    passwordDerivation = source->passwordDerivation;
    buf = [NSData data];
    memcpy(&wk, &(source->wk), sizeof(wk));
    
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

- (BOOL)valid;
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

static uint16_t derive(uint8_t derivedKey[MAX_SYMMETRIC_KEY_BYTES], NSString *password, NSData *salt, CCPseudoRandomAlgorithm prf, unsigned int rounds, NSError **outError)
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
    _Static_assert(kCCKeySizeAES256 <= MAX_SYMMETRIC_KEY_BYTES, "");
    
    CCCryptorStatus cerr = CCKeyDerivationPBKDF(kCCPBKDF2, [passBytes bytes], [passBytes length],
                                                [salt bytes], [salt length],
                                                prf, rounds,
                                                derivedKey, outputLength);
    
    if (cerr) {
        if (outError)
            *outError = ofsWrapCCError(cerr, @"CCKeyDerivationPBKDF", nil, nil);
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
    uint8_t wrappingKey[MAX_SYMMETRIC_KEY_BYTES];
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
        if (cerr < 0 && cerr > -4000) {
            // CCSymmetricKeyUnwrap() returns bogus error codes.
            cerr = kCCDecodeError;
        }
        if (outError)
            *outError = ofsWrapCCError(cerr, @"CCSymmetricKeyUnwrap", nil, nil);
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

/* Return an encryption worker for an active key slot. Encryption workers can be used from multiple threads, so we can safely cache one and return it here. */
- (OFSSegmentEncryptWorker *)encryptionWorker;
{
    @synchronized(self) {
        
        if (!self.valid)
            return nil;
        
        if (!reusableEncryptionWorker) {
            
            __block BOOL sawAESWRAP = NO;
            traverseSlots(buf, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength) {
                if (tp == SlotTypeActiveAES_CTR_HMAC && keylength == SEGMENTED_INNER_LENGTH) {
                    reusableEncryptionWorker = [[OFSSegmentEncryptWorker alloc] initWithBytes:keydata length:keylength];
                    uint8_t sbuf[2];
                    OSWriteBigInt16(sbuf, 0, sn);
                    reusableEncryptionWorker.wrappedKey = [NSData dataWithBytes:sbuf length:2];
                    return YES;
                }
                if (tp == SlotTypeActiveAESWRAP)
                    sawAESWRAP = YES;
                return NO;
            });
            
            if (!reusableEncryptionWorker && sawAESWRAP) {
                uint8_t kbuf[SEGMENTED_INNER_LENGTH_PADDED];
                randomBytes(kbuf, SEGMENTED_INNER_LENGTH, NULL);
                memset(kbuf + SEGMENTED_INNER_LENGTH, 0, sizeof(kbuf) - SEGMENTED_INNER_LENGTH);
                NSData *wrapped = [self wrapFileKey:kbuf length:sizeof(kbuf) error:NULL];
                reusableEncryptionWorker = [[OFSSegmentEncryptWorker alloc] initWithBytes:kbuf length:sizeof(kbuf)];
                memset(kbuf, 0, sizeof(kbuf));
                reusableEncryptionWorker.wrappedKey = wrapped;
            }
            
        }
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

static void fillSlot(NSMutableData *slotbuffer, uint8_t slottype, uint16_t slotlength, uint16_t slotnumber)
{
    uint8_t newslot[4 + slotlength];
    newslot[0] = SlotTypeActiveAESWRAP;
    if (slotlength > (4 * 255))
        abort();
    newslot[1] = (uint8_t)(slotlength / 4);
    OSWriteBigInt16(newslot, 2, slotnumber);
    memset(newslot+4, 0, slotlength);
    
    [slotbuffer replaceBytesInRange:(NSRange){0, 0} withBytes:newslot length:sizeof(newslot)];
    
    NSError *e = NULL;
    if (!randomBytes([slotbuffer mutableBytes]+4, slotlength, &e)) {
        [NSException raise:NSGenericException
                    format:@"Failure generating random data: %@", [e description]];
    }
}

- (void)discardKeysExceptSlots:(NSIndexSet *)keepThese retireCurrent:(BOOL)retire generate:(enum OFSDocumentKeySlotType)ensureSlot;
{
    if (keepThese && !buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    @synchronized(self) {
        reusableEncryptionWorker = nil;
    }
    
    NSMutableIndexSet *usedSlots = [NSMutableIndexSet indexSet];
    NSMutableData *newBuffer = [NSMutableData data];
    __block BOOL seenActiveKey = NO;
    traverseSlots(buf, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength){
        BOOL copyThis = (keepThese == nil) || ([keepThese containsIndex:sn] && ![usedSlots containsIndex:sn]);
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
            if (tp == ensureSlot)
                seenActiveKey = YES;
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
    
    /* Make sure we have an active key slot */
    if (!seenActiveKey) {
        switch (ensureSlot) {
            case SlotTypeNone:
                /* not asked to generate a key */
                break;
            case SlotTypeActiveAESWRAP:
                fillSlot(newBuffer, SlotTypeActiveAESWRAP, kCCKeySizeAES128, chooseUnusedSlot(usedSlots));
                break;
            case SlotTypeActiveAES_CTR_HMAC:
                fillSlot(newBuffer, SlotTypeActiveAES_CTR_HMAC, SEGMENTED_INNER_LENGTH, chooseUnusedSlot(usedSlots));
                break;
            default:
                OBRejectInvalidCall(self, _cmd, @"bad ensureSlot vaule");
                break;
        }
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

- (NSIndexSet *)retiredKeySlots;
{
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
    traverseSlots(buf, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength){
        switch(tp) {
            case SlotTypeRetiredAESWRAP:
            case SlotTypeRetiredAES_CTR_HMAC:
                [result addIndex:sn];
                break;
            default:
                break;
        }
        return NO;
    });
    
    return result;
}

- (NSIndexSet *)keySlots;
{
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
    traverseSlots(buf, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength){
        [result addIndex:sn];
        return NO;
    });
    
    return result;
}

#pragma mark File-subkey wrapping and unwrapping

- (NSData *)wrapFileKey:(const uint8_t *)fileKeyInfo length:(size_t)fileKeyInfoLength error:(NSError **)outError;
{
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    /* AESWRAP is only defined for multiples of 64 bits, but CCSymmetricKeyWrap() "handles" this by silently truncating and indicating success in that case; check here so we fail before writing out an unusable blob. (RFC5649 defines a variation on AESWRAP that handles other byte lengths, but CCSymmetricKeyWrap/Unwrap() doesn't implement it, nor is its API flexible enough for us to implement RFC5649 on top of Apple's RFC3394 implementation.) */
    if (fileKeyInfoLength < 16 || (fileKeyInfoLength % 8 != 0)) {
        if (outError)
            *outError = ofsWrapCCError(kCCParamError, @"CCSymmetricKeyWrap", @"len", @( fileKeyInfoLength ));
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
            *outError = ofsWrapCCError(cerr, @"CCSymmetricKeyWrap", nil, nil);
        return nil;
    }
    
    return result;
}

/* This is just CCSymmetricKeyUnwrap() with some error checking */
static inline NSError *do_AESUNWRAP(const uint8_t *keydata, size_t keylength, const uint8_t *wrappedBlob, size_t wrappedBlobLength, uint8_t *unwrappedKeyBuffer, size_t unwrappedKeyBufferLength, ssize_t *outputBufferUsed)
{
    /* AESWRAP key wrapping is only defined for multiples of 64 bits, and CCSymmetricKeyUnwrap() does not check this, so we check it here. */
    if (wrappedBlobLength < 16 || wrappedBlobLength % 8 != 0) {
        return ofsWrapCCError(kCCParamError, @"CCSymmetricKeyUnwrap", @"len", @( wrappedBlobLength ));
    }
    
    /* Unwrap the file key using the document key */
    size_t blobSize = CCSymmetricUnwrappedSize(kCCWRAPAES, wrappedBlobLength);
    if (blobSize > unwrappedKeyBufferLength) {
        return ofsWrapCCError(kCCBufferTooSmall, @"CCSymmetricKeyUnwrap", @"len", @( unwrappedKeyBufferLength ));
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
        return ofsWrapCCError(cerr, @"CCSymmetricKeyUnwrap", nil, nil);
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

#pragma mark Keychain storage

#if 0

static NSArray *retrieveFromKeychain(NSString *applicationLabel, NSError **outError)
{
    const void *keys[6] = { kSecMatchLimit, kSecAttrKeyClass, kSecAttrApplicationLabel, kSecClass, kSecReturnAttributes, kSecReturnRef };
    const void *vals[6] = { kSecMatchLimitAll, kSecAttrKeyClassSymmetric, (__bridge CFStringRef)applicationLabel, kSecClassKey, kCFBooleanTrue, kCFBooleanTrue };
    
    // See RADAR 24489395: in order to get results consistently, we need to ask for attributes, or we get nothing.
    
    CFDictionaryRef query = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 6, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
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
        failure = @"API error (not a CFArrayRef)";
    } else {
        failure = nil;
        CFIndex resultCount = CFArrayGetCount(result);
        for (CFIndex resultIndex = 0; resultIndex < resultCount; resultIndex ++) {
            CFDictionaryRef item = CFArrayGetValueAtIndex(result, resultIndex);
            if (CFGetTypeID(item) != CFDictionaryGetTypeID()) {
                failure = @"API error (not a CFDictionaryRef)";
                break;
            }
            SecKeyRef keyItem = (SecKeyRef)CFDictionaryGetValue(item, kSecValueRef);
            if (keyItem) {
                if (CFGetTypeID(keyItem) != SecKeyGetTypeID()) {
                    failure = @"API error (not a SecKeyRef)";
                    break;
                }
            } else {
                // See RADAR 24489177: we ask for a key ref back, and we don't get one, but we do get the actual (supposedly secret?) contents of the key.
                CFDataRef keyData = (CFDataRef)CFDictionaryGetValue(item, kSecValueData);
                if (keyData) {
                    if (CFGetTypeID(keyData) != CFDataGetTypeID()) {
                        failure = @"API error (not a CFDataRef)";
                        break;
                    }
                } else {
                    failure = @"API error (missing requested result key)";
                }
            }
            CFTypeRef keyClass = CFDictionaryGetValue(item, kSecAttrKeyClass);
            if (!keyClass) {
                failure = @"API error (not a symmetric key)";
                break;
            }
#if 0
            /* This consistency check fails (RADAR 19804744), but it appears to be benign */
            if (!CFEqual(keyClass, kSecAttrKeyClassSymmetric)) {
                failure = @"API error (not a symmetric key)";
                break;
            }
#endif
        }
    }
    
    if (failure) {
        if (result)
            CFRelease(result);
        if (outError) {
            NSString *fullMessage = [@"Invalid data retrieved from keychain: " stringByAppendingString:failure];
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:(-25304)
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Internal error updating keychain",
                                                    NSLocalizedFailureReasonErrorKey: fullMessage }];
        }
        
        return nil;
    }
    
    return CFBridgingRelease(result);
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
static OSStatus storeInKeychain(CFDataRef keymaterial, id applicationLabel, id applicationTag, NSError **outError)
{
    
#define NUM_LOOKUP_ITEMS 4
#define NUM_STORED_ITEMS 6
    const void *keys[NUM_LOOKUP_ITEMS + NUM_STORED_ITEMS] = {
        /* Search attributes */
        kSecAttrKeyClass, kSecClass, kSecAttrApplicationLabel, kSecAttrApplicationTag,
        
        /* Storage attributes */
        kSecValueData,
        kSecAttrIsPermanent, kSecAttrCanWrap, kSecAttrCanUnwrap, kSecAttrSynchronizable,
        kSecAttrAccessible,
        // kSecAttrDescription,     // "Description" only applies to password items, not keys
    };
    const void *vals[NUM_LOOKUP_ITEMS + NUM_STORED_ITEMS] = {
        kSecAttrKeyClassSymmetric, kSecClassKey, (__bridge CFTypeRef)applicationLabel, (__bridge CFTypeRef)applicationTag,
        
        keymaterial,
        kCFBooleanTrue, kCFBooleanTrue, kCFBooleanTrue, kCFBooleanFalse,
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        // CFSTR("Password-Based-Encryption Key")
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
            return err;
        }
    }
    
    {
        CFDictionaryRef query = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, NUM_LOOKUP_ITEMS + NUM_STORED_ITEMS, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        OSStatus err = SecItemAdd(query, NULL);
        CFRelease(query);
        if (err != noErr && outError != NULL) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:@{ @"function": @"SecItemAdd" }];
        }
        return err;
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

static BOOL storeInKeychain(CFDataRef keymaterial, CFDataRef keylabel, NSString *displayName, NSError **outError)
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
        CFDictionaryRef attrs = CFDictionaryCreate(kCFAllocatorDefault, itkeys, itvals, arraycount(itkeys), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
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
        NSString *descr = @"Sync Encryption Key";
        err = SecAccessCreate((__bridge CFStringRef)descr, NULL /* "If NULL, defaults to (just) the application creating the item." */, &initialAccess);
        if (err != noErr) {
            NSLog(@"SecAccessCreate -> %d", (int)err);
        }
        
        SInt32 bitsize = 8 * (int)CFDataGetLength(keymaterial);
        CFNumberRef num = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitsize);
        const void *itkeys[] = {
            /* kSecUseKeychain, */ kSecAttrKeyType, kSecAttrKeySizeInBits, kSecAttrLabel,
            kSecAttrCanEncrypt, kSecAttrCanDecrypt, kSecAttrCanWrap, kSecAttrCanUnwrap,
            kSecAttrAccess
        };
        const void *itvals[] = {
            /* kcRef, */ kSecAttrKeyTypeAES, num, CFSTR("Temporary Keychain Entry"),
            kCFBooleanFalse, kCFBooleanFalse, kCFBooleanTrue, kCFBooleanTrue,
            initialAccess
        };
        _Static_assert(arraycount(itkeys) == arraycount(itvals), "");
        CFDictionaryRef attrs = CFDictionaryCreate(kCFAllocatorDefault, itkeys, itvals, arraycount(itkeys), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
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
            
            attrs[attrCount++] = (SecKeychainAttribute){ kSecKeyLabel, (UInt32)CFDataGetLength(keylabel), (void *)CFDataGetBytePtr(keylabel) };

            displayBytes = CFBridgingRetain([displayName dataUsingEncoding:NSUTF8StringEncoding]);
            attrs[attrCount++] = (SecKeychainAttribute){ kSecKeyPrintName, (UInt32)CFDataGetLength(displayBytes), (void *)CFDataGetBytePtr(displayBytes) };
        }
        
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

static OSStatus removeItemFromKeychain(SecKeychainItemRef keyRef)
{
    const void *kk[1] = { kSecValueRef };
    const void *vv[1] = { keyRef };
    CFDictionaryRef del = CFDictionaryCreate(kCFAllocatorDefault, kk, vv, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    OSStatus result = SecItemDelete(del);
    CFRelease(del);
    return result;
}

#endif


#if 0
static OSStatus removeDerivations(CFStringRef attrKey, NSData *attrValue)
{
    const void *keys[3] = { kSecClass, kSecAttrKeyClass, attrKey };
    const void *vals[3] = { kSecClassKey, kSecAttrKeyClassSymmetric, (__bridge CFDataRef)attrValue };
    
    CFDictionaryRef query = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    OSStatus err = SecItemDelete(query);
    CFRelease(query);
    
    return err;
}
#endif

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
        CFDictionaryRef query = CFDictionaryCreate(kCFAllocatorDefault, ks, vs, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        result = NULL;
        kerr = SecItemCopyMatching(query, &result);
        CFRelease(query);
    }
    
    if (kerr == errSecParam || kerr == errSecItemNotFound) {
        /* Try again, using the documented parameters */
        ks[1] = kSecMatchItemList;
        vs[1] = CFArrayCreate(kCFAllocatorDefault, &(vs[1]), 1, &kCFTypeArrayCallBacks);
        CFDictionaryRef query = CFDictionaryCreate(kCFAllocatorDefault, ks, vs, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
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

#endif

@end


