// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <objc/objc.h>

@protocol OFWeakRetain
// Must be implemented by the class itself
- (void)invalidateWeakRetains;

// Implemented by the OFWeakRetainConcreteImplementation_IMPLEMENTATION macro
- (void)incrementWeakRetainCount;
- (void)decrementWeakRetainCount;
- (id)strongRetain;
@end
