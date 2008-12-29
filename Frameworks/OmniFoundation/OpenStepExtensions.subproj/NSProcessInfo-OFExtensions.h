// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSProcessInfo.h>

@class NSNumber;

@interface NSProcessInfo (OFExtensions)

- (NSNumber *)processNumber;
    // Returns a number uniquely identifying the current process among those running on the same host.  Assumes that this number can be described in a short.  While this may or may not be true on a particular system, it is generally true.

@end
