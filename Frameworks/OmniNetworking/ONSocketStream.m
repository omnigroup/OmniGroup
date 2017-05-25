// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONSocketStream.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <CoreFoundation/CoreFoundation.h>

#import <OmniNetworking/ONSocket.h>
#include <sys/types.h>
#include <sys/uio.h>

RCS_ID("$Id$")


@implementation ONSocketStream
{
    ONSocket *socket;
    
    NSMutableData *readBuffer;
    BOOL readBufferContainsEOF;
    
    // BOOL socketPushDisabled;
    unsigned int writeBufferingCount;   // count of nested -beginBuffering / -endBuffering calls
    size_t totalBufferedBytes;          // number of bytes in writeBuffer
    size_t firstBufferOffset;           // number of bytes from first buffer to ignore (not counted in totalBufferedBytes)
    NSMutableArray *writeBuffer;        // array of NSDatas to write
}

+ streamWithSocket:(ONSocket *)aSocket;
{
    return [[[self alloc] initWithSocket:aSocket] autorelease];
}

- initWithSocket:(ONSocket *)aSocket;
{
    if (!(self = [super init]))
	return nil;
    socket = [aSocket retain];
    [self clearReadBuffer];
    readBufferContainsEOF = NO;
    return self;
}

- (void)dealloc;
{
    [socket release];
    [readBuffer release];
    [super dealloc];
}


- (ONSocket *)socket;
{
    return socket;
}

- (BOOL)isReadable;
{
    if ([readBuffer length])
        return YES;
    else
        return [socket isReadable];
}

- (void)setReadBuffer:(NSMutableData *)aData;
{
    if ((NSData *)readBuffer == aData)
	return;
    [readBuffer release];
    readBuffer = [aData retain];
    readBufferContainsEOF = NO;
}

- (void)clearReadBuffer;
{
    [readBuffer release];
    readBuffer = [[NSMutableData alloc] init];
}

- (void)advanceReadBufferBy:(NSUInteger)advanceAmount;
{
    NSData *oldReadBuffer;

    oldReadBuffer = readBuffer;
    readBuffer = [[NSMutableData alloc] initWithBytes:([readBuffer bytes] + advanceAmount) length:([oldReadBuffer length] - advanceAmount)];
    [oldReadBuffer release];
}

- (BOOL)readSocket;
{
    NSData *newData;
    
    newData = [socket readData];
    if (!newData) {
        readBufferContainsEOF = YES;
	return NO; // End Of File
    }
    readBufferContainsEOF = NO;
    [readBuffer appendData:newData];
    return YES;
}


- (size_t)getLengthOfNextLine:(size_t *)eolBytes;
{
    const char *bytes;
    size_t bytesCount, byteIndex, firstEOLByte;
    enum {
        seenNothing, 
        seenCR,
        seenLF,
        seenCRCR,
        seenEOL
    } searchState;
    
    // Search for the first NL or CR character in the buffer.
    byteIndex = 0;
    firstEOLByte = ~0u; // Never read; guarded by searchState==seenNothing
    searchState = seenNothing;

    bytes = [readBuffer bytes];
    bytesCount = [readBuffer length];
    do {
        // See if we need to get more data from the socket. 
        if (byteIndex >= bytesCount) {
            if (readBufferContainsEOF || ![self readSocket]) {
                // We've reached EOF without finding an EOL that we're satisfied with. Return what we have.
                if (eolBytes != NULL)
                    *eolBytes = (searchState == seenNothing) ? 0 : byteIndex - firstEOLByte;
                return [readBuffer length];
            }
            
            // Update our cached info
            bytes = [readBuffer bytes];
            bytesCount = [readBuffer length];
        }

        OBINVARIANT( (searchState == seenNothing) ? firstEOLByte == ~0u : firstEOLByte != ~0u );

        switch (searchState) {
            case seenNothing:
                // Look for EOL-like characters.
                if (bytes[byteIndex] == '\n') {
                    searchState = seenLF;
                    firstEOLByte = byteIndex;
                } else if(bytes[byteIndex] == '\r') {
                    searchState = seenCR;
                    firstEOLByte = byteIndex;
                }
                break;
            case seenCR:
                if (bytes[byteIndex] == '\n') {
                    // We've seen a CRLF, which is the correct EOL indicator for most internet protocols.
                    searchState = seenEOL;
                } else if(bytes[byteIndex] == '\r') {
                    // Nov 7, 2000:  A WebSitePro/2.4.9 server at www.alpa.org was returning \r\r\n in some of its headers, so let's go ahead and allow that (since obviously it works in other browsers)
                    searchState = seenCRCR;
                } else {
                    // Saw a CR followed by something else, so the CR must have been the EOL indicator. Back up a byte.
                    byteIndex --;
                    searchState = seenEOL;
                }
                break;
            case seenLF:
                if(bytes[byteIndex] == '\r') {
                    // LFCR is somewhat bogus, but still encountered in practice.
                    searchState = seenEOL;
                } else {
                    // LF followed by something other than a CR, so the LF was the EOL indicator. Back up a byte.
                    byteIndex --;
                    searchState = seenEOL;
                }
                break;
            case seenCRCR:
                // Handle the bizarre \r\r\n case.
                if (bytes[byteIndex] == '\n') {
                    searchState = seenEOL;
                } else {
                    // Otherwise, we've been on a wild-goose chase, and that first CR was the real EOL. Back up two bytes.
                    byteIndex -= 2;
                    searchState = seenEOL;
                }
                break;
            case seenEOL:
                OBASSERT_NOT_REACHED("bad state");
                break;
        }

        byteIndex ++;
    } while (searchState != seenEOL);

    OBASSERT(firstEOLByte <= byteIndex);
    
    if (eolBytes != NULL)
        *eolBytes = byteIndex - firstEOLByte;

    return byteIndex;
}

- (NSString *)readLineAndAdvance:(BOOL)shouldAdvance;
{
    size_t lineLength, eolLength;
    NSString *resultString;
    CFStringRef cfString;
    CFStringEncoding cfEncoding;

    lineLength = [self getLengthOfNextLine:&eolLength];
    OBASSERT(eolLength <= lineLength);
    OBASSERT(lineLength <= [readBuffer length]);

    // At EOF, we'll see a zero-length line, since we treat EOF as a valid EOL character.
    if (lineLength == 0) {
        OBASSERT(readBufferContainsEOF);
        if (shouldAdvance) {
            // "Consume" the EOF marker that's at the end of the buffer. This makes the next -readLine... call attempt to read from the socket again, which will produce an "attempted to read past end of file" exception, which is consistent with the rest of our socket API.
            readBufferContainsEOF = NO;
        }
        return nil;  // Return EOF indicator to caller.
    }

    // We want to return a result that doesn't contain the EOL character(s).
    // We use the CF interface here to create a string without copying the bytes an extra time.
    cfEncoding = CFStringConvertNSStringEncodingToEncoding([self stringEncoding]);
    cfString = CFStringCreateWithBytes(kCFAllocatorDefault,
                                       (void *)[readBuffer bytes],
                                       lineLength - eolLength,
                                       cfEncoding, 1);
    resultString = [(NSString *)cfString autorelease];
    
    if (shouldAdvance)
        [self advanceReadBufferBy:lineLength];

    return resultString;
}

- (NSString *)readLine;
{
    return [self readLineAndAdvance:YES];
}

- (NSString *)peekLine;
{
    return [self readLineAndAdvance:NO];
}

- (NSData *)readData;
{
    NSData *data;

    if ([readBuffer length] == 0) {
	if (![self readSocket])
	    return nil;
    }
    data = [[readBuffer retain] autorelease];
    [self clearReadBuffer];
    return data;
}

- (NSData *)readDataWithMaxLength:(NSUInteger)length;
{
    NSData *result;

    if (![readBuffer length])
        if (![self readSocket])
            return nil;
    
    if ([readBuffer length] <= length) {
        result = [readBuffer retain];
        [self clearReadBuffer];

        return [result autorelease];
    } else  {
        result = [readBuffer subdataWithRange:NSMakeRange(0, length)];
        [self advanceReadBufferBy:length];

        return result;
    }
}

- (NSData *)readDataOfLength:(NSUInteger)length;
{
    NSData *result;
    NSUInteger readBufferLength;

    readBufferLength = [readBuffer length];
    if (readBufferLength == length) {
        result = [readBuffer retain];
        [self clearReadBuffer];
        return [result autorelease];
    } else if (readBufferLength > length) {
        result = [readBuffer subdataWithRange:NSMakeRange(0, length)];
        [self advanceReadBufferBy:length];
        return result;
    } else {
        NSMutableData *mutableBuffer;
        unsigned char *mutableBytes;
        size_t remainingByteCount;

        mutableBuffer = [[NSMutableData alloc] initWithCapacity:length];
        [mutableBuffer appendData:readBuffer];
        [mutableBuffer setLength:length];

        [self clearReadBuffer];

        mutableBytes = [mutableBuffer mutableBytes] + readBufferLength;
        remainingByteCount = length - readBufferLength;
        while (remainingByteCount != 0) {
            size_t lengthRead = [socket readBytes:remainingByteCount intoBuffer:mutableBytes];
            remainingByteCount -= lengthRead;
            mutableBytes += lengthRead;
        }
        return [mutableBuffer autorelease];
    }
}

- (size_t)readBytesWithMaxLength:(size_t)length intoBuffer:(void *)buffer;
{
    size_t readBufferLength;
    
    if ((readBufferLength = [readBuffer length]) != 0) {
        length = MIN(readBufferLength, length);
        [readBuffer getBytes:buffer length:length];
        if (readBufferLength == length)
            [self clearReadBuffer];
        else
            [self advanceReadBufferBy:length];
        return length;
    } else {
        return [socket readBytes:length intoBuffer:buffer];
    }
}

- (void)readBytesOfLength:(size_t)length intoBuffer:(void *)buffer;
{
    while(length) {
        size_t read = [self readBytesWithMaxLength:length intoBuffer:buffer];
        length -= read;
        buffer += read;
    }
}

- (BOOL)skipBytes:(size_t)length;
{
    NSUInteger readBufferLength;
    
    if ((readBufferLength = [readBuffer length]) != 0) {
        if (length > readBufferLength) {
            [self clearReadBuffer];
            length -= readBufferLength;
        } else {
            [self advanceReadBufferBy:length];
            return YES;
        }
    }
    
    char worthlessBuffer[1024];
    while (length > 0) {
        size_t read = [socket readBytes:MIN(1024U, length) intoBuffer:worthlessBuffer];
        if (read == 0)
            return NO;
        length -= read;
    }
    return YES;
}

- (void)writeData:(NSData *)theData;
{
    if (writeBufferingCount == 0) {
        [socket writeData:theData];
    } else {
        OBASSERT(writeBuffer != nil);
        if (theData != nil && [theData length] != 0) {
            [writeBuffer addObject:theData];
            totalBufferedBytes += [theData length];
#ifdef BUFFERED_DATA_SEND_THRESHOLD
            if (totalBufferedBytes >= BUFFERED_DATA_SEND_THRESHOLD)
                [self _writeSomeBufferedData];
#endif
        }
    }
}

- (void)beginBuffering
{
    if (writeBufferingCount == 0) {
        OBPRECONDITION(writeBuffer == nil);
        writeBufferingCount ++;
        writeBuffer = [[NSMutableArray alloc] init];
        totalBufferedBytes = 0;
    } else {
        writeBufferingCount ++;
    }
}

- (void)endBuffering
{
    if (writeBufferingCount == 0) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"-[%@ %@] called too many times", [self shortDescription], NSStringFromSelector(_cmd)];
    } else if (writeBufferingCount == 1) {
        OBPRECONDITION(writeBuffer != nil);
        writeBufferingCount --;
        while ([writeBuffer count] > 0)
            [self _writeSomeBufferedData];
        [writeBuffer release];
        OBPOSTCONDITION(totalBufferedBytes == 0);
        writeBuffer = nil;
    } else {
        writeBufferingCount --;
    }
}

- (NSString *)readString;
{
    NSData *data;
    
    data = [self readData];
    if (!data)
	return nil;
    // Note that this will only work with single byte encodings (which is probably why we don't use it anymore).
    // We should assert that the string encoding is reasonable for this sort of operation; it's perfectly reasonable to call -readString on an ASCII stream, but not on a Unicode stream (unless we make this more complex).
    return [[[NSString alloc] initWithData:data encoding:[self stringEncoding]] autorelease];
}

- (void)writeString:(NSString *)aString;
{
    // This duplicates -[ONSocket writeString:] but goes through our buffering code if that's enabled.
    [self writeData:[aString dataUsingEncoding:[socket stringEncoding] allowLossyConversion:YES]];
}

- (void)writeFormat:(NSString *)aFormat, ...;
{
    va_list argList;
    NSString *formattedString;

    va_start(argList, aFormat);
    formattedString = [[NSString alloc] initWithFormat:aFormat arguments:argList];
    va_end(argList);
    [self writeString:formattedString];
    [formattedString release];
}

- (NSStringEncoding)stringEncoding;
{
    return [socket stringEncoding];
}

- (void)setStringEncoding:(NSStringEncoding)aStringEncoding;
{
    [socket setStringEncoding:aStringEncoding];
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (socket)
	[debugDictionary setObject:socket forKey:@"socket"];
    if (readBuffer)
	[debugDictionary setObject:readBuffer forKey:@"readBuffer"];

    return debugDictionary;
}

#pragma mark - Private

// UIO_MAXIOV is documented in writev(2), but <sys/uio.h> only declares it if defined(KERNEL)
#ifndef UIO_MAXIOV
#define UIO_MAXIOV 512
#endif


- (void)_writeSomeBufferedData
{
    struct iovec *vectors;
    unsigned int bufferCount, bufferIndex;
    size_t bytesWritten;

    OBASSERT(writeBuffer != nil);
    
    bufferCount = (unsigned int)[writeBuffer count];
    if (bufferCount == 0)
        return;

    if (bufferCount > UIO_MAXIOV)
        bufferCount = UIO_MAXIOV;
        
    vectors = malloc(sizeof(*vectors) * bufferCount);
    for(bufferIndex = 0; bufferIndex < bufferCount; bufferIndex ++) {
        NSData *buffer = [writeBuffer objectAtIndex:bufferIndex];
        vectors[bufferIndex].iov_base = (void *)[buffer bytes];
        vectors[bufferIndex].iov_len = [buffer length];
    }
    OBASSERT(vectors[0].iov_len > firstBufferOffset);
    vectors[0].iov_base += firstBufferOffset;
    vectors[0].iov_len -= firstBufferOffset;

    NS_DURING
        bytesWritten = [socket writeBuffers:vectors count:bufferCount];
    NS_HANDLER
        free(vectors);
        bytesWritten = 0;
        [localException raise];
    NS_ENDHANDLER;

    free(vectors);
    OBASSERT(bytesWritten <= totalBufferedBytes);

    firstBufferOffset += bytesWritten;

    // Fast path
    if (firstBufferOffset >= totalBufferedBytes) {
        [writeBuffer removeAllObjects];
        totalBufferedBytes = 0;
        firstBufferOffset = 0;
        return;
    }

    // Slow path (partial write)
    bufferIndex = 0;
    while (firstBufferOffset > 0) {
        NSUInteger thisBufferLength = [[writeBuffer objectAtIndex:bufferIndex] length];
        if (firstBufferOffset >= thisBufferLength) {
            firstBufferOffset -= thisBufferLength;
            totalBufferedBytes -= thisBufferLength;
            bufferIndex ++;
        } else {
            break;
        }
    }
    [writeBuffer removeObjectsInRange:NSMakeRange(0, bufferIndex)];
}

@end

