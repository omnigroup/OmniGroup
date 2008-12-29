// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ONUDPSocket.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniBase/system.h>

#import "ONInternetSocket-Private.h"
#import "ONHost.h"
#import "ONPortAddress.h"

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniNetworking/ONUDPSocket.m 66423 2005-08-03 00:31:11Z kc $")


#define THIS_BUNDLE [NSBundle bundleForClass:[ONUDPSocket class]]

@implementation ONUDPSocket

- (unsigned int)writeBytes:(unsigned int)byteCount fromBuffer:(const void *)aBuffer toPortAddress:(ONPortAddress *)aPortAddress;
{
    // Note, you can be connected and still do a sendto()
    int bytesWritten;
    const struct sockaddr *portAddress;

    [self ensureSocketFD:[aPortAddress addressFamily]];

    portAddress = [aPortAddress portAddress];

    bytesWritten = sendto(socketFD, (char *)aBuffer, byteCount, 0, portAddress, portAddress->sa_len);

    if (bytesWritten == -1)
	[NSException raise:ONInternetSocketWriteFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:NSLocalizedStringFromTableInBundle(@"Unable to write to socket: %s", @"OmniNetworking", THIS_BUNDLE, @"error"), strerror(OMNI_ERRNO())];
    return (unsigned int)bytesWritten;
}


// ONSocket subclass

- (unsigned int)readBytes:(unsigned int)byteCount intoBuffer:(void *)aBuffer;
{
    ONSocketAddressLength bytesRead;

    if (flags.connected)
	bytesRead = recv(socketFD, aBuffer, byteCount, 0);
    else {
        ONSocketAddressLength senderAddressLength;
        ONSockaddrAny senderAddress;
        
        senderAddressLength = sizeof(senderAddress);

	bytesRead = recvfrom(socketFD, aBuffer, byteCount, 0, &(senderAddress.generic), &senderAddressLength);
        OBASSERT(bytesRead == (ONSocketAddressLength)-1 || senderAddressLength == 0 || senderAddressLength == senderAddress.generic.sa_len);
        
        if (bytesRead == (ONSocketAddressLength)-1 || senderAddressLength == 0 ||
            !remoteAddress || ![remoteAddress isEqualToSocketAddress:&(senderAddress.generic)]) {

            // Either we didn't receive anything, or we didn't have a cached remoteAddress, or the old remoteAddress was different from the one we just got. In each of these cases, we want to null out the old remoteAddress, and possibly create a new one.

            if (remoteAddress != nil) {
                [remoteAddress release];
                remoteAddress = nil;
            }
            if (remoteHost != nil) {
                [remoteHost release];
                remoteHost = nil;
            }

            if (senderAddressLength > 0)
                remoteAddress = [[ONPortAddress allocWithZone:[self zone]] initWithSocketAddress:&(senderAddress.generic)];
        }
    }

    if (flags.userAbort)
        [NSException raise:ONInternetSocketUserAbortExceptionName format:NSLocalizedStringFromTableInBundle(@"Read aborted", @"OmniNetworking", THIS_BUNDLE, @"error")];

    if (bytesRead == (ONSocketAddressLength)-1)
	[NSException raise:ONInternetSocketReadFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:NSLocalizedStringFromTableInBundle(@"Unable to read from socket: %s", @"OmniNetworking", THIS_BUNDLE, @"error"), strerror(OMNI_ERRNO())];
    return (unsigned int)bytesRead;
}

- (unsigned int)writeBytes:(unsigned int)byteCount fromBuffer:(const void *)aBuffer;
{
    int bytesWritten;

    if (!flags.connected) {
        NSString *localizedErrorMsg = NSLocalizedStringFromTableInBundle(@"Attempted write to a non-connected socket", @"OmniNetworking", THIS_BUNDLE, @"error - socket is not connected");
	[NSException raise:ONInternetSocketNotConnectedExceptionName format:localizedErrorMsg];
    }

    OBASSERT(socketFD != -1);  // if we're connected, we should have a valid socket fd
    
    bytesWritten = send(socketFD, (char *)aBuffer, byteCount, 0);
    if (bytesWritten == -1)
	[NSException raise:ONInternetSocketWriteFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:NSLocalizedStringFromTableInBundle(@"Unable to write to socket: %s", @"OmniNetworking", THIS_BUNDLE, @"error"), strerror(OMNI_ERRNO())];
    return (unsigned int)bytesWritten;
}


// ONInternetSocket subclass

+ (int)socketType;
{
    return SOCK_DGRAM;
}

+ (int)ipProtocol;
{
    return IPPROTO_UDP;
}

- (ONPortAddress *)remoteAddress;
{
    // The ONInternetSocket implementation of this tries to find the remote address by using getpeername(), which only works on connected sockets.
    if (!remoteAddress && flags.connected)
        return [super remoteAddress];
    // We subclass this method to return the remote address associated with the last read.
    return remoteAddress;
}

@end
