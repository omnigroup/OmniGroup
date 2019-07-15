// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONSocket.h>
#import <OmniNetworking/ONInterface.h>
#import <pthread.h>

@class ONHost;
@class ONHostAddress;
@class ONPortAddress;
@class ONServiceEntry;

#import <Foundation/NSDate.h> // For NSTimeInterval

@interface ONInternetSocket : ONSocket
{
@protected
    /* The underlying BSD socket descriptor, or -1 */
    int socketFD;
    
    /* A mutex which protects changes to socketFD and other ivars */
    pthread_mutex_t socketLock;

    struct {
        unsigned int listening:1;
        unsigned int connected:1;
        unsigned int userAbort:1;
        unsigned int shouldNotCloseFD:1;
        
        /* These flags track the options we've set on the socket, so we can set them again if  we have to close and recreate the socket in a new protocol family */
        unsigned int nonBlocking:1;
        unsigned int allowAddressReuse:1;
        unsigned int allowBroadcast:1;
    } flags;
    
    /* Cached attributes of the endpoints of the socket connection, if any */
    ONPortAddress *localAddress;
    ONPortAddress *remoteAddress;
    ONHost *remoteHost;
}

+ (int)socketType;
+ (int)ipProtocol;

+ (ONInternetSocket *)socket;

+ (ONInternetSocket *)socketWithConnectedFileDescriptor:(int)fd shouldClose:(BOOL)closeOnDealloc;

- (void)setLocalPortNumber;
    // Sets the local port to any available local port number

- (void)setLocalPortNumber:(int)port;
    // Sets the local port that will be used when sending and receiving messages.

- (void)setLocalPortNumber:(int)port allowingAddressReuse:(BOOL)reuse;
    // Sets the local port that will be used when sending and receiving messages.  If reuse is true, other sockets will be allowed to use the same local port.

- (int)addressFamily;
    // Returns the socket's current address family, or AF_UNSPEC if none. Note that an ONInternetSocket, unlike the underlying BSD socket, can change its address family.
- (void)setAddressFamily:(int)newAddressFamily;
    // Sets the address family of the receiver (typically to AF_INET or AF_INET6). A subsequent -connect... call might change the socket's address family to match the family of the remote address. -setAddressFamily: can be used before a call to -setLocalPortNumber in order to cause the socket to bind to an address in a family other than AF_INET.
    
- (ONPortAddress *)localAddress;
- (unsigned short int)localAddressPort;

- (ONHost *)remoteAddressHost;
- (ONPortAddress *)remoteAddress;
- (unsigned short int)remoteAddressPort;

- (ONInterface *)localInterface;

- (void)connectToPortAddress:(ONPortAddress *)portAddress;
- (void)connectToHost:(ONHost *)host serviceEntry:(ONServiceEntry *)service;
- (void)connectToHost:(ONHost *)host port:(unsigned short int)port;
- (void)connectToAddress:(ONHostAddress *)hostAddress port:(unsigned short int)port;
- (void)connectToAddressFromArray:(NSArray *)portAddresses;
    // This attempts to connect to one of a list of addresses, e.g. for a multi-homed host or for a service with multiple MX or SRV records. Most of the -connectTo... methods invoke -connectToAddressFromArray: to do the actual work.

- (void)setNonBlocking:(BOOL)shouldBeNonBlocking;
- (BOOL)waitForInputWithTimeout:(NSTimeInterval)timeout;

- (void)setAllowsBroadcast:(BOOL)shouldAllowBroadcast;
// This really only makes sense for UDP and Multicast sockets

- (int)socketFD;

- (BOOL)isConnected;
- (BOOL)didAbort;

@end

/* These are here in case they become nontrivial someday */
static inline int ONProtocolFamilyForAddressFamily(int addressFamily)
{
    return addressFamily;
}

static inline int ONAddressFamilyForProtocolFamily(int protocolFamily)
{
    return protocolFamily;
}

// Exceptions which may be raised by this class
extern NSString * const ONInternetSocketBindFailedExceptionName;
extern NSString * const ONInternetSocketReuseSelectionFailedExceptionName;
extern NSString * const ONInternetSocketBroadcastSelectionFailedExceptionName;
extern NSString * const ONInternetSocketConnectFailedExceptionName;
extern NSString * const ONInternetSocketConnectTemporarilyFailedExceptionName;
extern NSString * const ONInternetSocketGetNameFailedExceptionName;
extern NSString * const ONInternetSocketNotConnectedExceptionName;
extern NSString * const ONInternetSocketReadFailedExceptionName;
extern NSString * const ONInternetSocketSetOptionFailedExceptionName;
extern NSString * const ONInternetSocketUserAbortExceptionName;
extern NSString * const ONInternetSocketWriteFailedExceptionName;
extern NSString * const ONInternetSocketCloseFailedExceptionName;
