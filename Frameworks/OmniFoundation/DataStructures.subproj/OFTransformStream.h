// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSStream.h>

/*
 NSStreams are toll-free-bridged to CFStreams. You can't make custom CFStreams, even though they have a function-table dispatch internally, but it's documented to work if you create a custom NSStream subclass and use that as a CFStream. Go figure.
 */

struct OFTransformStreamBuffer {
    uint8_t *buffer;                        // uint8_t is really the wrong typedef to use here, but it's what NSStream uses, and we follow their questionable lead
    unsigned int dataStart, dataLength;     // Range of interesting (valid, unconsumed) data in the buffer
    unsigned int bufferSize;                // how large is the actual buffer (malloc size)
    BOOL ownsBuffer;                        // should we realloc/free this buffer, or just ignore it when done?
};

@protocol OFStreamTransformer

enum OFStreamTransformerResult {
    OFStreamTransformerContinue,
    OFStreamTransformerError,
    OFStreamTransformerNeedInput,
    OFStreamTransformerNeedOutputSpace,
    OFStreamTransformerFinished
};

- (void)open;
- (void)noMoreInput;

- (struct OFTransformStreamBuffer *)inputBuffer;
- (unsigned int)goodBufferSize;
- (enum OFStreamTransformerResult)transform:(struct OFTransformStreamBuffer *)intoBuffer error:(NSError **)outError;

- (NSArray *)allKeys;
- propertyForKey:(NSString *)aKey;
- (void)setProperty:prop forKey:(NSString *)aKey;

@end


#define OFStreamTransformer_Opening             000001    // Are we in the middle of a call to -open ?
#define OFStreamTransformer_Open                000002    // Have we successfully opened?
#define OFStreamTransformer_Processing          000004    // Are we in the middle of a call to -transform:error: ?
#define OFStreamTransformer_InputDone           000010    // Have we called -noMoreInput ?
#define OFStreamTransformer_OutputDone          000020    // Is it impossible for any more output to be generated, ever?
#define OFStreamTransformer_Starved             000040    // Is it impossible for any more output to be generated without getting more input?
#define OFStreamTransformer_Error               000200    // Has the transformer entered an error state ?


#if 0 // TODO

@interface OFOutputTransformStream : NSOutputStream
{
    
}

- initWithStream:(NSInputStream *)underlyingStream transform:(id <NSObject,OFStreamTransformer>)xf;

@end

#endif

@interface OFInputTransformStream : NSInputStream
{
    NSInputStream *sourceStream;
    struct OFTransformStreamBuffer inBuf, outBuf;
    struct {
        unsigned closed: 1;
        unsigned inRead: 1;
    } ofFlags;
    
    id <NSObject,OFStreamTransformer> transformer;
    unsigned transformerFlags;
    NSError *transformerError;
    NSSet *transformerProperties;
    
    NSStreamStatus thisStreamStatus;
    
    NSObject *nonretainedDelegate;
}

- initWithStream:(NSInputStream *)underlyingStream transform:(id <NSObject,OFStreamTransformer>)xf;

    // Private
- (BOOL)fill:(BOOL)shouldBlock;
- (void)transform:(struct OFTransformStreamBuffer *)into;

@end

// Properties
OmniFoundation_EXTERN NSString * const OFStreamUnderlyingStreamKey;
OmniFoundation_EXTERN NSString * const OFStreamTransformerKey;

