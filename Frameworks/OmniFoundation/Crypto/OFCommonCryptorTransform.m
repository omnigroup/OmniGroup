// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFCommonCryptorTransform.h"

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

@implementation OFCommonCryptorTransform
{
    CCCryptorRef cryptor;
    NSData *buffered;
}

- (instancetype)initWithCryptor:(CCCryptorRef /* CONSUMED */)cr;
{
    self = [super init];
    
    if (!cr) {
        OBRejectInvalidCall(self, _cmd, @"cryptor must not be NULL");
    }
    
    cryptor = cr;
    
    return self;
}

- (void)dealloc
{
    CCCryptorRelease(cryptor);
}

/// Copy any internally buffered output to the caller's buffer.
/// Returns YES if there is still more buffered output to produce, NO if the buffer is empty.
/// In either case, updates *outputProduced.
- (BOOL)_emitBuffered:(void *)output size:(size_t)outputLength produced:(size_t *)outputProduced;
{
    if (buffered) {
        size_t alreadyProduced = *outputProduced;
        size_t amountBuffered = buffered.length;
        if ((alreadyProduced+amountBuffered) <= outputLength) {
            [buffered getBytes:output length:amountBuffered];
            buffered = nil;
            *outputProduced = alreadyProduced + amountBuffered;
            return NO;
        } else {
            [buffered getBytes:output length:outputLength];
            buffered = [buffered subdataWithRange:(NSRange){ .location = outputLength, .length = amountBuffered - outputLength }];
            *outputProduced = alreadyProduced + outputLength;
            return YES;
        }
    } else {
        return NO;
    }
}

static size_t round_down_a_bit(size_t len)
{
    if (len > 0x1000) {
        return len & ~0x0FFF;
    } else if (len > 0x10) {
        return len & ~0x0F;
    } else {
        return len;
    }
}

- (BOOL)transformBuffer:(const void *)input size:(size_t)inputLength final:(BOOL)lastInput consumed:(size_t *)inputConsumed toBuffer:(void *)output size:(size_t)outputLength produced:(size_t *)outputProduced;
{
    size_t alreadyConsumed = 0;
    size_t alreadyProduced = 0;
    OSStatus cerr;
    
    /* Write out any buffered data */
    if ([self _emitBuffered:output size:outputLength produced:&alreadyProduced]) {
        /* More is buffered than we have room for right now; return */
        OBPOSTCONDITION(alreadyProduced == outputLength);
        *inputConsumed = 0;
        *outputProduced = alreadyProduced;
        return YES;
    }
    OBINVARIANT(!buffered);
    
    /* We only deallocate the cryptor after consuming all of the input (lastInput==YES). If we have more input after that, the caller is doing something wrong (sneaking more data in after indicating EOF). */
    OBASSERT_IF(!cryptor, inputLength == 0);
    OBASSERT_IF(!cryptor, lastInput == YES);
    
    /* Run the cryptor over the data, until we either run out of input data, or run out of output space. */
    while (inputLength > alreadyConsumed && outputLength > alreadyProduced) {
        
        size_t amountOfferedThisCall = inputLength - alreadyConsumed;
        size_t amountProducedThisCall = 0;
        cerr = CCCryptorUpdate(cryptor, input + alreadyConsumed, amountOfferedThisCall, output + alreadyProduced, outputLength - alreadyProduced, &amountProducedThisCall);
        if (cerr == kCCSuccess) {
            alreadyConsumed += amountOfferedThisCall;
            alreadyProduced += amountProducedThisCall;
        }
        
        if (cerr == kCCBufferTooSmall) {
            // Two possibilities: either we only have a smidgen of output space, in which case write to a temporary buffer and copy slices out; or we have a lot of output space, in which case fill most of it then repeat.
            size_t spaceAvailable = outputLength - alreadyProduced;
            if (spaceAvailable <= 8*1024) {
                // Smidgen.
                amountOfferedThisCall = MIN(inputLength - alreadyConsumed, 8*1024u);
                size_t expectedOutput = CCCryptorGetOutputLength(cryptor, amountOfferedThisCall, false);
                NSMutableData *newBufferedData = [[NSMutableData alloc] initWithLength:expectedOutput + 1024];
                amountProducedThisCall = 0;
                cerr = CCCryptorUpdate(cryptor, input + alreadyConsumed, amountOfferedThisCall, [newBufferedData mutableBytes], [newBufferedData length], &amountProducedThisCall);
                // NSLog(@"Making smidgen buffer, expecting size %zu bytes", expectedOutput);
                if (cerr == kCCSuccess) {
                    OBASSERT(amountProducedThisCall == expectedOutput);
                    [newBufferedData setLength:amountProducedThisCall];
                    buffered = newBufferedData;
                    alreadyConsumed += amountOfferedThisCall;
                    [self _emitBuffered:output + alreadyProduced size:outputLength - alreadyProduced produced:&alreadyProduced];
                    // If _emitBuffered: didn't fully consume the buffer, then it guarantees that alreadyProduced has been advanced to the end of the output buffer, which will cause us to break out of this loop and return to the caller.
                }
            } else {
                // Large amount. Try to figure out how much we can process with the buffer we have.
                size_t bufferSpaceWanted = CCCryptorGetOutputLength(cryptor, amountOfferedThisCall, false);
                OBASSERT(bufferSpaceWanted > spaceAvailable); // Otherwise, we shouldn't have gotten kCCBufferTooSmall the last time.
                
                // Try to guess how much we can feed the cryptor to exactly fill our output buffer.
                amountOfferedThisCall = (bufferSpaceWanted >= amountOfferedThisCall)? (spaceAvailable - (bufferSpaceWanted - amountOfferedThisCall)) : spaceAvailable;
                bufferSpaceWanted = CCCryptorGetOutputLength(cryptor, amountOfferedThisCall, false);
                // NSLog(@"Adjusting cryptor input chunk to %zu bytes, hoping to get %zu out (looks like we do get %zu)", amountOfferedThisCall, spaceAvailable, bufferSpaceWanted);
                
                if (bufferSpaceWanted > spaceAvailable) {
                    // Nope. Phooey. Assume that the cryptor isn't expanding things by very much. Any slop will be taken up by the smidgen buffer.
                    amountOfferedThisCall = round_down_a_bit(MIN(amountOfferedThisCall, spaceAvailable) - 512);
                }
                
                // Okay, invoke the cryptor again. If this fails, we just fall through to the failure check below; there's obviously something unexpected going on.
                amountProducedThisCall = 0;
                cerr = CCCryptorUpdate(cryptor, input + alreadyConsumed, amountOfferedThisCall, output + alreadyProduced, outputLength - alreadyProduced, &amountProducedThisCall);
                if (cerr == kCCSuccess) {
                    alreadyConsumed += amountOfferedThisCall;
                    alreadyProduced += amountProducedThisCall;
                }
            }
        }
        
        if (cerr != kCCSuccess) {
            self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:@{ @"function": @"CCCryptorUpdate" }];
            *inputConsumed = alreadyConsumed;
            *outputProduced = alreadyProduced;
            return NO;
        }
        
        // Abort immediately on buffer overrun. Should only be able to happen if CCCryptorUpdate() misbehaves.
        assert(inputLength >= alreadyConsumed);
        assert(outputLength >= alreadyProduced);
    }
    
    BOOL successful;
    if (!lastInput || (inputLength > alreadyConsumed) || buffered) {
        /* We're done with this buffer, but there will be more later. */
        successful = YES;
    } else if (cryptor == NULL) {
        /* See the above OBASSERT_IF()s. */
        [NSException raise:NSInvalidArgumentException format:@"Invalid calling sequence."];
    } else {
        /* Squeeze out any final dribbles produced by CCCryptorFinal(). */
        
        size_t expectedOutputLength = CCCryptorGetOutputLength(cryptor, 0, true);
        if (alreadyProduced + expectedOutputLength <= outputLength) {
            /* Write it directly into the caller's buffer if there's space */
            size_t amountProduced = 0;
            cerr = CCCryptorFinal(cryptor, output + alreadyProduced, outputLength - alreadyProduced, &amountProduced);
            if (cerr != kCCSuccess) {
                self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:@{ @"function": @"CCCryptorFinal" }];
                successful = NO;
            } else {
                OBASSERT(amountProduced == expectedOutputLength); // Hopefully CCCryptorGetOutputLength isn't lying to us
                alreadyProduced += amountProduced;
                successful = YES;
            }
        } else {
            /* Otherwise, buffer it internally */
            size_t amountProduced = 0;
            NSMutableData *buffer = [[NSMutableData alloc] initWithLength:expectedOutputLength];
            cerr = CCCryptorFinal(cryptor, [buffer mutableBytes], [buffer length], &amountProduced);
            if (cerr != kCCSuccess) {
                self.error = [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:@{ @"function": @"CCCryptorFinal" }];
                successful = NO;
            } else {
                OBASSERT(amountProduced == expectedOutputLength); // Hopefully CCCryptorGetOutputLength isn't lying to us
                [buffer setLength:amountProduced];
                [self _emitBuffered:output size:outputLength produced:&alreadyProduced];
                successful = YES;
            }
        }
        
        CCCryptorRelease(cryptor);
        cryptor = NULL;
    }
    
    if (successful) {
        // Our contract with the caller is that, unless we error out, we either consume all input data or all output space.
        OBPOSTCONDITION(inputLength == alreadyConsumed || outputLength == alreadyProduced);
    }
    
    *inputConsumed = alreadyConsumed;
    *outputProduced = alreadyProduced;
    return successful;
}

@end

