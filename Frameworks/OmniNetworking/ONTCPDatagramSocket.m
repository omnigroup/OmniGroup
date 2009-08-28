// Copyright 1999-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ONTCPDatagramSocket.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import "ONTCPSocket.h"

RCS_ID("$Id$")

@implementation ONTCPDatagramSocket

- initWithTCPSocket:(ONSocket *)aSocket;
{
    if (![super init])
        return nil;

    socket = [aSocket retain];

    return self;
}

- (void)dealloc;
{
    [socket release];
    [super dealloc];
}

//

- (unsigned int)readBytes:(unsigned int)byteCount intoBuffer:(void *)aBuffer;
{
    // read the packet length - if the socket raises we already have all the state we need to continue later
    if (readLength < sizeof(unsigned int)) {
        while (readLength < sizeof(unsigned int)) {
            unsigned int bytesRead;

            bytesRead = [socket readBytes:(sizeof(unsigned int) - readLength) intoBuffer:((void *)&readPacketLength) + readLength];
            if (bytesRead == 0)
                return 0;
            readLength += bytesRead;
        }
        readPacketLength = NSSwapBigShortToHost(readPacketLength);
    }

    // check to see that the buffer is big enough for the packet
    if (byteCount < readPacketLength)
        [NSException raise:ONTCPDatagramSocketPacketTooLargeExceptionName format:@"Attempted to read a packet with a buffer that is too small"];

    // read the packet
    unsigned int totalBytesRead = readLength - sizeof(unsigned int);
    unsigned int start = totalBytesRead;
    NSException *raisedException = nil;
    @try {
        while (totalBytesRead < readPacketLength) {
            unsigned int bytesRead = [socket readBytes:(readPacketLength - totalBytesRead) intoBuffer:(aBuffer + totalBytesRead)];
            if (bytesRead == 0)
                return 0;
            totalBytesRead += bytesRead;
        }
    } @catch (NSException *localException) {
        raisedException = [[localException retain] autorelease];
    }

    if (raisedException) {
        // if we got a partial packet save it to try more later
        if (totalBytesRead != start) {
            if (!readRemainder)
                readRemainder = NSZoneMalloc(NULL, readPacketLength);
            memcpy(readRemainder + start, aBuffer + start, totalBytesRead - start);
        }
        readLength = totalBytesRead + sizeof(unsigned int);
        [raisedException raise];
    }
    
    // copy previously saved partial packet into the buffer
    if (readRemainder) {
        memcpy(aBuffer, readRemainder, readLength - sizeof(unsigned int));
        NSZoneFree(NULL, readRemainder);
    }
    readLength = 0;
    return readPacketLength;
}

- (unsigned int)writeBytes:(unsigned int)byteCount fromBuffer:(const void *)aBuffer;
{
    unsigned int position, packetLength;
    
    // finish writing a previous packet - if this raises we'll continue with the old packet again later, and the one we are called with now is lost
    if (writeRemainder) {
        while (writePosition < writeLength) {
            unsigned int bytesWritten;

            bytesWritten = [socket writeBytes:(writeLength - writePosition) fromBuffer:(writeRemainder + writePosition)];
            if (bytesWritten == 0)
                return 0;
            writePosition += bytesWritten;
        }
        NSZoneFree(NULL, writeRemainder);
    }

    // write the length of this packet
    packetLength = NSSwapHostLongToBig(byteCount);
    position = 0;
    NS_DURING {
        while (position < sizeof(unsigned int)) {
            unsigned int bytesWritten;

            bytesWritten = [socket writeBytes:(sizeof(unsigned int) - position) fromBuffer:((void *)(&packetLength)) + position];
            if (bytesWritten == 0)
                NS_VALUERETURN(0, unsigned int);
            position += bytesWritten;
        }
    } NS_HANDLER {
        // didn't finish the length - if we wrote nothing just discard this packet, otherwise save it
        if (position) {
            writeRemainder = NSZoneMalloc(NULL, byteCount + sizeof(unsigned int));
            *(int *)writeRemainder = packetLength;
            memcpy(writeRemainder + sizeof(unsigned int), aBuffer, byteCount);
            writeLength = byteCount + sizeof(unsigned int);
            writePosition = position;
        }
        [localException raise];
    } NS_ENDHANDLER;

    // write the packet data itself
    NS_DURING {
        position = 0;
        while (position < byteCount) {
            unsigned int bytesWritten;

            bytesWritten = [socket writeBytes:(byteCount - position) fromBuffer:(aBuffer + position)];
            if (bytesWritten == 0)
                NS_VALUERETURN(0, unsigned int);
            position += bytesWritten;
        }        
    } NS_HANDLER {
        writeLength = byteCount - position;
        writeRemainder = NSZoneMalloc(NULL, writeLength);
        memcpy(writeRemainder, aBuffer + position, writeLength);
        writePosition = 0;
        [localException raise];
    } NS_ENDHANDLER;

    return (unsigned int)byteCount;
}

- (void)abortSocket;
{
    [socket abortSocket];
}

- (BOOL)isReadable;
{
    return [socket isReadable];
}

- (BOOL)isWritable;
{
    return [socket isWritable];
}

@end

NSString *ONTCPDatagramSocketPacketTooLargeExceptionName = @"ONTCPDatagramSocketPacketTooLargeExceptionName";
