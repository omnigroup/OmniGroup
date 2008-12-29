// Copyright 2002-2005, 2007, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCFCallbacks.h>

#import <OmniFoundation/CFString-OFExtensions.h>

#include <inttypes.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/CoreFoundationExtensions/OFCFCallbacks.m 103106 2008-07-21 20:34:05Z wiml $");

//
// NSObject callbacks
//

const void * OFNSObjectRetain(CFAllocatorRef allocator, const void *value)
{
    return [(id)value retain];
}

const void * OFNSObjectRetainCopy(CFAllocatorRef allocator, const void *value)
{
    return [(id)value copyWithZone:NULL];
}

void OFNSObjectRelease(CFAllocatorRef allocator, const void *value)
{
    [(id)value release];
}

CFStringRef OFNSObjectCopyDescription(const void *value)
{
    return (CFStringRef)[[(id)value description] retain];
}

CFStringRef OFNSObjectCopyShortDescription(const void *value)
{
    return (CFStringRef)[[(id)value shortDescription] retain];
}

Boolean OFNSObjectIsEqual(const void *value1, const void *value2)
{
    return [(id)value1 isEqual: (id)value2];
}

CFHashCode OFNSObjectHash(const void *value1)
{
    return [(id)value1 hash];
}

//
// CFTypeRef callbacks
//

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

//
// Special purpose callbacks
//

CFStringRef OFPointerCopyDescription(const void *ptr)
{
    return (CFStringRef)[[NSString alloc] initWithFormat: @"<%p>", ptr];
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


Boolean OFCaseInsensitiveStringIsEqual(const void *value1, const void *value2)
{
    OBASSERT([(id)value1 isKindOfClass:[NSString class]] && [(id)value2 isKindOfClass:[NSString class]]);
    return CFStringCompare((CFStringRef)value1, (CFStringRef)value2, kCFCompareCaseInsensitive) == kCFCompareEqualTo;
}

CFHashCode OFCaseInsensitiveStringHash(const void *value)
{
    OBASSERT([(id)value isKindOfClass:[NSString class]]);
    
    // This is the only interesting function in the bunch.  We need to ensure that all
    // case variants of the same string (when 'same' is determine case insensitively)
    // have the same hash code.  We will do this by using CFStringGetCharacters over
    // the first 16 characters of each key.
    // This is obviously not a good hashing algorithm for all strings.
    UniChar characters[16];
    NSUInteger length;
    CFStringRef string;
    
    string = (CFStringRef)value;
    
    length = CFStringGetLength(string);
    if (length > 16)
        length = 16;
        
    CFStringGetCharacters(string, CFRangeMake(0, length), characters);
    
    return OFCaseInsensitiveHash(characters, length);
}
