// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBObject.h>
#import <OmniBase/system.h>

@class NSData;

@interface ONHostAddress : OBObject <NSCopying>

+ (ONHostAddress *)hostAddressWithInternetAddress:(const void *)anInternetAddress family:(unsigned char)addressFamily;
    // Returns an ONHostAddress with the given internet address, which is interpreted in the given address family. The address should be in network byte order. addressFamily can be AF_INET, AF_INET6, or AF_APPLETALK.
    
+ (ONHostAddress *)addressWithIPv4UnsignedLong:(uint32_t)anAddress;
    // Returns an ONHostAddress with the specified IPv4 host address. The address is in host byte order.

+ (ONHostAddress *)hostAddressWithSocketAddress:(const struct sockaddr *)newPortAddress;
    // Returns an ONHostAddress created from the relevant portion of a socket address structure.

+ (ONHostAddress *)hostAddressWithNumericString:(NSString *)internetAddressString;
    // Returns an ONHostAddress from a numeric representation such as a dotted quad. If the string cannot be parsed as a host address, this method returns nil.

+ (ONHostAddress *)anyAddress;
    // Returns a wildcard address (currently INADDR_ANY).
+ (ONHostAddress *)loopbackAddress;
    // Returns a loopback address (currently INADDR_LOOPBACK, [127.0.0.1]).
+ (ONHostAddress *)broadcastAddress;
    // Returns a broadcast address (currently INADDR_BROADCAST).

- (int)addressFamily;
    // Returns the address family of this host address, currently one of AF_INET, AF_INET6, AF_APPLETALK, or AF_LINK.
- (BOOL)isMulticastAddress;
    // Returns YES if this host address is a multicast (possibly including broadcast) address.
- (BOOL)isLocalInterfaceAddress;
    // Returns YES if this is an address of one of our local network interfaces

- (struct sockaddr *)mallocSockaddrWithPort:(unsigned short int)portNumber;
    // Allocates and fills in a socket address structure, with the host address set to the receiver's value, and the port number set to the supplied port number. The portNumber prameter is in host byte order. The caller is responsible for freeing the returned pointer with free().

- (NSString *)stringValue;
    // Returns a textual representation of this address. Currently this is the same as the string returned by -description, but -description may become more verbose at some point.

- (NSData *) addressData;
    // Returns a binary representation of this address.  Later we may add an initializer that accepts this format.

@end

