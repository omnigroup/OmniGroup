// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonCryptoError.h>
#import <CommonCrypto/CommonHMAC.h>
#import <dispatch/once.h>

#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
#import <CommonCrypto/CommonRandom.h>
#endif

/* File magic */
#define FMT_V0_6_MAGIC_LEN 35
extern const char magic_ver0_6[FMT_V0_6_MAGIC_LEN] OB_HIDDEN;

#define FMT_V1_0_MAGIC_LEN 20
extern const char magic_ver1_0[FMT_V1_0_MAGIC_LEN] OB_HIDDEN;

/* Error reporting utility functions */
NSError *ofsWrapCCError(CCCryptorStatus cerr, NSString *op, NSString *extra, NSObject *val) __attribute__((cold)) OB_HIDDEN; /* CommonCrypto errors fit in the OSStatus error domain */
#define ofsWrapSecError(e,o,k,v) ofsWrapCCError(e,o,k,v) /* Security.framework errors are also OSStatus error codes */
BOOL ofsUnsupportedError_(NSError **outError, int lineno, NSString *badThing) __attribute__((cold)) OB_HIDDEN;

/* AESWRAP utilities */
extern NSData *unwrapData(const uint8_t *wrappingKey, size_t wrappingKeyLength, NSData *wrappedData, NSError **outError) OB_HIDDEN;

/* CTR cryptor utilities */
extern CCCryptorRef createOrResetCryptor(CCCryptorRef cryptor, const uint8_t segmentIV[kCCBlockSizeAES128], const uint8_t *key, unsigned keyLength, NSError **outError) OB_HIDDEN;
extern void cryptOrCrash(CCCryptorRef cryptor, const void *dataIn, size_t dataLength, void *dataOut, int lineno) OB_HIDDEN;

/* MAC utilities */
BOOL verifySegment(const uint8_t *hmacKey, NSUInteger segmentNumber, const uint8_t *hdr, const uint8_t *ciphertext, size_t ciphertextLength) OB_HIDDEN;
void hmacSegmentHeader(CCHmacContext *hashContext, const uint8_t *segmentIV, uint32_t order) OB_HIDDEN;
uint8_t finishAndVerifyHMAC256(CCHmacContext *hashContext, const uint8_t *expectedValue, unsigned hashLength) __attribute__((noinline)) OB_HIDDEN;

/* CTR cryptor bug workaround */
extern dispatch_once_t testRADARsOnce OB_HIDDEN;
extern BOOL canResetCTRIV OB_HIDDEN;
extern void testRADAR18222014(void *dummy) __attribute__((cold)) OB_HIDDEN;

static inline BOOL randomBytes(uint8_t *buffer, size_t bufferLength, NSError **outError)
{
#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
    CCRNGStatus randomErr = CCRandomGenerateBytes(buffer, bufferLength);
    if (randomErr) {
        if (outError)
            *outError = ofsWrapCCError(randomErr, @"CCRandomGenerateBytes", @"length", [NSNumber numberWithUnsignedInteger:bufferLength]);
        return NO;
    }
#else
    if (SecRandomCopyBytes(kSecRandomDefault, bufferLength, buffer) != 0) {
        /* Documentation says "check errno to find out the real error" but a look at the published source code shows that's not going to be very reliable */
        if (outError)
            *outError = ofsWrapSecError(kCCRNGFailure, @"SecRandomCopyBytes", @"length", [NSNumber numberWithUnsignedInteger:bufferLength]);
        return NO;
    }
#endif
    
    return YES;
}

