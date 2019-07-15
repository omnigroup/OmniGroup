// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <CoreFoundation/CFSet.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniBase/objc.h>

extern const CFSetCallBacks OFCaseInsensitiveStringSetCallbacks;

@class NSMutableSet;
extern NSMutableSet *OFCreateNonOwnedPointerSet(void) NS_RETURNS_RETAINED;
extern NSMutableSet *OFCreatePointerEqualObjectSet(void) NS_RETURNS_RETAINED;


// Conveniences for when the value is an integer
// Making these inline functions (rather than macros) means that the compiler will handle any integer width conversions for us
static inline Boolean OFCFSetContainsIntegerValue(CFSetRef theSet, intptr_t value)
{
    return CFSetContainsValue(theSet, (const void *)value);
}

static inline void OFCFSetAddIntegerValue(CFMutableSetRef theSet, intptr_t value)
{
    CFSetAddValue(theSet, (void *)value);
}

static inline void OFCFSetRemoveIntegerValue(CFMutableSetRef theSet, intptr_t value)
{
    CFSetRemoveValue(theSet, (void *)value);
}

