// Copyright 1997-2005, 2007, 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ONHostAddress.h"
#import "ONFeatures.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniBase/system.h>

#if ON_SUPPORT_APPLE_TALK
#import <netat/appletalk.h>
#endif

#import "ONHostAddress-Private.h"
#import "ONInterface.h"
#import "ONLinkLayerHostAddress.h"

RCS_ID("$Id$")

// The 10.5 SDK shows this as being availabe on 10.4, but the 10.4 SDK doesn't list it (presumably this was SPI but then opened up).
#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
enum {
    NSStringEncodingConversionAllowLossy = 1,
    NSStringEncodingConversionExternalRepresentation = 2
};
typedef unsigned NSStringEncodingConversionOptions;
@interface NSString (TigerAPIExposedInLeopard)
- (BOOL)getBytes:(void *)buffer maxLength:(unsigned)maxBufferCount usedLength:(unsigned *)usedBufferCount encoding:(NSStringEncoding)encoding options:(NSStringEncodingConversionOptions)options range:(NSRange)range remainingRange:(NSRangePointer)leftover;
@end
#endif

#define ADDRSTRLEN ((unsigned)MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN))

// Private concrete subclasses.
@interface ONIPv4HostAddress : ONHostAddress
{
    struct in_addr internetAddress;
}

- initWithInternetAddress:(const struct in_addr *)anInternetAddress;

@end

@interface ONIPv6HostAddress : ONHostAddress
{
    struct in6_addr internetAddress;
}

- initWithInternetAddress:(const struct in6_addr *)anInternetAddress;

@end

#if ON_SUPPORT_APPLE_TALK
@interface ONAppleTalkHostAddress : ONHostAddress
{
    struct at_addr appletalkAddress;
}

- initWithInternetAddress:(const struct at_addr *)anAppletalkAddress;

@end
#endif

@implementation ONHostAddress

+ (ONHostAddress *)hostAddressWithInternetAddress:(const void *)anInternetAddress
                                           family:(unsigned char)addressFamily
{
    switch (addressFamily) {
        case AF_INET:
            return [[(ONIPv4HostAddress *)[ONIPv4HostAddress alloc] initWithInternetAddress:anInternetAddress] autorelease];
        case AF_INET6:
            return [[(ONIPv6HostAddress *)[ONIPv6HostAddress alloc] initWithInternetAddress:anInternetAddress] autorelease];
#if ON_SUPPORT_APPLE_TALK
        case AF_APPLETALK:
            return [[(ONAppleTalkHostAddress *)[ONAppleTalkHostAddress alloc] initWithInternetAddress:anInternetAddress] autorelease];
#endif
        case AF_UNSPEC:
            return nil;
        default:
#ifdef DEBUG
            NSLog(@"%@: Unsupported address family %d", self, addressFamily);
#endif
            return nil;
    }
}

+ (ONHostAddress *)addressWithIPv4UnsignedLong:(uint32_t)anAddress;
{
    struct in_addr address;

    bzero(&address, sizeof(address));
    address.s_addr = htonl(anAddress);
    return [self hostAddressWithInternetAddress:&address family:AF_INET];
}

+ (ONHostAddress *)hostAddressWithSocketAddress:(const struct sockaddr *)portAddress;
{
    const void *hostPortion;

    if (portAddress == NULL)
        return nil;
    
    switch(portAddress->sa_family) {
        default:           hostPortion = &(portAddress->sa_data); break;
        case AF_INET:      hostPortion = &(((struct sockaddr_in *)portAddress)->sin_addr); break;
        case AF_INET6:     hostPortion = &(((struct sockaddr_in6 *)portAddress)->sin6_addr); break;
#if ON_SUPPORT_APPLE_TALK
        case AF_APPLETALK: hostPortion = &(((struct sockaddr_at *)portAddress)->sat_addr); break;
#endif
        case AF_LINK:
        {
            ONLinkLayerHostAddress *address = [[ONLinkLayerHostAddress alloc] initWithLinkLayerAddress:(const struct sockaddr_dl *)portAddress];
            [address autorelease];
            return address;
        }
    }

    return [self hostAddressWithInternetAddress:hostPortion family:portAddress->sa_family];
}

/* A quick little charset implementation. This returns true if a character is a hexadecimal digit or an 'x', case-insensitive. Aside from punctuation, these are the only characters allowed in numeric addresses. */
static inline u_int32_t isCharNumeric(unsigned char ch) {
    static const u_int32_t numerics[8] = {0, 0x03ff0000, 0x0100007e, 0x0100007e, 0, 0, 0, 0};
    return numerics[ch / 32] & ((u_int32_t)1 << (ch % 32));
}

+ (ONHostAddress *)hostAddressWithNumericString:(NSString *)addressString
{
    NSRange infoRange, extraRange;
    int charIndex;
    int dotCount, colonCount, doubleDotCount, doubleColonCount;
    BOOL didTrim;

    if (addressString == nil ||
        ![addressString canBeConvertedToEncoding:NSASCIIStringEncoding])
        return nil;

    if ([addressString hasPrefix:@"["] && [addressString hasSuffix:@"]"]) {
        infoRange.location = 1;
        infoRange.length = [addressString length]-2;
        didTrim = YES;
    } else {
        infoRange.location = 0;
        infoRange.length = [addressString length];
        didTrim = NO;
    }

    if (infoRange.length > ADDRSTRLEN)
        return nil; // Too long to be a valid IP address.

    char *asciiBuf = calloc(infoRange.length + 1, 1);
    if (![addressString getBytes:asciiBuf maxLength:infoRange.length usedLength:NULL encoding:NSASCIIStringEncoding options:0 range:infoRange remainingRange:&extraRange]) {
        free(asciiBuf);
        return nil;
    }
    if (extraRange.length > 0) {
        free(asciiBuf);
        return nil;
    }

    // Attempt to characterize the string by looking at its punctuation.
    dotCount = colonCount = doubleDotCount = doubleColonCount = 0;
    for(charIndex = 0; asciiBuf[charIndex] != 0; charIndex ++) {
        unsigned char ch = asciiBuf[charIndex];
        if (ch == ':') {
            colonCount ++;
            if (charIndex > 0 && asciiBuf[charIndex-1] == ':')
                doubleColonCount ++;
        } else if (ch == '.') {
            dotCount ++;
            if (charIndex > 0 && asciiBuf[charIndex-1] == '.')
                doubleDotCount ++;
        } else if (!isCharNumeric(ch)) {
            // Contains a character that's neither numeric nor puctuation. Must not be a numeric address.
            free(asciiBuf);
            return nil;
        }
    }

    // Check for de-bogusified IPv6 addresses (normal syntax with dots instead of colons)
    if (colonCount == 0 && (dotCount == 7 || (dotCount <= 7 && doubleDotCount == 1))) {
        for(charIndex = 0; asciiBuf[charIndex] != 0; charIndex ++) {
            if (asciiBuf[charIndex] == '.')
                asciiBuf[charIndex] = ':';
        }
        colonCount = dotCount;
        doubleColonCount = doubleDotCount;
        dotCount = 0;
        doubleDotCount = 0;
    }

    // Attempt to parse the string as an IPv4 address.
    if (dotCount <= 3 && doubleDotCount == 0 && colonCount == 0) {
        ONHostAddress *ipv4host;

        // Note: inet_pton() is documented not to handle 1-, 2-, or 3-part dotted IPv4 addresses, which we do want to be able to handle for OmniWeb. Also, it appears to incorrectly handle octal values, which we want to support for consistency with inet(3) and occasional practice. So we've written our own address parsing routine, yet again.
        if (didTrim)
            addressString = [NSString stringWithUTF8String:asciiBuf];
        ipv4host = [ONIPv4HostAddress hostAddressWithNumericString:addressString];

        if (ipv4host != nil) {
            free(asciiBuf);
            return ipv4host;
        }
    }

    // Attempt to parse the string as an IPv6 address.
    if (dotCount == 0 && (colonCount == 7 || (colonCount <= 7 && doubleColonCount == 1))) {
        struct in6_addr ipv6addr;

        if (inet_pton(AF_INET6, asciiBuf, &ipv6addr) > 0) {
            free(asciiBuf);
            return [self hostAddressWithInternetAddress:&ipv6addr family:AF_INET6];
        }
    }

#if ON_SUPPORT_APPLE_TALK
    // Attempt to parse the string as an AppleTalk node address.
    if (colonCount == 1 && (dotCount == 0 || dotCount == 1)) {
        ONHostAddress *atalkAddress;
        
        if (didTrim)
            addressString = [NSString stringWithCString:asciiBuf encoding: NSASCIIStringEncoding];
        atalkAddress = [ONAppleTalkHostAddress hostAddressWithNumericString:addressString];
        
        if (atalkAddress) {
            free(asciiBuf);
            return atalkAddress;
        }
    }
#endif
    
    // We haven't been able to parse this address.
    free(asciiBuf);
    return nil;
}

+ (ONHostAddress *)anyAddress;
{
    return [self addressWithIPv4UnsignedLong:INADDR_ANY];
}

+ (ONHostAddress *)loopbackAddress;
{
    return [self addressWithIPv4UnsignedLong:INADDR_LOOPBACK];
}

+ (ONHostAddress *)broadcastAddress;
{
    return [self addressWithIPv4UnsignedLong:INADDR_BROADCAST];
}

- (BOOL)isEqual:anotherObject
{
    if (![anotherObject isKindOfClass:[ONHostAddress class]])
        return NO;
    if ([(ONHostAddress *)anotherObject addressFamily] != [self addressFamily] ||
        [(ONHostAddress *)anotherObject _addressLength] != [self _addressLength])
        return NO;
    if (bcmp([self _internetAddress], [(ONHostAddress *)anotherObject _internetAddress], [self _addressLength]) != 0)
        return NO;

    return YES;
}

- copyWithZone:(NSZone *)aZone
{
    return [self retain];
}

- (int)addressFamily
    { OBRequestConcreteImplementation(self, _cmd); return 0; }

- (BOOL)isMulticastAddress
    { OBRequestConcreteImplementation(self, _cmd); return NO; }

- (BOOL)isLocalInterfaceAddress;
{
    NSArray *interfaces = [ONInterface interfaces];
    NSUInteger interfaceIndex = [interfaces count];
    while (interfaceIndex--) {
        ONInterface *interface = [interfaces objectAtIndex:interfaceIndex];

        if ([[interface addresses] containsObject:self])
            return YES;
    }

    return NO;
}

- (struct sockaddr *)mallocSockaddrWithPort:(unsigned short int)portNumber
    { OBRequestConcreteImplementation(self, _cmd); return NULL; }

- (NSString *)stringValue
{
    char abuf[ADDRSTRLEN+1];
    const char *addrstr;

    bzero(abuf, ADDRSTRLEN+1);
    addrstr = inet_ntop([self addressFamily], [self _internetAddress], abuf, ADDRSTRLEN);
    if (addrstr)
        return [NSString stringWithUTF8String:addrstr];
    else
        return nil;
}

- (NSData *) addressData;
{
    return [NSData dataWithBytes: [self _internetAddress] length: [self _addressLength]];
}

@end

@implementation ONHostAddress (Debugging)

- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(NSUInteger)level
{
    return [self stringValue];
}

- (NSString *)shortDescription;
{
    return [self stringValue];
}

@end

@implementation ONIPv4HostAddress

/* Parses one part of a dotted-quad IP address into its integer value. This routine is fairly picky about what it accepts as an integer, because we don't want to accidentally parse a domain name as a dotted-quad address. */
static u_int32_t parseIpaddrPart(NSString *str, int *ok)
{
    unichar ch;
    NSUInteger strLength;
    int strBase;
    const char *buf, *endp;
    unsigned long parsedPart;
    
    strLength = [str length];
    if (strLength == 0) {
        *ok = 0;
        return 0;
    }

    /* A part can be decimal, octal with a leading 0, or hexadecimal with a leading 0x or 0X. Figure out which one this is. */

    ch = [str characterAtIndex:0];
    if (ch == '0') {
        if (strLength == 1)
            return 0; /* A valid representation of zero. */
        else {
            ch = [str characterAtIndex:1];
            if (ch == 'x' || ch == 'X') {
                strBase = 16; /* parse as hexadecimal */
            } else {
                strBase = 8; /* parse as octal */
            }
        }
    } else if (ch >= '0' && ch <= '9') {
        strBase = 10; /* parse as decimal */
    } else {
        /* Starts with a non-digit. Strtoul() might accept this, but we don't want to. */
        *ok = 0;
        return 0;
    }

    /* Okay, now that we've decided what base this number must be in, we can parse it. */

    buf = [str UTF8String];
    endp = NULL;
    parsedPart = strtoul(buf, (char **)&endp, strBase);
    if (*endp != (char)0) {
        /* String had trailing garbage --- reject it. */
        *ok = 0;
        return 0;
    }
    
    if (parsedPart > 0xFFFFFFFFUL) {
        /* Number simply isn't plausible --- reject it. */
        *ok = 0;
        return 0;
    }

    return (u_int32_t)parsedPart;
}

+ (ONHostAddress *)hostAddressWithNumericString:(NSString *)addressString;
{
    NSArray *parts;
    NSUInteger partsCount, partIndex;
    u_int32_t ipaddr;
    int isOK;

    parts = [addressString componentsSeparatedByString:@"."];
    partsCount = [parts count];
    if (partsCount > 4 || partsCount < 1)
        return nil;
    
    /* This algorithm follows the description in the inet(3) man page, which describes the inet_aton() functions, etc. Only the 4-part and 1-part variations are very common, and the 1-part variation is mostly used by spammers... */

    ipaddr = 0;
    isOK = 1;
    for(partIndex = 0; partIndex < partsCount; partIndex ++) {
        u_int32_t part = parseIpaddrPart([parts objectAtIndex:partIndex], &isOK);
        if (!isOK)
            return nil;
        // All but the last part get shifted up to the network-address end. If there are fewer than four parts, the last part is expected to be wider than 8 bits.
        if (partIndex+1 < partsCount)
            part <<= (8 * (3 - partIndex));
        ipaddr |= part;
    }

    return [ONHostAddress addressWithIPv4UnsignedLong:ipaddr];
}

- initWithInternetAddress:(const struct in_addr *)anInternetAddress;
{
    if (!(self = [self init]))
        return nil;

    if (!anInternetAddress) {
        [self release];
        return nil;
    }

    internetAddress = *anInternetAddress;

    return self;
}

- (int)addressFamily
{
    return AF_INET;
}

- (const void *)_internetAddress
{
    return &internetAddress;
}

- (unsigned int)_addressLength
{
    return sizeof(struct in_addr);
}

- (struct sockaddr *)mallocSockaddrWithPort:(unsigned short int)portNumber
{
    struct sockaddr_in *addr;

    addr = malloc(sizeof(struct sockaddr_in));
    bzero(addr, sizeof(*addr));

    addr->sin_len = sizeof(*addr);
    addr->sin_family = AF_INET;
    addr->sin_addr = internetAddress;
    addr->sin_port = htons(portNumber);

    return (struct sockaddr *)addr;
}

- (BOOL) isMulticastAddress;
{
    // inet_addr() returns addresses in host byte order (as documented in man 3 inet)
    // and this macro expects them in host byte order.
    return IN_MULTICAST(ntohl(internetAddress.s_addr));
}

- (NSUInteger)hash
{
    return (NSUInteger)(internetAddress.s_addr);
}

@end

@implementation ONIPv6HostAddress

- initWithInternetAddress:(const struct in6_addr *)anInternetAddress;
{
    if (!(self = [self init]))
        return nil;

    if (!anInternetAddress) {
        [self release];
        return nil;
    }

    bcopy(anInternetAddress, &internetAddress, sizeof(internetAddress));

    return self;
}

- (int)addressFamily
{
    return AF_INET6;
}

- (const void *)_internetAddress
{
    return &internetAddress;
}

- (unsigned int)_addressLength
{
    return sizeof(struct in6_addr);
}

- (struct sockaddr *)mallocSockaddrWithPort:(unsigned short int)portNumber
{
    struct sockaddr_in6 *addr;

    addr = malloc(sizeof(struct sockaddr_in6));
    bzero(addr, sizeof(*addr));

    addr->sin6_len = sizeof(*addr);
    addr->sin6_family = AF_INET6;
    addr->sin6_addr = internetAddress;
    addr->sin6_port = htons(portNumber);

    return (struct sockaddr *)addr;
}

- (BOOL)isMulticastAddress;
{
    return IN6_IS_ADDR_MULTICAST(&internetAddress);
}

- (NSUInteger)hash
{
    NSUInteger hashValue;

    hashValue  = (internetAddress.s6_addr[ 0] << 24  |  internetAddress.s6_addr[ 1] << 16  | internetAddress.s6_addr[ 2] << 8  | internetAddress.s6_addr[ 3]);
    hashValue ^= (internetAddress.s6_addr[ 4] << 24  |  internetAddress.s6_addr[ 5] << 16  | internetAddress.s6_addr[ 6] << 8  | internetAddress.s6_addr[ 7]);
    hashValue ^= (internetAddress.s6_addr[ 8] << 24  |  internetAddress.s6_addr[ 9] << 16  | internetAddress.s6_addr[10] << 8  | internetAddress.s6_addr[11]);
    hashValue ^= (internetAddress.s6_addr[12] << 24  |  internetAddress.s6_addr[13] << 16  | internetAddress.s6_addr[14] << 8  | internetAddress.s6_addr[15]);

    return hashValue;
}

@end

#if ON_SUPPORT_APPLE_TALK
@implementation ONAppleTalkHostAddress

+ (ONHostAddress *)hostAddressWithNumericString:(NSString *)addressString
{
    NSScanner *scan;
    struct at_addr atalkAddress;
    int netPart, hostPart;

    scan = [[NSScanner alloc] initWithString:addressString];
    if (![scan scanInt:&netPart])
        goto scanFailure;
    if ([scan scanString:@"." intoString:NULL]) {
        int lowNetPart;
        if (![scan scanInt:&lowNetPart])
            goto scanFailure;
        netPart = (netPart * 256) + lowNetPart;
    }
    if (![scan scanString:@":" intoString:NULL])
        goto scanFailure;
    if (![scan scanInt:&hostPart])
        goto scanFailure;
    if (![scan isAtEnd])
        goto scanFailure;

    [scan release];

    /* We've scanned a syntactically valid appletalk address. */
    if (netPart < 0 || netPart > 65536 || hostPart < 0 || hostPart > 255)
        return nil; /* but not a semantically valid one. */

    bzero(&atalkAddress, sizeof(atalkAddress));
    atalkAddress.s_net = htons(netPart);
    atalkAddress.s_node = hostPart;
    return [ONHostAddress hostAddressWithInternetAddress:&atalkAddress family:AF_APPLETALK];

scanFailure:
    [scan release];
    return nil;
}

- initWithInternetAddress:(const struct at_addr *)anAppletalkAddress;
{
    if (![self init])
        return nil;

    if (!anAppletalkAddress) {
        [self release];
        return nil;
    }

    bcopy(anAppletalkAddress, &appletalkAddress, sizeof(appletalkAddress));

    return self;
}

- (int)addressFamily
{
    return AF_APPLETALK;
}

- (const void *)_internetAddress
{
    return &appletalkAddress;
}

- (unsigned int)_addressLength
{
    return sizeof(struct at_addr);
}

- (struct sockaddr *)mallocSockaddrWithPort:(unsigned short int)portNumber
{
    struct sockaddr_at *sat;

    /* AppleTalk "socket numbers" (the equivalent of a TCP or UDP port number) are only 8 bits wide */
    if (portNumber > 255)
        return NULL;

    sat = malloc(sizeof(struct sockaddr_at));
    bzero(sat, sizeof(*sat));

    sat->sat_len = sizeof(*sat);
    sat->sat_family = AF_APPLETALK;
    sat->sat_port = portNumber;
    bcopy(&appletalkAddress, &(sat->sat_addr), sizeof(sat->sat_addr));

    return (struct sockaddr *)sat;
}

- (BOOL)isMulticastAddress;
{
    return ( appletalkAddress.s_node == ATADDR_BCASTNODE ) ? YES : NO;
}

- (NSUInteger)hash
{
    return ( appletalkAddress.s_node ) | ( (NSUInteger)(appletalkAddress.s_net) << 8 );;
}

- (NSString *)stringValue
{
    return [NSString stringWithFormat:@"%d:%d", (int)ntohs(appletalkAddress.s_net), appletalkAddress.s_node];
}

@end
#endif // ON_SUPPORT_APPLE_TALK
