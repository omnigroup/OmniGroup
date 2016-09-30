// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWDataStreamFilterCursor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFInvocation.h>
#import <OmniFoundation/OFMessageQueue.h>
#import <OWF/OWProcessor.h>

RCS_ID("$Id$");

@interface OWDataStreamFilterCursor (Private)
@end

@implementation OWDataStreamFilterCursor

// Init and dealloc

static NSException *OWDataStreamCursor_SeekException;

+ (void)initialize;
{
    OBINITIALIZE;

    OWDataStreamCursor_SeekException = [[NSException alloc] initWithName:OWDataStreamCursor_SeekExceptionName reason:OWDataStreamCursor_SeekExceptionName userInfo:nil];
}

- init;
{
    if (!(self = [super init]))
        return nil;

    haveStartedFilter = NO;
    canFillMoreBuffer = YES;

    return self;
}

// API

- (void)processBegin
{
    OBPRECONDITION(!haveStartedFilter);

    haveStartedFilter = YES;
    bufferedData = [[NSMutableData alloc] init];
    bufferedDataStart = 0;
    bufferedDataValidLength = 0;

    OBPOSTCONDITION(haveStartedFilter);
}

- (void)_processBegin
{
    if (abortException)
        [abortException raise];

    NS_DURING {
        OBPRECONDITION(!haveStartedFilter);
        [self processBegin];
        OBPOSTCONDITION(haveStartedFilter);
    } NS_HANDLER {
        [self abortWithException:localException];
        [localException raise];
    } NS_ENDHANDLER;

}

- (BOOL)enlargeBuffer
{
    if (!haveStartedFilter)
        [self processBegin];
    if (abortException)
        [abortException raise];

    if (!canFillMoreBuffer)
        return NO;

    NSUInteger atLeast = bufferedDataValidLength + 1024;
    if ([bufferedData length] < atLeast)
        [bufferedData setLength:atLeast];

    NSUInteger oldValidLength = bufferedDataValidLength;
    do {
        [self fillBuffer:NULL length:[bufferedData length] filledToIndex:&bufferedDataValidLength];
    } while (canFillMoreBuffer && bufferedDataValidLength == oldValidLength);

    return (bufferedDataValidLength != oldValidLength);
}

- (void)bufferBytes:(NSUInteger)count
{
    if (bufferedDataStart + bufferedDataValidLength >= dataOffset + count)
        return;

    if (!haveStartedFilter)
        [self processBegin];
    if (abortException)
        [abortException raise];

    if (dataOffset < bufferedDataStart)
        [OWDataStreamCursor_SeekException raise];

    if (bufferedDataStart + bufferedDataValidLength == dataOffset) {
        bufferedDataValidLength = 0;
        bufferedDataStart = dataOffset;
    } else if (dataOffset - bufferedDataStart > 2 * (bufferedDataStart + bufferedDataValidLength - dataOffset)) {
        // heuristic: if we have more than twice as much data behind the cursor than in front of it, copy it down to the front of the buffer
        void *buf = [bufferedData mutableBytes];
        memmove(buf, buf + (dataOffset - bufferedDataStart),
               bufferedDataStart + bufferedDataValidLength - dataOffset);
        bufferedDataValidLength -= (dataOffset - bufferedDataStart);
        bufferedDataStart = dataOffset;
    }
    
    if ([bufferedData length] < ( (dataOffset + count) - (bufferedDataStart + bufferedDataValidLength) ))
        [bufferedData setLength:( (dataOffset + count) - (bufferedDataStart + bufferedDataValidLength) )];

    while (bufferedDataStart + bufferedDataValidLength < dataOffset + count) {
        if (!canFillMoreBuffer)
            [OWDataStreamCursor_UnderflowException raise];
        [self fillBuffer:nil length:[bufferedData length] filledToIndex:&bufferedDataValidLength];
    }
}

- (BOOL)haveBufferedBytes:(NSUInteger)count
{
    return (bufferedDataStart + bufferedDataValidLength >= dataOffset + count);
}

- (NSUInteger)copyBytesToBuffer:(void *)buffer minimumBytes:(NSUInteger)maximum maximumBytes:(NSUInteger)minimum advance:(BOOL)shouldAdvance
{
    NSUInteger bytesPeeked;

    if (minimum > 0)
        [self bufferBytes:minimum];

    bytesPeeked = bufferedDataValidLength - ( dataOffset - bufferedDataStart );
    bytesPeeked = MIN(bytesPeeked, maximum);
    [bufferedData getBytes:buffer range:(NSRange){ ( dataOffset - bufferedDataStart ), bytesPeeked }];
    
    if (shouldAdvance)
        dataOffset += bytesPeeked;
    
    return bytesPeeked;
}


- (void)readBytes:(NSUInteger)count intoBuffer:(void *)buffer
{
    [self bufferBytes:count];
    [bufferedData getBytes:buffer range:(NSRange){ ( dataOffset - bufferedDataStart ), count }];
    dataOffset += count;
}

- (void)peekBytes:(NSUInteger)count intoBuffer:(void *)buffer
{
    [self bufferBytes:count];
    [bufferedData getBytes:buffer range:(NSRange){ ( dataOffset - bufferedDataStart ), count }];
}

- (NSUInteger)peekUnderlyingBuffer:(void **)returnedBufferPtr
{
    NSUInteger availableUnreadBytes;
    
    if ([self isAtEOF])
        return 0;
        
    [self bufferBytes:1];

    OBINVARIANT(dataOffset >= bufferedDataStart);
    availableUnreadBytes = bufferedDataStart + bufferedDataValidLength - dataOffset;
    *returnedBufferPtr = (void *)[bufferedData bytes] + ( dataOffset - bufferedDataStart );
    return availableUnreadBytes;
}

- (NSUInteger)dataLength
{
    while ([self enlargeBuffer])
        ;

    return bufferedDataStart + bufferedDataValidLength;
}

- (BOOL)isAtEOF
{
    if (!haveStartedFilter)
        [self processBegin];

    if (bufferedDataStart + bufferedDataValidLength > dataOffset)
        return NO;
    if (!canFillMoreBuffer)
        return YES;

    return ![self enlargeBuffer];
}

- (BOOL)haveFinishedReadingData
{
    if (!haveStartedFilter)
        [self processBegin];

    if (bufferedDataStart + bufferedDataValidLength > dataOffset)
        return NO;
    if (!canFillMoreBuffer)
        return YES;

    return NO;
}

- (NSData *)peekBytesOrUntilEOF:(NSUInteger)count
{
    NSUInteger availableUnreadBytes;
    NSRange peekRange;
    
    while (![self haveBufferedBytes:count]) {
        if (![self enlargeBuffer])
            break;
    }

    availableUnreadBytes = bufferedDataStart + bufferedDataValidLength - dataOffset;
    peekRange.location = bufferedDataStart - dataOffset;
    peekRange.length = MIN(count, availableUnreadBytes);
    return [bufferedData subdataWithRange:peekRange];
}

- (NSData *)readAllData
{
    if (dataOffset < bufferedDataStart)
        [OWDataStreamCursor_SeekException raise];
    if (abortException)
        [abortException raise];

    if (bufferedDataStart + bufferedDataValidLength == dataOffset) {
        bufferedDataValidLength = 0;
        bufferedDataStart = dataOffset;
    }
    
    while ([self enlargeBuffer])
        ;


    OBASSERT(dataOffset >= bufferedDataStart); // Otherwise, we raise the seek exception above
    NSUInteger oldBytesInBuffer = dataOffset - bufferedDataStart;

    if (bufferedDataValidLength == oldBytesInBuffer)
        return nil; // We have no more data

    NSData *result = [bufferedData subdataWithRange:NSMakeRange(oldBytesInBuffer, bufferedDataValidLength - oldBytesInBuffer)];
    bufferedData = [[NSMutableData alloc] initWithCapacity:0];
    bufferedDataStart += bufferedDataValidLength;
    bufferedDataValidLength = 0;
    dataOffset = bufferedDataStart;
    
    return result;
}

- (void)fillBuffer:(void *)buffer length:(NSUInteger)bufferLength filledToIndex:(NSUInteger *)bufferFullp
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)_bufferInThreadAndThenScheduleInQueue:(OFMessageQueue *)aQueue invocation:(OFInvocation *)anInvocation
{
    NS_DURING {
        [self bufferBytes:1];
    } NS_HANDLER {
#ifdef DEBUG
        NSLog(@"%@, recording exception: %@", NSStringFromSelector(_cmd), localException);
#endif
        [self abortWithException:localException];
    } NS_ENDHANDLER;
    
    if (aQueue)
        [aQueue addQueueEntry:anInvocation];
    else
        [anInvocation invoke];
}

- (void)scheduleInQueue:(OFMessageQueue *)aQueue invocation:(OFInvocation *)anInvocation
{
    if ([self haveBufferedBytes:1]) {
        // We have some buffered data, so perform the invocation right now.
        if (aQueue)
            [aQueue addQueueEntry:anInvocation];
        else
            [anInvocation invoke];
    } else {
        // We don't have any data buffered, so buffer some in another thread
        [[OWProcessor processorQueue] queueSelector:@selector(_bufferInThreadAndThenScheduleInQueue:invocation:) forObject:self withObject:aQueue withObject:anInvocation];
    }
}

@end

NSString * const OWDataStreamCursor_SeekExceptionName = @"OWDataStreamCursor Seek Exception";

