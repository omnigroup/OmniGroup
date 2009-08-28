// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <CoreFoundation/CFString.h>


// Callbacks for NSObjects
extern const void *OFNSObjectRetain(CFAllocatorRef allocator, const void *value);
extern const void *OFNSObjectRetainCopy(CFAllocatorRef allocator, const void *value);
extern void        OFNSObjectRelease(CFAllocatorRef allocator, const void *value);
extern CFStringRef OFNSObjectCopyDescription(const void *value);
extern CFStringRef OFNSObjectCopyShortDescription(const void *value);
extern Boolean     OFNSObjectIsEqual(const void *value1, const void *value2);
extern CFHashCode  OFNSObjectHash(const void *value1);

// Callbacks for CFTypeRefs (should usually be interoperable with NSObject, but not always)
extern const void *OFCFTypeRetain(CFAllocatorRef allocator, const void *value);
extern void        OFCFTypeRelease(CFAllocatorRef allocator, const void *value);
extern CFStringRef OFCFTypeCopyDescription(const void *value);
extern Boolean     OFCFTypeIsEqual(const void *value1, const void *value2);
extern CFHashCode  OFCFTypeHash(const void *value);

// Special purpose callbacks
extern CFStringRef OFPointerCopyDescription(const void *ptr);
extern CFStringRef OFIntegerCopyDescription(const void *ptr);
extern CFStringRef OFUnsignedIntegerCopyDescription(const void *ptr);

// Collection callback structs using the callbacks above
#import <CoreFoundation/CFArray.h>
extern const CFArrayCallBacks OFNonOwnedPointerArrayCallbacks;
extern const CFArrayCallBacks OFNSObjectArrayCallbacks;
extern const CFArrayCallBacks OFIntegerArrayCallbacks;

#import <CoreFoundation/CFDictionary.h>
extern const CFDictionaryKeyCallBacks    OFNonOwnedPointerDictionaryKeyCallbacks;
extern const CFDictionaryValueCallBacks  OFNonOwnedPointerDictionaryValueCallbacks;

extern const CFDictionaryKeyCallBacks    OFPointerEqualObjectDictionaryKeyCallbacks;

extern const CFDictionaryKeyCallBacks    OFIntegerDictionaryKeyCallbacks;
extern const CFDictionaryKeyCallBacks    OFUnsignedIntegerDictionaryKeyCallbacks;
extern const CFDictionaryValueCallBacks  OFIntegerDictionaryValueCallbacks;
extern const CFDictionaryValueCallBacks  OFUnsignedIntegerDictionaryValueCallbacks;

extern const CFDictionaryKeyCallBacks    OFNSObjectDictionaryKeyCallbacks;
extern const CFDictionaryKeyCallBacks    OFNSObjectCopyDictionaryKeyCallbacks;
extern const CFDictionaryValueCallBacks  OFNSObjectDictionaryValueCallbacks;

#import <CoreFoundation/CFSet.h>
extern const CFSetCallBacks OFNonOwnedPointerSetCallbacks;
extern const CFSetCallBacks OFIntegerSetCallbacks;
extern const CFSetCallBacks OFPointerEqualObjectSetCallbacks;
extern const CFSetCallBacks OFNonOwnedObjectCallbacks;
extern const CFSetCallBacks OFNSObjectSetCallbacks;
