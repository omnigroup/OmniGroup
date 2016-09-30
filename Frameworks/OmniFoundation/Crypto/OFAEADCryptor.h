// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#include <inttypes.h>
#include <CommonCrypto/CommonCrypto.h>
#include <CoreFoundation/CoreFoundation.h>

#undef OF_AEAD_GCM_ENABLED /* We have a working GCM implementation, but the GHASH code has not been reviewed for cryptographic soundness. */

struct OFAuthenticatedStreamEncryptorState;
struct OFAuthenticatedStreamDecryptorState;

/* Feed a block of data to the decryptor. Except for the last call, it is the caller's responsibility to ensure a integral number of ciphertext blocks per call. */
typedef CCCryptorStatus (*OFAuthenticatedStreamDecryptorUpdateFunc)(struct OFAuthenticatedStreamDecryptorState *st,
                                                                    const uint8_t *input, size_t length,
                                                                    uint8_t *output);
typedef CCCryptorStatus (*OFAuthenticatedStreamDecryptorFinalFunc)(struct OFAuthenticatedStreamDecryptorState *st, const uint8_t *icv, size_t icvLen);

typedef struct OFAuthenticatedStreamDecryptorState {
    OFAuthenticatedStreamDecryptorUpdateFunc update;
    OFAuthenticatedStreamDecryptorFinalFunc final;
} *OFAuthenticatedStreamDecryptorState;

typedef CCCryptorStatus (*OFAuthenticatedStreamEncryptorUpdateFunc)(struct OFAuthenticatedStreamEncryptorState *st,
                                                                    const uint8_t *input, size_t length,
                                                                    int (^consumer)(dispatch_data_t));
typedef CCCryptorStatus (*OFAuthenticatedStreamEncryptorFinalFunc)(struct OFAuthenticatedStreamEncryptorState *st, uint8_t *outIcv, size_t icvLen);

typedef struct OFAuthenticatedStreamEncryptorState {
    OFAuthenticatedStreamEncryptorUpdateFunc update;
    OFAuthenticatedStreamEncryptorFinalFunc final;
} *OFAuthenticatedStreamEncryptorState;

#ifdef __OBJC__
/* Utility function. This decrypts a ciphertext and disposes of the decryptor state. */
dispatch_data_t OFAuthenticatedStreamDecrypt(OFAuthenticatedStreamDecryptorState st, NSData *ciphertext, NSData *mac, NSError **outError) DISPATCH_RETURNS_RETAINED;
#endif

/* Constructors for authenticated stream encryption/decryption contexts. Note that each algorithm requires slightly different pieces of information to be known ahead of time, so it's beneficial to have different entry points here instead of a generic dispatch: it allows the type system to help us. */
CCCryptorStatus OFCCMBeginEncryption(const uint8_t *key, unsigned int keySizeBytes,
                                     const uint8_t *nonce, unsigned int nonceSizeBytes,
                                     size_t plaintextLength, unsigned int icvLen, CFDataRef aad,
                                     OFAuthenticatedStreamEncryptorState *outState);
CCCryptorStatus OFCCMBeginDecryption(const uint8_t *key, unsigned int keySizeBytes,
                                     const uint8_t *nonce, unsigned int nonceSizeBytes,
                                     size_t plaintextLength, unsigned int icvLen, CFDataRef aad,
                                     OFAuthenticatedStreamDecryptorState *outState);

#ifdef OF_AEAD_GCM_ENABLED
CCCryptorStatus OFGCMBeginEncryption(const uint8_t *key, unsigned short keySizeBytes,
                                     const uint8_t *nonce, unsigned short nonceSizeBytes,
                                     CFDataRef aad,
                                     OFAuthenticatedStreamEncryptorState *outState);
CCCryptorStatus OFGCMBeginDecryption(const uint8_t *key, unsigned short keySizeBytes,
                                     const uint8_t *nonce, unsigned short nonceSizeBytes,
                                     CFDataRef aad,
                                     OFAuthenticatedStreamDecryptorState *outState);
#endif
