// Copyright 1999-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONTCPDatagramSocket.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniNetworking/ONTCPSocket.h>

RCS_ID("$Id$")

@implementation ONTCPDatagramSocket
{
    ONSocket *socket;
    void *writeRemainder;
    size_t writeLength;
    size_t writePosition;
    void *readRemainder;
    uint32_t readPacketLength;
    size_t readLength;
}

- initWithTCPSocket:(ONSocket *)aSocket;
{
    if (!(self = [super init]))
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

// Originally, packets were headed by sizeof(unsigned int) bytes; but that can vary.
#define PKT_HDR_LEN 4

- (size_t)readBytes:(size_t)byteCount intoBuffer:(void *)aBuffer;
{
    // read the packet length - if the socket raises we already have all the state we need to continue later
    if (readLength < PKT_HDR_LEN) {
        while (readLength < PKT_HDR_LEN) {
            size_t bytesRead;

            bytesRead = [socket readBytes:(PKT_HDR_LEN - readLength) intoBuffer:((void *)&readPacketLength) + readLength];
            if (bytesRead == 0)
                return 0;
            readLength += bytesRead;
        }
        readPacketLength = OSSwapBigToHostInt32(readPacketLength);
    }

    // check to see that the buffer is big enough for the packet
    if (byteCount < readPacketLength)
        [NSException raise:ONTCPDatagramSocketPacketTooLargeExceptionName format:@"Attempted to read a packet with a buffer that is too small"];

    // read the packet
    size_t totalBytesRead = readLength - PKT_HDR_LEN;
    size_t start = totalBytesRead;
    @try {
        while (totalBytesRead < readPacketLength) {
            size_t bytesRead = [socket readBytes:(readPacketLength - totalBytesRead) intoBuffer:(aBuffer + totalBytesRead)];
            if (bytesRead == 0)
                return 0;
            totalBytesRead += bytesRead;
        }
    } @catch (NSException *raisedException) {
        // if we got a partial packet save it to try more later
        if (totalBytesRead != start) {
            if (!readRemainder)
                readRemainder = malloc(readPacketLength);
            memcpy(readRemainder + start, aBuffer + start, totalBytesRead - start);
        }
        readLength = totalBytesRead + PKT_HDR_LEN;
        [raisedException raise];
    }
    
    // copy previously saved partial packet into the buffer
    if (readRemainder) {
        memcpy(aBuffer, readRemainder, readLength - PKT_HDR_LEN);
        free(readRemainder);
    }
    readLength = 0;
    return readPacketLength;
}

- (size_t)writeBytes:(size_t)byteCount fromBuffer:(const void *)aBuffer;
{
    size_t position, packetLength;
    
    // finish writing a previous packet - if this raises we'll continue with the old packet again later, and the one we are called with now is lost
    if (writeRemainder) {
        while (writePosition < writeLength) {
            size_t bytesWritten;

            bytesWritten = [socket writeBytes:(writeLength - writePosition) fromBuffer:(writeRemainder + writePosition)];
            if (bytesWritten == 0)
                return 0;
            writePosition += bytesWritten;
        }
        free(writeRemainder);
    }

    if (byteCount > 0xFFFFFFFFU) {
        [NSException raise:ONTCPDatagramSocketPacketTooLargeExceptionName format:@"Attempted to write a packet that's longer than 2^32-1 bytes"];
    }
    
    // write the length of this packet
    packetLength = OSSwapHostToBigInt32((uint32_t)byteCount);
    position = 0;
    NS_DURING {
        while (position < PKT_HDR_LEN) {
            size_t bytesWritten;

            bytesWritten = [socket writeBytes:(PKT_HDR_LEN - position) fromBuffer:((void *)(&packetLength)) + position];
            if (bytesWritten == 0)
                NS_VALUERETURN(0, unsigned int);
            position += bytesWritten;
        }
    } NS_HANDLER {
        // didn't finish the length - if we wrote nothing just discard this packet, otherwise save it
        if (position) {
            writeRemainder = malloc(byteCount + PKT_HDR_LEN);
            memcpy(writeRemainder, &packetLength, PKT_HDR_LEN);
            memcpy(writeRemainder + PKT_HDR_LEN, aBuffer, byteCount);
            writeLength = byteCount + PKT_HDR_LEN;
            writePosition = position;
        }
        [localException raise];
    } NS_ENDHANDLER;

    // write the packet data itself
    NS_DURING {
        position = 0;
        while (position < byteCount) {
            size_t bytesWritten;

            bytesWritten = [socket writeBytes:(byteCount - position) fromBuffer:(aBuffer + position)];
            if (bytesWritten == 0)
                NS_VALUERETURN(0, unsigned int);
            position += bytesWritten;
        }        
    } NS_HANDLER {
        writeLength = byteCount - position;
        writeRemainder = malloc(writeLength);
        memcpy(writeRemainder, aBuffer + position, writeLength);
        writePosition = 0;
        [localException raise];
    } NS_ENDHANDLER;

    return byteCount;
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

NSString * const ONTCPDatagramSocketPacketTooLargeExceptionName = @"ONTCPDatagramSocketPacketTooLargeExceptionName";
