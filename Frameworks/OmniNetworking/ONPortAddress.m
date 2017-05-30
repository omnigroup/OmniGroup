// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONPortAddress.h>
#import <OmniNetworking/ONFeatures.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniBase/system.h>

#import <OmniNetworking/ONHost.h>
#import <OmniNetworking/ONHostAddress.h>

RCS_ID("$Id$")

@implementation ONPortAddress
{
    struct sockaddr *portAddress;
}

- initWithHost:(ONHost *)aHost portNumber:(unsigned short int)port;
{
    NSArray *hostAddresses;

    hostAddresses = [aHost addresses];
    if ([hostAddresses count] == 0)
        [NSException raise:ONInternetSocketConnectFailedExceptionName format:NSLocalizedStringFromTableInBundle(@"Unable to create port address: no IP address for host '%@'", @"OmniNetworking", [NSBundle bundleForClass:[ONPortAddress class]], @"error"), [aHost hostname]];
    return [self initWithHostAddress:[hostAddresses objectAtIndex:0] portNumber:port];
}

- initWithHostAddress:(ONHostAddress *)hostAddress portNumber:(unsigned short int)port;
{
    if (!(self = [super init]))
        return nil;

    if (hostAddress == nil)
        hostAddress = [ONHostAddress anyAddress];

    portAddress = [hostAddress mallocSockaddrWithPort:port];
    if (portAddress == NULL) {
        [self release];
        return nil;
    }
        
    return self;
}

- initWithSocketAddress:(const struct sockaddr *)newPortAddress
{
    if (!(self = [super init]))
        return nil;

    portAddress = malloc(newPortAddress->sa_len);
    bcopy(newPortAddress, portAddress, newPortAddress->sa_len);

    return self;
}

- (void)dealloc;
{
    if (portAddress)
        free(portAddress);
    [super dealloc];
}

- (int)addressFamily;
{
    return portAddress->sa_family;
}

- (const struct sockaddr *)portAddress;
{
    return portAddress;
}

- (ONHostAddress *)hostAddress
{
    return [ONHostAddress hostAddressWithSocketAddress:portAddress];
}

- (unsigned short int)portNumber;
{
    switch(portAddress->sa_family) {
        case AF_INET:
            return ntohs(((struct sockaddr_in *)portAddress)->sin_port);
        case AF_INET6:
            return ntohs(((struct sockaddr_in6 *)portAddress)->sin6_port);
        default:
            OBASSERT_NOT_REACHED("Unexpected address family");
            return 0;
    }
}

- (BOOL)isMulticastAddress
{
    // This could be more cleanly implemented as [[self hostAddress] isMulticastAddress], but that ends up creating a few objects, and this method is called from some inner loops. So we do a little encapsulation-breaking.

    if (portAddress->sa_family == AF_INET) {
        return IN_MULTICAST(ntohl(((struct sockaddr_in *)portAddress)->sin_addr.s_addr));
    } else if (portAddress->sa_family == AF_INET6) {
        return IN6_IS_ADDR_MULTICAST(&(((struct sockaddr_in6 *)portAddress)->sin6_addr));
    } else
        return [[self hostAddress] isMulticastAddress];
}

- (NSMutableDictionary *) debugDictionary;
{
    NSMutableDictionary *dict;

    dict = [super debugDictionary];
    [dict setObject: [NSNumber numberWithShort: (portAddress->sa_family)] forKey:@"addressFamily"];
    [dict setObject: [self hostAddress] forKey: @"hostAddress"];
    [dict setObject: [NSNumber numberWithShort:[self portNumber]] forKey: @"portNumber"];

    return dict;
}

- (NSString *)stringValue;
{
    NSString *hostString = [[self hostAddress] stringValue];
    if (hostString != nil)
        return [NSString stringWithFormat:@"%@:%d", hostString, (int)[self portNumber]];
    else
        return nil;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(NSUInteger)level
{
    return [self stringValue];
}

- (NSString *)shortDescription;
{
    return [self stringValue];
}

//
// NSObject methods
//

- (BOOL)isEqual:(id)otherObject;
{
    if (!otherObject)
        return NO;

    if (!OBClassIsSubclassOfClass([otherObject class], [self class]))
        return NO;

    return [self isEqualToSocketAddress:[(ONPortAddress *)otherObject portAddress]];
}

- (BOOL)isEqualToSocketAddress:(const struct sockaddr *)otherPortAddress
{
    if (otherPortAddress->sa_family != portAddress->sa_family ||
        otherPortAddress->sa_len != portAddress->sa_len)
        return NO;

    if (bcmp(portAddress, otherPortAddress, portAddress->sa_len) != 0)
        return NO;

    return YES;
}

//
// NSCoding protocol
//

+ (NSInteger)version
{
    return 3;
}

#define ONEncode(coder, var) [coder encodeValueOfObjCType:@encode(typeof(var)) at:&(var)];
#define ONDecode(coder, var) [coder decodeValueOfObjCType:@encode(typeof(var)) at:&(var)];

- (id)initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super init]))
        return nil;

    if ([coder versionForClassName:@"ONPortAddress"] < 3) {
        struct sockaddr_in *ipv4Address;
        
        ipv4Address = (struct sockaddr_in *)malloc(sizeof(struct sockaddr_in));
        bzero(ipv4Address, sizeof(*ipv4Address));

        ipv4Address->sin_len = sizeof(*ipv4Address);
        ipv4Address->sin_family = AF_INET;

        // These two fields are always stored in network byte order internally, so we don't need to swap them.
        ONDecode(coder, ipv4Address->sin_addr.s_addr);
        ONDecode(coder, ipv4Address->sin_port);

        portAddress = (struct sockaddr *)ipv4Address;
    } else {
        NSData *saddr = [coder decodeDataObject];
        NSUInteger saddrLength = [saddr length];

        portAddress = malloc(saddrLength);
        bcopy([saddr bytes], portAddress, saddrLength);
        OBASSERT((signed)saddrLength > ((void *)&portAddress->sa_len - (void *)portAddress)); // Otherwise the following assertion is looking at a garbage value
        OBASSERT(portAddress->sa_len == saddrLength);
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder;
{
#ifdef OLD_VERSION
    // These two fields are always stored in network byte order internally, so we don't need to swap them.
    ONEncode(coder, portAddress->sin_addr.s_addr);
    ONEncode(coder, portAddress->sin_port);
#else
    [coder encodeDataObject:[NSData dataWithBytes:portAddress length:(portAddress->sa_len)]];
#endif
}

// Make sure we go bycopy or byref as appropriate
- (id)replacementObjectForPortCoder:(NSPortCoder *)encoder;
{
    if ([encoder isByref])
        return [super replacementObjectForPortCoder:encoder]; // NSObject returns an NSDistantObject by default
    else
        return self; // But if we're bycopy, we want to encode/decode our object directly rather than a proxy
}

//
// NSCopying
//

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

@end
