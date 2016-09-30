// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniFoundation/OFAEADCryptor.h>
#import <OmniBase/OmniBase.h>
#import <dispatch/dispatch.h>

RCS_ID("$Id$");

dispatch_data_t OFAuthenticatedStreamDecrypt(OFAuthenticatedStreamDecryptorState st, NSData *ciphertext, NSData *mac, NSError **outError)
{
    uint8_t partialBlockBuf[kCCBlockSizeAES128], *partialBlock = partialBlockBuf;
    unsigned partialBlockUsed __block = 0;
    NSError *failure __block = nil;
    NSUInteger ciphertextLength = ciphertext.length;
    NSMutableArray *segments = [[NSMutableArray alloc] init];
    
    [ciphertext enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
        
        /* The OFAuthenticatedStreamDecryptorUpdateFunc requires integral numbers of blocks per call, except for the last call. */
        BOOL isLastBlock = ( NSMaxRange(byteRange) == ciphertextLength );
        if (partialBlockUsed) {
            if (partialBlockUsed + byteRange.length < kCCBlockSizeAES128) {
                memcpy(partialBlock + partialBlockUsed, bytes, byteRange.length);
                partialBlockUsed += byteRange.length;
                if (!isLastBlock)
                    return;
            } else {
                size_t amount = kCCBlockSizeAES128 - partialBlockUsed;
                memcpy(partialBlock + partialBlockUsed, bytes, amount);
                bytes += amount;
                byteRange.location += amount;
                byteRange.length -= amount;
                partialBlockUsed = kCCBlockSizeAES128;
            }
        }
        
        size_t amountToProcess = byteRange.length + partialBlockUsed;
        if (!isLastBlock) {
            amountToProcess = amountToProcess & ~(kCCBlockSizeAES128 - 1);
        }
        
        void *plaintextBuffer = malloc(amountToProcess);
        if (!plaintextBuffer)
            abort();
        
        OFAuthenticatedStreamDecryptorUpdateFunc update = st->update;
        CCCryptorStatus cerr;
        if (partialBlockUsed) {
            OBASSERT((isLastBlock && byteRange.length == 0) || partialBlockUsed == kCCBlockSizeAES128);
            cerr = update(st, partialBlock, partialBlockUsed, plaintextBuffer);
            if (cerr == kCCSuccess && amountToProcess > partialBlockUsed)
                cerr = update(st, bytes, amountToProcess - partialBlockUsed, plaintextBuffer + partialBlockUsed);
            partialBlockUsed = 0;
        } else {
            cerr = update(st, bytes, amountToProcess, plaintextBuffer);
        }
        
        if (cerr != kCCSuccess) {
            free(plaintextBuffer);
            failure = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:@{ @"function" : @"OFAuthenticatedStreamDecryptorUpdate" }];
            *stop = YES;
            return;
        }
        
        dispatch_data_t segment = dispatch_data_create(plaintextBuffer, amountToProcess, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
        [segments addObject:segment];
        dispatch_release(segment);
    }];
    
    CCCryptorStatus cerr = st->final(st, [mac bytes], [mac length]);
    if (!failure && cerr != kCCSuccess) {
        failure = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:@{ @"function" : @"OFAuthenticatedStreamDecryptorFinal" }];
    }
    
    if (failure) {
        [segments release];
        if (outError)
            *outError = failure;
        return nil;
    }
    
    while (segments.count > 1) {
        for (NSUInteger i = 0; i+1 < segments.count; i++) {
            dispatch_data_t left = [segments objectAtIndex:i];
            dispatch_data_t right = [segments objectAtIndex:i+1];
            dispatch_data_t conc = dispatch_data_create_concat(left, right);
            [segments replaceObjectAtIndex:i withObject:conc];
            [segments removeObjectAtIndex:i+1];
            dispatch_release(conc);
        }
    }
    
    dispatch_data_t result;
    if (segments.count) {
        result = [segments objectAtIndex:0];
    } else {
        result = dispatch_data_empty;
    }
    
    dispatch_retain(result);
    [segments release];
    return result;
}

