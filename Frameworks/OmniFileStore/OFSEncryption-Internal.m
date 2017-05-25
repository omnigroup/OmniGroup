// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFSEncryption-Internal.h"

#import <OmniFoundation/NSRange-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFileStore/OFSEncryptionConstants.h>
#import <OmniFileStore/Errors.h>

#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <OmniBase/OmniBase.h>
#import <dispatch/dispatch.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

/* We could use the derived key to simply wrap the bulk encryption keys themselves instead of having an intermediate document key, but that would make it difficult for the user to change their password without re-writing every encrypted file in the wrapper. This way we can simply wrap the same document key with a new password-derived key. It also leaves open the possibility of using keys on smartcards, phone TPMs, or whatever, to decrypt the document key, possibly with asymmetric crypto for least-authority background operation, and all that fun stuff. */

/* Utility functions */
static CCCryptorRef createCryptor(const uint8_t segmentIV[kCCBlockSizeAES128], const uint8_t *key, unsigned keyLength, NSError **outError);
static BOOL resetCryptor(CCCryptorRef cryptor, const uint8_t segmentIV[kCCBlockSizeAES128], NSError **outError);

dispatch_once_t testRADARsOnce;
BOOL canResetCTRIV;

const char magic_ver0_6[FMT_V0_6_MAGIC_LEN] = "OmniFileStore encryption\x00STRAWMAN-6";  // STRAWMAN-6 is the same as version 1.0.
const char magic_ver1_0[FMT_V1_0_MAGIC_LEN] = "OmniFileEncryption\x00\x00";  // Our published version. We can bump that NUL if we want to.

#pragma mark HMAC

/* Format and hash in the IV and block number parts of the hashed data */
void hmacSegmentHeader(CCHmacContext *hashContext, const uint8_t *segmentIV, uint32_t order)
{
    uint8_t hashPrefix[ kCCBlockSizeAES128 ];
    memset(hashPrefix, 0, kCCBlockSizeAES128);
    memcpy(hashPrefix, segmentIV, SEGMENTED_IV_LEN);
    OSWriteBigInt32(hashPrefix, kCCBlockSizeAES128 - 4, order);
    _Static_assert( SEGMENTED_IV_LEN + 4 == sizeof(hashPrefix), "");
    CCHmacUpdate(hashContext, hashPrefix, kCCBlockSizeAES128);
}

uint8_t finishAndVerifyHMAC256(CCHmacContext *hashContext, const uint8_t *expectedValue, unsigned hashLength)
{
    uint8_t mismatches = 0;
    
    uint8_t computedMac[CC_SHA256_DIGEST_LENGTH];
    CCHmacFinal(hashContext, computedMac);
    
    memset(hashContext, 0, sizeof(*hashContext));
    
    /* Constant-time compare (this is why this function is marked noinline--- we can't control compiler settings, especially if we start distributing as bitcode, so this hopefully keeps the comparison hidden from the optimizer) */
    for(unsigned i = 0; i < hashLength; i++)
        mismatches |= (computedMac[i] ^ expectedValue[i]);
    
    return mismatches;
}

/* Verify the HMAC on an encrypted segment */
BOOL verifySegment(const uint8_t *hmacKey, NSUInteger segmentNumber, const uint8_t *hdr, const uint8_t *ciphertext, size_t ciphertextLength)
{
    if (segmentNumber > UINT32_MAX)
        return NO;
    
    CCHmacContext hashContext;
    CCHmacInit(&hashContext, kCCHmacAlgSHA256, hmacKey, SEGMENTED_MAC_KEY_LEN);
    hmacSegmentHeader(&hashContext, hdr, (uint32_t)segmentNumber);
    CCHmacUpdate(&hashContext, ciphertext, ciphertextLength);
    
    return (finishAndVerifyHMAC256(&hashContext, hdr + SEGMENTED_IV_LEN, SEGMENTED_MAC_LEN) == 0)? YES : NO;
}

#pragma mark AES-CTR encryption

static CCCryptorRef createCryptor(const uint8_t segmentIV[kCCBlockSizeAES128], const uint8_t *key, unsigned keyLength, NSError **outError)
{
    CCCryptorRef cryptor = NULL;
    CCCryptorStatus cerr;
    cerr = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCTR, kCCAlgorithmAES, 0,
                                   segmentIV, key, keyLength,
                                   NULL, 0, 0,
                                   /* This mode option is "deprecated" and "not in use", but if you don't supply it, the call fails with kCCUnimplemented (at least on 10.9.4) */
                                   kCCModeOptionCTR_BE,
                                   &cryptor);
    if (cerr != kCCSuccess) {
        if (outError)
            *outError = ofsWrapCCError(cerr, @"CCCryptorCreate", @"mode", @"AES128-CTR");
        return NULL;
    }
    return cryptor;
}

static BOOL resetCryptor(CCCryptorRef cryptor, const uint8_t segmentIV[kCCBlockSizeAES128], NSError **outError)
{
    /* Note that this function does not work correctly in released versions of iOS (see RADARs 18222014 and 12680772). We test the functionality and don't call this function if it does not appear to work. */
    /* (This means that this code path has never actually been tested for real, unfortunately.) */
    OBASSERT(canResetCTRIV);
    CCCryptorStatus cerr = CCCryptorReset(cryptor, segmentIV);
    if (cerr != kCCSuccess) {
        if (outError)
            *outError = ofsWrapCCError(cerr, @"CCCryptorReset", nil, nil);
        return NO;
    }
    return YES;
}

CCCryptorRef createOrResetCryptor(CCCryptorRef cryptor, const uint8_t segmentIV[kCCBlockSizeAES128], const uint8_t *key, unsigned keyLength, NSError **outError)
{
    if (cryptor) {
        if (canResetCTRIV) {
            if (!resetCryptor(cryptor, segmentIV, outError)) {
                CCCryptorRelease(cryptor);
                return NULL;
            } else {
                return cryptor;
            }
        } else {
            CCCryptorRelease(cryptor);
        }
    }
    
    return createCryptor(segmentIV, key, keyLength, outError);
}

/* There's no plausible reason for our bulk data encryption to fail--- there's no mallocing or anything variable happening in there. So just crash if any error is returned. */
void cryptOrCrash(CCCryptorRef cryptor, const void *dataIn, size_t dataLength, void *dataOut, int lineno)
{
    
    /* The documentation says that the input and output buffers can be the same, but according to a March 2015 thread on the apple-cdsa list, the documentation is wrong. */
    OBASSERT(dataIn != dataOut);
    
    /*
     bug:///142883 (iOS-OmniFocus Crasher: Needs Repro: Crash on decryption)
     Sometimes we'll get a NULL dataOut pointer passed in here, but we haven't yet determined how that occurs in practice. We still want to crash (see the function name), but in a way that produces just a little extra information for our caller and crash reporter.
     */
    if (dataOut == NULL) {
        NSDictionary *userInfo = @{ @"line" : @(lineno),
                                    @"input_len" : @(dataLength),
                                    };
        [[NSException exceptionWithName:NSInvalidArgumentException reason:@"Cannot update cryptor using NULL out buffer" userInfo:userInfo] raise];
    }
    
    size_t actualAmountEncrypted = 0;
    CCCryptorStatus cerr = CCCryptorUpdate(cryptor,
                                           dataIn, dataLength,
                                           dataOut, dataLength,
                                           &actualAmountEncrypted);
    if (cerr != kCCSuccess) {
        NSLog(@"Unexpected CCCryptorUpdate failure: code=%" PRId32 ", line %d", cerr, lineno);
        abort();
    }
    if (actualAmountEncrypted != dataLength) {
        NSLog(@"Unexpected CCCryptorUpdate failure: line %d, expected %zu bytes moved, got %zu", lineno, dataLength, actualAmountEncrypted);
        abort();
    }
}

#pragma mark Error reporting

NSError *ofsWrapCCError(CCCryptorStatus cerr, NSString *func, NSString *extra, NSObject *val)
{
    NSString *ks[2] = { @"function", extra };
    NSObject *vs[2] = { func, val };
    
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjects:vs forKeys:ks count:extra? 2 : 1];
    
    /* CCCryptorStatus is actually in the Carbon OSStatus error domain. However, many CommonCrypto functions just return -1 on failure, instead of the error codes they are documented to return; perhaps we should check for that here and substitute a better error code? */
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:userInfo];
}

BOOL ofsUnsupportedError_(NSError **outError, int lineno, NSString *badThing)
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

#pragma mark RADAR workarounds

/* RADAR 18222014 (which has been closed as a dup of 12680772) is that CCCryptorReset() just plain does nothing for a CTR-mode cryptor. */
void testRADAR18222014(void *dummy)
{
    _Static_assert(kCCKeySizeAES128 == kCCBlockSizeAES128, "");
    static const uint8_t v[kCCKeySizeAES128] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    static const uint8_t expected[12] = { 148, 88, 198, 83, 234, 90, 2, 99, 236, 148, 102, 24 };
    uint8_t buf[4 * kCCBlockSizeAES128];
    uint8_t zbuf[2 * kCCBlockSizeAES128];
    
    CCCryptorRef c = createCryptor(v, v, kCCKeySizeAES128, NULL);
    if (!c) {
        /* ???? */
        return;
    }
    
    memset(buf, 0, sizeof(buf));
    memset(zbuf, 0, sizeof(zbuf));
    cryptOrCrash(c, zbuf, 2 * kCCBlockSizeAES128, buf, __LINE__);
    
    if (memcmp(buf+10, expected, 12) != 0) {
        NSLog(@"AES self-test failure");
        abort();
    }
    
    CCCryptorStatus cerr = CCCryptorReset(c, v);
    if (cerr != kCCSuccess) {
        /* Shouldn't be possible for this to fail */
        NSLog(@"CCCryptorReset() returns %ld", (long)cerr);
        CCCryptorRelease(c);
        canResetCTRIV = NO;
        return;
    }
    
    cryptOrCrash(c, zbuf, 2 * kCCBlockSizeAES128, buf + 2 * kCCBlockSizeAES128, __LINE__);
    CCCryptorRelease(c);
    
    if (!memcmp(buf, buf + 2 * kCCBlockSizeAES128, 2 * kCCBlockSizeAES128)) {
        /* Everything looks good! */
        canResetCTRIV = YES;
    } else {
#if defined(DEBUG)
        NSLog(@"Working around RADAR 12680772 and 18222014 - performance may suffer");
#endif
        canResetCTRIV = NO;
    }
}

