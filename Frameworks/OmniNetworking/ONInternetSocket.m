// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONInternetSocket.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniBase/system.h>

#import "ONInternetSocket-Private.h"
#import <OmniNetworking/ONServiceEntry.h>
#import <OmniNetworking/ONHostAddress.h>
#import <OmniNetworking/ONHost.h>
#import <OmniNetworking/ONInterface.h>
#import <OmniNetworking/ONPortAddress.h>

RCS_ID("$Id$")

#ifdef OMNI_ASSERTIONS_ON
static BOOL is_mutex_locked(pthread_mutex_t *m);
#endif

@implementation ONInternetSocket
{
    /* protocol family of socket, if socketFD is not -1 */
    short socketPF;
    
    
    int requestedLocalPort;  // 0=any port, -1=not bound to a local address yet
}

BOOL ONSocketStateDebug = NO;

+ (int)ipProtocol;
{
    OBRequestConcreteImplementation(self, _cmd);
    return -1; // Not executed
}

+ (int)socketType;
{
    OBRequestConcreteImplementation(self, _cmd);
    return -1; // Not executed
}

+ (ONInternetSocket *)socket;
{
    return [[[self alloc] _initWithSocketFD:-1 connected:NO] autorelease];
}

+ (ONInternetSocket *)socketWithConnectedFileDescriptor:(int)fd shouldClose:(BOOL)closeOnDealloc;
{
    ONInternetSocket *s = [[self alloc] _initWithSocketFD:fd connected:YES];
    s->flags.shouldNotCloseFD = closeOnDealloc ? 0 : 1;
        
    return [s autorelease];
}

// Init and dealloc

- (void)dealloc;
{
    pthread_mutex_lock(&socketLock);
    
    if (socketFD != -1 && !flags.shouldNotCloseFD) {
#ifdef OMNI_ASSERTIONS_ON
	int closeReturn = 
#endif
	close(socketFD);
	OBASSERT(closeReturn == 0);
    }
    socketFD = -1;

    [localAddress release];
    [remoteAddress release];
    [remoteHost release];

    localAddress = nil;
    remoteAddress = nil;
    remoteHost = nil;

    pthread_mutex_unlock(&socketLock);
    pthread_mutex_destroy(&socketLock);

    [super dealloc];
}

//

- (void)setLocalPortNumber;
{
    // Bind to any available local port
    [self setLocalPortNumber: 0];
}

- (void)setLocalPortNumber:(int)port;
{
    ONSockaddrAny socketAddress;
    int socketAddressLength;
    NSException *pendingException;

    pendingException = nil;
    
    pthread_mutex_lock(&socketLock);

    if (localAddress != nil) {
        [localAddress release];
        localAddress = nil;
    }

    if (port < 0) {
        pthread_mutex_unlock(&socketLock);
        return;
    }

    /* If we don't have a socket, go ahead and create one. We don't want to defer this because the caller will expect to get an error from this method if the port is already in use, and will expect us to allocate a port if they pass in '0' here --- so we have to actually call bind(). */

    if (socketFD == -1) {
        int desiredSocketAF;
        
        requestedLocalPort = -1;  /* prevent -createSocketFD: from trying to re-invoke us */
        
        /* Default to binding to an IPv4 address. TODO: Can we make this more address-family-agnostic? */
        /* Note that if we were to bind to the v6 wildcard address, then as long as there isn't a socket bound to the v4 wildcard address, we'll get the v4 traffic as well as the v6 traffic (with a v4-mapped-in-v6-address for the remote address; see "man 4 inet6"). That might be the right thing to do, except that it might confuse applications which only expect v4 remote addresses --- perhaps we should unmap v4-in-v6 addresses in ONHostAddress? That sounds like a mess... */
        if (socketPF == PF_UNSPEC)
            desiredSocketAF = AF_INET;
        else
            desiredSocketAF = ONAddressFamilyForProtocolFamily(socketPF);

        NS_DURING {
            [self _locked_createSocketFD:desiredSocketAF];
        } NS_HANDLER {
            pendingException = localException;
        } NS_ENDHANDLER;
    }

    requestedLocalPort = port;

    pthread_mutex_unlock(&socketLock);
    
    if (pendingException)
        [pendingException raise];

    switch([self addressFamily]) {
        case AF_INET:
            bzero(&socketAddress, sizeof(socketAddress.ipv4));
            socketAddressLength                = sizeof(socketAddress.ipv4);
            socketAddress.ipv4.sin_len         = sizeof(socketAddress.ipv4);
            socketAddress.ipv4.sin_family      = AF_INET;
            socketAddress.ipv4.sin_addr.s_addr = htonl(INADDR_ANY);
            socketAddress.ipv4.sin_port        = htons(port);
            break;
        case AF_INET6:
            bzero(&socketAddress, sizeof(socketAddress.ipv6));
            socketAddressLength                = sizeof(socketAddress.ipv6);
            socketAddress.ipv6.sin6_len        = sizeof(socketAddress.ipv6);
            socketAddress.ipv6.sin6_family     = AF_INET6;
            socketAddress.ipv6.sin6_addr       = (struct in6_addr)IN6ADDR_ANY_INIT;
            socketAddress.ipv6.sin6_port       = htons(port);
            break;
        default:
            [NSException raise:ONInternetSocketBindFailedExceptionName posixErrorNumber:EPFNOSUPPORT format:@"Unable to bind a socket: %s", strerror(EPFNOSUPPORT)];
            return;
    }

    if (bind(socketFD, (struct sockaddr *)&socketAddress, socketAddressLength) == -1)
	[NSException raise:ONInternetSocketBindFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:@"Unable to bind a socket: %s", strerror(OMNI_ERRNO())];
}

- (void)setLocalPortNumber:(int)port allowingAddressReuse:(BOOL)reuse;
{
    BOOL hadError;
    
    hadError = NO;

    flags.allowAddressReuse = reuse? 1 : 0;

    if (socketFD != -1) {
        int shouldReuse;

        shouldReuse = reuse? 1 : 0;
        if (setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &shouldReuse, sizeof(shouldReuse)) == -1)
            hadError = YES;

        shouldReuse = reuse? 1 : 0;
        if (setsockopt(socketFD, SOL_SOCKET, SO_REUSEPORT, &shouldReuse, sizeof(shouldReuse)) == -1)
            hadError = YES;
    }

    if (hadError)
        [NSException raise:ONInternetSocketReuseSelectionFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:@"Failed to set address reuse on socket: %s", strerror(OMNI_ERRNO())];

    if (port >= 0)
        [self setLocalPortNumber:port];
}

/* Utility function for retrieving a sockaddr and returning it as an ONPortAddress */
static ONPortAddress *getEndpointAddress(ONInternetSocket *self, int (*getaddr)(int, struct sockaddr *, ONSocketAddressLength *), NSException **exc)
{
    ONSocketAddressLength addressLength;
    ONSockaddrAny endpointAddress;
    
    if (self->socketFD == -1)
        return nil;
    
    addressLength = sizeof(endpointAddress);
    if (getaddr(self->socketFD, &(endpointAddress.generic), &addressLength) == -1) {
        *exc = [NSException exceptionWithName:ONInternetSocketGetNameFailedExceptionName
                             posixErrorNumber:OMNI_ERRNO()
                                       format:@"Unable to get socket name: %s", strerror(OMNI_ERRNO())];
        return nil;
    }

    return [[[ONPortAddress alloc] initWithSocketAddress:&(endpointAddress.generic)] autorelease];
}

- (int)addressFamily
{
    /* If necessary we can determine the family of a pre-existing socket by extracting it from the socket's local name */
    if (socketPF == PF_UNSPEC && socketFD != -1) {
        int socketAF = [[self localAddress] addressFamily];
        socketPF = ONProtocolFamilyForAddressFamily(socketAF);
        return socketAF;
    }

    return ONAddressFamilyForProtocolFamily(socketPF);
}

- (void)setAddressFamily:(int)newAddressFamily
{
    if (newAddressFamily == PF_UNSPEC ||
        newAddressFamily == [self addressFamily])
        return;

    if (socketFD != -1) {
        // In the normal case, -setAddressFamily: will only be called before the socketFD is allocated.
        // We don't really want to close and re-open the BSD socket, because that will lose connections, port assignments, etc. --- if, for some reason, it makes sense to be able to call -setAddressFamily: after the socket exists, then we can change this logic
        [NSException raise:ONInternetSocketBindFailedExceptionName posixErrorNumber:EEXIST format:NSLocalizedStringFromTableInBundle(@"Unable to set address family of already-allocated socket", @"OmniNetworking", [NSBundle bundleForClass:[ONInternetSocket class]], @"error - attempted to change protocol family after the fact")];
    }

    /* Since we don't have a socket, we can just set the socketPF to tell us what kind of socket to create later */
    OBASSERT(socketFD == -1);
    socketPF = ONProtocolFamilyForAddressFamily(newAddressFamily);
}

- (ONPortAddress *)localAddress;
{
    ONPortAddress *myLocalAddress;
    NSException *exception = nil;

    pthread_mutex_lock(&socketLock);

    if (!localAddress)
        localAddress = [getEndpointAddress(self, getsockname, &exception) retain];
    myLocalAddress = [localAddress retain];

    pthread_mutex_unlock(&socketLock);

    if (exception)
        [exception raise];
    return [myLocalAddress autorelease];
}

- (unsigned short int)localAddressPort;
{
    ONPortAddress *myLocalAddress = [self localAddress];

    if (myLocalAddress == nil) {
        if (requestedLocalPort > 0)
            return requestedLocalPort;
        else
            return 0;
    } else
        return [myLocalAddress portNumber];
}

//

- (ONHost *)remoteAddressHost;
{
    ONHost *myRemoteHost;
    
    pthread_mutex_lock(&socketLock);

    if (remoteHost) {
        myRemoteHost = [remoteHost retain];
        pthread_mutex_unlock(&socketLock);
	return [myRemoteHost autorelease];
    } else {
        ONPortAddress *myRemoteAddress;
        
        pthread_mutex_unlock(&socketLock);

        /* This may take a while (to resolve the hostname) and may raise an exception, so we release the lock while we do it */
        myRemoteAddress = [self remoteAddress];
        myRemoteHost = myRemoteAddress? [ONHost hostForAddress:[myRemoteAddress hostAddress]] : nil;

        pthread_mutex_lock(&socketLock);
        if (remoteHost == nil && remoteAddress == myRemoteAddress)
            remoteHost = [myRemoteHost retain];
        pthread_mutex_unlock(&socketLock);

        return myRemoteHost;
    }
}

- (ONPortAddress *)remoteAddress;
{
    ONPortAddress *myRemoteAddress;
    NSException *exception = nil;
    
    pthread_mutex_lock(&socketLock);

    if (!remoteAddress) {
        OBASSERT(remoteHost == nil);
        remoteAddress = [getEndpointAddress(self, getpeername, &exception) retain];
    }
    myRemoteAddress = [remoteAddress retain];

    pthread_mutex_unlock(&socketLock);

    if (exception)
        [exception raise];
    return [myRemoteAddress autorelease];
}

- (unsigned short int)remoteAddressPort;
{
    return [[self remoteAddress] portNumber];
}

//

- (ONInterface *)localInterface;
{
    ONHostAddress *myAddress = [[self localAddress] hostAddress];
    unsigned int triesRemaining = 2;
    while (triesRemaining--) {
        NSArray *interfaces = [ONInterface getInterfaces:triesRemaining == 0];
        NSUInteger interfaceCount = [interfaces count];
        while (interfaceCount--) {
            ONInterface  *interface = [interfaces objectAtIndex:interfaceCount];

            // In the future, we might want to handle the case in which multiple network
            // interfaces have the same IP address.  In that case, we'd either need to
            // return an array of the possible interfaces, or look at a destination address
            // and the routing tables in order to determine which interface will get used.
            // There still might be multiple interfaces that might be sharing the load,
            // in which case it seems like we wouldn't be able to determine with any certainty
            // which one would get used.  The best solution would probably be to return an
            // array of possibilities and let the caller work with that set (for example, in
            // the case of the -maximumTransmissionUnit, they could just use the smallest unit.
            if ([[interface addresses] containsObject:myAddress])
                return interface;
        }
    }

    [NSException raise:NSInternalInconsistencyException format:@"No interface found matching local address %@ for socket %@.", myAddress, self];
    return nil; // We raise before reaching this line
}

//

- (void)connectToAddressFromArray:(NSArray *)portAddresses
{
    NSUInteger addressCount, addressIndex;
    NSException *firstTemporaryException;

    firstTemporaryException = nil;
    
    addressCount = [portAddresses count];
    for(addressIndex = 0; addressIndex < addressCount; addressIndex ++) {
        ONPortAddress *anAddress = [portAddresses objectAtIndex:addressIndex];

        OBASSERT([anAddress isKindOfClass:[ONPortAddress class]]);

        NS_DURING {
            [self connectToPortAddress:anAddress];
        } NS_HANDLER {
            if (![[localException name] isEqualToString:
                ONInternetSocketConnectTemporarilyFailedExceptionName])
                [localException raise];
            if (!firstTemporaryException)
                firstTemporaryException = localException;
        } NS_ENDHANDLER;
        
        if (flags.connected)
            return;
    }

    if (firstTemporaryException)
        [firstTemporaryException raise];
    else
        [[NSException exceptionWithName:ONInternetSocketConnectFailedExceptionName reason:NSLocalizedStringFromTableInBundle(@"Unable to connect: no IP addresses to connect to", @"OmniNetworking", [NSBundle bundleForClass:[ONInternetSocket class]], @"error") userInfo:nil] raise];
}

- (void)connectToPortAddress:(ONPortAddress *)portAddress;
{
    NSException *pendingException = nil;
    const struct sockaddr *socketAddress;
    BOOL connectSucceeded;
    
    socketAddress = [portAddress portAddress];
    
    OBPRECONDITION(!is_mutex_locked(&socketLock));
    
    pthread_mutex_lock(&socketLock);
    
    if (remoteAddress != nil) {
        [remoteAddress release];
        remoteAddress = nil;
    }
    if (remoteHost != nil) {
        [remoteHost release];
        remoteHost = nil;
    }
    
    /* If we have a socket of the wrong family, get rid of it */
    if (socketFD != -1 && [self addressFamily] != (socketAddress->sa_family))
        [self _locked_destroySocketFD];
    /* Create a socket of the appropriate protocol family */
    if (socketFD == -1) {
        NS_DURING {
            [self _locked_createSocketFD:socketAddress->sa_family];
        } NS_HANDLER {
            pendingException = localException;
        } NS_ENDHANDLER;
    }
        
    pthread_mutex_unlock(&socketLock);
    
    if (pendingException == nil) {
        errno = 0;
        connectSucceeded = connect(socketFD, socketAddress, socketAddress->sa_len) == 0;
        if (ONSocketStateDebug)
            NSLog(@"%@: connect(%@) --> %@", [self shortDescription], [portAddress description],
                  connectSucceeded ? @"Success" : [NSString stringWithFormat:@"Failure (errno=%d)", errno]);
    } else {
        connectSucceeded = NO;
        if (ONSocketStateDebug)
            NSLog(@"%@: connect(%@) skipped due to pending exception (%@)", [self shortDescription], [portAddress description], [pendingException name]);
    }
    
    if (connectSucceeded) {
        flags.connected = YES;
    } else {
        pthread_mutex_lock(&socketLock);
        
        // Check to see if the user aborted the connect()
        if (flags.userAbort)
            pendingException = [NSException exceptionWithName:ONInternetSocketUserAbortExceptionName reason:NSLocalizedStringFromTableInBundle(@"Connect aborted", @"OmniNetworking", [NSBundle bundleForClass:[ONInternetSocket class]], @"error - user (or other event) canceled attempt to connect to remote host") userInfo:nil];
        
        [self _locked_destroySocketFD];
        
        if (pendingException == nil)
            switch (OMNI_ERRNO()) {
                case ETIMEDOUT:
                case ECONNREFUSED:
                case ENETDOWN:
                case ENETUNREACH:
                case EHOSTDOWN:
                case EADDRNOTAVAIL:
                case EAFNOSUPPORT:
                case EHOSTUNREACH:
                    pendingException = [NSException exceptionWithName:ONInternetSocketConnectTemporarilyFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:NSLocalizedStringFromTableInBundle(@"Temporarily unable to connect to %@: %s", @"OmniNetworking", [NSBundle bundleForClass:[ONInternetSocket class]], @"error - one of ETIMEDOUT ECONNREFUSED ENETDOWN ENETUNREACH EHOSTDOWN or EHOSTUNREACH"), [portAddress description], strerror(OMNI_ERRNO())];
                    break;
                default:
                    pendingException = [NSException exceptionWithName:ONInternetSocketConnectFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:NSLocalizedStringFromTableInBundle(@"Unable to connect to %@: %s", @"OmniNetworking", [NSBundle bundleForClass:[ONInternetSocket class]], @"error - non-transient error when connecting to remote host"), portAddress, strerror(OMNI_ERRNO())];
                    break;
            };
        
        pthread_mutex_unlock(&socketLock);
        if (ONSocketStateDebug)
            NSLog(@"%@ %@: raising %@", [self shortDescription], NSStringFromSelector(_cmd), [pendingException name]);
        [pendingException raise];
    }
}

- (void)connectToHost:(ONHost *)host serviceEntry:(ONServiceEntry *)service;
{
    [self connectToAddressFromArray:[host portAddressesForService:service]];
}

- (void)connectToHost:(ONHost *)host port:(unsigned short int)port;
{
    NSArray *hostAddresses;
    NSMutableArray *portAddresses;
    NSUInteger addressCount, addressIndex;

    /* Make an array of ONPortAddresses from the host's list of ONHostAddresses. TODO: This logic should really be in ONHost; perhaps by calling -portAddressesForService: with an anonymous numeric service object */
    hostAddresses = [host addresses];
    addressCount = [hostAddresses count];
    portAddresses = [[NSMutableArray alloc] initWithCapacity:addressCount];
    [portAddresses autorelease];
    for (addressIndex = 0; addressIndex < addressCount; addressIndex ++) {
        ONPortAddress *portAddress = [[ONPortAddress alloc] initWithHostAddress:[hostAddresses objectAtIndex:addressIndex] portNumber:port];
        [portAddresses addObject:portAddress];
        [portAddress release];
    }

    [self connectToAddressFromArray:portAddresses];
}

- (void)connectToAddress:(ONHostAddress *)hostAddress port:(unsigned short int)port;
{
    [self connectToPortAddress:[[[ONPortAddress alloc] initWithHostAddress:hostAddress portNumber:port] autorelease]];
}

- (void)setNonBlocking:(BOOL)shouldBeNonBlocking;
{
    fcntl(socketFD, F_SETFL, shouldBeNonBlocking ? O_NONBLOCK : 0x0);
    flags.nonBlocking = shouldBeNonBlocking? 1 : 0;
}

- (BOOL)waitForInputWithTimeout:(NSTimeInterval)timeout;
{
    struct timeval selectTimeout;
    fd_set readfds;
    int returnValue;

    if (socketFD == -1) {
        NSString *localizedErrorMsg = NSLocalizedStringFromTableInBundle(@"Attempted read from a non-connected socket", @"OmniNetworking", [NSBundle bundleForClass:[ONInternetSocket class]], @"error - socket is unxepectedly closed or not connected");
        [[NSException exceptionWithName:ONInternetSocketNotConnectedExceptionName reason:localizedErrorMsg userInfo:nil] raise];
    }

    if (timeout < 0.0)
        timeout = 0.0;
    
    double usec, isec;
    usec = modf(timeout, &isec);
    selectTimeout.tv_sec = (unsigned int)isec;
    selectTimeout.tv_usec = (unsigned int)floor(1.0e6 * usec);
    FD_ZERO(&readfds);
    FD_SET(socketFD, &readfds);
    returnValue = select(socketFD + 1, &readfds, NULL, NULL, &selectTimeout);
    switch (returnValue) {
        case -1:
            [NSException raise:ONInternetSocketReadFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:NSLocalizedStringFromTableInBundle(@"Error waiting for input: %s", @"OmniNetworking", [NSBundle bundleForClass:[ONInternetSocket class]], @"error return from select()"), strerror(OMNI_ERRNO())];
        case 0:
            return NO;
        default:
            return FD_ISSET(socketFD, &readfds) != 0;
    }
}

- (void)setAllowsBroadcast:(BOOL)shouldAllowBroadcast;
{
    int allows;

    // convert BOOL to an int
    allows = shouldAllowBroadcast? 1 : 0;

    // convert BOOL to a bit flag
    flags.allowBroadcast = shouldAllowBroadcast? 1 : 0;

    if (socketFD != -1) {
        if (setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, (char *)&allows, sizeof(allows)) == -1)
            [NSException raise:ONInternetSocketBroadcastSelectionFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:@"Failed to set broadcast to %d on socket: %s", allows, strerror(OMNI_ERRNO())];
    }
}

- (int)socketFD;
{
    return socketFD;
}

- (BOOL)isConnected;
{
    return (flags.connected > 0) ? YES : NO;
}

- (BOOL)didAbort;
{
    return (flags.userAbort > 0) ? YES : NO;
}

- (BOOL)isWritable;
{
    fd_set writeSet;
    struct timeval timeout;
    int writability;
    
    if (socketFD == -1)
        return NO;
    
    timeout.tv_sec = 0;
    timeout.tv_usec = 0;
    FD_ZERO(&writeSet);
    FD_SET(socketFD, &writeSet);
    writability = select(socketFD + 1, NULL, &writeSet, NULL, &timeout);
    
    return (writability == 1);
}

- (BOOL)isReadable;
{
    fd_set readSet;
    struct timeval timeout;

    if (socketFD == -1)
        return NO;

    timeout.tv_sec = 0;
    timeout.tv_usec = 0;
    FD_ZERO(&readSet);
    FD_SET(socketFD, &readSet);
    return select(socketFD + 1, &readSet, NULL, NULL, &timeout) == 1;
}

// ONSocket subclass

- (void)abortSocket;
{
    pthread_mutex_lock(&socketLock);
    
    flags.userAbort = YES;
    if (socketFD != -1)
        [self _locked_destroySocketFD];
    flags.connected = NO;

    pthread_mutex_unlock(&socketLock);
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (socketFD != -1)
	[debugDictionary setObject:[NSNumber numberWithInt:socketFD] forKey:@"socketFD"];
#define NOTE_FLAG(flag) [debugDictionary setObject:flags.flag ? @"YES" : @"NO" forKey:(NSString *)CFSTR(#flag)]
    NOTE_FLAG(listening);
    NOTE_FLAG(connected);
    NOTE_FLAG(userAbort);
    NOTE_FLAG(shouldNotCloseFD);
    NOTE_FLAG(allowAddressReuse);
    NOTE_FLAG(allowBroadcast);
    NOTE_FLAG(nonBlocking);

    if (socketPF != PF_UNSPEC)
        [debugDictionary setObject:[NSNumber numberWithInt:socketPF] forKey:@"socketPF"];
    if (requestedLocalPort != -1)
        [debugDictionary setObject:[NSNumber numberWithInt:requestedLocalPort] forKey:@"requestedLocalPort"];

    return debugDictionary;
}

@end

@implementation ONInternetSocket (SubclassAPI)

- _initWithSocketFD:(int)aSocketFD connected:(BOOL)isConnected;
{
    if (!(self = [super init]))
	return nil;

    OBASSERT(!(isConnected && (aSocketFD == -1)));

    socketFD = aSocketFD;
    flags.connected = isConnected;

    socketPF = PF_UNSPEC;
    requestedLocalPort = -1;

    pthread_mutex_init(&socketLock, NULL);

    return self;
}

#ifdef OMNI_ASSERTIONS_ON
static BOOL is_mutex_locked(pthread_mutex_t *m)
{
    int err = pthread_mutex_trylock(m);

    if (err == EBUSY)
        return YES;

    if (err == 0) {
        pthread_mutex_unlock(m);
        return NO;
    }

    return NO;
}
#endif

- (void)ensureSocketFD:(int)af;
{
    pthread_mutex_lock(&socketLock);

    if (socketFD == -1) {
        NS_DURING {
            [self _locked_createSocketFD:af];
        } NS_HANDLER {
            if (socketFD != -1)
                [self _locked_destroySocketFD];
            pthread_mutex_unlock(&socketLock);
            [localException raise];
        } NS_ENDHANDLER;
    }

    pthread_mutex_unlock(&socketLock);
}


- (void)_locked_createSocketFD:(int)af;
{
    int newSocketFD;
    int protocolFamily;

    OBPRECONDITION(is_mutex_locked(&socketLock));
    OBPRECONDITION(socketFD == -1);
    OBPRECONDITION(localAddress == nil);
    OBPRECONDITION(remoteAddress == nil);
    OBPRECONDITION(remoteHost == nil);
    
    protocolFamily = ONProtocolFamilyForAddressFamily(af);

    newSocketFD = socket(protocolFamily, [[self class] socketType], [[self class] ipProtocol]);
    if (ONSocketStateDebug)
        NSLog(@"%@: opened new fd %d", [self shortDescription], newSocketFD);
    if (newSocketFD == -1) {
        [NSException raise:ONInternetSocketConnectFailedExceptionName posixErrorNumber:OMNI_ERRNO() format:@"Unable to create a socket: %s", strerror(OMNI_ERRNO())];
        return;
    }

    socketFD = newSocketFD;
    socketPF = protocolFamily;
    flags.shouldNotCloseFD = 0;
    flags.listening = 0;
    flags.connected = 0;
    
    if (requestedLocalPort != -1 || flags.allowAddressReuse)
        [self setLocalPortNumber:requestedLocalPort allowingAddressReuse:(flags.allowAddressReuse)? YES : NO];
    if (flags.nonBlocking)
        [self setNonBlocking:(flags.nonBlocking)? YES : NO];
    if (flags.allowBroadcast)
        [self setAllowsBroadcast:(flags.allowBroadcast)? YES : NO];

    OBPOSTCONDITION(socketFD != -1);
}

- (void)_locked_destroySocketFD
{
    int oldSocketFD;

    OBPRECONDITION(is_mutex_locked(&socketLock));

    oldSocketFD = socketFD;

    if (ONSocketStateDebug)
        NSLog(@"%@: releasing fd %d", [self shortDescription], oldSocketFD);

    if (oldSocketFD == -1)
        return;
        
    socketFD = -1;

    /* Unclear what this call to shutdown() is needed for; it used to be in -abortSocket. We need to call shutdown() after copying the fd into oldSocketFD, however, since shutdown() may cause another thread to wake up and start closing things, that being one of the few threadsafe operations on ONInternetSocket. */
    /* TODO: Perhaps -abortSocket should merely call shutdown(), and not destroy the FD (or call this method)? In which case, -destroySocketFD wouldn't call shutdown() */
    if (flags.connected && flags.userAbort)
        shutdown(oldSocketFD, SHUT_RDWR); // disallow further sends and receives
    
    if (!flags.shouldNotCloseFD) {
#ifdef OMNI_ASSERTIONS_ON
        int closeReturn =
#endif
        close(oldSocketFD);
        OBASSERT(closeReturn == 0);
    }

    if (localAddress != nil) {
        [localAddress release];
        localAddress = nil;
    }
    if (remoteAddress != nil) {
        [remoteAddress release];
        remoteAddress = nil;
    }
    if (remoteHost != nil) {
        [remoteHost release];
        remoteHost = nil;
    }

    flags.listening = 0;
    flags.connected = 0;    
}

@end


NSString * const ONInternetSocketBroadcastSelectionFailedExceptionName = @"ONInternetSocketBroadcastSelectionFailedExceptionName";
NSString * const ONInternetSocketReuseSelectionFailedExceptionName = @"ONInternetSocketReuseSelectionFailedExceptionName";
NSString * const ONInternetSocketBindFailedExceptionName = @"ONInternetSocketBindFailedExceptionName";
NSString * const ONInternetSocketConnectFailedExceptionName = @"ONInternetSocketConnectFailedExceptionName";
NSString * const ONInternetSocketConnectTemporarilyFailedExceptionName = @"ONInternetSocketConnectTemporarilyFailedExceptionName";
NSString * const ONInternetSocketGetNameFailedExceptionName = @"ONInternetSocketGetNameFailedExceptionName";
NSString * const ONInternetSocketNotConnectedExceptionName = @"ONInternetSocketNotConnectedExceptionName";
NSString * const ONInternetSocketReadFailedExceptionName = @"ONInternetSocketReadFailedExceptionName";
NSString * const ONInternetSocketUserAbortExceptionName = @"ONInternetSocketUserAbortExceptionName";
NSString * const ONInternetSocketWriteFailedExceptionName = @"ONInternetSocketWriteFailedExceptionName";
NSString * const ONInternetSocketCloseFailedExceptionName = @"ONInternetSocketCloseFailedExceptionName";
NSString * const ONInternetSocketSetOptionFailedExceptionName = @"ONInternetSocketSetOptionFailedExceptionName";
