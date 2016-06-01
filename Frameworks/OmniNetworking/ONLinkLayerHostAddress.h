// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniNetworking/ONHostAddress.h>

@interface ONLinkLayerHostAddress : ONHostAddress
{
    struct sockaddr_dl *linkAddress;
}

- initWithLinkLayerAddress:(const struct sockaddr_dl *)dlAddress;

- (int)interfaceType;
    // Returns one of IFT_ETHER, IFT_LOOP, etc.
    
- (int)index;
    // Returns an integer index assigned to this interface by the kernel at boot time (or, perhaps, when a hot-pluggable interface is discovered). 

@end
