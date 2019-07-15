// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONInternetSocket.h>

#import <OmniNetworking/ONFeatures.h>

#include <netinet/in.h>
#include <sys/un.h>

typedef union {
    struct sockaddr generic;           // Generic "abstract superclass" sockaddr
    struct sockaddr_in ipv4;           // IPv4 addresses
    struct sockaddr_in6 ipv6;          // IPv6 addresses
    struct sockaddr_un local;          // UNIX-domain socket addresses
    struct sockaddr_storage storage;   // Forces alignment and size
    
#if 0
    /* Other sockaddr types we may want someday but don't need right now */
    struct sockaddr_dl link;           // Data-link layer address (e.g. interface+MAC address)
#endif
} ONSockaddrAny;

typedef socklen_t ONSocketAddressLength;

// This API is for use by subclasses of ONInternetSocket.  It shouldn't be used by the world at large.

@interface ONInternetSocket (SubclassAPI)

- _initWithSocketFD:(int)aSocketFD connected:(BOOL)isConnected;
    // Designated initializer

- (void)ensureSocketFD:(int)family;
- (void)_locked_createSocketFD:(int)family;
    // Creates and sets up socketFD with the specified address family, and with any remembered socket options. May raise.

- (void)_locked_destroySocketFD;
    // Sets the socketFD to -1, as well as doing related cleanup. Must not raise.

OB_HIDDEN extern BOOL ONSocketStateDebug;

@end
