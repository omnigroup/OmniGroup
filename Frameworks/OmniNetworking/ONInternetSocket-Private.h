// Copyright 1997-2005, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "ONInternetSocket.h"

#import "ONFeatures.h"

#include <netinet/in.h>
#include <sys/un.h>

#if ON_SUPPORT_APPLE_TALK
#include <netat/appletalk.h>
#endif

typedef union {
    struct sockaddr generic;           // Generic "abstract superclass" sockaddr
    struct sockaddr_in ipv4;           // IPv4 addresses
    struct sockaddr_in6 ipv6;          // IPv6 addresses
    struct sockaddr_un local;          // UNIX-domain socket addresses
    struct sockaddr_storage storage;   // Forces alignment and size
#if ON_SUPPORT_APPLE_TALK
    struct sockaddr_at atalk;          // AF_APPLETALK addresses [net.work:node/socket]
#endif
    
#if 0
    /* Other sockaddr types we may want someday but don't need right now */
    struct sockaddr_dl link;           // Data-link layer address (e.g. interface+MAC address)
#endif
} ONSockaddrAny;

// gcc 4.0 & 10.4 result in warnings if we use int for this since the BSD headers were modified to add a socklen_t type (which is unsigned) and gcc 4 complains about signed vs. unsigned mismatches.
#if defined(MAC_OS_X_VERSION_10_4) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
typedef socklen_t ONSocketAddressLength;
#else
typedef int ONSocketAddressLength;
#endif

// This API is for use by subclasses of ONInternetSocket.  It shouldn't be used by the world at large.

@interface ONInternetSocket (SubclassAPI)

- _initWithSocketFD:(int)aSocketFD connected:(BOOL)isConnected;
    // Designated initializer

- (void)ensureSocketFD:(int)family;
- (void)_locked_createSocketFD:(int)family;
    // Creates and sets up socketFD with the specified address family, and with any remembered socket options. May raise.

- (void)_locked_destroySocketFD;
    // Sets the socketFD to -1, as well as doing related cleanup. Must not raise.

OmniNetworking_PRIVATE_EXTERN BOOL ONSocketStateDebug;

@end
