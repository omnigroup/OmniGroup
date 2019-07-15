// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

//
// This class was not part of the original design, and it clearly suffers as a result.  For example, it doesn't handle multiple host addresses at all.  I'm tempted to remove it altogether, but it does serve a useful purpose and while I don't have time to fix it right now it might be useful to some.
//
// But it does really bug me in that it duplicates some of the logic from ONInternetSocket, and in a less robust manner.
// 
// Right now, the only time you would want to use this class is when sending lots of messages to lots of differing hosts via an unconnected ONUDPSocket (for example, if you were talking to lots of Quake servers via a single socket).
//
// Eventually, I think I'd like to replace this with an object that stores an ONHost and a port number, has some mechanism for  looping through addresses (or selecting a preferred one), and perhaps caches the socketaddr_in structure for each.
// 

#import <OmniBase/OBObject.h>

@class ONHostAddress;
@class ONHost;

@interface ONPortAddress : OBObject <NSCoding, NSCopying>

- initWithHost:(ONHost *)aHost portNumber:(unsigned short int)port;
- initWithHostAddress:(ONHostAddress *)hostAddress portNumber:(unsigned short int)port;
- initWithSocketAddress:(const struct sockaddr *)newPortAddress;

- (int)addressFamily;
- (const struct sockaddr *)portAddress;
- (ONHostAddress *)hostAddress;
- (unsigned short int)portNumber;
- (BOOL)isMulticastAddress;

// - (BOOL)hasSameHostAddressAsHostAddress: (ONHostAddress *)hostAddress;
- (BOOL)isEqualToSocketAddress:(const struct sockaddr *)otherPortAddress;

@end

// Exceptions which may be raised by this class
extern NSString * const ONInternetSocketConnectFailedExceptionName;
