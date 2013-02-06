// Copyright 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFWeakReference.h>

RCS_ID("$Id$")

// Stuff from the old OFWeakRetain protocol
OBDEPRECATED_METHOD(-invalidateWeakRetains);
OBDEPRECATED_METHOD(-incrementWeakRetainCount);
OBDEPRECATED_METHOD(-decrementWeakRetainCount);
OBDEPRECATED_METHOD(-strongRetain);

// Helper from OFWeakRetainConcreteImplementation.h
OBDEPRECATED_METHOD(-_releaseFromWeakRetainHelper);

#if !OB_ARC
#error This file must be built with ARC enabled to support auto-zeroing weak references
#endif

@implementation OFWeakReference
{
    __weak id _weak_object;
}

@synthesize object = _weak_object;

- initWithObject:(id)object;
{
    if (!(self = [super init]))
        return nil;
    
    _weak_object = object;
    return self;
}

@end
