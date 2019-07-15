// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <Foundation/NSStream.h>
#import <dispatch/dispatch.h>
#import <compression.h>

// #define HAVE_OF_DATA_TRANSFORM 1

#if HAVE_OF_DATA_TRANSFORM

@class NSError;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(unsigned, OFDataTransformOptions) {
    OFDataTransformOptionNone      = 0,
    OFDataTransformOptionChunked   = 1 << 0
};

@interface OFDataTransform : NSObject

/// This is the only method subclasses need to override. It must either fill the output buffer, consume all of the input buffer, or return an error.
- (BOOL)transformBuffer:(const void *)input size:(size_t)inputLength final:(BOOL)lastInput consumed:(size_t *)inputConsumed toBuffer:(void *)output size:(size_t)outputLength produced:(size_t *)outputProduced;

/// Calls -transformBuffer:... for the contiguous ranges of `input`.
- (BOOL)transformData:(NSData *)input range:(NSRange)inputRange final:(BOOL)lastInput consumed:(size_t *)inputConsumed toBuffer:(void *)output size:(size_t)outputLength produced:(size_t *)outputProduced;

/// Produces a sequence of dispatch_data objects of size self.chunkSize or smaller. Implemented in terms of -transformData:...toBuffer:.
- (BOOL)transformData:(NSData *)input range:(NSRange)inputRange final:(BOOL)lastInput consumed:(size_t *)inputConsumed toBlock:(BOOL (NS_NOESCAPE ^)(dispatch_data_t  __attribute__((ns_consumed)) buf, NSError **))bufferConsumer;

/// One-shot convenience method for transforming a data object.
///
/// If OFDataTransformOptionChunked is specified, the result will be a dispatch_data_t (which is a concrete subclass of NSData).
- (NSData * __nullable)transformData:(NSData *)input options:(OFDataTransformOptions)options error:(NSError **)outError;

/// If a call has failed, contains the error.
@property (readwrite,strong,nullable) NSError *error;

/// The chunk size hint for -transformData:...toBlock: and OFDataTransformOptionChunked. The default is reasonable.
@property (readwrite) size_t chunkSize;

@property (readonly) BOOL expanding;

@end

@interface OFLimitedBufferSizeTransform : OFDataTransform
{
@protected
    size_t max_input;
    size_t max_output;
}
@end

@interface OFLibSystemCompressionTransform : OFDataTransform
- (instancetype __nullable)initWithAlgorithm:(compression_algorithm)alg operation:(compression_stream_operation)op;
@end
@interface OFBZip2Compress : OFLimitedBufferSizeTransform
- (instancetype __nullable)initWithCompressionLevel:(int)blockSize100k workFactor:(int)wf;
@end
@interface OFBZip2Decompress : OFLimitedBufferSizeTransform
@end

NS_ASSUME_NONNULL_END

#endif
