// Copyright 1997-2010, 2012-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

id OBAllocateObjectWithIndexedIvars(Class cls, size_t indexedIvarsSize)
{
    return NSAllocateObject(cls, indexedIvarsSize, NULL);
}

void *OBObjectGetIndexedIvars(id object)
{
    return object_getIndexedIvars(object);
}

void OBObjectGetUnsafeObjectIvar(id object, const char *ivarName, __unsafe_unretained id *outValue)
{
    __unsafe_unretained id value = nil;
    object_getInstanceVariable(object, ivarName, (void **)&value);
    if (outValue)
        *outValue = value;
}

__unsafe_unretained id *OBCastMemoryBufferToUnsafeObjectArray(void *buffer)
{
    return (__unsafe_unretained id *)buffer;
}

