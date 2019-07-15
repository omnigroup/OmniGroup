// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONInternetSocket.h>

@class ONPortAddress;

@interface ONUDPSocket : ONInternetSocket

- (size_t)writeBytes:(size_t)byteCount fromBuffer:(const void *)aBuffer toPortAddress:(ONPortAddress *)aPortAddress;

@end
