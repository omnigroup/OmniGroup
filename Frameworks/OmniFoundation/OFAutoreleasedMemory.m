// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFAutoreleasedMemory.h>

#import <objc/objc-class.h>

RCS_ID("$Id$")

static NSZone *defaultMallocZone = NULL;

@implementation OFAutoreleasedMemory

+ (void)initialize;
{
    OBINITIALIZE;
    defaultMallocZone = NSDefaultMallocZone();
}

+ (void *)mallocMemoryWithCapacity: (unsigned long) length;
{
    OFAutoreleasedMemory *memory;
    Class aClass;
    char *buffer;


    aClass = (Class)self;
    memory = (OFAutoreleasedMemory *)NSAllocateObject(aClass, length, defaultMallocZone);
    [memory autorelease];

    buffer = (char *)memory + class_getInstanceSize(aClass);
    return (void *)buffer;
}

- (void)release;
{
    // Can't ever get more than one reference to an instance of this class
    NSDeallocateObject(self);
}

@end
