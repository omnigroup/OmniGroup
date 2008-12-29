// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "ONInternetSocket.h"

@class ONPortAddress;

@interface ONUDPSocket : ONInternetSocket

- (unsigned int)writeBytes:(unsigned int)byteCount fromBuffer:(const void *)aBuffer toPortAddress:(ONPortAddress *)aPortAddress;

@end
