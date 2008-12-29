// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFTransformStream.h>
#import <Foundation/Foundation.h>

RCS_ID("$Id$");

NSString * const OFStreamUnderlyingStreamKey = @"OFStreamUnderlyingStream";
NSString * const OFStreamTransformerKey = @"OFStreamTransformer";

static inline void clearBuffer(struct OFTransformStreamBuffer *buf)
{
    if (buf->ownsBuffer && buf->buffer != NULL)
        free(buf->buffer);
    *buf = (struct OFTransformStreamBuffer){
        .buffer = NULL,
        .dataStart = 0,
        .dataLength = 0,
        .bufferSize = 0,
        .ownsBuffer = NO
    };
}

static inline void sizeEmptyBuffer(struct OFTransformStreamBuffer *buf, unsigned minSize)
{
    OBPRECONDITION(buf->dataLength == 0);
    OBASSERT(minSize > 0);
    
    if (buf->bufferSize < minSize) {
        if (buf->ownsBuffer && buf->buffer != NULL)
            free(buf->buffer);
        buf->buffer = malloc(minSize);
        buf->bufferSize = minSize;
        buf->ownsBuffer = YES;
    }
    
    buf->dataStart = 0;
}

static inline BOOL bufferIsEmpty(struct OFTransformStreamBuffer *buf)
{
    return (!buf->buffer || !buf->dataLength);
}

static inline BOOL bufferIsFull(struct OFTransformStreamBuffer *buf)
{
    return (buf->dataStart+buf->dataLength) >= buf->bufferSize;
}


@implementation OFInputTransformStream

/*
 OFInputTransformStream has the following states:
 NSStreamStatusNotOpen: Initial state. Underlying stream may or may nt be open when the OFInputTransformStream is created.
 NSStreamStatusOpening: Opening. Either the underlying stream is "opening" as well, or we're currently executing -[OFStreamTransformer open].
 NSStreamStatusOpen: Open. The underlying stream has been opened and the transformer's -open method has also been invoked. Various sun-states are important to the implementation bou generally shouldn't be visible to the users:
 - Underlying stream has bytes available or not.
 - Transformer has output bytes available.
 - Transformer has input space available.
 - Transformer requires more input data to continue.
 NSStreamStatusReading: The meaning of this is totally undocumented, but from reading the source to CFStream, it appears to mean that the stream is currently blocked in a "read" call. Other than that it's identical to NSStreamStatusOpen.
 NSStreamStatusAtEnd: We've reached EOF. The underlying stream is also AtEnd, we've fed all its data to the transformer, we've called the transformer's -noMoreInput method, and the user has read all of the data the transformer has generated.
 NSStreamStatusClosed: Someone has called -close.
 NSStreamStatusError: An error has occurred. This is a dead-end state --- once an error has occurred, nothing else can be done with the stream. (Again, we're imitating Apple's undocumented behavior here.)
 */


- initWithStream:(NSInputStream *)underlyingStream transform:(id <NSObject,OFStreamTransformer>)xf;
{
    self = [super init];
    if (!self)
        return nil;
    
    if (!underlyingStream || ![underlyingStream isKindOfClass:[NSInputStream class]])
        OBRejectInvalidCall(self, _cmd, @"Invalid input stream: %@", underlyingStream);
    if (!xf
#if defined(OMNI_ASSERTIONS_ON)
        || ![xf conformsToProtocol:@protocol(OFStreamTransformer)]  // -conformsToProtocol: is surprisingly expensive, so restrict this to debug builds
#endif
        )
        OBRejectInvalidCall(self, _cmd, @"Invalid stream transformer: %@", xf);
    
    sourceStream = [underlyingStream retain];
    transformer = [xf retain];
    //    [sourceStream setDelegate:self];
    
    NSArray *transformerPropertyKeys = [xf allKeys];
    if (transformerPropertyKeys && [transformerPropertyKeys count]) {
        transformerProperties = [[NSSet alloc] initWithArray:transformerPropertyKeys];
        OBASSERT(![transformerProperties member:OFStreamUnderlyingStreamKey]);
        OBASSERT(![transformerProperties member:OFStreamTransformerKey]);
    } else
        transformerProperties = nil;
    
    // ...;
    
    return self;
}

#define D(x) NSLog(@"Calling [%@ %s]", sourceStream, x)

- (void)open
{
    OBINVARIANT(sourceStream != nil);
    
    if ([sourceStream streamStatus] == NSStreamStatusNotOpen) {
        D("open");
        [sourceStream open];
    }
    
    if (!(transformerFlags & (OFStreamTransformer_Opening|OFStreamTransformer_Open|OFStreamTransformer_Error))) {
        transformerFlags |= OFStreamTransformer_Opening;
        [transformer open];
        transformerFlags = ( transformerFlags & ~(OFStreamTransformer_Opening) ) | OFStreamTransformer_Open;
    }
}

- (NSStreamStatus)streamStatus
{
    if (transformerFlags & OFStreamTransformer_Opening)
        return NSStreamStatusOpening;
    
    if (!(transformerFlags & OFStreamTransformer_Open))
        return NSStreamStatusNotOpen;
    
    if (transformerFlags & OFStreamTransformer_Error)
        return NSStreamStatusError;
    
    if ((transformerFlags & OFStreamTransformer_OutputDone) && bufferIsEmpty(&outBuf))
        return NSStreamStatusAtEnd;
    
    if (ofFlags.closed)
        return NSStreamStatusClosed;
    
    NSStreamStatus srcStatus = [sourceStream streamStatus];
    switch (srcStatus) {
        case NSStreamStatusNotOpen:
        case NSStreamStatusOpening:
        case NSStreamStatusError:
            return srcStatus;
        default:
            break;
    }
    
    if (ofFlags.inRead)
        return NSStreamStatusReading;
    else
        return NSStreamStatusOpen;
}

- (int)read:(uint8_t *)buffer maxLength:(unsigned int)len;
{
    unsigned int bytesReturned;
    
    OBASSERT(!ofFlags.inRead);
    ofFlags.inRead = 1;
    len = MIN(len, (unsigned int)INT_MAX); // Stupid API can request UINT_MAX bytes but can only return INT_MAX bytes
    
    if (outBuf.dataLength) {
        unsigned copyOut = MIN(outBuf.dataLength, len);
        memcpy(buffer, outBuf.buffer + outBuf.dataStart, copyOut);
        outBuf.dataStart += copyOut;
        bytesReturned = copyOut;
    } else {
        struct OFTransformStreamBuffer buf = (struct OFTransformStreamBuffer){
            .buffer = buffer,
            .dataStart = 0,
            .dataLength = 0,
            .bufferSize = len,
            .ownsBuffer = NO
        };
        
        [self transform:&buf];
        
        bytesReturned = buf.dataLength;
    }
    
    if (outBuf.dataLength == 0)
        clearBuffer(&outBuf);
    
    ofFlags.inRead = 0;
    
    return bytesReturned;
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(unsigned int *)len
{
    OBASSERT(!ofFlags.inRead);
    ofFlags.inRead = 1;
    
    if (!outBuf.dataLength) {
        clearBuffer(&outBuf);
        [self transform:&outBuf];
    }
    
    ofFlags.inRead = 0;
    
    if (outBuf.dataLength) {
        *buffer = outBuf.buffer + outBuf.dataStart;
        *len = outBuf.dataLength;
        
        outBuf.dataStart += outBuf.dataLength;
        outBuf.dataLength = 0;
        
        return YES;
    } else {
        return NO;
    }
}

#define DEFAULT_GOOD_BUFFER_SIZE 8192
#define EASILY_MOVABLE_BUFFER_SIZE 1024

- (unsigned int)goodBufferSize
{
    unsigned int transformerSuggestion = [transformer goodBufferSize];
    if (transformerSuggestion)
        return transformerSuggestion;
    return DEFAULT_GOOD_BUFFER_SIZE; // WAG
}

- (BOOL)fill:(BOOL)shouldBlock
{
    OBPRECONDITION(ofFlags.inRead);
    
    NSLog(@"fill:%@", shouldBlock ? @"YES" : @"NO");
    
    if (transformerFlags & (OFStreamTransformer_InputDone|OFStreamTransformer_Error))
        return NO;
    
    // Must be open, and may be starved, but must have no other flags set
    OBASSERT((transformerFlags & ~(OFStreamTransformer_Starved)) == OFStreamTransformer_Open);
    
    NSStreamStatus sourceStatus = [sourceStream streamStatus];
    NSLog(@"sourceStatus<%@> = %d", sourceStream, sourceStatus);
    if (sourceStatus == NSStreamStatusAtEnd || sourceStatus == NSStreamStatusClosed) {
        [transformer noMoreInput];
        transformerFlags |= OFStreamTransformer_InputDone;
        return YES;
    }
    OBASSERT(sourceStatus == NSStreamStatusOpen);
    
    struct OFTransformStreamBuffer *fillMe = [transformer inputBuffer];
    
    for (;;) {
        NSLog(@"  source hba=%d", [sourceStream hasBytesAvailable]);
        if (!shouldBlock && ![sourceStream hasBytesAvailable])
            return NO;
        
#if 0
        // It wuld be nice and efficient to use -getBuffer:length: or CFReadStreamGetBuffer() here, but those calls are too buggy to use (RADAR #5177472 and RADAR #5177598, respectively).
        
        if (fillMe->buffer == NULL) {
            uint8_t *externalBuffer;
            unsigned externalBufferLength;
            D("getBuffer:length:");
            BOOL ok = [sourceStream getBuffer:&externalBuffer length:&externalBufferLength];
            if (ok) {
                NSLog(@" -> Got buffer=%p size=%d", externalBuffer, externalBufferLength);
                fillMe->buffer = externalBuffer;
                fillMe->dataStart = 0;
                fillMe->dataLength = externalBufferLength;
                fillMe->bufferSize = externalBufferLength;
                fillMe->ownsBuffer = NO;
                return YES;
            } else {
                NSLog(@" -> Didn't get buffer, but if I had, it'd be %d bytes [%.*s]", externalBufferLength, externalBufferLength, externalBuffer);
            }
        }
#endif
        
        NSLog(@"dstart=%d dlen=%d bufsize=%d start+len=%d", fillMe->dataStart, fillMe->dataLength, fillMe->bufferSize, fillMe->dataStart+fillMe->dataLength);
        
        if (fillMe->buffer != NULL && !fillMe->ownsBuffer) {
            // Might be left over from a previous call to getBuffer:length:, in which case it's not safe to call a sourceStream method again until we've copied all the data out of this buffer.
            // TODO: do something in this case.
            if (!shouldBlock)
                return NO;
            unsigned goodBufferSize = [self goodBufferSize];
            if (fillMe->dataLength < goodBufferSize) {
                uint8_t *newBuffer = malloc(goodBufferSize);
                memcpy(newBuffer, fillMe->buffer + fillMe->dataStart, fillMe->dataLength);
                fillMe->buffer = newBuffer;
                fillMe->dataStart = 0;
                /* fillMe->dataLength unchanged */
                fillMe->bufferSize = goodBufferSize;
                fillMe->ownsBuffer = YES;
            }
            // TODO: else?
        }
        
        if (fillMe->buffer == NULL) {
            sizeEmptyBuffer(fillMe, [self goodBufferSize]);
            NSLog(@" new empty buffer at %p", fillMe->buffer);
        } else {
            // If we just have a small amount of data at the end of the buffer, move it to the beginning
            if (fillMe->dataStart > 0 && fillMe->dataLength < EASILY_MOVABLE_BUFFER_SIZE) {
                NSLog(@"Shifting down %d bytes @ %d", fillMe->dataLength, fillMe->dataStart);
                if (fillMe->dataLength)
                    memmove(fillMe->buffer, fillMe->buffer + fillMe->dataStart, fillMe->dataLength);
                fillMe->dataStart = 0;
            }
            
            // If there's no space at the end of the buffer, do something reasonable.
            if ((fillMe->dataStart+fillMe->dataLength) >= fillMe->bufferSize) {
                // Make room, make room!
                if (!shouldBlock) {
                    // If we would need to reallocate, but the caller doesn't absolutely need more data, don't reallocate --- otherwise we can end up slurping too much data into our buffer all at once. (Avoids buffering the entire sourceStream unnecessarily.)
                    NSLog(@"Buffer full, returning NO");
                    return NO;
                } else {
                    if (fillMe->dataStart > 0) {
                        NSLog(@"Shifting down %d bytes @ %d", fillMe->dataLength, fillMe->dataStart);
                        memmove(fillMe->buffer, fillMe->buffer + fillMe->dataStart, fillMe->dataLength);
                        fillMe->dataStart = 0;
                    } else {
                        unsigned newBufferSize = fillMe->bufferSize + MAX([self goodBufferSize], ( fillMe->bufferSize / 2 ));
                        NSLog(@"Enlarging buffer to %d bytes", newBufferSize);
                        void *newBuffer = realloc(fillMe->buffer, newBufferSize);
                        if (!newBuffer)
                            return NO;
                        fillMe->buffer = newBuffer;
                        fillMe->bufferSize = newBufferSize;
                    }
                }
            }
        }
        
        D("read:maxLength:");
        unsigned got = [sourceStream read: fillMe->buffer + (fillMe->dataStart+fillMe->dataLength)
                                maxLength: fillMe->bufferSize - (fillMe->dataStart+fillMe->dataLength)];
        NSLog(@" -> Filled buffer=%p size=%d with bytecount=%d", fillMe->buffer + (fillMe->dataStart+fillMe->dataLength), fillMe->bufferSize - (fillMe->dataStart+fillMe->dataLength), got);
        if (got) {
            OBASSERT(got <= fillMe->bufferSize);
            OBASSERT(got+fillMe->dataStart+fillMe->dataLength <= fillMe->bufferSize);
            fillMe->dataLength += got;
            return YES;
        }
    }
}

- (void)transform:(struct OFTransformStreamBuffer *)into
{
    OBPRECONDITION(ofFlags.inRead);
    OBPRECONDITION(!(transformerFlags & OFStreamTransformer_OutputDone));
    OBPRECONDITION(!(transformerFlags & OFStreamTransformer_Error));
    
    for(;;) {
        BOOL didFill = [self fill: (transformerFlags & OFStreamTransformer_Starved) ? YES : NO];
        NSError *transformError = nil;    
        
        unsigned oldDataLength = into->dataLength;
        
        NSLog(@"Calling transform: flags=%04o", transformerFlags);
        enum OFStreamTransformerResult result = [transformer transform:into error:&transformError];
        NSLog(@"Transform result = %d", result);
        
        if (result == OFStreamTransformerError) {
            OBASSERT(transformError != nil);
            transformerFlags |= OFStreamTransformer_Error|OFStreamTransformer_OutputDone;
            [transformerError release];
            transformerError = [transformError retain];
            return;
        }
        
        if (result == OFStreamTransformerNeedInput) {
            transformerFlags |= OFStreamTransformer_Starved;
        } else {
            transformerFlags &= ~( OFStreamTransformer_Starved );
        }
        
        if (result == OFStreamTransformerFinished)
            transformerFlags |= OFStreamTransformer_OutputDone;
        
        if ((transformerFlags & OFStreamTransformer_OutputDone) || (into->dataLength != oldDataLength))
            break;
        if (result == OFStreamTransformerNeedOutputSpace || bufferIsFull(into))
            break;
        // TODO: Handle the case where the transformer needs to emit a large block all at once (!starved, needOutputSpace, !bufferIsFull) by enlarging the buffer.
    }
}

#if 0  // TODO
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
{
    [sourceStream scheduleInRunLoop:aRunLoop forMode:mode];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
{
    [sourceStream removeFromRunLoop:aRunLoop forMode:mode];
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode;
{
    OBASSERT(aStream == sourceStream);
    
    NSStreamEvent forwardEvents = NSStreamEventNone;
    
    if ( (eventCode & NSStreamEventOpenCompleted) && ( thisStreamStatus == NSStreamStatusNotOpen || thisStreamStatus == NSStreamStatusOpening ) ) {
        thisStreamStatus = NSStreamStatusOpen;
        forwardEvents |= NSStreamEventOpenCompleted;
    }
    
    if ( (eventCode & NSStreamEventHasBytesAvailable) && ( ... ) ) {
        ...;
    }
    
    
    if ( (eventCode & NSStreamEventErrorOccurred) && ( ... ) ) {
        ...;
    }
    
    
    if ( (eventCode & NSStreamEventEndEncountered) && ( ... ) ) {
        ...;
    }
    
    
}
#endif

@end


