// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONMulticastSocket.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniBase/system.h>

#import "ONInternetSocket-Private.h"
#import <OmniNetworking/ONHostAddress.h>
#import "ONHostAddress-Private.h"
#import <OmniNetworking/ONPortAddress.h>


RCS_ID("$Id$")

#define ONMCAST_OPT_USE_DEFAULT 2

@implementation ONMulticastSocket
{
    int mcastTTL;  // Requested TTL for multicast packets, or -1 if not specified by caller
    struct {
        unsigned int shouldLoop: 2;
    } mcastFlags;
}

+ (unsigned int)maximumGroupMemberships;
{
#if defined(IP_MAX_MEMBERSHIPS)
    return IP_MAX_MEMBERSHIPS;
#else
    return INT_MAX; // Seems this limitation does not exist in Solaris 2.6
#endif
}

- (void)setSendTimeToLive:(unsigned char)ttl;
{
    int result;
    
    mcastTTL = ttl;
    
    if (socketFD == -1)
        return;

    switch([self addressFamily]) {
        case AF_INET6:
            result = setsockopt(socketFD, IPPROTO_IPV6, IPV6_MULTICAST_HOPS, (char *)&ttl, sizeof(ttl));
            break;
        case AF_INET:
            result = setsockopt(socketFD, IPPROTO_IP, IP_MULTICAST_TTL, (char *)&ttl, sizeof(ttl));
            break;
        default:
            /* Don't know how to deal with multicast in other families --- probably doesn't make sense */
            result = -1;
            break;
    }
    
    if (result == -1)
        [NSException raise:ONMulticastSocketSetTimeToLiveFailed format:@"Failed to set time to live to %d on socket %@", ttl, self];
}

- (void)joinReceiveGroup:(ONHostAddress *)groupAddress localInterface:(ONInterface *)localInterface;
{
    [self _changeGroupMembership:groupAddress localInterface:localInterface add:YES];
}

- (void)leaveReceiveGroup:(ONHostAddress *)groupAddress localInterface:(ONInterface *)localInterface;
{
    [self _changeGroupMembership:groupAddress localInterface:localInterface add:NO];
}

- (void)joinReceiveGroup:(ONHostAddress *)groupAddress;
{
    [self joinReceiveGroup:groupAddress localInterface:nil];
}

- (void)leaveReceiveGroup:(ONHostAddress *)groupAddress;
{
    [self leaveReceiveGroup:groupAddress localInterface:nil];
}

// Wim 8April2003: This needs to be rewritten to handle the possibility of v6 addresses; see the implementation of _changeGroupMembership:localInterface:add: or setSendTimeToLive: for an example.
#if 0
// This is untested since I don't actually have a machine with multiple interfaces yet
- (void)setSendMulticastInterface:(ONHostAddress *)interfaceAddress;
{
    struct in_addr address;

    if (interfaceAddress) {
        address = *[interfaceAddress _internetAddress];
    } else
        // Use the default interface
        address.s_addr = INADDR_ANY;

    if (setsockopt(socketFD, [isa ipProtocol], IP_MULTICAST_IF, (char *)&address, sizeof(address)) == -1)
        [NSException raise:ONMulticastSocketSendInterfaceSelectionFailed format:@"Failed to set interface to %@ socket %@", interfaceAddress, self];
}
#endif

- (void)setShouldLoopMessagesToMemberGroups:(BOOL)shouldLoopMessages;
{
    int result;

    mcastFlags.shouldLoop = shouldLoopMessages? 1 : 0;
    
    if (socketFD == -1)
        return;

    switch([self addressFamily]) {
        case AF_INET6:
            result = setsockopt(socketFD, IPPROTO_IPV6, IPV6_MULTICAST_LOOP, &shouldLoopMessages, sizeof(shouldLoopMessages));
            break;
        case AF_INET:
            result = setsockopt(socketFD, IPPROTO_IP, IP_MULTICAST_LOOP, &shouldLoopMessages, sizeof(shouldLoopMessages));
            break;
        default:
            result = -1;
            break;
    }
        
    if (result == -1)
        [NSException raise:ONMulticastSocketFailedToSelectLooping format:@"Failed to set local looping to %d on socket %@", shouldLoopMessages, self];
}

// ONSocket subclass

- (size_t)writeBytes:(size_t)byteCount fromBuffer:(const void *)aBuffer toPortAddress:(ONPortAddress *)aPortAddress;
{
    if (![aPortAddress isMulticastAddress])
        [NSException raise:ONMulticastSocketNonMulticastAddress format:@"Cannot send to the address %@ since it is not a multicast address", aPortAddress];

    return [super writeBytes:byteCount fromBuffer:aBuffer toPortAddress:aPortAddress];
}

#pragma mark - Private

- _initWithSocketFD:(int)aSocketFD connected:(BOOL)isConnected
{
    if (!(self = [super _initWithSocketFD:aSocketFD connected:isConnected]))
        return nil;

    mcastTTL = -1;
    mcastFlags.shouldLoop = ONMCAST_OPT_USE_DEFAULT;

    return self;
}

- (void)_locked_createSocketFD:(int)af
{
    [super _locked_createSocketFD:af];

    if (socketFD != -1) {
        if (mcastTTL >= 0)
            [self setSendTimeToLive:mcastTTL];
        if (mcastFlags.shouldLoop != ONMCAST_OPT_USE_DEFAULT)
            [self setShouldLoopMessagesToMemberGroups: (mcastFlags.shouldLoop?YES:NO) ];
    }
}

- (void)_changeGroupMembership:(ONHostAddress *)groupAddress localInterface:(ONInterface *)localInterface add:(BOOL)shouldAdd;
{
    int result;

    [self ensureSocketFD:[groupAddress addressFamily]];
    
    if ([groupAddress addressFamily] == AF_INET) {
        struct ip_mreq imr;
        int op;

        OBASSERT([groupAddress _addressLength] == sizeof(imr.imr_multiaddr));
        bcopy([groupAddress _internetAddress], &(imr.imr_multiaddr), sizeof(imr.imr_multiaddr));

        if (localInterface) {
            ONHostAddress *interfaceAddress = [localInterface interfaceAddress];
            OBASSERT([interfaceAddress _addressLength] == sizeof(imr.imr_interface));
            bcopy([interfaceAddress _internetAddress], &(imr.imr_interface), sizeof(imr.imr_interface));
        } else
            imr.imr_interface.s_addr = INADDR_ANY;

        op = shouldAdd? IP_ADD_MEMBERSHIP : IP_DROP_MEMBERSHIP;

        result = setsockopt(socketFD, IPPROTO_IP, op, (char *)&imr, sizeof(imr));
    } else if ([groupAddress addressFamily] == AF_INET6) {
        struct ipv6_mreq imr;
        int op;

        OBASSERT([groupAddress _addressLength] == sizeof(imr.ipv6mr_multiaddr));
        bcopy([groupAddress _internetAddress], &(imr.ipv6mr_multiaddr), sizeof(imr.ipv6mr_multiaddr));

        if (localInterface)
            imr.ipv6mr_interface = [localInterface index];
        else
            imr.ipv6mr_interface = 0;  /* 0 specifies the default interface, see ip6(4) */

        op = shouldAdd? IPV6_JOIN_GROUP : IPV6_LEAVE_GROUP;

        result = setsockopt(socketFD, IPPROTO_IPV6, op, (char *)&imr, sizeof(imr));
    } else {
        OBASSERT_NOT_REACHED("Unexpected protocol family in multicast group modification");
        result = -1;
    }

    if (result == -1)
        [NSException raise:ONMulticastSocketGroupMembershipOperationFailed format:@"Multicast socket %@ failed to %@ the address %@ on the interface %@", self, shouldAdd ? @"join" : @"leave", groupAddress, localInterface];
}

@end


NSString * const ONMulticastSocketNonMulticastAddress = @"ONMulticastSocketNonMulticastAddress";
NSString * const ONMulticastSocketSetTimeToLiveFailed = @"ONMulticastSocketSetTimeToLiveFailed";
NSString * const ONMulticastSocketGroupMembershipOperationFailed = @"ONMulticastSocketGroupMembershipOperationFailed";
NSString * const ONMulticastSocketSendInterfaceSelectionFailed = @"ONMulticastSocketSendInterfaceSelectionFailed";
NSString * const ONMulticastSocketFailedToSelectLooping = @"ONMulticastSocketFailedToSelectLooping";

