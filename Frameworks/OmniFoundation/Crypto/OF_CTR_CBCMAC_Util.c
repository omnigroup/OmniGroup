// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#include "OF_CTR_CBCMAC_Util.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CommonCrypto/CommonCrypto.h>

/*
 * We always call CCCryptorUpdate() with a whole number of blocks (because our padding is defined by the CBC-MAC description in RFC3610).
 * It should always return the same amount of data we feed it. This macro checks for that, as well as for CCCryptorUpdate() return codes, and jumps to 'failure' if there is a failure. The ccerr variable will hold an error code in that case.
 */
#define CHECK_CRYPT(inBuf_, inBufSize_, outBuf_, outBufSize_) do{                                   \
    size_t dummyLength = 0;                                                                         \
    ccerr = CCCryptorUpdate(cbcState, inBuf_, inBufSize_, outBuf_, outBufSize_, &dummyLength);      \
    if (ccerr != kCCSuccess) goto failure;                                                          \
    if (dummyLength != inBufSize_) { ccerr = kCCUnimplemented; goto failure; }                      \
} while(0)

#pragma mark CCM

__attribute__((visibility ("internal")))
CCCryptorStatus ccmProcessHeaderBlocks(CCCryptorRef cbcState, unsigned int authTagBytes, unsigned int lengthFieldBytes, size_t messageBytes, size_t aadBytes, const uint8_t *aad, const uint8_t *nonce, uint8_t *outLastBlock)
{
#define WORKING_BUF_SIZE  ( 16 * 16 ) /* This must be at least 2 blocks (for B_0, plus the encoding of l(a) which may take another block). Increase it a little to make AAD computation a little more efficient. */
    uint8_t block[WORKING_BUF_SIZE];
    uint8_t dummy[WORKING_BUF_SIZE];
    CCCryptorStatus ccerr;
    
    // Parameter restrictions mentioned in RFC3610 sec. 2
    if (authTagBytes < 4 || authTagBytes > 16 || (authTagBytes & 0x01))
        return kCCParamError;
    if (lengthFieldBytes < 2 || lengthFieldBytes > 8)
        return kCCParamError;
    
    // Block 0 byte 0: flags
    block[0] = ( (authTagBytes - 2) << 2 ) | ( lengthFieldBytes - 1 );  /* Adata flag is added later */
    
    // Nonce bytes
    memcpy(block+1, nonce, 15 - lengthFieldBytes);
    
    // Length field
    for (unsigned int i = 15; i > 15 - lengthFieldBytes; i--) {
        block[i] = messageBytes & 0xFF;
        messageBytes >>= 8;
    }
    
    if (!aad && aadBytes)
        return kCCParamError;
    
    if (aadBytes > 0) {
        int l_a_encoding;
        
        block[0] |= 0x40; /* Set the Adata flag */
        memset(block + 16, 0, sizeof(block) - 16);
        
        /* Format the length field into B_1 */
        if (aadBytes < 0xFF00) {
            block[16] = ( aadBytes & 0xFF00 ) >> 8;
            block[17] = ( aadBytes & 0x00FF );
            l_a_encoding = 2;
        } else
#if SIZE_MAX > 0x100000000
            if (aadBytes < 0x100000000)
#endif
            {
            block[16] = 0xFF;
            block[17] = 0xFE;
            OSWriteBigInt32(block, 18, aadBytes);
            l_a_encoding = 6;
        }
#if SIZE_MAX > 0x100000000
            else {
            block[16] = 0xFF;
            block[17] = 0xFF;
            OSWriteBigInt64(block, 18, aadBytes);
            l_a_encoding = 10;
        }
#endif
        
        /* Append however much of AAD fits into B_1 */
        unsigned aadInFirstBlock = 16 - l_a_encoding;
        if (aadInFirstBlock > aadBytes)
            aadInFirstBlock = (unsigned)aadBytes;
        memcpy(block + 16 + l_a_encoding, aad, aadInFirstBlock);
        
        CHECK_CRYPT(block, 32, dummy, sizeof(dummy));
        
        aadBytes -= aadInFirstBlock;
        aad += aadInFirstBlock;
        
        unsigned lastBlockOffset = 16; // The location of the last CBC output block in the dummy buffer
        
        // Run the remaining AAD through CBC
        while (aadBytes >= WORKING_BUF_SIZE) {
            CHECK_CRYPT(aad, WORKING_BUF_SIZE, dummy, sizeof(dummy));
            
            aadBytes -= WORKING_BUF_SIZE;
            aad += WORKING_BUF_SIZE;
            lastBlockOffset = WORKING_BUF_SIZE - 16;
        }
        if (aadBytes > 0) {
            /* We have a partial buffer remaining, so pad it with zeroes, run it through CBC, and copy out the last block */
            memset(block, 0, WORKING_BUF_SIZE);
            memcpy(block, aad, aadBytes);
            size_t stub = ( aadBytes + 15 ) & ~0x0F;  // Round up to block boundary
            CHECK_CRYPT(block, stub, dummy, sizeof(dummy));
            lastBlockOffset = (unsigned)stub - 16;
        }
        
        /* Copy the final CBC output to caller, in case the encrypted data length is 0 */
        memcpy(outLastBlock, dummy + lastBlockOffset, 16);
    } else {
        // No AAD. We're just encrypting the first block (with the flags and nonce).
        
        CHECK_CRYPT(block, 16, outLastBlock, 16);
    }
    
    return kCCSuccess;
#undef WORKING_BUF_SIZE
    
failure:
    return ccerr;
}

__attribute__((visibility ("internal")))
CCCryptorStatus ccmProcessMessage(CCCryptorRef cbcState, uint8_t *outLastBlock, const uint8_t *bytes, size_t byteCount)
{
    CCCryptorStatus ccerr;
    uint8_t *discardBuf;
    
    if (byteCount == 0)
        return kCCSuccess;
    
#define DISCARD_BUF_SIZE 8192
    discardBuf = malloc(DISCARD_BUF_SIZE);
    
    while (byteCount >= DISCARD_BUF_SIZE) {
        CHECK_CRYPT(bytes, DISCARD_BUF_SIZE, discardBuf, DISCARD_BUF_SIZE);
        
        byteCount -= DISCARD_BUF_SIZE;
        bytes += DISCARD_BUF_SIZE;
    }
    
    if (byteCount == 0) {
        memcpy(outLastBlock, discardBuf - 16, 16);
    } else {
        size_t wholeBlocks = byteCount & ~0x0F;
        
        if (wholeBlocks) {
            CHECK_CRYPT(bytes, wholeBlocks, discardBuf, DISCARD_BUF_SIZE);
            
            byteCount -= wholeBlocks;
            bytes += wholeBlocks;
        }
        
        if (byteCount == 0) {
            memcpy(outLastBlock, discardBuf + wholeBlocks - 16, 16);
        } else {
            memset(discardBuf, 0, 16);
            memcpy(discardBuf, bytes, byteCount);
            CHECK_CRYPT(discardBuf, 16, outLastBlock, 16);
        }
    }
    
    free(discardBuf);
    return kCCSuccess;
    
failure:
    free(discardBuf);
    return ccerr;
#undef DISCARD_BUF_SIZE
}

__attribute__((visibility ("internal")))
CCCryptorStatus ccmCreateCTRCryptor(CCOperation operation, const uint8_t *key, unsigned int keyBytes, const uint8_t *nonce, unsigned int L, CCCryptorRef *outKeystreamState)
{
    CCCryptorStatus cerr;
    
    /* If this parameter is out of range we should have caught it before here */
    if (L < 2 || L > 8)
        abort();
    
    /* Set up the initial CTR state per RFC3610[2.3] */
    _Static_assert(kCCBlockSizeAES128 == 16, "16 != 16");
    uint8_t ctrIV[16];
    memset(ctrIV, 0, 16);
    ctrIV[0] = (uint8_t)( L - 1 );
    memcpy(ctrIV + 1, nonce, 15 - L);  /* L=8 --> 7 bytes of nonce. */
    
    /* Apple's documentation isn't explicit on this point, but the IV input for kCCModeCTR is the contents of the counter buffer for the first block. It is incremented each block as if it were a single big-endian 128-bit number (or perhaps a 64-bit number--- anyway, it's incremented). */
    cerr = CCCryptorCreateWithMode(operation, kCCModeCTR, kCCAlgorithmAES, ccNoPadding,
                                   ctrIV, key, keyBytes,
                                   NULL, 0, 0,
                                   kCCModeOptionCTR_BE /* "Deprecated", but if you don't use it, this call fails (on 10.9 at least) */,
                                   outKeystreamState);
    
    return cerr;
}


