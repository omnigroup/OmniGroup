// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONTCPSocket.h>

#import <sys/types.h>
#import <errno.h>
#import <netinet/tcp.h>

#import <Foundation/NSDictionary.h>
#import <Foundation/NSBundle.h> // for NSLocalized...() macros
#import <OmniBase/OmniBase.h>
#import <OmniBase/system.h>

#import <OmniNetworking/ONHost.h>
#import <OmniNetworking/ONHostAddress.h>
#import "ONInternetSocket-Private.h"
#import <OmniNetworking/ONPortAddress.h>
#import <OmniNetworking/ONServiceEntry.h>

#define THIS_BUNDLE [NSBundle bundleForClass:[ONTCPSocket class]]

RCS_ID("$Id$")

#define ONTCP_OPT_USE_DEFAULT 2

@implementation ONTCPSocket
{
    struct {
        unsigned int useNagle: 2;
        unsigned int pushWrites: 2;
    } tcpFlags;
}

static Class defaultTCPSocketClass = nil;

+ (void)initialize;
{
    OBINITIALIZE;

    defaultTCPSocketClass = [ONTCPSocket class];

    // get rid of pesky SIGPIPE signals - we want an exception instead
    signal(SIGPIPE, SIG_IGN);
}

+ (Class)defaultTCPSocketClass;
{
    return defaultTCPSocketClass;
}

+ (void)setDefaultTCPSocketClass:(Class)aClass;
{
    OBASSERT([aClass isSubclassOfClass:[ONTCPSocket class]]);
    defaultTCPSocketClass = aClass;
}

+ (ONTCPSocket *)tcpSocket;
{
    return (ONTCPSocket *)[defaultTCPSocketClass socket];
}

//

- (void)startListeningOnAnyLocalPort;
{
    [self startListeningOnLocalPort:0];
}

#define PENDING_CONNECTION_LIMIT 5

- (void)startListeningOnLocalPort:(unsigned short int)port;
{
    [self startListeningOnLocalPort:port allowingAddressReuse:NO];
}

- (void)startListeningOnLocalPort:(unsigned short int)port allowingAddressReuse:(BOOL)reuse;
{
    [self setLocalPortNumber:port allowingAddressReuse:(BOOL)reuse];

    if (listen(socketFD, PENDING_CONNECTION_LIMIT) == -1)
        [NSException raise:ONTCPSocketListenFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:@"Unable to listen on socket: %s", strerror(OMNI_ERRNO())];
    flags.listening = YES;
}

- (void)startListeningOnLocalService:(ONServiceEntry *)service;
{
    [self startListeningOnLocalPort:[service portNumber]];
}

- (void)acceptConnection;
{
    int newSocketFD;

    newSocketFD = [self socketFDForAcceptedConnection];
    pthread_mutex_lock(&socketLock);
    [self _locked_destroySocketFD];
    socketFD = newSocketFD;
    flags.connected = YES;
    flags.listening = NO;
    pthread_mutex_unlock(&socketLock);
}

- (ONTCPSocket *)acceptConnectionOnNewSocket;
{
    return (ONTCPSocket *)[[self class] socketWithConnectedFileDescriptor:[self socketFDForAcceptedConnection] shouldClose:YES];
}

- (void)setUsesNagleDelay:(BOOL)nagle;
{
    int optval = nagle? 0 : 1;  // enabling TCP_NODELAY means disabling the Nagle algorithm
    tcpFlags.useNagle = nagle? 1 : 0;

    if (socketFD != -1) {
        if (setsockopt(socketFD, IPPROTO_TCP, TCP_NODELAY, &optval, sizeof(optval))) {
            [NSException raise:ONInternetSocketSetOptionFailedExceptionName
              posixErrorNumber:OMNI_ERRNO()
                        format:@"Failed to set TCP_NODELAY to %d: %s", optval, strerror(OMNI_ERRNO())];
        }
    }
}

- (void)setPushesWrites:(BOOL)push;
{
    int optval = push? 0 : 1;  // enabling TCP_NOPUSH means disabling push-on-write
    tcpFlags.pushWrites = push? 1 : 0;

    if (socketFD != -1) {
        if (setsockopt(socketFD, IPPROTO_TCP, TCP_NOPUSH, &optval, sizeof(optval))) {
            [NSException raise:ONInternetSocketSetOptionFailedExceptionName
              posixErrorNumber:OMNI_ERRNO()
                        format:@"Failed to set TCP_NOPUSH to %d: %s", optval, strerror(OMNI_ERRNO())];
        }
    }
}

// ONInternetSocket subclass

+ (int)socketType;
{
    return SOCK_STREAM;
}

+ (int)ipProtocol;
{
    return IPPROTO_TCP;
}

- (void)connectToPortAddress:(ONPortAddress *)aPortAddress;
{
    if (socketFD != -1 && flags.connected) {
        // TCP sockets can't be re-connected once they've been connected
        // TODO: Should we raise here? The old code wouldn't, but it seems reasonable to raise in this case
        return;
    }
    
    [super connectToPortAddress:aPortAddress];
}

// ONSocket subclass

- (size_t)readBytes:(size_t)byteCount intoBuffer:(void *)aBuffer;
{
    ssize_t bytesRead;
    int read_errno;

    while (!flags.connected) {
        if (!flags.listening) {
            NSString *localizedErrorMsg = NSLocalizedStringFromTableInBundle(@"Attempted read from a non-connected socket", @"OmniNetworking", THIS_BUNDLE, @"error - socket is unxepectedly closed or not connected");
	    [[NSException exceptionWithName:ONInternetSocketNotConnectedExceptionName reason:localizedErrorMsg userInfo:nil] raise];
        } else
	    [self acceptConnection];
    }
    bytesRead = read(socketFD, aBuffer, byteCount);
    switch (bytesRead) {
        case -1:
            if (flags.userAbort)
                [[NSException exceptionWithName:ONInternetSocketUserAbortExceptionName reason:NSLocalizedStringFromTableInBundle(@"Read aborted", @"OmniNetworking", THIS_BUNDLE, @"error: userAbort") userInfo:nil] raise];
            // Error reading socket
            read_errno = OMNI_ERRNO();
            if (read_errno == EAGAIN)
                [[NSException exceptionWithName:ONTCPSocketWouldBlockExceptionName reason:NSLocalizedStringFromTableInBundle(@"Read aborted", @"OmniNetworking", THIS_BUNDLE, @"error: EAGAIN") userInfo:nil] raise];
            if (read_errno == EPIPE)
                goto read_eof;
            [NSException raise:ONInternetSocketReadFailedExceptionName posixErrorNumber:read_errno format:NSLocalizedStringFromTableInBundle(@"Unable to read from socket: %s", @"OmniNetworking", THIS_BUNDLE, @"error"), strerror(OMNI_ERRNO())];
            return 0; // Not reached
        case 0:
        read_eof:
            // Our peer closed the socket, resulting in an end-of-file.  Close it on this end.
            // NOTE: This is incorrect; it keeps us from using a half-closed socket. However,  other code probably depends on this behavior. Perhaps we should add a flag to control whether ONTCPSocket can tolerate being half-closed or not.
            flags.connected = NO;
            // 0 can be returned when we closed the socket ourselves (from another thread), so we may not still have a file descriptor...
            pthread_mutex_lock(&socketLock);
            [self _locked_destroySocketFD];
            pthread_mutex_unlock(&socketLock);
            return 0;
        default:
            // Normal successful read
            return bytesRead;
    }
}

- (size_t)writeBytes:(size_t)byteCount fromBuffer:(const void *)aBuffer;
{
    struct iovec io_vector;
    
    /* We have to cast away the 'const' here because the iovec type is used for both read and write and therefore don't have a const qualifier of their own. */
    io_vector.iov_base = (void *)aBuffer;
    io_vector.iov_len = byteCount;
    
    return [self writeBuffers:&io_vector count:1];
}

- (size_t)writeBuffers:(const struct iovec *)buffers count:(unsigned int)num_iov
{
    ssize_t bytesWritten;

    while (!flags.connected) {
        if (!flags.listening) {
            NSString *localizedErrorMsg = NSLocalizedStringFromTableInBundle(@"Attempted write to a non-connected socket", @"OmniNetworking", THIS_BUNDLE, "error - socket is unxepectedly closed, not connected, or not listening for connections");
            [[NSException exceptionWithName:ONInternetSocketNotConnectedExceptionName reason:localizedErrorMsg userInfo:nil] raise];
        } else
            [self acceptConnection];
    }
    
    if (num_iov == 1)
        bytesWritten = write(socketFD, buffers[0].iov_base, buffers[0].iov_len);
    else if (num_iov > 1)
        bytesWritten = writev(socketFD, buffers, num_iov);
    else
        bytesWritten = 0;
        
    if (bytesWritten < 0) {
        if (flags.userAbort)
            [[NSException exceptionWithName:ONInternetSocketUserAbortExceptionName reason:NSLocalizedStringFromTableInBundle(@"Write aborted", @"OmniNetworking", THIS_BUNDLE, @"error: userAbort") userInfo:nil] raise];
        if (OMNI_ERRNO() == EAGAIN)
            [[NSException exceptionWithName:ONTCPSocketWouldBlockExceptionName reason:NSLocalizedStringFromTableInBundle(@"Write aborted", @"OmniNetworking", THIS_BUNDLE, @"error: EAGAIN") userInfo:nil] raise];
        [NSException raise:ONInternetSocketWriteFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:NSLocalizedStringFromTableInBundle(@"Unable to write to socket: %s", @"OmniNetworking", THIS_BUNDLE, @"error"), strerror(OMNI_ERRNO())];
    }

    return bytesWritten;
}
    
#pragma mark - Private

- _initWithSocketFD:(int)aSocketFD connected:(BOOL)isConnected
{
    if (!(self = [super _initWithSocketFD:aSocketFD connected:isConnected]))
        return nil;

    tcpFlags.useNagle = ONTCP_OPT_USE_DEFAULT;
    tcpFlags.pushWrites = ONTCP_OPT_USE_DEFAULT;

    return self;
}

- (int)socketFDForAcceptedConnection;
{
    int newSocketFD;
    ONSockaddrAny acceptAddress;
    ONSocketAddressLength acceptAddressLength;

    acceptAddressLength = sizeof(acceptAddress);
    do {
	newSocketFD = accept(socketFD, &(acceptAddress.generic), &acceptAddressLength);
    } while (newSocketFD == -1 && OMNI_ERRNO() == EINTR);

    if (newSocketFD == -1)
	[NSException raise:ONTCPSocketAcceptFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:@"Socket accept failed: %s", strerror(OMNI_ERRNO())];
    if (!remoteAddress)
        remoteAddress = [[ONPortAddress alloc] initWithSocketAddress:&(acceptAddress.generic)];
    return newSocketFD;
}

- (void)_locked_createSocketFD:(int)af
{
    [super _locked_createSocketFD:af];
    
    if (socketFD == -1)  // some sort of failure
        return;

    if (tcpFlags.useNagle != ONTCP_OPT_USE_DEFAULT)
        [self setUsesNagleDelay: tcpFlags.useNagle];
    if (tcpFlags.pushWrites != ONTCP_OPT_USE_DEFAULT)
        [self setPushesWrites: tcpFlags.pushWrites];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];

    if (tcpFlags.useNagle != ONTCP_OPT_USE_DEFAULT)
        [debugDictionary setObject:tcpFlags.useNagle ? @"YES" : @"NO" forKey:@"useNagle"];
    if (tcpFlags.pushWrites != ONTCP_OPT_USE_DEFAULT)
        [debugDictionary setObject:tcpFlags.pushWrites ? @"YES" : @"NO" forKey:@"pushWrites"];

    return debugDictionary;
}

@end


NSString * const ONTCPSocketListenFailedExceptionName = @"ONTCPSocketListenFailedExceptionName";
NSString * const ONTCPSocketAcceptFailedExceptionName = @"ONTCPSocketAcceptFailedExceptionName";
NSString * const ONTCPSocketWouldBlockExceptionName = @"ONTCPSocketWouldBlockExceptionName";
