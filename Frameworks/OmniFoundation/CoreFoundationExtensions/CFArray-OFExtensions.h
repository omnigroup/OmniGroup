// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <CoreFoundation/CFArray.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniBase/objc.h>

// Convenience functions
@class NSMutableArray;
extern CFMutableArrayRef OFCreateNonOwnedPointerArray(void) CF_RETURNS_RETAINED;

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

extern Boolean OFCFArrayIsSortedAscendingUsingComparator(CFArrayRef self, NSComparator comparator);
extern Boolean OFCFArrayIsSortedAscendingUsingFunction(CFArrayRef self, CFComparatorFunction comparator, void *context);
