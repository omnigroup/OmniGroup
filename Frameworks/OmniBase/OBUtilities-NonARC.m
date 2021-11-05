// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

void OBObjectGetUnsafeObjectIvar(id _Nullable object, const char *ivarName, __unsafe_unretained id _Nullable * _Nullable outValue)
{
    __unsafe_unretained id value = nil;
    object_getInstanceVariable(object, ivarName, (void **)&value);
    if (outValue)
        *outValue = value;
}

__unsafe_unretained id _Nullable * _Nullable OBCastMemoryBufferToUnsafeObjectArray(void * _Nullable buffer)
{
    return (__unsafe_unretained id *)buffer;
}

id OBAllocateObject(Class cls, NSUInteger extraBytes)
{
    return NSAllocateObject(cls, extraBytes, NULL);
}

void *OBGetIndexedIvars(id object)
{
    return object_getIndexedIvars(object);
}

#ifdef DEBUG
NSUInteger OBRetainCount(id object)
{
    return [object retainCount];
}
#endif

NS_ASSUME_NONNULL_END

