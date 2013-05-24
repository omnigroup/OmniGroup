// Copyright 2003-2005, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniNetworking/ONHostAddress.h>
#import <OmniNetworking/ONFeatures.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <SenTestingKit/SenTestingKit.h>

#include <sys/socket.h>
#include <netinet/in.h>

RCS_ID("$Id$");

@interface ONHostAddressTests : SenTestCase
{
}

@end

@implementation ONHostAddressTests

- (void)testV4Parsing
{
    ONHostAddress *loopback, *examplecom, *bcast;

    loopback = [ONHostAddress addressWithIPv4UnsignedLong:0x7f000001];
    examplecom = [ONHostAddress addressWithIPv4UnsignedLong:0xC00022A6];
    bcast = [ONHostAddress broadcastAddress];

    shouldnt([loopback isEqual:examplecom]);
    shouldnt([loopback isEqual:bcast]);
    shouldnt([bcast isEqual:examplecom]);

    shouldBeEqual([loopback stringValue], @"127.0.0.1");
    shouldBeEqual([examplecom stringValue], @"192.0.34.166");
    shouldBeEqual([bcast stringValue], @"255.255.255.255");

    /* Here we test various combinations of "dotted-quad" representation. It's valid to combine bytes from the host end of the address into larger quantities (up to and including representing the entire address as a single integer), and it's valid to represent each part in decimal, octal, or hex, using C-style notation to distinguish between these. */

    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"127.0.0.1"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"[127.0.0.1]"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"127.1"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"127.0.1"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"0x7f.0.0.1"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"0177.0.0.1"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"0X7F.000.0x000.001"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"0x7f000001"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"[0x7f000001]"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"[017700000001]"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"2130706433"]);

    shouldBeEqual(examplecom, [ONHostAddress hostAddressWithNumericString:@"192.0.34.166"]);
    shouldBeEqual(examplecom, [ONHostAddress hostAddressWithNumericString:@"[0300.0.042.0246]"]);
    shouldBeEqual(examplecom, [ONHostAddress hostAddressWithNumericString:@"030000021246"]);
    shouldBeEqual(examplecom, [ONHostAddress hostAddressWithNumericString:@"3221234342"]);

    shouldBeEqual(bcast, [ONHostAddress hostAddressWithNumericString:@"255.255.255.255"]);
    shouldBeEqual(bcast, [ONHostAddress hostAddressWithNumericString:@"0xFF.0xFF.0xFFFF"]);
    shouldBeEqual(bcast, [ONHostAddress hostAddressWithNumericString:@"0xFFFFFFFF"]);
    shouldBeEqual(bcast, [ONHostAddress hostAddressWithNumericString:@"037777777777"]);
    shouldBeEqual(bcast, [ONHostAddress hostAddressWithNumericString:@"4294967295"]);

    shouldBeEqual(nil, [ONHostAddress hostAddressWithNumericString:@" "]);
    shouldBeEqual(nil, [ONHostAddress hostAddressWithNumericString:@"cafe.babe"]);
    shouldBeEqual(nil, [ONHostAddress hostAddressWithNumericString:@"this.is.a.test"]);
    shouldBeEqual(nil, [ONHostAddress hostAddressWithNumericString:@"128.95.-6.3"]);
    shouldBeEqual(nil, [ONHostAddress hostAddressWithNumericString:@"0x7f.0.0.7fx0"]);
}

- (void)testV6Parsing
{
    const unsigned char someMacBytes[16] = {0xfe, 128, 0, 0, 0, 0, 0, 0, 2, 3, 0x93, 255, 254, 0x8e, 0x4e, 0x3c};
    const unsigned char someV4encBytes[16] = {32, 2, 216, 39, 137, 58, 1, 1, 0, 0, 0, 0x50, 0xBA, 8, 13, 0x61};
    ONHostAddress *loopback, *localHost, *localNodes, *localRouters;
    ONHostAddress *someMac, *someV4enc;
    struct sockaddr_in6 sin6, *sin6p;

    loopback = [ONHostAddress hostAddressWithInternetAddress:&in6addr_loopback family:AF_INET6];
    localHost = [ONHostAddress hostAddressWithInternetAddress:&in6addr_nodelocal_allnodes family:AF_INET6];
    localNodes = [ONHostAddress hostAddressWithInternetAddress:&in6addr_linklocal_allnodes family:AF_INET6];
    localRouters = [ONHostAddress hostAddressWithInternetAddress:&in6addr_linklocal_allrouters family:AF_INET6];

    shouldnt([loopback isEqual:localHost]);
    shouldnt([localHost isEqual:localNodes]);
    shouldnt([localNodes isEqual:localRouters]);
    shouldnt([localRouters isEqual:loopback]);
    shouldnt([loopback isEqual:localNodes]);
    shouldnt([localHost isEqual:localRouters]);

    shouldnt([loopback isEqual:[ONHostAddress loopbackAddress]]); /* IPv4 loopback isn't the same as IPv6 loopback */

    /* IPv6 addresses don't have quite the same number of variations as IPv4 addresses (for this we are thankful). But we still have the ability to elide strings for 0s, and we have case-insensitive hexadecimal to test, plus the dots-instead-of-colons notation. */

    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"::1"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"0::1"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"[0:0::0:1]"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"..1"]);
    shouldBeEqual(loopback, [ONHostAddress hostAddressWithNumericString:@"0000:0000:0000:0000:0000:0000:0000:0001"]);
    shouldBeEqual([loopback stringValue], @"::1");

    sin6p = (struct sockaddr_in6 *)[loopback mallocSockaddrWithPort:32769];
    should(bcmp(&(sin6p->sin6_addr), &in6addr_loopback, sizeof(sin6p->sin6_addr)) == 0);
    free(sin6p);

    shouldBeEqual(localHost, [ONHostAddress hostAddressWithNumericString:@"[Ff01::1]"]);
    shouldBeEqual(localHost, [ONHostAddress hostAddressWithNumericString:@"FF01:0000::0001"]);
    shouldBeEqual(localHost, [ONHostAddress hostAddressWithNumericString:@"[fF01::0000:0001]"]);
    shouldBeEqual(localHost, [ONHostAddress hostAddressWithNumericString:@"[ff01..0000.1]"]);
    shouldBeEqual(nil, [ONHostAddress hostAddressWithNumericString:@"[fF01::0x0000:0x1]"]);
    shouldBeEqual([localHost stringValue], @"ff01::1");

    shouldBeEqual(localNodes, [ONHostAddress hostAddressWithNumericString:@"ff02::1"]);
    shouldBeEqual(localNodes, [ONHostAddress hostAddressWithNumericString:@"[ff02:0000:000:00:0:00:000:0001]"]);
    shouldBeEqual([localNodes stringValue], @"ff02::1");

    shouldBeEqual(localRouters, [ONHostAddress hostAddressWithNumericString:@"ff02::2"]);
    shouldBeEqual([localRouters stringValue], @"ff02::2");

    someMac = [ONHostAddress hostAddressWithNumericString:@"[fe80::203:93ff:fe8e:4e3c]"];
    should([someMac addressFamily] == AF_INET6);
    shouldBeEqual(someMac, [ONHostAddress hostAddressWithInternetAddress:(const void *)someMacBytes family:AF_INET6]);
    shouldBeEqual([someMac stringValue], @"fe80::203:93ff:fe8e:4e3c");
    
    sin6p = (struct sockaddr_in6 *)[someMac mallocSockaddrWithPort:909];
    should(ntohs(sin6p->sin6_port) == 909);
    should(bcmp(&(sin6p->sin6_addr), (const void *)someMacBytes, sizeof(sin6p->sin6_addr)) == 0);
    free(sin6p);
    
    bzero(&sin6, sizeof(sin6));
    sin6.sin6_len = sizeof(sin6);
    sin6.sin6_family = AF_INET6;
    sin6.sin6_port = htons(4243);
    bcopy((const void *)someV4encBytes, (void *)&(sin6.sin6_addr), sizeof(sin6.sin6_addr));
    someV4enc = [ONHostAddress hostAddressWithSocketAddress:(void *)&sin6];
    shouldBeEqual([someV4enc stringValue], @"2002:d827:893a:101::50:ba08:d61");
    shouldBeEqual(someV4enc, [ONHostAddress hostAddressWithNumericString:@"2002:D827:893A:101:0000:0050:ba08:0D61"]);
    shouldBeEqual(someV4enc, [ONHostAddress hostAddressWithNumericString:@"2002.d827.893a.101..50.ba08.d61"]);
    shouldBeEqual(someV4enc, [ONHostAddress hostAddressWithNumericString:@"2002.d827.893a.101.0.50.ba08.d61"]);
    
    shouldBeEqual(nil, [ONHostAddress hostAddressWithNumericString:@"2002.d827.893a.101.50.ba08.d61"]);
    shouldBeEqual(nil, [ONHostAddress hostAddressWithNumericString:@"2002.d827.893a.101.0..50.ba08.d61"]);
}

@end

