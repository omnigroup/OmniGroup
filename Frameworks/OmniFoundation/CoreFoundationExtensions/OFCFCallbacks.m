// Copyright 2002-2005, 2007, 2008, 2010-2012, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCFCallbacks.h>

#import <Foundation/NSString.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>
#import <OmniBase/macros.h>
#import <inttypes.h>

RCS_ID("$Id$");

#pragma mark NSObject callbacks

const void * OFNSObjectRetain(CFAllocatorRef allocator, const void *value)
{
    OBStrongRetain((OB_BRIDGE id)value);
    return value;
}

const void * OFNSObjectRetainCopy(CFAllocatorRef allocator, const void *value)
{
    return [(OB_BRIDGE id)value copyWithZone:NULL];
}

void OFNSObjectRelease(CFAllocatorRef allocator, const void *value)
{
    OBStrongRelease((OB_BRIDGE id)value);
}

CFStringRef OFNSObjectCopyDescription(const void *value)
{
    CFStringRef str = (CFStringRef)[(OB_BRIDGE id)value description];
    if (str)
        CFRetain(str);
    return str;
}

// See OBObject.h for OBNSObjectCopyShortDescription

Boolean OFNSObjectIsEqual(const void *value1, const void *value2)
{
    return [(OB_BRIDGE id)value1 isEqual: (OB_BRIDGE id)value2];
}

CFHashCode OFNSObjectHash(const void *value1)
{
    return [(OB_BRIDGE id)value1 hash];
}

#pragma mark CFTypeRef callbacks

const void *OFCFTypeRetain(CFAllocatorRef allocator, const void *value)
{
    return CFRetain((CFTypeRef)value);
}

void OFCFTypeRelease(CFAllocatorRef allocator, const void *value)
{
    CFRelease((CFTypeRef)value);
}

CFStringRef OFCFTypeCopyDescription(const void *value)
{
    return CFCopyDescription((CFTypeRef)value);
}

Boolean OFCFTypeIsEqual(const void *value1, const void *value2)
{
    return CFEqual((CFTypeRef)value1, (CFTypeRef)value2);
}

CFHashCode OFCFTypeHash(const void *value)
{
    return CFHash((CFTypeRef)value);
}

#pragma mark Special purpose callbacks

CFStringRef OFPointerCopyDescription(const void *ptr)
{
    return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("<%p>"), ptr);
}

CFStringRef OFIntegerCopyDescription(const void *ptr)
{
    intptr_t i = (intptr_t)ptr;
    assert(sizeof(ptr) >= sizeof(i));
    return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%" PRIdPTR), i);
}

CFStringRef OFUnsignedIntegerCopyDescription(const void *ptr)
{
    uintptr_t u = (uintptr_t)ptr;
    assert(sizeof(ptr) >= sizeof(u));
    return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%" PRIuPTR), u);
}

#pragma mark Collection callback structs using the callbacks above

const CFArrayCallBacks OFNonOwnedPointerArrayCallbacks = {
    0,     // version;
    NULL,  // retain;
    NULL,  // release;
    OFPointerCopyDescription, // copyDescription
    NULL,  // equal
};

const CFArrayCallBacks OFNSObjectArrayCallbacks = {
    0,     // version;
    OFNSObjectRetain,
    OFNSObjectRelease,
    OFNSObjectCopyDescription,
    OFNSObjectIsEqual,
};

const CFArrayCallBacks OFPointerEqualObjectArrayCallbacks = {
    0,     // version;
    OFNSObjectRetain,
    OFNSObjectRelease,
    OFNSObjectCopyDescription,
    NULL, // equal
};

const CFArrayCallBacks OFIntegerArrayCallbacks = {
    0,     // version;
    NULL,  // retain;
    NULL,  // release;
    OFIntegerCopyDescription, // copyDescription
    NULL,  // equal
};

const CFDictionaryKeyCallBacks OFNonOwnedPointerDictionaryKeyCallbacks = {
    0,    // version
    NULL, // retain
    NULL, // release
    OFPointerCopyDescription,
    NULL, // equal
    NULL, // hash
};
const CFDictionaryValueCallBacks OFNonOwnedPointerDictionaryValueCallbacks = {
    0, // version
    0, // retain
    0, // release
    OFPointerCopyDescription,
    0, // equal
};

// -retain/-release, but no -hash/-isEqual:
const CFDictionaryKeyCallBacks OFPointerEqualObjectDictionaryKeyCallbacks = {
    0,   // version
    OFNSObjectRetain,
    OFNSObjectRelease,
    OFNSObjectCopyDescription,
    NULL, // equal
    NULL, // hash
};

const CFDictionaryKeyCallBacks OFIntegerDictionaryKeyCallbacks = {
    0,    // version
    NULL, // retain
    NULL, // release
    OFIntegerCopyDescription,
    NULL, // equal
    NULL, // hash
};
const CFDictionaryKeyCallBacks OFUnsignedIntegerDictionaryKeyCallbacks = {
    0,    // version
    NULL, // retain
    NULL, // release
    OFUnsignedIntegerCopyDescription,
    NULL, // equal
    NULL, // hash
};
const CFDictionaryValueCallBacks OFIntegerDictionaryValueCallbacks = {
    0,    // version
    NULL, // retain
    NULL, // release
    OFIntegerCopyDescription,
    NULL, // equal
};
const CFDictionaryValueCallBacks OFUnsignedIntegerDictionaryValueCallbacks = {
    0,    // version
    NULL, // retain
    NULL, // release
    OFUnsignedIntegerCopyDescription,
    NULL, // equal
};

const CFDictionaryKeyCallBacks OFNSObjectDictionaryKeyCallbacks = {
    0,    // version
    OFNSObjectRetain,
    OFNSObjectRelease,
    OFNSObjectCopyDescription,
    OFNSObjectIsEqual,
    OFNSObjectHash
};
const CFDictionaryKeyCallBacks OFNSObjectCopyDictionaryKeyCallbacks = {
    0,    // version
    OFNSObjectRetainCopy,
    OFNSObjectRelease,
    OFNSObjectCopyDescription,
    OFNSObjectIsEqual,
    OFNSObjectHash
};
const CFDictionaryValueCallBacks OFNSObjectDictionaryValueCallbacks = {
    0,    // version
    OFNSObjectRetain,
    OFNSObjectRelease,
    OFNSObjectCopyDescription,
    OFNSObjectIsEqual,
};

const CFSetCallBacks OFNonOwnedPointerSetCallbacks  = {
    0,    // version
    NULL, // retain
    NULL, // release
    OFPointerCopyDescription,
    NULL, // isEqual
    NULL, // hash
};

const CFSetCallBacks OFIntegerSetCallbacks = {
    0,    // version
    NULL, // retain
    NULL, // release
    OFIntegerCopyDescription,
    NULL, // isEqual
    NULL, // hash
};

// -retain/-release, but no -hash/-isEqual:
const CFSetCallBacks OFPointerEqualObjectSetCallbacks = {
    0,   // version
    OFNSObjectRetain,
    OFNSObjectRelease,
    OFNSObjectCopyDescription,
    NULL,
    NULL,
};

// Not retained, but -hash/-isEqual:
const CFSetCallBacks OFNonOwnedObjectCallbacks = {
    0,    // version
    NULL, // retain
    NULL, // release
    OFNSObjectCopyDescription,
    OFNSObjectIsEqual,
    OFNSObjectHash,
};

const CFSetCallBacks OFNSObjectSetCallbacks = {
    0,   // version
    OFNSObjectRetain,
    OFNSObjectRelease,
    OFNSObjectCopyDescription,
    OFNSObjectIsEqual,
    OFNSObjectHash,
};
