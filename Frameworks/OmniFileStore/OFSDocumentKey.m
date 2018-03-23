// Copyright 2014-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSDocumentKey-Internal.h"

#import <Security/Security.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSData-OFEncoding.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSIndexSet-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFSymmetricKeywrap.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSDocumentKey-KeychainStorageSupport.h>
#import <OmniFileStore/OFSEncryptionConstants.h>
#import <OmniFileStore/OFSSegmentedEncryptionWorker.h>
#import "OFSEncryption-Internal.h"
#include <stdlib.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

static uint16_t derive(uint8_t derivedKey[MAX_SYMMETRIC_KEY_BYTES], NSString *password, NSData *salt, CCPseudoRandomAlgorithm prf, unsigned int rounds, NSError **outError);
static OFSKeySlots *deriveFromPassword(NSDictionary *docInfo, NSString *password, struct skbuf *outWk, NSError **outError);

#define unsupportedError(e, t) ofsUnsupportedError_(e, __LINE__, t)
#define arraycount(a) (sizeof(a)/sizeof(a[0]))

/* String names read/written to the file */
static const struct { CFStringRef name; CCPseudoRandomAlgorithm value; } prfNames[] = {
    { CFSTR(PBKDFPRFSHA1),   kCCPRFHmacAlgSHA1   },
    { CFSTR(PBKDFPRFSHA256), kCCPRFHmacAlgSHA256 },
    { CFSTR(PBKDFPRFSHA512), kCCPRFHmacAlgSHA512 },
};

@implementation OFSDocumentKeyDerivationParameters

- initWithAlgorithm:(NSString *)algorithm rounds:(unsigned)rounds salt:(NSData *)salt pseudoRandomAlgorithm:(NSString *)pseudoRandomAlgorithm;
{
    _algorithm = [algorithm copy];
    _rounds = rounds;
    _salt = [salt copy];
    _pseudoRandomAlgorithm = [pseudoRandomAlgorithm copy];

    return self;
}

- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

- (BOOL)isEqual:(id)otherObject;
{
    if (![otherObject isKindOfClass:[OFSDocumentKeyDerivationParameters class]]) {
        return NO;
    }
    OFSDocumentKeyDerivationParameters *otherParameters = otherObject;
    return [_algorithm isEqual:otherParameters.algorithm] && _rounds == otherParameters.rounds && [_salt isEqual:otherParameters.salt] && [_pseudoRandomAlgorithm isEqual:otherParameters.pseudoRandomAlgorithm];
}

- (NSString *)description;
{
    return [NSString stringWithFormat:@"<%@:%p algorithm:%@ rounds:%u salt:%@ pseudoRandomAlgorithm:%@>", NSStringFromClass([self class]), self, _algorithm, _rounds, [_salt unadornedLowercaseHexString], _pseudoRandomAlgorithm];
}

@end


@interface OFSMutableDocumentKey ()
- (instancetype)_init;
@end

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
    NSError * __autoreleasing serializationError = nil;
    NSData *serialized = [NSPropertyListSerialization dataWithPropertyList:docInfo format:NSPropertyListXMLFormat_v1_0 options:0 error:&serializationError];
    if (!serialized) {
        /* This really shouldn't ever happen, since we generate the plist ourselves. Throw an exception instead of propagating the error. */
        [NSException exceptionWithName:NSInternalInconsistencyException reason:@"OFSDocumentKey: unable to serialize" userInfo:@{ @"error": serializationError }];
    }
    
    /* clang-sa doesn't recognize the throw above, so cast this as non-null to avoid an analyzer false positive */
    return (NSData * _Nonnull)serialized;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OBASSERT([self isMemberOfClass:[OFSDocumentKey class]]);  // Make sure we're exactly an OFSDocumentKey, not an OFSMutableDocumentKey
    return self;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone
{
    OFSDocumentKey *newInstance = [[OFSMutableDocumentKey alloc] _init];
    newInstance->passwordDerivation = [passwordDerivation copy];
    newInstance->slots = [slots copy];
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
    return (slots != nil)? YES : NO;
}

@synthesize keySlots = slots;

#pragma mark Passphrase handling and wrapping/unwrapping

- (BOOL)hasPassword;
{
    return (passwordDerivation != nil)? YES : NO;
}

- (OFSDocumentKeyDerivationParameters *)passwordDerivationParameters:(NSError **)outError;
{
    return keyDerivationParametersFromDocumentInfo(passwordDerivation, outError);
}

static void _incorrectPassword(NSError **outError, id inputValue)
{
    // If we got a password but the derivation failed with a decode error, wrap that up in our own bad-password error
    // Note that the kCCDecodeError code here is actually set by other OFS bits – per unwrapData() in OFSDocumentKey.m, CCSymmetricKeyUnwrap() can return bad codes, so we substitute a better code there
    // (If the CommonCrypto unwrap function is someday updated to conform to its own documentation, it will return kCCDecodeError naturally)
    if (outError && [*outError hasUnderlyingErrorDomain:NSOSStatusErrorDomain code:kCCDecodeError]) {
        id wrongPasswordInfoValue;
#if defined(DEBUG)
        wrongPasswordInfoValue = inputValue;
#else
        wrongPasswordInfoValue = @YES;
#endif

        NSString *description = NSLocalizedStringFromTableInBundle(@"Incorrect encryption password.", @"OmniFileStore", OMNI_BUNDLE, @"bad password error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Could not decode encryption document key.", @"OmniFileStore", OMNI_BUNDLE, @"bad password error reason");
        OFSErrorWithInfo(outError, OFSEncryptionNeedAuth, description, reason, OFSEncryptionWrongPassword, wrongPasswordInfoValue, nil);
    }

}

- (BOOL)deriveWithPassword:(NSString *)password error:(NSError **)outError;
{
    OFSKeySlots *derivedKeyTable = deriveFromPassword(passwordDerivation, password, &wk, outError);
    if (derivedKeyTable && wk.len) {
        slots = derivedKeyTable;
        return YES;
    } else {
        _incorrectPassword(outError, password);
        return NO;
    }
}

// Here, the assumption is that the password+parameters -> wrappingKey was done externally.
- (BOOL)deriveWithWrappingKey:(NSData *)wrappingKey error:(NSError **)outError;
{
    OFSKeySlots *derivedKeyTable = deriveFromWrappingKey(passwordDerivation, wrappingKey, &wk, outError);
    if (derivedKeyTable && wk.len) {
        slots = derivedKeyTable;
        return YES;
    } else {
        _incorrectPassword(outError, wrappingKey);
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

static OFSDocumentKeyDerivationParameters *keyDerivationParametersFromDocumentInfo(NSDictionary *docInfo, NSError **outError)
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

    NSString *prfString = [docInfo objectForKey:PBKDFPRFKey defaultObject:@"" PBKDFPRFSHA1];
    if (![prfString isKindOfClass:[NSString class]]) {
        unsupportedError(outError, NSStringFromClass([prfString class]));
        return nil;
    }

    return [[OFSDocumentKeyDerivationParameters alloc] initWithAlgorithm:alg rounds:pbkdfRounds salt:salt pseudoRandomAlgorithm:prfString];
}

static OFSKeySlots *deriveFromWrappingKey(NSDictionary *docInfo, NSData *wrappingKey, struct skbuf *outWk, NSError **outError)
{
    NSData *wrappedKey = [docInfo objectForKey:DocumentKeyKey];

    /* Unwrap the document key(s) using the key-wrapping-key */
    const uint8_t *wrappingKeyBytes = (const uint8_t *)[wrappingKey bytes];
    size_t wrappingKeyLength = [wrappingKey length];
    OFSKeySlots *retval = [[OFSKeySlots alloc] initWithData:wrappedKey wrappedWithKey:wrappingKeyBytes length:wrappingKeyLength error:outError];

    if (retval) {
        OBASSERT(wrappingKeyLength <= UINT16_MAX);
        outWk->len = (uint16_t)wrappingKeyLength;
        memcpy(outWk->bytes, wrappingKeyBytes, wrappingKeyLength);
    }

    // TODO: Not wiping the wrapping key -- might be nice to have a NSData subclass that memsets itself in -dealloc, but we're making a copy of it above anyway, so...
    // memset(wrappingKey, 0, sizeof(wrappingKey));

    return retval;
}

+ (NSData *)wrappingKeyFromPassword:(NSString *)password parameters:(OFSDocumentKeyDerivationParameters *)parameters error:(NSError **)outError;
{
    NSString *prfString = parameters.pseudoRandomAlgorithm;
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

    /* Derive the key-wrapping-key from the user's password */
    uint8_t wrappingKey[MAX_SYMMETRIC_KEY_BYTES];
    uint16_t wrappingKeyLength = derive(wrappingKey, password, parameters.salt, prf, parameters.rounds, outError);
    if (!wrappingKeyLength) {
        return nil;
    }

    return [NSData dataWithBytes:wrappingKey length:wrappingKeyLength];
}

static OFSKeySlots *deriveFromPassword(NSDictionary *docInfo, NSString *password, struct skbuf *outWk, NSError **outError)
{
    OFSDocumentKeyDerivationParameters *parameters = keyDerivationParametersFromDocumentInfo(docInfo, outError);
    if (!parameters) {
        return nil;
    }

    NSData *wrappingKey = [OFSDocumentKey wrappingKeyFromPassword:password parameters:parameters error:outError];
    if (!wrappingKey) {
        return nil;
    }

    NSData *wrappedKey = [docInfo objectForKey:DocumentKeyKey];

    /* Unwrap the document key(s) using the key-wrapping-key */
    const uint8_t *wrappingKeyBytes = (const uint8_t *)[wrappingKey bytes];
    size_t wrappingKeyLength = [wrappingKey length];
    OFSKeySlots *retval = [[OFSKeySlots alloc] initWithData:wrappedKey wrappedWithKey:wrappingKeyBytes length:wrappingKeyLength error:outError];
    
    if (retval) {
        OBASSERT(wrappingKeyLength <= UINT16_MAX);
        outWk->len = (uint16_t)wrappingKeyLength;
        memcpy(outWk->bytes, wrappingKeyBytes, wrappingKeyLength);
    }
    
    // TODO: Not wiping the wrapping key -- might be nice to have a NSData subclass that memsets itself in -dealloc, but we're making a copy of it above anyway, so...
    // memset(wrappingKey, 0, sizeof(wrappingKey));

    return retval;
}

#pragma mark Non-passphrase unwrapping

- (BOOL)borrowUnwrappingFrom:(OFSDocumentKey *)otherKey;
{
    if (!otherKey)
        return NO;
    
    if (!otherKey.valid)
        return NO;
    
    NSDictionary *otherDerivation = otherKey->passwordDerivation;
    NSString *myMethod = [passwordDerivation objectForKey:KeyDerivationMethodKey];
    NSData *wrappedKeys;
    
    // This method is just a shortcut for re-using a known password without repeating the time-consuming PBKDF2 step.
    // So make sure that the resulting unwrapped-and-rewrapped blob probably still makes sense.
    if ([myMethod isEqual:KeyDerivationMethodPassword]) {
        if (![[otherDerivation objectForKey:KeyDerivationMethodKey] isEqual:KeyDerivationMethodPassword])
            return NO;
        if (![[passwordDerivation objectForKey:PBKDFAlgKey] isEqual:[otherDerivation objectForKey:PBKDFAlgKey]])
            return NO;
        if (![[passwordDerivation objectForKey:PBKDFSaltKey] isEqual:[otherDerivation objectForKey:PBKDFSaltKey]])
            return NO;
        if (![[passwordDerivation objectForKey:PBKDFPRFKey] isEqual:[otherDerivation objectForKey:PBKDFPRFKey]])
            return NO;
        
        wrappedKeys = [passwordDerivation objectForKey:DocumentKeyKey];
    } else if ([myMethod isEqual:KeyDerivationStatic]) {
        // The "static" pseudo-method doesn't care where the wrapping key came from.
        wrappedKeys = [passwordDerivation objectForKey:StaticKeyKey];
    } else {
        // We don't currently have any other key derivation methods, so we don't know how to get the wrapped key from them.
        return NO;
    }
    
    OFSKeySlots *unwrapped = [[OFSKeySlots alloc] initWithData:wrappedKeys wrappedWithKey:otherKey->wk.bytes length:otherKey->wk.len error:NULL];
    if (!unwrapped) {
        // The other document key was wrapped with a different password, passphrase, salt, or something.
        return NO;
    }
    
    // Success: we've recovered the KEK (and the wrapped keys as well).
    // Continue as if -deriveWithPassword: had been called with the correct password.
    memcpy(&wk, &(otherKey->wk), sizeof(wk));
    slots = unwrapped;
    return YES;
}

#pragma mark Client usage

/* Return an encryption worker for an active key slot. Encryption workers can be used from multiple threads, so we can safely cache one and return it here. */
- (nullable OFSSegmentEncryptWorker *)encryptionWorker:(NSError **)outError;
{
    OFSKeySlots *localSlots = self.keySlots;
    
    if (!localSlots) {
        if (outError)
            *outError = [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionNeedAuth userInfo:nil];
        return nil;
    }
    
    return [localSlots encryptionWorker:outError];
}

- (unsigned)flagsForFilename:(NSString *)filename;
{
    return [self.keySlots flagsForFilename:filename fromSlot:NULL];
}

- (NSString *)description;
{
    return [NSString stringWithFormat:@"<%@:%p slots=%@>", NSStringFromClass([self class]), self, [self.keySlots description]];
}

- (NSDictionary *)descriptionDictionary;   // For the UI. See keys below.
{
    NSMutableDictionary *description = [NSMutableDictionary dictionary];

    NSDictionary *slotInfo = [slots descriptionDictionary];
    if (slotInfo)
        [description addEntriesFromDictionary:slotInfo];
    
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
    OFSMutableKeySlots *mutableSlots;
    
    /* Incremented when -data changes */
    NSInteger additionalChangeCount;
}

- (instancetype)_init
{
    return [super initWithData:nil error:NULL];
}

- (instancetype)init
{
    return [self initWithData:nil error:NULL];
}

- initWithData:(NSData *)storeData error:(NSError **)outError;
{
    if (!(self = [super initWithData:storeData error:outError])) {
        return nil;
    }
    
    // Unlike an immutable key, initializing a mutable key with no data produces a valid, but empty, key table.
    if (!storeData) {
        OBASSERT(!slots);
        mutableSlots = [[OFSMutableKeySlots alloc] init];
    }
    
    return self;
}

- (instancetype)initWithAuthenticator:(OFSDocumentKey *)source error:(NSError **)outError;
{
    self = [self init];
    
    if (!(source.valid)) {
        unsupportedError(outError, @"source.valid = NO");
        return nil;
    }
    
    passwordDerivation = [source->passwordDerivation dictionaryWithObjectRemovedForKey:DocumentKeyKey];
    slots = nil;
    mutableSlots = [[OFSMutableKeySlots alloc] init];
    memcpy(&wk, &(source->wk), sizeof(wk));
    
    return self;
}

- (id)copyWithZone:(NSZone *)zone;
{
    [self _updateInner];
    OFSDocumentKey *newInstance = [[OFSDocumentKey alloc] initWithData:nil error:NULL];
    newInstance->passwordDerivation = [passwordDerivation copy];
    newInstance->slots = [slots copy];
    newInstance->wk = wk;
    newInstance->_prefix = _prefix;
    
    return newInstance;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone
{
    [self _updateInner];
    OFSMutableDocumentKey *newInstance = [super mutableCopyWithZone:zone];
    newInstance->additionalChangeCount = additionalChangeCount;
    
    return newInstance;
}

- (OFSKeySlots *)keySlots;
{
    [self _updateInner];
    return super.keySlots;
}

- (NSData *)data;
{
    [self _updateInner];
    return super.data;
}

- (BOOL)valid;
{
    return (slots != nil || mutableSlots != nil)? YES : NO;
}

- (OFSMutableKeySlots *)mutableKeySlots;
{
    [self _makeMutableSlots:_cmd];
    return mutableSlots;
}

- (BOOL)deriveWithPassword:(NSString *)password error:(NSError **)outError;
{
    slots = nil;
    mutableSlots = nil;
    return [super deriveWithPassword:password error:outError];
}

- (NSString *)description;
{
    if (mutableSlots) {
        return [NSString stringWithFormat:@"<%@:%p cc=%" PRIdNS " mutableSlots=%@>", NSStringFromClass([self class]), self, additionalChangeCount, [mutableSlots description]];
    }
    
    return [super description];
}

- (NSDictionary *)descriptionDictionary;
{
    [self _updateInner];
    return [super descriptionDictionary];
}

- (NSInteger)changeCount;
{
    NSInteger count = additionalChangeCount;
    if (mutableSlots)
        count += mutableSlots.changeCount;
    return count;
}

- (BOOL)setPassword:(NSString *)password error:(NSError **)outError;
{
    [self _makeMutableSlots:_cmd];
    
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
    
    passwordDerivation = kminfo;
    additionalChangeCount ++;
    
    OBPOSTCONDITION(mutableSlots);
    OBPOSTCONDITION(!slots);
    
    return YES;
}

/* We make a mutable copy on write of the slots table when a mutating method is called */
- (void)_makeMutableSlots:(SEL)caller;
{
    if (!mutableSlots) {
        if (!slots)
            OBRejectInvalidCall(self, caller, @"not currently valid");
        mutableSlots = [slots mutableCopy];
        slots = nil;
    }
    
    OBPOSTCONDITION(!slots);
}

/* Convert our slots table back to its immutable form */
- (void)_updateInner;
{
    if (mutableSlots) {
        OBASSERT(!slots);
        
        if (passwordDerivation) {
            passwordDerivation = [passwordDerivation dictionaryWithObject:[mutableSlots wrapWithKey:wk.bytes length:wk.len] forKey:DocumentKeyKey];
        }

        slots = [mutableSlots copy];
        additionalChangeCount += mutableSlots.changeCount;
        mutableSlots = nil;
    }
}

@end


