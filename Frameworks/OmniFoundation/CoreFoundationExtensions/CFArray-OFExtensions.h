// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/CoreFoundationExtensions/CFArray-OFExtensions.h 103751 2008-08-05 20:59:05Z wiml $

#import <CoreFoundation/CFArray.h>

extern const CFArrayCallBacks OFNonOwnedPointerArrayCallbacks;
extern const CFArrayCallBacks OFNSObjectArrayCallbacks;
extern const CFArrayCallBacks OFIntegerArrayCallbacks;

// Convenience functions
@class NSMutableArray;
extern NSMutableArray *OFCreateNonOwnedPointerArray(void);
extern NSMutableArray *OFCreateIntegerArray(void);

// Conveniences for when the value is an integer
// Making these inline functions (rather than macros) means that the compiler will handle any integer width conversions for us

static inline void OFCFArrayAppendIntegerValue(CFMutableArrayRef theArray, intptr_t value)
{
    CFArrayAppendValue(theArray, (const void *)value);
}

static inline void OFCFArrayAppendUIntegerValue(CFMutableArrayRef theArray, uintptr_t value)
{
    CFArrayAppendValue(theArray, (const void *)value);
}

static inline Boolean OFCFArrayContainsIntegerValue(CFArrayRef theArray, CFRange range, intptr_t value)
{
    return CFArrayContainsValue(theArray, range, (const void *)value);
}

static inline Boolean OFCFArrayContainsUIntegerValue(CFArrayRef theArray, CFRange range, uintptr_t value)
{
    return CFArrayContainsValue(theArray, range, (const void *)value);
}

static inline CFIndex OFCFArrayGetFirstIndexOfIntegerValue(CFArrayRef theArray, CFRange range, intptr_t value)
{
    return CFArrayGetFirstIndexOfValue(theArray, range, (const void *)value);
}

static inline CFIndex OFCFArrayGetFirstIndexOfUIntegerValue(CFArrayRef theArray, CFRange range, uintptr_t value)
{
    return CFArrayGetFirstIndexOfValue(theArray, range, (const void *)value);
}

static inline intptr_t OFCFArrayGetIntegerValueAtIndex(CFArrayRef theArray, CFIndex idx)
{
    const void *value = CFArrayGetValueAtIndex(theArray, idx);
    return (intptr_t)value;
}

static inline uintptr_t OFCFArrayGetUIntegerValueAtIndex(CFArrayRef theArray, CFIndex idx)
{
    const void *value = CFArrayGetValueAtIndex(theArray, idx);
    return (uintptr_t)value;
}

