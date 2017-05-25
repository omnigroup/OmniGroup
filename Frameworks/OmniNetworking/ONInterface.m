// Copyright 1999-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONInterface.h>

#import <OmniNetworking/ONHostAddress.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>

#import <sys/ioctl.h>
#import <sys/socket.h>
#import <sys/sockio.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <net/if_types.h>
#import <netinet/in.h>

#import <arpa/inet.h>         // for inet_ntoa()
#import <net/if_dl.h>         // for 'struct sockaddr_dl'
#import <netinet/if_ether.h>  // for ETHERMTU

RCS_ID("$Id$")

static NSArray *interfaces = nil;

static ONHostAddress *firstAddressOfFamily(NSArray *addresses, int desiredFamily);

@implementation ONInterface
{
    NSString *name;
    NSArray *interfaceAddresses;
    /* Not sure if this is the right way to represent this. Possibly "destinationAddresses" should be an array instead of a dictionary. Possibly these dictionaries need to be able to represent multiple values for a key. */
    NSDictionary *destinationAddresses; // for point-to-point links
    NSDictionary *broadcastAddresses;   // for shared-medium links, e.g. ethernet
    NSDictionary *netmaskAddresses;
    
    ONInterfaceCategory interfaceCategory;
    int interfaceType;
    unsigned int maximumTransmissionUnit;
    unsigned int flags;
    unsigned int index;
}

static const struct { int ift; ONInterfaceCategory cat; } interfaceClassification[] = {
    { IFT_ETHER,   ONEtherInterfaceCategory },
    { IFT_PPP,     ONPPPInterfaceCategory },
    { IFT_SLIP,    ONPPPInterfaceCategory },
    { IFT_LOOP,    ONLoopbackInterfaceCategory },
    { IFT_FDDI,    ONEtherInterfaceCategory },
    { IFT_L2VLAN,  ONEtherInterfaceCategory },  /* is 802.1Q more like a tunnel, or ethernet? more like an ethernet, I think */
    { IFT_GIF,     ONTunnelInterfaceCategory },
    { IFT_STF,     ONTunnelInterfaceCategory },
    { IFT_FAITH,   ONTunnelInterfaceCategory },

    /* TODO: IFT_LOCALTALK, IFT_IEEE1394 ? */
    { IFT_IEEE1394, ONEtherInterfaceCategory },

    { -1,          ONUnknownInterfaceCategory }
    
};

#define ONUnknownMTU (~(unsigned int)0)

- (id)_initFromIfaddrs:(struct ifaddrs *)info
{
    struct ifaddrs *ifp;
    NSMutableArray *ifAddresses;
    NSMutableDictionary *maskAddresses, *remoteAddresses;
    
    if (!(self = [super init]))
        return nil;

    name = [[NSString alloc] initWithBytes:info->ifa_name length:strlen(info->ifa_name) encoding:NSASCIIStringEncoding];
    flags = info->ifa_flags;
    maximumTransmissionUnit = 0;
    interfaceCategory = ONUnknownInterfaceCategory;
    interfaceType = IFT_OTHER;
    index = 0;

    ifAddresses = [[NSMutableArray alloc] init];
    maskAddresses = [[NSMutableDictionary alloc] init];
    remoteAddresses = [[NSMutableDictionary alloc] init];

    for(ifp = info; ifp != NULL; ifp = ifp->ifa_next) {
        ONHostAddress *ifAddress, *maskAddress, *remoteAddress;
    
        // Ignore entries for other interfaces
        if (strcmp(ifp->ifa_name, info->ifa_name) != 0)
            continue;

        // Some link-layer interface information is stashed in the link address structure
        if (ifp->ifa_addr != NULL && ifp->ifa_addr->sa_family == AF_LINK) {
            struct sockaddr_dl *dlp = (struct sockaddr_dl *)(ifp->ifa_addr);
            int catIndex;

            index = dlp->sdl_index;
            interfaceType = dlp->sdl_type;

            catIndex = 0;
            while(interfaceClassification[catIndex].ift != interfaceType &&
                  interfaceClassification[catIndex].ift != -1)
                catIndex ++;
            interfaceCategory = interfaceClassification[catIndex].cat;
        }

        // Copy out the addresses from the ifaddrs structure. Note that the header actually defines ifa_dstaddr to be the same field as ifa_broadaddr right now, so there's really no chance that we're losing information by only retrieving one of them.
        ifAddress = [ONHostAddress hostAddressWithSocketAddress:ifp->ifa_addr];
        maskAddress = [ONHostAddress hostAddressWithSocketAddress:ifp->ifa_netmask];
        remoteAddress = [ONHostAddress hostAddressWithSocketAddress:(flags & IFF_POINTOPOINT)? ifp->ifa_dstaddr : ifp->ifa_broadaddr];

        if (ifAddress != nil) {
            [ifAddresses addObject:ifAddress];
            if (maskAddress != nil)
                [maskAddresses setObject:maskAddress forKey:ifAddress];
            if (remoteAddress != nil)
                [remoteAddresses setObject:remoteAddress forKey:ifAddress];
        }
    }

    interfaceAddresses = [ifAddresses copy];
    [ifAddresses release];

    if ([maskAddresses count] > 0)
        netmaskAddresses = [maskAddresses copy];
    [maskAddresses release];

    if ([remoteAddresses count] > 0) {
        if (flags & IFF_POINTOPOINT)
            destinationAddresses = [remoteAddresses copy];
        else
            broadcastAddresses = [remoteAddresses copy];
    }
    [remoteAddresses release];

    return self;
}

+ (NSArray *)getInterfaces:(BOOL)rescan
{
    int oserr;
    struct ifaddrs *ifs, *ifptr, *ifcursor;
    NSMutableArray *newInterfaces;

    if (interfaces != nil) {
        if (rescan) {
            [interfaces release];
            interfaces = nil;
        } else {
            return interfaces;
        }
    }
    
    ifs = NULL;
    oserr = getifaddrs(&ifs);
    if (oserr != 0) {
        [NSException raise:NSGenericException posixErrorNumber:OMNI_ERRNO() format:@"Unable to retrieve list of network interfaces: getifaddrs: %s", strerror(OMNI_ERRNO())];
    }

    /* Scan through the list of struct ifaddrs, creating a set of ONInterface objects. A given interface may appear in the list more than once if it supports multiple address families. (Physical interfaces will support at least two address families: their link-level address and a protocol family such as AF_INET). But we only want to create one ONInterface for each actual interface. */

    newInterfaces = [NSMutableArray array];
    for(ifcursor = ifs; ifcursor != NULL; ifcursor = ifcursor->ifa_next) {
        BOOL duplicate;
        ONInterface *anInterface;

        /* Check whether we've already seen (and created) an interface by this name. */
        duplicate = NO;
        for(ifptr = ifs; ifptr != ifcursor && ifptr != NULL; ifptr = ifptr->ifa_next) {
            if (strcmp(ifcursor->ifa_name, ifptr->ifa_name) == 0) {
                duplicate = YES;
                break;
            }
        }

        if (!duplicate) {
            anInterface = [[ONInterface alloc] _initFromIfaddrs:ifcursor];
            [newInterfaces addObject:anInterface];
            [anInterface release];
        }
    }

    freeifaddrs(ifs);

    if (!interfaces)
        interfaces = [newInterfaces retain];

    return newInterfaces;
}

+ (NSArray *)interfaces
{
    return [self getInterfaces:NO];
}

- (NSString *)name;
{
    return name;
}

- (ONHostAddress *)interfaceAddress;
{
    return firstAddressOfFamily(interfaceAddresses, AF_INET);
}

- (NSArray *)addresses;
{
    return interfaceAddresses;
}

- (ONHostAddress *)destinationAddressForAddress:(ONHostAddress *)localAddress
{
    return [destinationAddresses objectForKey:localAddress];
}

- (ONHostAddress *)broadcastAddressForAddress:(ONHostAddress *)localAddress;
{
    return [broadcastAddresses objectForKey:localAddress];
}

- (ONHostAddress *)netmaskAddressForAddress:(ONHostAddress *)localAddress;
{
    return [netmaskAddresses objectForKey:localAddress];
}

- (ONHostAddress *)linkLayerAddress;
{
    return firstAddressOfFamily(interfaceAddresses, AF_LINK);
}

- (ONInterfaceCategory)interfaceCategory;
{
    return interfaceCategory;
}

- (int)interfaceType;
{
    return interfaceType;
}

- (int)index
{
    return index;
}

- (unsigned int)maximumTransmissionUnit;
{
    if (!maximumTransmissionUnit) {
        int fd;
        struct ifreq ifr;

        bzero(&ifr, sizeof(ifr));
        [name getCString:ifr.ifr_name maxLength:sizeof(ifr.ifr_name) encoding:NSASCIIStringEncoding];

        // To get an interface's MTU, we need to use the old stinky ioctl interface.
        // TODO [wiml]: What protocol family should we use for the socket? Does it even matter? PF_LINK is an obvious choice, but results in a "not supported" error when creating the socket. PF_INET, PF_INET6, PF_LOCAL and PF_SYSTEM are the ones that work. They all return the same MTU in my tests, even for unconfigured interfaces like gif0 or stf0. So I'm assuming it doesn't matter.
        fd = socket(PF_INET, SOCK_DGRAM, 0);
        if (fd < 0)
            [NSException raise:NSGenericException posixErrorNumber:OMNI_ERRNO() format:@"-[%@ %@]: socket(PF_INET): %s", OBShortObjectDescription(self), NSStringFromSelector(_cmd), strerror(OMNI_ERRNO())];
        if (ioctl(fd, SIOCGIFMTU, &ifr) < 0) {
            // Signal that we tried to retrieve this and failed. See below for our fallback numbers.
            maximumTransmissionUnit = ONUnknownMTU;
            NSLog(@"%@: Cannot get MTU of %@: SIOCGIFMTU: %s", [self class], name, strerror(OMNI_ERRNO()));
        } else {
            maximumTransmissionUnit = ifr.ifr_mtu;
            OBASSERT(maximumTransmissionUnit != 0);
        }
        close(fd);
    }

    if (maximumTransmissionUnit == ONUnknownMTU) {
        // Fallback to hardcoded MTUs.
        switch(interfaceCategory) {
#ifdef ETHERMTU
            case ONEtherInterfaceCategory:
            case ONLoopbackInterfaceCategory:
                return ETHERMTU;
#endif
#ifdef FDDIMTU
            case ONFDDIInterfaceCategory:
                return FDDIMTU;
#endif
            default:
                [NSException raise:NSGenericException format:@"-[%@ %@] -- Unable to get interface MTU for %@", [self class], NSStringFromSelector(_cmd), name];
        }
    }

    return maximumTransmissionUnit;
}


- (BOOL)isUp;
{
    return (flags & IFF_UP) != 0;
}

- (BOOL)supportsBroadcast;
{
    return (flags & IFF_BROADCAST) != 0;
}

- (BOOL)isLoopback;
{
    return (flags & IFF_LOOPBACK) != 0;
}

- (BOOL)isPointToPoint;
{
    return (flags & IFF_POINTOPOINT) != 0;
}

- (BOOL)supportsAddressResolutionProtocol;
{
    return (flags & IFF_NOARP) == 0;
}

- (BOOL)supportsPromiscuousMode;
{
    return (flags & IFF_PROMISC) != 0;
}

- (BOOL)isSimplex;
{
    return (flags & IFF_SIMPLEX) != 0;
}

- (BOOL)supportsMulticast;
{
    return (flags & IFF_MULTICAST) != 0;
}

// Debugging

static const struct { ONInterfaceCategory tp; const char *descr; } interfaceNames[] = {
    { ONEtherInterfaceCategory, "ether" },
    { ONPPPInterfaceCategory, "ppp" },
    { ONTunnelInterfaceCategory, "tunnel" },
    { ONLoopbackInterfaceCategory, "loopback" },
    { ONUnknownInterfaceCategory, "unknown" }
};

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;
    NSMutableArray *flagArray;
    int interfaceNameIndex;
    
    debugDictionary = [super debugDictionary];
    if (name)
        [debugDictionary setObject:name forKey:@"name"];
    if (interfaceAddresses)
        [debugDictionary setObject:interfaceAddresses forKey:@"interfaceAddresses"];
    if (destinationAddresses)
        [debugDictionary setObject:destinationAddresses forKey:@"destinationAddresses"];
    if (broadcastAddresses)
        [debugDictionary setObject:broadcastAddresses forKey:@"broadcastAddresses"];
    if (netmaskAddresses)
        [debugDictionary setObject:netmaskAddresses forKey:@"netmaskAddresses"];

    interfaceNameIndex = 0;
    while(interfaceNames[interfaceNameIndex].tp != interfaceCategory &&
          interfaceNames[interfaceNameIndex].tp != ONUnknownInterfaceCategory)
        interfaceNameIndex ++;
    [debugDictionary setObject:[NSString stringWithUTF8String:interfaceNames[interfaceNameIndex].descr] forKey:@"interfaceCategory"];

    [debugDictionary setObject:[NSNumber numberWithInt:interfaceType] forKey:@"interfaceType"];
    
    if (maximumTransmissionUnit == ONUnknownMTU)
        [debugDictionary setObject:@"(unknown)" forKey:@"maximumTransmissionUnit"];
    else if (maximumTransmissionUnit == 0)
        [debugDictionary setObject:@"(not retrieved)" forKey:@"maximumTransmissionUnit"];
    else
        [debugDictionary setObject:[NSNumber numberWithUnsignedInt:maximumTransmissionUnit] forKey:@"maximumTransmissionUnit"];

    flagArray = [NSMutableArray array];
    if ([self isUp])
        [flagArray addObject:@"UP"];
    if ([self supportsBroadcast])
        [flagArray addObject:@"BROADCAST"];
    if ([self isLoopback])
        [flagArray addObject:@"LOOPBACK"];
    if ([self isPointToPoint])
        [flagArray addObject:@"POINTOPOINT"];
    if ([self supportsAddressResolutionProtocol])
        [flagArray addObject:@"ARP"];
    if ([self supportsPromiscuousMode])
        [flagArray addObject:@"PROMISC"];
    if ([self isSimplex])
        [flagArray addObject:@"SIMPLEX"];
    if ([self supportsMulticast])
        [flagArray addObject:@"MULTICAST"];
    [debugDictionary setObject:flagArray forKey:@"flags"];
    
    return debugDictionary;
}

@end

static ONHostAddress *firstAddressOfFamily(NSArray *addresses, int desiredFamily)
{
    NSUInteger addressCount, addressIndex;

    addressCount = [addresses count];
    for(addressIndex = 0; addressIndex < addressCount; addressIndex ++) {
        ONHostAddress *anAddress = [addresses objectAtIndex:addressIndex];
        if ([anAddress addressFamily] == desiredFamily)
            return anAddress;
    }

    return nil;
}

