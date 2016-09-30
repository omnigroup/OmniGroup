// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFAEADCryptor.h"
#include <dispatch/dispatch.h>
#include "OF_CTR_CBCMAC_Util.h"
#ifdef OF_AEAD_GCM_ENABLED
#include "OF_GHASH_Util.h"
#endif

#define PARAM_FROM_ST(tp, st) (struct tp *)(((char *)(st)) - offsetof(struct tp, public))

/* x86-32, x86-64, and ARM32 all seem to use 64-byte cache lines. Not sure about ARM64. */
#define CACHE_ALIGN __attribute__((aligned(64)))

static const uint8_t allZeroes[16] = { 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0 };

#define BULK_CRYPTO_CHUNK_SIZE (128*1024)

#define MAX_CCM_NONCE_LENGTH   13   /* One block, minus at least one byte of flags and two bytes of length */
#define MAX_CCM_TAG_LENGTH     kCCBlockSizeAES128

#pragma mark CCM Encryption

struct OFCCMEncryptionState {
    struct OFAuthenticatedStreamEncryptorState public;
    CCCryptorRef keystreamState;
    dispatch_queue_t cmacComputationQueue;
    uint8_t authTagEncryptionBuffer[kCCBlockSizeAES128];
    
    /* These members are read and written by code running on a separate thread. Put them on a separate cache line. */
    uint8_t finalCBCBlock[kCCBlockSizeAES128] CACHE_ALIGN;
    CCCryptorRef cbcMacState;
    CCCryptorStatus cmacQueueErrorState;
};

static CCCryptorStatus ccmEncryptBuffer(struct OFAuthenticatedStreamEncryptorState *st,
                                        const uint8_t *plaintext, size_t plaintextLength,
                                        int (^consumer)(dispatch_data_t));
static CCCryptorStatus ccmEncryptFinal(struct OFAuthenticatedStreamEncryptorState *st, uint8_t *icv, size_t icvLen);

static void do_nothing_fn(void *dummy)
{
    /* In a few cases we just need to wait for everything on an async serial queue to finish. The easiest way to do this seems to be to synchronously invoke a do-nothing function. */
}

CCCryptorStatus OFCCMBeginEncryption(const uint8_t *key, unsigned int keySizeBytes,
                                     const uint8_t *nonce, unsigned int nonceSizeBytes,
                                     size_t plaintextLength, unsigned int icvLen,
                                     CFDataRef aad,
                                     OFAuthenticatedStreamEncryptorState *outState)
{
    CCCryptorStatus cerr;
    unsigned int ccmParameterM = icvLen;
    unsigned int ccmParameterL;
        
    /* Per RFC3610: L = 15-nonceSize, and 2 <= L <= 8 */
    if (nonceSizeBytes < 7 || nonceSizeBytes > MAX_CCM_NONCE_LENGTH) {
        return kCCParamError;
    }
    
    struct {
        // Make a copy of this so we don't lose it before it's used by our CMAC thread
        uint8_t bytes[MAX_CCM_NONCE_LENGTH];
    } nonceBuffer;
    memcpy(nonceBuffer.bytes, nonce, nonceSizeBytes);
    
    ccmParameterL = 15 - nonceSizeBytes;
    
    /* Per RFC3610: Valid values are 4, 6, 8, 10, 12, 14, and 16 octets */
    if (ccmParameterM < 4 || ccmParameterM > 16 || (ccmParameterM & 1)) {
        return kCCParamError;
    }
    
    struct OFCCMEncryptionState *param = calloc(sizeof(*param), 1);
    
    cerr = ccmCreateCTRCryptor(kCCEncrypt, key, keySizeBytes, nonce, ccmParameterL, &param->keystreamState);
    if (cerr != kCCSuccess) {
        fprintf(stderr, "CCCryptorCreateWithMode[AES-CTR] returns %d", (int)cerr);
        free(param);
        return cerr;
    }
    cerr = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCBC, kCCAlgorithmAES, ccNoPadding,
                                   allZeroes, key, keySizeBytes,
                                   NULL, 0, 0,
                                   0,
                                   &param->cbcMacState);
    if (cerr != kCCSuccess) {
        fprintf(stderr, "CCCryptorCreateWithMode[AES-CBC] returns %d", (int)cerr);
        CCCryptorRelease(param->keystreamState);
        free(param);
        return cerr;
    }
    
    param->cmacComputationQueue = dispatch_queue_create("CCM-CBCMAC", DISPATCH_QUEUE_SERIAL);

    if (aad) {
        CFRetain(aad);
    }
    dispatch_async(param->cmacComputationQueue, ^{
        CCCryptorStatus ccerr;
        
        /* The parameters L=8 (15 - c->nonceLength) and M=12 (c->macTag->size) are from RFC5084 [3.1] */
        ccerr = ccmProcessHeaderBlocks(param->cbcMacState,
                                       ccmParameterM /* Parameter M, typically 12 */,
                                       ccmParameterL /* Parameter L, typically 8 */,
                                       plaintextLength,
                                       aad? CFDataGetLength(aad) : 0, aad? CFDataGetBytePtr(aad) : NULL,
                                       nonceBuffer.bytes, param->finalCBCBlock);
        
        if (aad) {
            CFRelease(aad);
        }
        
        param->cmacQueueErrorState = ccerr;
    });
    
    /* The first block of keystream (with counter=0) is not used to encrypt the message itself, but to encrypt the authentication tag. */
    {
        size_t moved = 0;
        cerr = CCCryptorUpdate(param->keystreamState, allZeroes, kCCBlockSizeAES128,
                               param->authTagEncryptionBuffer, sizeof(param->authTagEncryptionBuffer),
                               &moved);
        if (cerr != kCCSuccess || moved != kCCBlockSizeAES128) {
            if (cerr == kCCSuccess)
                cerr = kCCUnimplemented;
            dispatch_sync(param->cmacComputationQueue, ^{
                CCCryptorRelease(param->cbcMacState);
                param->cbcMacState = NULL;
            });
            dispatch_release(param->cmacComputationQueue);
            CCCryptorRelease(param->keystreamState);
            free(param);
            return cerr;
        }
    }
    
    param->public.update = ccmEncryptBuffer;
    param->public.final = ccmEncryptFinal;
    
    *outState = &param->public;
    return kCCSuccess;
}

static CCCryptorStatus ccmEncryptBuffer(struct OFAuthenticatedStreamEncryptorState *st,
                                        const uint8_t *plaintext, size_t plaintextLength,
                                        int (^consumer)(dispatch_data_t))
{
    struct OFCCMEncryptionState *param = PARAM_FROM_ST(OFCCMEncryptionState, st);

    /* Update the running CMAC with this block */
    dispatch_async(param->cmacComputationQueue, ^{
        if (param->cmacQueueErrorState != kCCSuccess)
            return;
        
        param->cmacQueueErrorState = ccmProcessMessage(param->cbcMacState, param->finalCBCBlock, plaintext, plaintextLength);
    });
    
    /* Encrypt the actual data buffer and pass it to the consumer callback */
    while (plaintextLength > 0) {
        size_t chunkLength = MIN(plaintextLength, BULK_CRYPTO_CHUNK_SIZE);
        uint8_t *runBuffer = malloc(chunkLength);
        size_t bytesProduced = 0;
        CCCryptorStatus cerr = CCCryptorUpdate(param->keystreamState, plaintext, chunkLength, runBuffer, BULK_CRYPTO_CHUNK_SIZE, &bytesProduced);
        if (cerr != kCCSuccess) {
            free(runBuffer);
            return cerr;
        }
        if (bytesProduced != chunkLength) {
            free(runBuffer);
            return kCCAlignmentError;
        }
        dispatch_data_t run = dispatch_data_create(runBuffer, chunkLength, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
        int cb_ok = consumer(run);
        dispatch_release(run);
        if (cb_ok < 0) {
            return -1;
        }
        plaintext += chunkLength;
        plaintextLength -= chunkLength;
    }
    
    /* Don't return from this function before ccmProcessMessage() is done using the passed-in buffer */
    dispatch_sync_f(param->cmacComputationQueue, NULL, do_nothing_fn);
    
    return kCCSuccess;
}

static CCCryptorStatus ccmEncryptFinal(struct OFAuthenticatedStreamEncryptorState *st, uint8_t *icv, size_t icvLen)
{
    struct OFCCMEncryptionState *param = PARAM_FROM_ST(OFCCMEncryptionState, st);
    
    CCCryptorRelease(param->keystreamState);
    param->keystreamState = NULL;
    
    /* This last block is enqueued synchronously so that we will block until the MAC computation is done */
    dispatch_sync(param->cmacComputationQueue, ^{
        CCCryptorRelease(param->cbcMacState);

        /* Compute the auth tag by encrypting it with the first block of keystream (see RFC3610 [2.3], last few paragraphs) */
        for(size_t i = 0; i < icvLen; i++) {
            icv[i] = param->finalCBCBlock[i] ^ param->authTagEncryptionBuffer[i];
        }

        memset(param->finalCBCBlock, 0, sizeof(param->finalCBCBlock));
        memset(param->authTagEncryptionBuffer, 0, sizeof(param->authTagEncryptionBuffer));
    });
    
    dispatch_release(param->cmacComputationQueue);
    
    CCCryptorStatus result = param->cmacQueueErrorState;
    free(param);
    return result;
}


#pragma mark CCM Decryption

struct OFCCMDecryptionState {
    struct OFAuthenticatedStreamDecryptorState public;
    
    CCCryptorRef keystreamState;
    dispatch_queue_t cmacComputationQueue;
    
    /* These members are read and written by code running on a separate thread. Put them on a separate cache line. */
    uint8_t authTagEncryptionBuffer[kCCBlockSizeAES128] CACHE_ALIGN;
    uint8_t authTagWorkingBuffer[kCCBlockSizeAES128];
    CCCryptorRef cbcMacState;
    CCCryptorStatus cmacQueueErrorState;
};

static CCCryptorStatus ccmDecryptBuffer(struct OFAuthenticatedStreamDecryptorState *st,
                                        const uint8_t *input, size_t length,
                                        uint8_t *output);
static CCCryptorStatus ccmDecryptFinal(struct OFAuthenticatedStreamDecryptorState *st, const uint8_t *icv, size_t icvLen);


CCCryptorStatus OFCCMBeginDecryption(const uint8_t *key, unsigned int keySizeBytes,
                                     const uint8_t *nonce, unsigned int nonceSizeBytes,
                                     size_t plaintextLength, unsigned int icvLen, CFDataRef aad,
                                     OFAuthenticatedStreamDecryptorState *outState)
{
    struct OFCCMDecryptionState *param;
    CCCryptorRef keystreamState;
    
    unsigned short parameterL;
    if (nonceSizeBytes < 7 || nonceSizeBytes > MAX_CCM_NONCE_LENGTH)
        return kCCParamError;
    parameterL = 15 - nonceSizeBytes;
    
    if (icvLen < 4 || icvLen > 16 || (icvLen & 1)) {
        return kCCParamError;
    }
    
    if (keySizeBytes < kCCKeySizeAES128 || keySizeBytes > kCCKeySizeAES256)
        return kCCParamError;
    
    {
        CCCryptorStatus cerr;
        cerr = ccmCreateCTRCryptor(kCCDecrypt, key, keySizeBytes, nonce, parameterL, &keystreamState);
        if (cerr)
            return cerr;
    }
    
    param = calloc(sizeof(*param), 1);
    param->keystreamState = keystreamState;
    param->cmacComputationQueue = dispatch_queue_create("CCM-CBCMAC", DISPATCH_QUEUE_SERIAL);
    
    struct {
        uint8_t key[kCCKeySizeAES256];
        uint8_t nonce[MAX_CCM_NONCE_LENGTH];
    } nonceBuffer;
    memcpy(nonceBuffer.key, key, keySizeBytes);
    memcpy(nonceBuffer.nonce, nonce, nonceSizeBytes);
    
    /* Start the MAC computation on its thread */
    if (aad)
        CFRetain(aad);
    dispatch_async(param->cmacComputationQueue, ^{
        CCCryptorStatus cerr;

        param->cbcMacState = NULL;
        cerr = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCBC, kCCAlgorithmAES, ccNoPadding,
                                       allZeroes, nonceBuffer.key, keySizeBytes,
                                       NULL, 0, 0,
                                       0,
                                       &param->cbcMacState);
        if (cerr != kCCSuccess) {
            fprintf(stderr, "CCCryptorCreateWithMode[AES-CBC] returns %d", (int)cerr);
            param->cmacQueueErrorState = cerr;
            if (aad)
                CFRelease(aad);
            return;
        }
        
        cerr = ccmProcessHeaderBlocks(param->cbcMacState,
                                      icvLen /* Parameter M, typically 12 */,
                                      parameterL /* Parameter L, typically 8 */,
                                      plaintextLength,
                                      aad? CFDataGetLength(aad) : 0, aad? CFDataGetBytePtr(aad) : NULL,
                                      nonceBuffer.nonce, param->authTagWorkingBuffer);
        if (aad)
            CFRelease(aad);

        if (cerr != kCCSuccess) {
            fprintf(stderr, "CCM process header returns %d", (int)cerr);
            param->cmacQueueErrorState = cerr;
            return;
        }
    });
    
    /* The first block of keystream (with counter=0) is not used to encrypt the message itself, but to encrypt the authentication tag. Compute it now and save it for later. */
    {
        CCCryptorStatus cerr;
        size_t moved = 0;
        cerr = CCCryptorUpdate(keystreamState, allZeroes, kCCBlockSizeAES128,
                               param->authTagEncryptionBuffer, sizeof(param->authTagEncryptionBuffer),
                               &moved);
        if (cerr != kCCSuccess || moved != kCCBlockSizeAES128) {
            if (cerr == kCCSuccess)
                cerr = kCCUnimplemented;
            dispatch_sync(param->cmacComputationQueue, ^{
                CCCryptorRelease(param->cbcMacState);
                param->cbcMacState = NULL;
            });
            dispatch_release(param->cmacComputationQueue);
            CCCryptorRelease(param->keystreamState);
            free(param);
            return cerr;
        }
    }
    
    param->public.update = ccmDecryptBuffer;
    param->public.final = ccmDecryptFinal;

    *outState = (struct OFAuthenticatedStreamDecryptorState *)param;
    return kCCSuccess;
}

static CCCryptorStatus ccmDecryptBuffer(struct OFAuthenticatedStreamDecryptorState *st,
                                        const uint8_t *input, size_t length,
                                        uint8_t *output)
{
    struct OFCCMDecryptionState *param = (struct OFCCMDecryptionState *)st;
    
    while (length) {
        size_t chunkLength = MIN(length, BULK_CRYPTO_CHUNK_SIZE);
        CCCryptorStatus cerr;
        size_t bytesOut;
        
        /* We know that our CCCryptorRef represents a CTR-mode cryptor, whose output is always the same size as its input, and which has no 'final' output */
        bytesOut = 0;
        cerr = CCCryptorUpdate(param->keystreamState, input, chunkLength, output, chunkLength, &bytesOut);
        if (cerr != kCCSuccess)
            return cerr;
        if (bytesOut != chunkLength)
            return kCCAlignmentError;
        
        dispatch_block_t updateCMAC = ^{
            if (param->cmacQueueErrorState != kCCSuccess)
                return;
            
            CCCryptorStatus err = ccmProcessMessage(param->cbcMacState, param->authTagWorkingBuffer, output, chunkLength);
            param->cmacQueueErrorState = err;
        };
        
        /* Our last block should be run synchronously, so that we don't return before we're done using the caller's buffer */
        if (length > chunkLength)
            dispatch_async(param->cmacComputationQueue, updateCMAC);
        else
            dispatch_sync(param->cmacComputationQueue, updateCMAC);
        
        input += chunkLength;
        length -= chunkLength;
    }
    
    return kCCSuccess;
}

static CCCryptorStatus ccmDecryptFinal(struct OFAuthenticatedStreamDecryptorState *st, const uint8_t *icv, size_t icvLen)
{
    struct OFCCMDecryptionState *param = (struct OFCCMDecryptionState *)st;
    
    CCCryptorRelease(param->keystreamState);
    param->keystreamState = NULL;
    
    /* This last dispatch is synchronous */
    dispatch_sync(param->cmacComputationQueue, ^{
        CCCryptorRelease(param->cbcMacState);
        param->cbcMacState = NULL;
        
        if (param->cmacQueueErrorState != kCCSuccess)
            return;
        
        if (!icv || icvLen < 1 || icvLen > kCCBlockSizeAES128) {
            param->cmacQueueErrorState = kCCParamError;
            return;
        }
        
        /* Verify the auth tag. It's computed by XORing outFinalCBCBlock[] with authTagEncryptionBuffer[]. We then do the usual constant-time compare by XORing that with icv[] and accumulating the mismatch bits. */
        uint8_t neq = 0;
        for(unsigned short i = 0; i < icvLen; i++) {
            neq |= ( param->authTagWorkingBuffer[i] ^ param->authTagEncryptionBuffer[i] ^ icv[i] );
        }
        
        if (neq) {
            /* Auth tag mismatch. */
            param->cmacQueueErrorState = kCCDecodeError;
        }
        
        memset(param->authTagEncryptionBuffer, 0, sizeof(param->authTagEncryptionBuffer));
        memset(param->authTagWorkingBuffer, 0, sizeof(param->authTagWorkingBuffer));
        
        return;
    });
    
    dispatch_release(param->cmacComputationQueue);
    
    CCCryptorStatus result = param->cmacQueueErrorState;
    free(param);
    return result;
}

#ifdef OF_AEAD_GCM_ENABLED

#pragma mark GCM Decryption

struct OFGCMDecryptionState {
    struct OFAuthenticatedStreamDecryptorState public;
    
    struct OFGHASHMultiplicand ghashTable;
    gf128 ghashState;
    dispatch_queue_t ctrComputationQueue;
    uint64_t aadLength;
    uint64_t totalDataLength;
    
    /* These members are read and written by code running on a separate thread. Put them on a separate cache line. */
    uint8_t counterState[kCCBlockSizeAES128] CACHE_ALIGN;
    uint8_t authTagEncryptionBuffer[kCCBlockSizeAES128];
    CCCryptorRef keystreamState_;
    unsigned ctrKeystreamFlags;
    CCCryptorStatus ctrErrorState;
};

static CCCryptorStatus gcmDecryptBuffer(struct OFAuthenticatedStreamDecryptorState *st,
                                        const uint8_t *input, size_t length,
                                        uint8_t *output);
static CCCryptorStatus gcmDecryptFinal(struct OFAuthenticatedStreamDecryptorState *st, const uint8_t *icv, size_t icvLen);

CCCryptorStatus OFGCMBeginDecryption(const uint8_t *key, unsigned short keySizeBytes,
                                     const uint8_t *nonce, unsigned short nonceSizeBytes,
                                     CFDataRef aad,
                                     OFAuthenticatedStreamDecryptorState *outState)
{
    CCCryptorStatus cerr;
    struct OFGCMDecryptionState *param = calloc(sizeof(*param), 1);
    
    /* Set up the AES-CTR state */
    cerr = gcmCreateCTRCryptor(kCCDecrypt, key, keySizeBytes, nonce, nonceSizeBytes, param->counterState, &param->ctrKeystreamFlags, &param->ghashTable, &param->keystreamState_);
    if (cerr != kCCSuccess) {
        free(param);
        return cerr;
    }
    
    /* We'll do the GCM computation (which is done on the ciphertext) on this thread, and perform in-place CTR decryption on a separate thread as we finish with the GCM processing of each block */
    param->ctrComputationQueue = dispatch_queue_create("GCM-Decrypt", DISPATCH_QUEUE_SERIAL);
    
    /* The first block of keystream is not used to encrypt the message itself, but to encrypt the authentication tag. */
    dispatch_async(param->ctrComputationQueue, ^{
        param->ctrErrorState = gcmCTRUpdate(param->keystreamState_, param->ctrKeystreamFlags, allZeroes, kCCBlockSizeAES128,
                                            param->authTagEncryptionBuffer,
                                            param->counterState);
    });
    
    gfZero(&param->ghashState);
    
    /* Process the AAD */
    if (aad) {
        const uint8_t *aadBytes = CFDataGetBytePtr(aad);
        size_t aadLength = CFDataGetLength(aad);
        param->aadLength = aadLength;
        gfMultiplyBytes(&param->ghashTable, &param->ghashState, aadBytes, aadLength);
    } else {
        param->aadLength = 0;
    }
    
    param->public.update = gcmDecryptBuffer;
    param->public.final = gcmDecryptFinal;
    *outState = &(param->public);
    return kCCSuccess;
}


static CCCryptorStatus gcmDecryptBuffer(struct OFAuthenticatedStreamDecryptorState *st,
                                        const uint8_t *buffer, size_t length,
                                        uint8_t *output)
{
    struct OFGCMDecryptionState *param = PARAM_FROM_ST(OFGCMDecryptionState, st);
    
    param->totalDataLength += length;
    
    while (length) {
        size_t chunkSize = MIN(length, BULK_CRYPTO_CHUNK_SIZE);
        /* GCM computation */
        gfMultiplyBytes(&param->ghashTable, &param->ghashState, buffer, chunkSize);
        /* AES-CTR decryption */
        dispatch_async(param->ctrComputationQueue, ^{
            if (param->ctrErrorState) {
                /* skip - already in an error state */
                return;
            }
            param->ctrErrorState = gcmCTRUpdate(param->keystreamState_, param->ctrKeystreamFlags, buffer, chunkSize, output, param->counterState);
        });
        
        buffer += chunkSize;
        length -= chunkSize;
    }
    
    dispatch_sync_f(param->ctrComputationQueue, NULL, do_nothing_fn); // Wait for the CTR thread to be done with buffer and output
    
    return kCCSuccess;
}

static CCCryptorStatus gcmDecryptFinal(struct OFAuthenticatedStreamDecryptorState *st, const uint8_t *icv, size_t icvSizeBytes)
{
    struct OFGCMDecryptionState *param = PARAM_FROM_ST(OFGCMDecryptionState, st);

    /* Finish off the GHASH computation */
    uint8_t intermediateAuthTagBuf[16];
    gcmFinal(&param->ghashTable, &param->ghashState, param->aadLength, param->totalDataLength, intermediateAuthTagBuf);
    
    /* Wait for enqueued operations to finish */
    dispatch_sync_f(param->ctrComputationQueue, NULL, do_nothing_fn);
    
    /* Verify the auth tag. It's computed by XORing the GHASH output with authTagEncryptionBuffer[]. We then do the usual constant-time compare by XORing that with icv[] and accumulating the mismatch bits. */
    uint8_t neq = 0;
    if (icvSizeBytes > 16) {
        neq = 0xFF;
    } else {
        for(unsigned short i = 0; i < icvSizeBytes; i++) {
            neq |= ( intermediateAuthTagBuf[i] ^ param->authTagEncryptionBuffer[i] ^ icv[i] );
        }
    }
    memset(intermediateAuthTagBuf, 0, 16);
    memset(param->authTagEncryptionBuffer, 0, 16);
    
    /* Clean up */
    CCCryptorRelease(param->keystreamState_);
    dispatch_release(param->ctrComputationQueue);
    CCCryptorStatus result = param->ctrErrorState;
    free(param);
    
    if (neq) {
        /* Auth tag mismatch. */
        result = kCCDecodeError;
    }
    
    return result;
}

#pragma mark GCM Encryption

/*
 The reference for GCM here is the NIST publication "The Galois/Counter Mode of Operation (GCM)" by David A. McGrew and John Viega, May 31, 2005.
 
 Aside from the different hash/MAC function, GCM differs from CCM in that the hash/MAC is applies to the ciphertext, not the plaintext. This means our GCM and CCM implementations aren't really parallel to each other. They also include different sets of information at different points in the MAC computation, which affects the argument lists of the constructors.
 
 */

struct OFGCMEncryptionState {
    struct OFAuthenticatedStreamEncryptorState public;
    
    CCCryptorRef keystreamState_;
    unsigned ctrKeystreamFlags;
    dispatch_queue_t hashComputationQueue;
    uint64_t aadLength;
    uint64_t totalCiphertextLength;
    uint8_t counterState[kCCBlockSizeAES128];
    uint8_t authTagEncryptionBuffer[kCCBlockSizeAES128];
    
    /* These members are read and written by code running on a separate thread. Put them on a separate cache line. */
    struct OFGHASHMultiplicand ghashTable CACHE_ALIGN;
    gf128 ghashState;
};

static CCCryptorStatus gcmEncryptBuffer(struct OFAuthenticatedStreamEncryptorState *st,
                                        const uint8_t *plaintext, size_t plaintextLength,
                                        int (^consumer)(dispatch_data_t));
static CCCryptorStatus gcmEncryptFinal(struct OFAuthenticatedStreamEncryptorState *st, uint8_t *icv, size_t icvLen);

CCCryptorStatus OFGCMBeginEncryption(const uint8_t *key, unsigned short keySizeBytes,
                                     const uint8_t *nonce, unsigned short nonceSizeBytes,
                                     CFDataRef aad,
                                     OFAuthenticatedStreamEncryptorState *outState)
{
    CCCryptorStatus cerr;
    struct OFGCMEncryptionState *param = calloc(sizeof(*param), 1);
    
    cerr = gcmCreateCTRCryptor(kCCEncrypt, key, keySizeBytes, nonce, nonceSizeBytes, param->counterState, &param->ctrKeystreamFlags, &param->ghashTable, &param->keystreamState_);
    if (cerr != kCCSuccess) {
        free(param);
        return cerr;
    }
    
    gfZero(&param->ghashState);

    param->hashComputationQueue = dispatch_queue_create("GCM-GHASH", DISPATCH_QUEUE_SERIAL);
    
    /* Process the AAD */
    if (aad) {
        CFRetain(aad);
        dispatch_async(param->hashComputationQueue, ^{
            const uint8_t *aadBytes = CFDataGetBytePtr(aad);
            size_t aadLength = CFDataGetLength(aad);
            gfMultiplyBytes(&param->ghashTable, &param->ghashState, aadBytes, aadLength);
            CFRelease(aad);
        });
        param->aadLength = CFDataGetLength(aad);
    } else {
        param->aadLength = 0;
    }
    param->totalCiphertextLength = 0;
    
    /* The first block of keystream is not used to encrypt the message itself, but to encrypt the authentication tag. */
    cerr = gcmCTRUpdate(param->keystreamState_, param->ctrKeystreamFlags,
                        allZeroes, kCCBlockSizeAES128,
                        param->authTagEncryptionBuffer, param->counterState);
    if (cerr != kCCSuccess) {
        abort(); // TODO
    }
    
#if 0
    {
        char buffer[33];
        for(int i = 0; i < 16; i++)
            sprintf(buffer + 2*i, "%02X", (unsigned int)(param->authTagEncryptionBuffer[i]));
        printf("GCM:    E(K,Y0) = %s\n", buffer);
    }
#endif
    
    param->public.update = gcmEncryptBuffer;
    param->public.final = gcmEncryptFinal;
    *outState = &(param->public);
    return kCCSuccess;
}

static CCCryptorStatus gcmEncryptBuffer(struct OFAuthenticatedStreamEncryptorState *st,
                                        const uint8_t *plaintext, size_t plaintextLength,
                                        int (^consumer)(dispatch_data_t))
{
    struct OFGCMEncryptionState *param = PARAM_FROM_ST(OFGCMEncryptionState, st);

    param->totalCiphertextLength += plaintextLength;
    
    while (plaintextLength) {
        size_t encryptionChunkSize = MIN(plaintextLength, BULK_CRYPTO_CHUNK_SIZE);

        size_t bufferSize = ( encryptionChunkSize + 15 ) & ~0xF;  /* Round up to the block size for GHASH padding */
        size_t blockCount = ( encryptionChunkSize + 15 ) / 16;
        uint8_t *buffer;
        CCCryptorStatus cerr;
        
        buffer = malloc(bufferSize);

        cerr = gcmCTRUpdate(param->keystreamState_, param->ctrKeystreamFlags, plaintext, encryptionChunkSize, buffer, param->counterState);
        if (cerr) {
            free(buffer);
            return cerr;
        }
        
        if (encryptionChunkSize & 0xF) {
            /* The last part of the buffer. CTR mode requires no padding, but the AAD and plaintext each need to be padded with zeroes to a 128-bit boundary before being processed by gfMultiplyBlocks. */
            memset(buffer + encryptionChunkSize, 0, 16 - (encryptionChunkSize & 0xF));
        }
        
        dispatch_data_t chunk = dispatch_data_create(buffer, bufferSize, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
        
        dispatch_retain(chunk);
        dispatch_async(param->hashComputationQueue, ^{
            gfMultiplyBlocks(&param->ghashTable, &param->ghashState, buffer, blockCount);
            dispatch_release(chunk);
        });
        
        if (encryptionChunkSize != bufferSize) {
            dispatch_data_t trimmed = dispatch_data_create_subrange(chunk, 0, bufferSize);
            dispatch_release(chunk);
            chunk = trimmed;
        }
        
        int cb_ok = (*consumer)(chunk);
        dispatch_release(chunk);
        
        if (cb_ok < 0) {
            fprintf(stderr, "EncryptedContent: cb returns %d", cb_ok);
            return -1;
        }
        
        plaintext += encryptionChunkSize;
        plaintextLength -= encryptionChunkSize;
    }
    
    return kCCSuccess;
}

static CCCryptorStatus gcmEncryptFinal(struct OFAuthenticatedStreamEncryptorState *st, uint8_t *icv, size_t icvLen)
{
    struct OFGCMEncryptionState *param = PARAM_FROM_ST(OFGCMEncryptionState, st);

    CCCryptorRelease(param->keystreamState_);
    
    /* This last block is enqueued synchronously so that we will block until the GHASH computation is done */
    dispatch_sync(param->hashComputationQueue, ^{
        uint8_t buf[16];
        gcmFinal(&param->ghashTable, &param->ghashState, param->aadLength, param->totalCiphertextLength, buf);
        
        for(unsigned i = 0; i < 16 && i < icvLen; i++) {
            icv[i] = buf[i] ^ param->authTagEncryptionBuffer[i];
        }
        
        memset(&param->ghashState, 0, sizeof(param->ghashState));
        memset(&param->ghashTable, 0, sizeof(param->ghashTable));
    });
    
    dispatch_release(param->hashComputationQueue);
    
    return kCCSuccess;
}

#endif /* OF_AEAD_GCM_ENABLED */

