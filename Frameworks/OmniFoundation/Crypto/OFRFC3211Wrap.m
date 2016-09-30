// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$")

#import "OFRFC3211Wrap.h"

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonRandom.h>

#if WITH_RFC3211_KEY_WRAP

NSData *OFRFC3211Wrap(NSData *CEK, NSData *KEK, NSData *iv, CCAlgorithm innerAlgorithm, size_t blockSize)
{
    NSUInteger cekLen = CEK.length;
    if (cekLen < 3 || cekLen > 255)
        return nil;
    
    uint8_t buf[4];
    buf[0] = (uint8_t)cekLen;
    [CEK getBytes:buf+1 range:(NSRange){0, 3}];
    buf[1] ^= 0xFF;  // One's-complement checksum bytes
    buf[2] ^= 0xFF;
    buf[3] ^= 0xFF;
    
    NSMutableData *toWrap = [NSMutableData dataWithBytes:buf length:4];
    [toWrap appendData:CEK];
    
    size_t unpaddedLength = toWrap.length;
    size_t padToLength = MAX(unpaddedLength, 2*blockSize);  // Minimum length is two blocks.
    padToLength = blockSize * ( (padToLength + blockSize - 1) / blockSize );  // Round up to integer number of blocks.
    if (unpaddedLength < padToLength) {
        // Pad with random data if necessary.
        [toWrap setLength:padToLength];
        CCRandomGenerateBytes(toWrap.mutableBytes + unpaddedLength, padToLength - unpaddedLength);
    }
    
    CCCryptorStatus cerr;
    
    CCCryptorRef cr = NULL;
    cerr = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCBC, innerAlgorithm, ccNoPadding,
                                   iv.bytes,
                                   KEK.bytes, KEK.length,
                                   NULL, 0, 0, 0,
                                   &cr);
    if (cerr)
        return nil;
    
    uint8_t *midBuffer = malloc(padToLength);
    size_t bytesMoved = 0;
    cerr = CCCryptorUpdate(cr, toWrap.bytes, padToLength, midBuffer, padToLength, &bytesMoved);
    if (cerr || (bytesMoved != padToLength)) {
        free(midBuffer);
        CCCryptorRelease(cr);
        return nil;
    }
    
    uint8_t *outBuffer = malloc(padToLength);
    bytesMoved = 0;
    cerr = CCCryptorUpdate(cr, midBuffer, padToLength, outBuffer, padToLength, &bytesMoved);
    free(midBuffer);
    CCCryptorRelease(cr);
    if (cerr || (bytesMoved != padToLength)) {
        free(outBuffer);
        return nil;
    }
    
    NSData *result = [NSData dataWithBytesNoCopy:outBuffer length:padToLength freeWhenDone:YES];
    return result;
}

NSData *OFRFC3211Unwrap(NSData *input, NSData *KEK, NSData *iv, CCAlgorithm innerAlgorithm, size_t blockSize)
{
    CCCryptorStatus cerr;
    size_t inputLength = input.length;
    
    if (inputLength < (2*blockSize) ||
        (inputLength % blockSize) != 0)
        return nil;
    if (iv.length != blockSize)
        return nil;
    
    uint8_t *midBuffer = malloc(inputLength);
    
    CCCryptorRef cr = NULL;
    cerr = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCBC, innerAlgorithm, ccNoPadding,
                                   [input bytes] + (inputLength - 2*blockSize),
                                   [KEK bytes], [KEK length],
                                   NULL, 0, 0, 0,
                                   &cr);
    if (cerr) {
        free(midBuffer);
        return nil;
    }
    
    size_t bytesMoved = 0;
    cerr = CCCryptorUpdate(cr,
                           [input bytes] + (inputLength - blockSize), blockSize,
                           midBuffer     + (inputLength - blockSize), blockSize,
                           &bytesMoved);
    if (cerr || (bytesMoved != blockSize)) {
        free(midBuffer);
        CCCryptorRelease(cr);
        return nil;
    }
    
    cerr = CCCryptorReset(cr, midBuffer + (inputLength - blockSize));
    if (cerr) {
        free(midBuffer);
        CCCryptorRelease(cr);
        return nil;
    }
    
    bytesMoved = 0;
    cerr = CCCryptorUpdate(cr,
                           [input bytes], inputLength - blockSize,
                           midBuffer, inputLength - blockSize,
                           &bytesMoved);
    if (cerr || (bytesMoved != (inputLength - blockSize))) {
        free(midBuffer);
        CCCryptorRelease(cr);
        return nil;
    }
    
    bytesMoved = 0;
    cerr = CCCryptorFinal(cr, midBuffer + inputLength, 0, &bytesMoved); // Should be a no-op
    if (cerr || (bytesMoved != 0)) {
        free(midBuffer);
        CCCryptorRelease(cr);
        return nil;
    }
    
    cerr = CCCryptorReset(cr, [iv bytes]);
    if (cerr) {
        free(midBuffer);
        CCCryptorRelease(cr);
        return nil;
    }
    
    uint8_t *outBuffer = malloc(inputLength);
    cerr = CCCryptorUpdate(cr,
                           midBuffer, inputLength,
                           outBuffer, inputLength,
                           &bytesMoved);
    free(midBuffer);
    if (cerr || (bytesMoved != inputLength)) {
        CCCryptorRelease(cr);
        free(outBuffer);
        return nil;
    }
    
    bytesMoved = 0;
    cerr = CCCryptorFinal(cr, midBuffer + inputLength, 0, &bytesMoved); // Should be a no-op
    CCCryptorRelease(cr);
    if (cerr || (bytesMoved != 0)) {
        free(outBuffer);
        return nil;
    }
    
    /* Sanity-check the length byte */
    uint8_t lengthByte = outBuffer[0];
    if ((lengthByte < 3) ||
        ((lengthByte + 4 + blockSize - 1) / blockSize != inputLength / blockSize)) {
        free(outBuffer);
        return nil;
    }
    
    /* Verify the checksum */
    uint8_t diffs = ( outBuffer[1] ^ outBuffer[4] ) & ( outBuffer[2] ^ outBuffer[5] ) & ( outBuffer[3] ^ outBuffer[6] );
    if (diffs != 0xFF) {
        free(outBuffer);
        return nil;
    }
    
    NSData *result = [NSData dataWithBytes:outBuffer + 4 length:lengthByte];
    free(outBuffer);
    
    return result;
}

#endif

