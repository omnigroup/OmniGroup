// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSDocumentKey-Internal.h"

#import <Security/Security.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDocumentKey-KeychainStorageSupport.h>
#import <OmniFileStore/OFSEncryptionConstants.h>
#import <OmniFileStore/OFSSegmentedEncryptionWorker.h>
#import "OFSEncryption-Internal.h"
#include <stdlib.h>


#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
#import <CommonCrypto/CommonRandom.h>
#endif

RCS_ID("$Id$");

OB_REQUIRE_ARC

static BOOL traverseSlots(NSData *slots, BOOL (^cb)(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *start, size_t len));
static uint16_t chooseUnusedSlot(NSIndexSet *used);
static uint16_t derive(uint8_t derivedKey[MAX_SYMMETRIC_KEY_BYTES], NSString *password, NSData *salt, CCPseudoRandomAlgorithm prf, unsigned int rounds, NSError **outError);
static NSData *deriveFromPassword(NSDictionary *docInfo, NSString *password, struct skbuf *outWk, NSError **outError);

#if 0 && !(defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE)
/* iOS doesn't have the concept of a keychain item ref */
static OSStatus removeItemFromKeychain(SecKeychainItemRef keyRef);
#endif

#define unsupportedError(e, t) ofsUnsupportedError_(e, __LINE__, t)
#define arraycount(a) (sizeof(a)/sizeof(a[0]))

static const char * const zeroes = "\0\0\0\0\0\0\0\0";

/* String names read/written to the file */
static const struct { CFStringRef name; CCPseudoRandomAlgorithm value; } prfNames[] = {
    { CFSTR(PBKDFPRFSHA1),   kCCPRFHmacAlgSHA1   },
    { CFSTR(PBKDFPRFSHA256), kCCPRFHmacAlgSHA256 },
    { CFSTR(PBKDFPRFSHA512), kCCPRFHmacAlgSHA512 },
};

/* These are used for debugging / logging */
static const char * const slotTypeNames[] = {
    [SlotTypeNone]                 = "None",
    [SlotTypeActiveAESWRAP]        = "AESWRAP",
    [SlotTypeRetiredAESWRAP]       = "AESWRAP",
    [SlotTypeActiveAES_CTR_HMAC]   = "AES_CTR_HMAC",
    [SlotTypeRetiredAES_CTR_HMAC]  = "AES_CTR_HMAC",
    [SlotTypePlaintextMask]        = "PlaintextMask",
    [SlotTypeRetiredPlaintextMask] = "TemporaryPlaintextMask"
};
static const char *nameOfSlotType(enum OFSDocumentKeySlotType tp)
{
    if ((int)tp >= 0 && (size_t)tp < arraycount(slotTypeNames)) {
        return slotTypeNames[tp];
    } else {
        return NULL;
    }
}

@implementation OFSDocumentKey

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

- (NSData *)data;
{
    /* Return an NSData blob with the information we'll need to recover the document key in the future. The caller will presumably store this blob in the underlying file manager or somewhere related, and hand it back to us via -initWithData:error:. */
    NSArray *docInfo = [NSArray arrayWithObject:passwordDerivation];
    return [NSPropertyListSerialization dataWithPropertyList:docInfo format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OBASSERT([self isMemberOfClass:[OFSDocumentKey class]]);  // Make sure we're exactly an OFSDocumentKey, not an OFSMutableDocumentKey
    return self;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone
{
    OFSDocumentKey *newInstance = [[OFSMutableDocumentKey alloc] init];
    newInstance->passwordDerivation = [passwordDerivation copy];
    newInstance->buf = [buf copy];
    newInstance->wk = wk;
    newInstance->_prefix = _prefix;
    
    return newInstance;
}

- (NSInteger)changeCount;
{
    return 0;
}

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
                     @"Could not parse key slots");

            return NO;
        }
        
        buf = derivedKey;
        return YES;
    } else {
        // If we got a password but the derivation failed with a decode error, wrap that up in our own bad-password error
        // Note that the kCCDecodeError code here is actually set by other OFS bits – per unwrapData() in OFSDocumentKey.m, CCSymmetricKeyUnwrap() can return bad codes, so we substitute a better code there
        if (outError && [*outError hasUnderlyingErrorDomain:NSOSStatusErrorDomain code:kCCDecodeError]) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Incorrect encryption password.", @"OmniFileStore", OMNI_BUNDLE, @"bad password error description");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"Could not decode encryption document key.", @"OmniFileStore", OMNI_BUNDLE, @"bad password error reason");
            OFSErrorWithInfo(outError, OFSEncryptionNeedAuth, description, reason, OFSEncryptionWrongPassword, password, nil);
        }
        
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
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:errSecAuthFailed
                                        userInfo:@{ NSLocalizedFailureReasonErrorKey: @"Missing password" }];
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
    
    id prfString = [docInfo objectForKey:PBKDFPRFKey defaultObject:@"" PBKDFPRFSHA1];
    CCPseudoRandomAlgorithm prf = 0;
    for (int i = 0; i < (int)arraycount(prfNames); i++) {
        if ([prfString isEqualToString:(__bridge NSString *)(prfNames[i].name)]) {
            prf = prfNames[i].value;
            break;
        }
    }
    if (prf == 0) {
        OFSErrorWithInfo(outError, OFSEncryptionBadFormat,
                         NSLocalizedStringFromTableInBundle(@"Could not decrypt file.", @"OmniFileStore", OMNI_BUNDLE, @"error description"),
                         NSLocalizedStringFromTableInBundle(@"Unrecognized settings in encryption header", @"OmniFileStore", OMNI_BUNDLE, @"error detail"),
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
    NSData *retval = unwrapData(wrappingKey, wrappingKeyLength, wrappedKey, outError);
    
    if (!retval)
        return nil;
    
    outWk->len = wrappingKeyLength;
    memcpy(outWk->bytes, wrappingKey, wrappingKeyLength);
    memset(wrappingKey, 0, sizeof(wrappingKey));
    
    return retval;
}

NSData *unwrapData(const uint8_t *wrappingKey, size_t wrappingKeyLength, NSData *wrappedData, NSError **outError)
{
    if (wrappingKeyLength != kCCKeySizeAES128 &&
        wrappingKeyLength != kCCKeySizeAES192 &&
        wrappingKeyLength != kCCKeySizeAES256) {
        if (outError) {
            *outError = ofsWrapCCError(kCCParamError, @"CCSymmetricKeyUnwrap", @"kekLen", @( wrappingKeyLength ));
        }
        return nil;
    }
    
    size_t wrappedDataLength = [wrappedData length];
    size_t unwrappedDataLength = CCSymmetricUnwrappedSize(kCCWRAPAES, wrappedDataLength);
    void *localData = malloc(MAX(unwrappedDataLength, wrappedDataLength));
    size_t unwrapt = unwrappedDataLength;
    CCCryptorStatus cerr = CCSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen,
                                                wrappingKey, wrappingKeyLength,
                                                [wrappedData bytes], wrappedDataLength,
                                                localData, &unwrapt);
    /* Note that RFC3394-style key wrapping does effectively include a check field --- if we pass an incorrect wrapping key, or the wrapped key is bogus or something, it should fail. (This is tested by OFUnitTests/OFCryptoTest.m) */
    if (cerr) {
        free(localData);
        if (cerr < 0 && cerr > -4000) {
            // CCSymmetricKeyUnwrap() returns bogus error codes.
            cerr = kCCDecodeError;
        }
        if (outError)
            *outError = ofsWrapCCError(cerr, @"CCSymmetricKeyUnwrap", nil, nil);
        return nil;
    } else {
        return [NSData dataWithBytesNoCopy:localData length:unwrappedDataLength freeWhenDone:YES];
    }
}

/* Return an encryption worker for an active key slot. Encryption workers can be used from multiple threads, so we can safely cache one and return it here. */
- (nullable OFSSegmentEncryptWorker *)encryptionWorker;
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
                    reusableEncryptionWorker.keySlot    = sn;
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

BOOL validateSlots(NSData *slots)
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

/* Appends an entry to the keyslots array. If slotcontents is NULL, then CCRandomGenerateBytes() is called. */
static void fillSlot(NSMutableData *slotbuffer, uint8_t slottype, const char *slotcontents, unsigned slotlength, uint16_t slotnumber)
{
    if (slotlength > (4 * 255))
        abort();
    uint8_t lengthInQuads = (uint8_t)((slotlength + 3) / 4);
    uint8_t newslot[4 + 4*lengthInQuads];
    newslot[0] = slottype;
    newslot[1] = lengthInQuads;
    OSWriteBigInt16(newslot, 2, slotnumber);
    memset(newslot+4, 0, 4*lengthInQuads);
    
    if (slotcontents) {
        memcpy(newslot+4, slotcontents, slotlength);
    }
    
    [slotbuffer replaceBytesInRange:(NSRange){0, 0} withBytes:newslot length:sizeof(newslot)];
    
    if (!slotcontents) {
        NSError *e = NULL;
        if (!randomBytes([slotbuffer mutableBytes]+4, slotlength, &e)) {
            [NSException raise:NSGenericException
                        format:@"Failure generating random data: %@", [e description]];
        }
    }
}

- (NSIndexSet *)retiredKeySlots;
{
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
    traverseSlots(buf, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength){
        if (tp != SlotTypeNone && (tp & 1) == 0) {
            [result addIndex:sn];
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

- (enum OFSDocumentKeySlotType)typeOfKeySlot:(NSUInteger)slot;
{
    // This is just used to let the unit tests check that things are behaving as expected
    
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    __block enum OFSDocumentKeySlotType slotType = SlotTypeNone;
    traverseSlots(buf, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength){
        if (sn == slot) {
            slotType = tp;
            return YES;
        }
        return NO;
    });
    
    return slotType;
}

- (unsigned)flagsForFilename:(NSString *)filename fromSlot:(int *)outSlotNumber;
{
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    const char *bytes = [filename UTF8String];
    size_t len = strlen(bytes);
    
    __block unsigned flags = 0;
    BOOL satisfied = traverseSlots(buf, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength){
        if (tp == SlotTypePlaintextMask || tp == SlotTypeRetiredPlaintextMask) {
            /* Remove the trailing NULs that might have been added to pad to an integer number of quads */
            while (keylength > 0 && (((const char *)keydata)[keylength-1]) == 0) {
                keylength --;
            }
            /* Check whether this item matches the filename in question */
            if (keylength <= len && (0 == memcmp(keydata, bytes + (len - keylength), keylength))) {
                /* Yep. Update the flags accordingly. */
                if (tp == SlotTypePlaintextMask)
                    flags |= OFSDocKeyFlagAllowUnencryptedRead | OFSDocKeyFlagAlwaysUnencryptedWrite;
                if (tp == SlotTypeRetiredPlaintextMask)
                    flags |= OFSDocKeyFlagAllowUnencryptedRead;
                if (outSlotNumber)
                    *outSlotNumber = sn;
                // NSLog(@"flagsForFilename %@: slot type %d, result 0x%02X, slot data '%.*s'", filename, tp, flags, (int)keylength, keydata);
                return YES;
            }
        }
        return NO;
    });
    
    if (!satisfied && outSlotNumber)
        *outSlotNumber = -1;
    
    return flags;
}

- (NSString *)suffixForSlot:(NSUInteger)slotnum;  // Only used by the unit tests
{
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    __block NSString *result = nil;
    traverseSlots(buf, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength){
        if (sn == slotnum && (tp == SlotTypePlaintextMask || tp == SlotTypeRetiredPlaintextMask)) {
            /* Remove the trailing NULs that might have been added to pad to an integer number of quads */
            while (keylength > 0 && (((const char *)keydata)[keylength-1]) == 0) {
                keylength --;
            }
            result = [[NSString alloc] initWithBytes:keydata length:keylength encoding:NSUTF8StringEncoding];
            return YES;
        }
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

- (ssize_t)unwrapFileKey:(NSData *)fileKeyInfo into:(uint8_t *)buffer length:(size_t)unwrappedKeyBufferLength error:(NSError **)outError;
{
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    NSInteger wrappedFileKeyInfoLen = [fileKeyInfo length];
    const unsigned char *wrappedFileKeyInfo = [fileKeyInfo bytes];
    
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
        }

        if (tp == SlotTypeActiveAES_CTR_HMAC || tp == SlotTypeRetiredAES_CTR_HMAC) {
            /* We've found a directly stored AES+HMAC key set */
            if (unwrappedKeyBufferLength < keylength || wrappedFileKeyInfoLen > 2) {
                /* Inapplicable! */
                unsupportedError(&localError, @"invalid length");
                return YES;
            }
            memcpy(buffer, keydata, keylength);
            result = keylength;
            return YES;
        }
        
        /* We found an applicable slot, but don't know how to use it. This could be due to a future version using an algorithm we don't know about, or it could be due to a file using a key slot that isn't applicable for encryption like the plaintext mask slots. */
        const char *slotTypeName = nameOfSlotType(tp);
        NSString *msg;
        if (slotTypeName) {
            msg = [NSString stringWithFormat:@"Unexpected key type (%s/%d) for encryption slot %u", slotTypeName, tp, sn];
        } else {
            msg = [NSString stringWithFormat:@"Unknown key type (%d) for slot %u", tp, sn];
        }
        localError = [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionBadFormat userInfo:@{ NSLocalizedDescriptionKey: msg }];
        return YES;
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

- (NSDictionary *)descriptionDictionary;   // For the UI. See keys below.
{
    NSMutableDictionary *description = [NSMutableDictionary dictionary];
    
    if (buf) {
        NSMutableArray *keys = [NSMutableArray array];
        NSMutableArray *ptsuffs = [NSMutableArray array];
        NSMutableArray *tmpsuffs = [NSMutableArray array];
        
        traverseSlots(buf, ^BOOL(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength) {
            if (tp == SlotTypePlaintextMask || tp == SlotTypeRetiredPlaintextMask) {
                /* Remove the trailing NULs that might have been added to pad to an integer number of quads */
                while (keylength > 0 && (((const char *)keydata)[keylength-1]) == 0) {
                    keylength --;
                }
                NSString *suff = [[NSString alloc] initWithBytes:keydata length:keylength encoding:NSUTF8StringEncoding];
                [ (tp == SlotTypePlaintextMask? ptsuffs : tmpsuffs) addObject:suff];
            } else {
                const char *name = nameOfSlotType(tp);
                [keys addObject:@{
                                  OFSDocKeyDescription_Key_TypeName: ( name? [NSString stringWithCString:name encoding:NSUTF8StringEncoding] : @((int)tp) ),
                                  OFSDocKeyDescription_Key_Active: [NSNumber numberWithBool:( (tp & 1)? YES : NO)],
                                  OFSDocKeyDescription_Key_Identifier: @((int)sn)
                                  }];
            }
            
            return NO; // NO = don't stop traversing
        });
        
        [description setObject:keys forKey:OFSDocKeyDescription_KeyList];
        [description setObject:ptsuffs forKey:OFSDocKeyDescription_PlaintextSuffixes];
        [description setObject:tmpsuffs forKey:OFSDocKeyDescription_TemporaryPlaintextSuffixes];
    }
    
    if (passwordDerivation) {
        [description setObject:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Password (%@; %@ rounds; %@)", @"OmniFileStore", OMNI_BUNDLE, @"encryption access method description - key derivation from password"),
                                [passwordDerivation objectForKey:PBKDFAlgKey],
                                [passwordDerivation objectForKey:PBKDFRoundsKey],
                                [passwordDerivation objectForKey:PBKDFPRFKey defaultObject:@"" PBKDFPRFSHA1]]
                        forKey:OFSDocKeyDescription_AccessMethod];
    }
    
    return description;
}

#pragma mark Key identification

- (NSData *)applicationLabel;
{
    if (!passwordDerivation)
        return nil;
    
    /* We generate a unique application label for each key we store, using the salt as the unique identifier. */
    
    if ([[passwordDerivation objectForKey:PBKDFAlgKey] isEqualToString:PBKDFAlgPBKDF2_WRAP_AES]) {
        
        NSData *salt = [passwordDerivation objectForKey:PBKDFSaltKey];
        if (!salt)
            return nil;
        NSString *prf = [passwordDerivation objectForKey:PBKDFPRFKey defaultObject:@"" PBKDFPRFSHA1];
        
        NSMutableData *label = [[[NSString stringWithFormat:@"PBKDF2$%@$", prf] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        
        if (_prefix) {
            [label replaceBytesInRange:(NSRange){0,0} withBytes:":" length:1];
            [label replaceBytesInRange:(NSRange){0,0} withBytes:_prefix length:strlen(_prefix)];
        }
        
        [label appendData:salt];
        
        return label;
    }
    
    return nil;
}

@end

#pragma mark -

@implementation OFSMutableDocumentKey
{
    /* Incremented when -data changes */
    NSInteger changeCount;
}

- (instancetype)init
{
    return [super initWithData:nil error:NULL];
}

- (instancetype)initWithAuthenticator:(OFSDocumentKey *)source error:(NSError **)outError;
{
    self = [self init];
    
    if (!(source.valid)) {
        unsupportedError(outError, @"source.valid = NO");
        return nil;
    }
    
    passwordDerivation = source->passwordDerivation;
    buf = [NSData data];
    memcpy(&wk, &(source->wk), sizeof(wk));
    
    return self;
}

- (id)copyWithZone:(NSZone *)zone;
{
    OFSDocumentKey *newInstance = [[OFSDocumentKey alloc] initWithData:nil error:NULL];
    newInstance->passwordDerivation = [passwordDerivation copy];
    newInstance->buf = [buf copy];
    newInstance->wk = wk;
    newInstance->_prefix = _prefix;
    
    return newInstance;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone
{
    OFSMutableDocumentKey *newInstance = [super mutableCopyWithZone:zone];
    newInstance->changeCount = changeCount;
    
    return newInstance;
}

@synthesize changeCount = changeCount;

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

/* Key rollover: this updates the receiver to garbage-collect any slots not mentioned in keepThese, and if retireCurrent=YES, mark any active keys as inactive (and generate new active keys as needed). If keepThese is nil, no keys are discarded (if you want to discard everything, pass a non-nil index set containing no indices). */
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
        if (retire && (tp == SlotTypeActiveAES_CTR_HMAC || tp == SlotTypeActiveAESWRAP)) {
            tp += 1; // Retired slot types are paired with active
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
                fillSlot(newBuffer, SlotTypeActiveAESWRAP, NULL, kCCKeySizeAES128, chooseUnusedSlot(usedSlots));
                break;
            case SlotTypeActiveAES_CTR_HMAC:
                fillSlot(newBuffer, SlotTypeActiveAES_CTR_HMAC, NULL, SEGMENTED_INNER_LENGTH, chooseUnusedSlot(usedSlots));
                break;
            default:
                OBRejectInvalidCall(self, _cmd, @"bad ensureSlot value");
                break;
        }
    }
    
    [self _updateInner:newBuffer];
}

- (void)_updateInner:(NSData *)newBuffer
{
    if (buf && [buf isEqual:newBuffer]) {
        /* This can be a no-op if retire=NO and all keys are listed in keepThese */
        return;
    }
    
    buf = [newBuffer copy];
    changeCount ++;
    
    if (passwordDerivation) {
        NSData *reWrapped = [self _rewrap];
        passwordDerivation = [passwordDerivation dictionaryWithObject:reWrapped forKey:DocumentKeyKey];
    }
}

- (void)setDisposition:(enum OFSEncryptingFileManagerDisposition)disposition forSuffix:(NSString *)ext;
{
    if (!buf)
        OBRejectInvalidCall(self, _cmd, @"not currently valid");
    
    NSMutableData *newBuffer = [buf mutableCopy];
    
    NSMutableIndexSet *usedSlots = [NSMutableIndexSet indexSet];
    traverseSlots(newBuffer, ^(enum OFSDocumentKeySlotType tp, uint16_t sn, const void *keydata, size_t keylength){
        [usedSlots addIndex:sn];
        return NO;
    });
    
    uint16_t slotnumber = chooseUnusedSlot(usedSlots);
    NSData *contents = [[ext precomposedStringWithCanonicalMapping] dataUsingEncoding:NSUTF8StringEncoding];
    if ([contents length] > 65535)
        OBRejectInvalidCall(self, _cmd, @"excessively long mask");
    
    switch(disposition) {
        case OFSEncryptingFileManagerDispositionPassthrough:
            fillSlot(newBuffer, SlotTypePlaintextMask, [contents bytes], (unsigned)[contents length], slotnumber);
            break;
        case OFSEncryptingFileManagerDispositionTemporarilyReadPlaintext:
            fillSlot(newBuffer, SlotTypeRetiredPlaintextMask, [contents bytes], (unsigned)[contents length], slotnumber);
            break;
    }
    
    [self _updateInner:newBuffer];
}


@end


