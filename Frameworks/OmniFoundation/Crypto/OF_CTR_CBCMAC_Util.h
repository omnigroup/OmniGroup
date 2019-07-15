// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#include <CommonCrypto/CommonCrypto.h>

/* Helpers for the CBC-MAC format described for CCM in RFC3610.
 *
 * ccmProcessHeaderBlocks() must be called first to process the nonce, header, and AAD.
 * ccmProcessMessage() may be called zero or more times afterwards. All but the last call *must* be an integer number of blocks, and the total byteCount must be exactly equal to the byte count passed to ccmProcessHeaderBlocks().
 *
 * The buffer pointed to by outLastBlock will contain the last block of CBC output after each call and can be used to compute the authentication tag.
 *
 * ccmCreateCTRCryptor() creates a CCCryptorRef in CTR mode with the appropriately formatted IV block.
 */
CCCryptorStatus ccmProcessHeaderBlocks(CCCryptorRef cbcState, unsigned int authTagBytes, unsigned int lengthFieldBytes, size_t messageBytes, size_t aadBytes, const uint8_t *aad, const uint8_t *nonce, uint8_t *outLastBlock) __attribute__((visibility ("internal"))) ;
CCCryptorStatus ccmProcessMessage(CCCryptorRef cbcState, uint8_t *outLastBlock, const uint8_t *bytes, size_t byteCount) __attribute__((visibility ("internal"))) ;
CCCryptorStatus ccmCreateCTRCryptor(CCOperation operation, const uint8_t *key, unsigned int keyBytes, const uint8_t *nonce, unsigned int L, CCCryptorRef *outKeystreamState) __attribute__((visibility ("internal"))) ;


