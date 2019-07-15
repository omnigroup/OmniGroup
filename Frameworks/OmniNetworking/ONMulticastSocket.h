// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONUDPSocket.h>

//
// Much of the information in this header was taken from:
//
//       IP Multicast Extensions
// for 4.3BSD UNIX and related systems
//       (MULTICAST 1.2 Release)
//
//            June 24, 1989
//
//            Steve Deering
//         Stanford University
//   <deering@pescadero.Stanford.EDU>
// 

@interface ONMulticastSocket : ONUDPSocket

+ (unsigned int)maximumGroupMemberships;
    // Returns the maximum number of groups of which a single socket may be made a member.

- (void)setSendTimeToLive:(unsigned char)ttl;
    // multicast datagrams with initial TTL of:
    //            0 are restricted to the same host
    //		  1 are restricted to the same subnet
    //		 32 are restricted to the same site
    //		 64 are restricted to the same region
    //		128 are restricted to the same continent
    //		255 are unrestricted in scope

- (void)joinReceiveGroup:(ONHostAddress *)groupAddress localInterface:(ONInterface *)localInterface;
    // Before a host can receive IP multicast datagrams, it must become a member of one or more IP multicast groups.  This call attempts to join the specified group on the specified local interface.  Messages to this group received on other interfaces will not be delivered to the socket.  Valid addresses are those between 224.0.0.0 and 239.255.255.255.

- (void)leaveReceiveGroup:(ONHostAddress *)groupAddress localInterface:(ONInterface *)localInterface;
    // Removes the socket from the specified group on the localInterface.

- (void)joinReceiveGroup:(ONHostAddress *)groupAddress;
    // Joins the specified group on the default local interface.

- (void)leaveReceiveGroup:(ONHostAddress *)groupAddress;
    // Leaves the specified group on the default local interface.

#if 0
- (void)setSendMulticastInterface:(ONHostAddress *)interfaceAddress;
    // If the local host has multiple interfaces that support multicast, this specifies which interface will be used to send outgoing datagrams.  If interfaceAddress is nil, the default interface will be used.
#endif

- (void)setShouldLoopMessagesToMemberGroups:(BOOL)shouldLoop;
    // If a message is set to a group to which the sending host itself belongs, by default a coup of the datagram is looped back by the IP layer for local delivery.  This allows this looping behaviour to be configured.
    //
    // A multicast datagram sent with an initial TTL greater than 1 may be delivered to the sending host on a different interface from that on which it was sent, if the host belongs to the destination group on that other interface.  The loopback control option has no effect on such delivery.

#if 0
// Potential additions to the API

- (NSArray *)currentMemberships;
    // Returns an array of ONHostAddresses for which the receiver is a member.  This is sort of ugly though since it wouldn't specify which interface the receiver was joined on.

#endif

@end

// Exceptions which may be raised by this class
extern NSString * const ONMulticastSocketNonMulticastAddress;
extern NSString * const ONMulticastSocketSetTimeToLiveFailed;
extern NSString * const ONMulticastSocketGroupMembershipOperationFailed;
extern NSString * const ONMulticastSocketSendInterfaceSelectionFailed;
extern NSString * const ONMulticastSocketFailedToSelectLooping;
