// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDataTransform.h>

#if HAVE_OF_DATA_TRANSFORM

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFErrors.h>
#include <compression.h>
#include <bzlib.h>

RCS_ID("$Id$")

OB_REQUIRE_ARC

@implementation OFDataTransform

@synthesize error, chunkSize;

- (BOOL)transformBuffer:(const void *)input size:(size_t)inputLength final:(BOOL)lastInput consumed:(size_t *)inputConsumed toBuffer:(void *)output size:(size_t)outputLength produced:(size_t *)outputProduced;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (BOOL)transformData:(NSData *)input range:(NSRange)inputRange final:(BOOL)lastInput consumed:(size_t *)inputConsumed toBuffer:(void *)output size:(size_t)outputLength produced:(size_t *)outputProduced;
{
    BOOL __block overallReturnValue = YES;
    size_t __block lastReadPosition = 0;
    size_t __block amountProducedSoFar = 0;
    
    if (NSMaxRange(inputRange) > [input length]) {
        OBRejectInvalidCall(self, _cmd, @"Input range %@ exceeds data length %" PRIuNS "", NSStringFromRange(inputRange), [input length]);
    }
    
    [input enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
        OBINVARIANT(lastReadPosition == byteRange.location);
        
        // Adjust the start location of the range if byteRange starts before the range of interest (inputRange)
        if (byteRange.location < inputRange.location) {
            if (NSMaxRange(byteRange) <= inputRange.location) {
                lastReadPosition = NSMaxRange(byteRange);
                return;
            }
            NSUInteger trimmedLeft = inputRange.location - byteRange.location;
            bytes += trimmedLeft;
            byteRange.location = inputRange.location;
            lastReadPosition = inputRange.location;
            byteRange.length -= trimmedLeft;
        }
        
        // Adjust the end location if byteRange extends past inputRange
        BOOL subblockIsFinal;
        if (NSMaxRange(byteRange) >= NSMaxRange(inputRange)) {
            byteRange.length = NSMaxRange(inputRange) - byteRange.location;
            *stop = YES;
            subblockIsFinal = lastInput;
        } else {
            subblockIsFinal = NO;
        }
        
        size_t amountConsumedHere = 0, amountProducedHere = 0;
        BOOL subOK = [self transformBuffer:bytes size:byteRange.length final:subblockIsFinal consumed:&amountConsumedHere
                                  toBuffer:output + amountProducedSoFar size:outputLength - amountProducedSoFar produced:&amountProducedHere];
        OBASSERT_IF(!subOK, self.error != nil);
        
        amountProducedSoFar += amountProducedHere;
        lastReadPosition = byteRange.location + amountConsumedHere;
        
        if (amountConsumedHere != byteRange.length)
            *stop = YES;
        
        if (!subOK) {
            *stop = YES;
            overallReturnValue = NO;
        }
    }];
    
    OBASSERT(lastReadPosition >= inputRange.location);  // This shouldn't be able to fail, unless -enumerateByteRangesUsingBlock: doesn't call us as much as it should
    
    *inputConsumed = lastReadPosition - inputRange.location;
    *outputProduced = amountProducedSoFar;
    if (overallReturnValue) {
        OBPOSTCONDITION(*outputProduced == outputLength || *inputConsumed == inputRange.length);
    }
    return overallReturnValue;
}

#define DEFAULT_CHUNK_SIZE (4 * 1024 * 1024)

static dispatch_data_t create_dispatch_data(char *, size_t, size_t) DISPATCH_RETURNS_RETAINED;

- (BOOL)transformData:(NSData *)input range:(NSRange)inputRange final:(BOOL)lastInput consumed:(size_t *)inputConsumed toBlock:(BOOL (^)(dispatch_data_t NS_RELEASES_ARGUMENT buf, NSError **))bufferConsumer;
{
    size_t chunk_size = self.chunkSize;

    if (chunk_size <= 0) {
        chunk_size = DEFAULT_CHUNK_SIZE;
    }
    
    char *intermediateBuffer = NULL;
    size_t intermediateFilled = 0;
    BOOL ok = YES;
    
    NSUInteger initialInputStart = inputRange.location;
    
    while (inputRange.length > 0) {
        if (!intermediateBuffer) {
            chunk_size = self.chunkSize;
            if (chunk_size <= 0) {
                chunk_size = DEFAULT_CHUNK_SIZE;
            }
            intermediateBuffer = malloc(chunk_size);
            OBASSERT(intermediateFilled == 0);
        }
        
        size_t intermediateFilledHere = 0;
        size_t inputConsumedHere = 0;
        
        ok = [self transformData:input range:inputRange final:lastInput consumed:&inputConsumedHere toBuffer:intermediateBuffer size:chunk_size produced:&intermediateFilledHere];
        
        intermediateFilled += intermediateFilledHere;
        inputRange.location += inputConsumedHere;
        inputRange.length -= inputConsumedHere;
        
        if (intermediateFilled == chunk_size) {
            dispatch_data_t chunk = dispatch_data_create(intermediateBuffer, intermediateFilled, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
            intermediateBuffer = NULL;
            intermediateFilled = 0;
            NSError * __autoreleasing intermediateError = nil;
            BOOL cb_ok = bufferConsumer(chunk, &intermediateError);
            OBASSERT_IF(!cb_ok, intermediateError);
            if (!cb_ok) {
                if (!error)
                    error = intermediateError;
                ok = NO;
            }
        }
        
        if (!ok)
            break;
    }
    
    if (intermediateFilled > 0) {
        dispatch_data_t chunk = create_dispatch_data(intermediateBuffer, intermediateFilled, chunk_size);
        intermediateBuffer = NULL;
        NSError * __autoreleasing intermediateError = nil;
        BOOL cb_ok = bufferConsumer(chunk, &intermediateError);
        OBASSERT_IF(!cb_ok, intermediateError);
        if (!cb_ok) {
            if (!error)
                error = intermediateError;
            ok = NO;
        }
    } else if (intermediateBuffer != NULL) {
        free(intermediateBuffer);
    }
    
    *inputConsumed = inputRange.location - initialInputStart;
    return ok;
}

static dispatch_data_t create_dispatch_data(char *buffer, size_t buffer_filled, size_t buffer_allocated)
{
    // For small enough chunks, instead of calling realloc(), we copy down into a new small allocation (well, we get libdispatch to do the copying). The reason is that large allocs come from a different, VM-managed arena than smaller ones, and realloc() never moves a block when it's shrunk. We don't want to chew up our address space with large-alloc regions that just hold a small buffer. If a memory block is small enough, it's cheap to copy.
    if (buffer_filled < (8 * 1024) && buffer_allocated >= (16 * 1024)) {
        dispatch_data_t chunk = dispatch_data_create(buffer, buffer_filled, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT); // DESTRUCTOR_DEFAULT causes the buffer to be copied
        free(buffer);
        return chunk;
    }
    
    if (buffer_filled + 4096 <= buffer_allocated) {
        // It's not clear that this actually helps us at all on OSX, but let's attempt to free up the unused end of the buffer
        buffer = reallocf(buffer, buffer_filled);
    }
    
    return dispatch_data_create(buffer, buffer_filled, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
}

- (NSData *)transformData:(NSData *)input options:(OFDataTransformOptions)options error:(NSError **)outError;
{
    if (options & OFDataTransformOptionChunked) {
        dispatch_data_t __block buf = dispatch_data_empty;
        size_t amountTaken = 0;
        
        if (![self transformData:input range:(NSRange){0, input.length} final:YES consumed:&amountTaken toBlock:^BOOL(dispatch_data_t  _Nonnull NS_RELEASES_ARGUMENT chunk, NSError **dummyOutError) {
            buf = dispatch_data_create_concat(buf, chunk);
            return YES;
        }]) {
            if (outError)
                *outError = self.error;
            return nil;
        }
        OBASSERT(amountTaken == input.length);
        
        return (NSData *)buf;
    } else {
        char *buf = NULL;
        size_t buf_allocated = 0;
        size_t buf_used = 0;
        size_t input_length = input.length;
        size_t input_consumed = 0;
        
        for (;;) {
            
            // Resize the output buffer intelligently.
            {
                size_t remaining = input_length - input_consumed;
                size_t space_required = MAX(1024u, buf_allocated - buf_used);
                float expansion;
                if (input_consumed > 512 && buf_used > 4*1024) {
                    // Adaptive exponential buffer expansion
                    expansion = (float)buf_used / (float)input_consumed;
                } else {
                    // Guesstimate
                    expansion = self.expanding? 2 : 0.5;
                }
                space_required = MAX(space_required, (unsigned long)lrintf(expansion * remaining));
                
                // Apple documents its realloc implementation to be equivalent to malloc if the old pointer is NULL.
                buf_allocated = buf_used + space_required;
                buf = reallocf(buf, buf_allocated);
            }
            
            // Process data.
            {
                size_t consumed_this_round = 0;
                size_t produced_this_round = 0;
                size_t input_available = input_length - input_consumed;
                size_t space_available = buf_allocated - buf_used;
                BOOL ok = [self transformData:input range:(NSRange){ input_consumed, input_available } final:YES
                                     consumed:&consumed_this_round toBuffer:buf + buf_used size:space_available produced:&produced_this_round];
                if (!ok) {
                    free(buf);
                    if (outError)
                        *outError = self.error;
                    return nil;
                }
                
                OBASSERT(consumed_this_round == input_available || produced_this_round == space_available);
                
                input_consumed += consumed_this_round;
                buf_used += produced_this_round;
                
                if (consumed_this_round == input_available && produced_this_round < space_available) {
                    // End condition.
                    break;
                }
            }
        }
        
        buf = reallocf(buf, buf_used);
        return [NSData dataWithBytesNoCopy:buf length:buf_used freeWhenDone:YES];
    }
}


@end

@implementation OFLibSystemCompressionTransform
{
    compression_stream cstrm;
    BOOL expanding;
}

- (instancetype __nullable)initWithAlgorithm:(compression_algorithm)alg operation:(compression_stream_operation)op;
{
    if (!(self = [super init]))
        return nil;
    
    expanding = ( op == COMPRESSION_STREAM_DECODE );
    
    compression_status cok = compression_stream_init(&cstrm, op, alg);
    if (cok != COMPRESSION_STATUS_OK) {
        return nil;
    } else {
        return self;
    }
}

- (void)dealloc
{
    compression_stream_destroy(&cstrm);
}

- (BOOL)transformBuffer:(const void *)input size:(size_t)inputLength final:(BOOL)lastInput consumed:(size_t *)inputConsumed toBuffer:(void *)output size:(size_t)outputLength produced:(size_t *)outputProduced;
{
    cstrm.src_ptr = input;
    cstrm.src_size = inputLength;
    cstrm.dst_ptr = output;
    cstrm.dst_size = outputLength;
    
    compression_status cok = compression_stream_process(&cstrm, lastInput? COMPRESSION_STREAM_FINALIZE : 0);
    
    *inputConsumed = inputLength - cstrm.src_size;
    *outputProduced = outputLength - cstrm.dst_size;
    
    if (cok == COMPRESSION_STATUS_ERROR) {
        // The compression API doesn't actually tell us why anything fails.
        self.error = [NSError errorWithDomain:OFErrorDomain
                                         code:(expanding? OFUnableToDecompressData : OFUnableToCompressData)
                                     userInfo:nil];
        return NO;
    } else {
        return YES;
    }
}

@synthesize expanding;

@end

@implementation OFLimitedBufferSizeTransform

- (BOOL)transformBuffer:(const void *)input size:(size_t)inputLength final:(BOOL)lastInput consumed:(size_t *)inputConsumed toBuffer:(void *)output size:(size_t)outputLength produced:(size_t *)outputProduced;
{
    if (inputLength > max_input || outputLength > max_output) {
        BOOL rok;
        size_t consumed = 0;
        size_t produced = 0;
        do {
            size_t ichunk = MIN(max_input, inputLength - consumed);
            size_t ochunk = MIN(max_output, outputLength - produced);
            BOOL isFinal = lastInput && (ichunk == (inputLength - consumed));
            size_t amountConsumedHere = 0, amountProducedHere = 0;
            rok = [self transformBuffer:input size:ichunk final:isFinal consumed:&amountConsumedHere toBuffer:output size:ochunk produced:&amountProducedHere];
            consumed += amountConsumedHere;
            produced += amountProducedHere;
            if (!rok)
                break;
            if (amountConsumedHere < ichunk && amountProducedHere < ochunk)
                break;
            if (produced >= outputLength)
                break;
        } while (inputLength < consumed);
        *inputConsumed = consumed;
        *outputProduced = produced;
        return rok;
    } else {
        OBRequestConcreteImplementation(self, _cmd);
    }
}

@end


static NSError *bz_error(NSInteger code, int bzcode, NSString *fnname);

@implementation OFBZip2Compress
{
    bz_stream bstrm;
    BOOL bzstrm_finalized;
    BOOL finishing;
}

- (instancetype __nullable)initWithCompressionLevel:(int)blockSize100k workFactor:(int)wf;
{
    if (!(self = [super init]))
        return nil;
    
    max_input = INT_MAX;
    max_output = INT_MAX;
    
    int bzok = BZ2_bzCompressInit(&bstrm, blockSize100k, 0, wf);
    if (bzok != BZ_OK) {
        self.error = bz_error(OFUnableToCompressData, bzok, @"BZ2_bzCompressInit");
        bzstrm_finalized = YES;
    } else {
        bzstrm_finalized = NO;
    }
    
    return self;
}

- (void)dealloc;
{
    if (!bzstrm_finalized) {
        BZ2_bzCompressEnd(&bstrm);
        bzstrm_finalized = YES;
    }
}

- (BOOL)transformBuffer:(const void *)input size:(size_t)inputLength final:(BOOL)lastInput consumed:(size_t *)inputConsumed toBuffer:(void *)output size:(size_t)outputLength produced:(size_t *)outputProduced;
{
    if (bzstrm_finalized)
        return NO;
    
    if (inputLength > max_input || outputLength > max_output)
        return [super transformBuffer:input size:inputLength final:lastInput consumed:inputConsumed toBuffer:output size:outputLength produced:outputProduced];
    
    bstrm.next_in = (char *)input;
    bstrm.avail_in = (int)inputLength;
    bstrm.next_out = (char *)output;
    bstrm.avail_out = (int)outputLength;
    
    int bzok = BZ2_bzCompress(&bstrm, lastInput ? BZ_FINISH : BZ_RUN);
    
    *inputConsumed = bstrm.next_in - (char *)input;
    *outputProduced = bstrm.next_out - (char *)output;
    
    switch(bzok) {
        case BZ_RUN_OK:
            OBASSERT(!lastInput);
            OBASSERT(bstrm.avail_in == 0 || bstrm.avail_out == 0);
            return YES;
            
        case BZ_FINISH_OK:
            OBASSERT(lastInput);
            OBASSERT(bstrm.avail_in == 0 || bstrm.avail_out == 0);
            return YES;
            
        case BZ_STREAM_END:
            OBASSERT(lastInput);
            OBASSERT(bstrm.avail_in == 0);
            return YES;
            
        default:
            self.error = bz_error(OFUnableToCompressData, bzok, @"BZ2_bzCompress");
            return NO;
            
    }
}

@end

@implementation OFBZip2Decompress
{
    bz_stream bstrm;
    BOOL bzstrm_finalized;
    BOOL stream_ended;
}

- (instancetype __nullable)init;
{
    if (!(self = [super init]))
        return nil;
    
    max_input = INT_MAX;
    max_output = INT_MAX;
    
    int bzok = BZ2_bzDecompressInit(&bstrm, 0, 0);
    if (bzok != BZ_OK) {
        self.error = bz_error(OFUnableToDecompressData, bzok, @"BZ2_bzDecompressInit");
        bzstrm_finalized = YES;
    } else {
        bzstrm_finalized = NO;
    }
    
    return self;
}

- (void)dealloc;
{
    if (!bzstrm_finalized) {
        BZ2_bzDecompressEnd(&bstrm);
        bzstrm_finalized = YES;
    }
}

- (BOOL)transformBuffer:(const void *)input size:(size_t)inputLength final:(BOOL)lastInput consumed:(size_t *)inputConsumed toBuffer:(void *)output size:(size_t)outputLength produced:(size_t *)outputProduced;
{
    if (stream_ended) {
        *inputConsumed = inputLength;
        *outputProduced = 0;
        return YES;
    }
    if (bzstrm_finalized)
        return NO;
    
    if (inputLength > max_input || outputLength > max_output)
        return [super transformBuffer:input size:inputLength final:lastInput consumed:inputConsumed toBuffer:output size:outputLength produced:outputProduced];
    
    bstrm.next_in = (char *)input;
    bstrm.avail_in = (int)inputLength;
    bstrm.next_out = (char *)output;
    bstrm.avail_out = (int)outputLength;
    
    int bzok = BZ2_bzDecompress(&bstrm);
    
    *inputConsumed = bstrm.next_in - (char *)input;
    *outputProduced = bstrm.next_out - (char *)output;
    
    switch(bzok) {
        case BZ_OK:
            if (lastInput) {
                if (bstrm.avail_in == 0 && bstrm.avail_out > 0) {
                    // Truncated input stream.
                    self.error = [NSError errorWithDomain:OFErrorDomain
                                                     code:OFUnableToDecompressData
                                                 userInfo:@{ NSLocalizedFailureReasonErrorKey: @"BZIP2 stream ended unexpectedly." }];
                    BZ2_bzDecompressEnd(&bstrm);
                    bzstrm_finalized = YES;
                    return NO;
                } else {
                    return YES;
                }
            } else {
                OBASSERT(bstrm.avail_in == 0 || bstrm.avail_out == 0);
                return YES;
            }
            
        case BZ_STREAM_END:
            // Discard any input past the end-of-stream
            *inputConsumed = inputLength;
            stream_ended = YES;
            BZ2_bzDecompressEnd(&bstrm);
            bzstrm_finalized = YES;
            return YES;
            
        default:
            self.error = bz_error(OFUnableToDecompressData, bzok, @"BZ2_bzDecompress");
            BZ2_bzDecompressEnd(&bstrm);
            bzstrm_finalized = YES;
            return NO;
    }
}

@end

static const struct { int v; CFStringRef n; } bzerrors[] = {
#define VAL(x) { x , CFSTR( #x )}
    VAL(BZ_OK),
    VAL(BZ_RUN_OK),
    VAL(BZ_FLUSH_OK),
    VAL(BZ_FINISH_OK),
    VAL(BZ_STREAM_END),
    VAL(BZ_SEQUENCE_ERROR),
    VAL(BZ_PARAM_ERROR),
    VAL(BZ_MEM_ERROR),
    VAL(BZ_DATA_ERROR),
    VAL(BZ_DATA_ERROR_MAGIC),
    VAL(BZ_IO_ERROR),
    VAL(BZ_UNEXPECTED_EOF),
    VAL(BZ_OUTBUFF_FULL),
    VAL(BZ_CONFIG_ERROR),
#undef VAL
};
static NSString *bz_errstr(int bzerr) {
    for (size_t i = 0; i < (sizeof(bzerrors)/sizeof(*bzerrors)); i++) {
        if (bzerrors[i].v == bzerr)
            return (__bridge NSString *)(bzerrors[i].n);
    }
    return [NSString stringWithFormat:@"%d", bzerr];
}

static NSError *bz_error(NSInteger code, int bzcode, NSString *fnname)
{
    return [NSError errorWithDomain:OFErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"%@() returned %@.", fnname, bz_errstr(bzcode)] }];
    
}

#endif
