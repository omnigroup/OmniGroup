// Copyright 2003-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONLinkLayerHostAddress.h>
#import "ONHostAddress-Private.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniBase/system.h>

#include <net/if_types.h>
#include <net/if_dl.h>

RCS_ID("$Id$");

@implementation ONLinkLayerHostAddress
{
    struct sockaddr_dl *linkAddress;
}

- initWithLinkLayerAddress:(const struct sockaddr_dl *)dlAddress
{
    int addrlen;

    if (!(self = [super init]))
        return nil;

    // We get empty link-layer addresses for pseudo-interfaces like the loopback interface and tunnel interfaces, which we might as well ignore. (They do contain a useful interface-index number and interface-type field, but those are extracted earlier by ONInterface.)
    if (dlAddress->sdl_alen == 0 && dlAddress->sdl_slen == 0) {
        [self release];
        return nil;
    }

    addrlen = MAX(dlAddress->sdl_len,
                  (int)( (unsigned char *)(dlAddress->sdl_data) - (unsigned char *)dlAddress ) +
                  dlAddress->sdl_nlen + dlAddress->sdl_alen + dlAddress->sdl_slen);
    linkAddress = malloc(addrlen);
    bcopy(dlAddress, linkAddress, addrlen);
    linkAddress->sdl_len = addrlen;

#if 0
    NSLog(@"<%p> (%@): ift=%d len=%d nlen=%d alen=%d slen=%d",
          self, self,
          linkAddress->sdl_type, linkAddress->sdl_len,
          linkAddress->sdl_nlen, linkAddress->sdl_alen, linkAddress->sdl_slen);
#endif

    return self;
}

- (void)dealloc
{
    if (linkAddress)
        free(linkAddress);
    [super dealloc];
}

- (int)addressFamily
{
    return AF_LINK;
}

- (int)interfaceType
{
    return linkAddress->sdl_type;
}

- (int)index
{
    return linkAddress->sdl_index;
}

- (NSString *)name
{
    if (linkAddress->sdl_nlen > 0)
        return [[[NSString alloc] initWithBytes:linkAddress->sdl_data length:linkAddress->sdl_nlen encoding:NSASCIIStringEncoding] autorelease];
    else
        return nil;
}

- (const void *)_internetAddress
{
    return &(linkAddress->sdl_data[linkAddress->sdl_nlen]);
}

- (unsigned int)_addressLength
{
    return linkAddress->sdl_alen;
}

- (struct sockaddr *)mallocSockaddrWithPort:(unsigned short int)portNumber
{
    void *buf;

    buf = malloc(linkAddress->sdl_len);
    bcopy(linkAddress, buf, linkAddress->sdl_len);

    return buf;
}

- (BOOL) isMulticastAddress;
{
    // We know how to parse Ethernet (IEEE802) addresses. FDDI seems to use the same address format; not 100% sure about that.
    if (linkAddress->sdl_type == IFT_ETHER || linkAddress->sdl_type == IFT_FDDI) {
        unsigned char oct0;
        // The first two address bits transmitted over the wire indicate the type of address. Like most serial protocols, Ethernet is bitwise-little-endian, so these first two bits end up in the least-significant bits of the first octet of the link-layer address.
        oct0 = linkAddress->sdl_data[linkAddress->sdl_nlen];
        
        // oct0 & 0x01:  I/G or "individual/group" bit a.k.a. unicast (0) vs. multicast (1)
        // oct0 & 0x02:  U/L or "universal/local address" bit (0=manufacturer-assigned universal unique address)
        // The next 22 bits of the address are assigned by Xerox or IEEE to a given organization, and the remaining 24 bits are assigned by that organization as they see fit. (May not be true if U/L is set to L.)

        // Return a value based on the I/G bit. Note that this ends up treating broadcast as a kind of multicast, which is reasonable but may differ from how other address families treat broadcast addresses.
        return (oct0 & 0x01)? YES : NO;
    }
    
    return NO;  // actually, maybe it is, but we don't understand this link's address type.
}

- (NSUInteger)hash
{
    NSUInteger hashValue = 0;
    for (int byteIndex = 0; byteIndex < linkAddress->sdl_nlen + linkAddress->sdl_alen + linkAddress->sdl_slen; byteIndex ++)
        hashValue = ( hashValue << 8 ) | ( 0xFF&( ((hashValue & 0xFF000000) >> 24) ^ (linkAddress->sdl_data[byteIndex]) ) );

    return hashValue;
}

- (NSString *)stringValue
{
    NSMutableString *descr;
    int byteIndex;

    descr = [[NSMutableString alloc] initWithCapacity: 3 * (linkAddress->sdl_alen + linkAddress->sdl_slen)];
    [descr autorelease];
    for(byteIndex = 0; byteIndex < linkAddress->sdl_alen + linkAddress->sdl_slen; byteIndex ++) {
        if (byteIndex > 0)
            [descr appendString: ( byteIndex == linkAddress->sdl_alen )? @"/" : @":"];
        [descr appendFormat:@"%02x", ( (unsigned char *)(linkAddress->sdl_data) )[linkAddress->sdl_nlen + byteIndex]];
    }

#if 0
    ifname = [self name];

    if ([descr length] == 0)
        return ifname;
    else if (ifname != nil)
        [descr appendFormat:@"(%@)", ifname];
#endif

    return descr;
}

@end
