// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ONSocket.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>

#include <sys/uio.h>  // for struct iovec

RCS_ID("$Id$")

static NSStringEncoding defaultStringEncoding = NSISOLatin1StringEncoding;
static unsigned int defaultReadBufferSize = 2048;

@implementation ONSocket

- init
{
    if (![super init])
	return nil;

    stringEncoding = defaultStringEncoding;
    readBufferSize = defaultReadBufferSize;

    return self;
}

- (unsigned int)readBytes:(unsigned int)byteCount intoBuffer:(void *)aBuffer;
{
    OBRequestConcreteImplementation(self, _cmd);
    return 0;
}

- (unsigned int)writeBytes:(unsigned int)byteCount fromBuffer:(const void *)aBuffer;
{
    OBRequestConcreteImplementation(self, _cmd);
    return 0;
}

- (void)abortSocket;
{
}

- (BOOL)isReadable;
{
    return YES;
}

- (BOOL)isWritable;
{
    return YES;
}

// This implementation is overridden by most classes to do gather-writing directly
- (unsigned int)writeBuffers:(const struct iovec *)buffers count:(unsigned int)num_iov
{
    if (num_iov == 0)
        return 0;
    else if (num_iov == 1)
        return [self writeBytes:buffers[0].iov_len fromBuffer:buffers[0].iov_base];
    else {
        unsigned int iovIndex;
        unsigned int totalSize;
        unsigned int bytesWritten;
        char *gatherBuf, *gatherBufPtr;

        totalSize = 0;
        for(iovIndex = 0; iovIndex < num_iov; iovIndex ++)
            totalSize += buffers[iovIndex].iov_len;

        gatherBuf = malloc(totalSize);
        gatherBufPtr = gatherBuf;
        for(iovIndex = 0; iovIndex < num_iov; iovIndex ++) {
            bcopy(buffers[iovIndex].iov_base, gatherBufPtr, buffers[iovIndex].iov_len);
            gatherBufPtr += buffers[iovIndex].iov_len;
        }

        NS_DURING {
            bytesWritten = [self writeBytes:totalSize fromBuffer:gatherBuf];
        } NS_HANDLER {
            free(gatherBuf);
            bytesWritten = 0;
            [localException raise];
        } NS_ENDHANDLER;
        free(gatherBuf);
        return bytesWritten;
    }
}

@end

@implementation ONSocket (General)

+ (void)setDefaultStringEncoding:(NSStringEncoding)aStringEncoding;
{
    defaultStringEncoding = aStringEncoding;
}

+ (void)setDefaultReadBufferSize:(int)aSize;
{
    defaultReadBufferSize = aSize;
}

- (void)writeData:(NSData *)data;
{
    const void *bytes;
    unsigned int length;

    bytes = [data bytes];
    length = [data length];
    while (length) {
        unsigned int bytesWritten;

        bytesWritten = [self writeBytes:length fromBuffer:bytes];
        if (bytesWritten > 0) {
	    if (bytesWritten > length)
		break;
	    length -= bytesWritten;
	    bytes += bytesWritten;
        }
    }
}

- (void)writeString:(NSString *)string;
{
    [self writeData:[string dataUsingEncoding:stringEncoding allowLossyConversion:YES]];
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

- (void)readData:(NSMutableData *)data;
{
    void *dataBytes;
    unsigned int dataLength, bytesRead;

    dataLength = [data length];
    dataBytes = [data mutableBytes];
    bytesRead = [self readBytes:dataLength intoBuffer:dataBytes];
    [data setLength:bytesRead];
}

- (NSData *)readData;
{
    NSMutableData *data;

    data = [NSMutableData dataWithLength:readBufferSize];
    [self readData:data];
    return [data length] > 0 ? data : nil;
}

- (NSString *)readString;
{
    NSData *data;
    
    data = [self readData];
    if (!data)
	return nil;
    return [[[NSString alloc] initWithData:data encoding:stringEncoding] autorelease];
}
    
- (NSStringEncoding)stringEncoding;
{
    return stringEncoding;
}

- (void)setStringEncoding:(NSStringEncoding)aStringEncoding;
{
    stringEncoding = aStringEncoding;
}

- (void)setReadBufferSize:(int)aSize;
{
    readBufferSize = aSize;
}

@end
