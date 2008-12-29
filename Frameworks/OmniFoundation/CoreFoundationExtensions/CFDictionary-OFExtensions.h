// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/CoreFoundationExtensions/CFDictionary-OFExtensions.h 103920 2008-08-11 20:16:00Z wiml $

#import <CoreFoundation/CFDictionary.h>
#import <Foundation/NSObjCRuntime.h>  // For NSInteger, etc.

extern const CFDictionaryKeyCallBacks OFCaseInsensitiveStringKeyDictionaryCallbacks;


extern const CFDictionaryKeyCallBacks    OFNonOwnedPointerDictionaryKeyCallbacks;
extern const CFDictionaryValueCallBacks  OFNonOwnedPointerDictionaryValueCallbacks;

extern const CFDictionaryKeyCallBacks    OFPointerEqualObjectDictionaryKeyCallbacks;

extern const CFDictionaryKeyCallBacks    OFIntegerDictionaryKeyCallbacks;
extern const CFDictionaryValueCallBacks  OFIntegerDictionaryValueCallbacks;

extern const CFDictionaryKeyCallBacks    OFNSObjectDictionaryKeyCallbacks;
extern const CFDictionaryKeyCallBacks    OFNSObjectCopyDictionaryKeyCallbacks;
extern const CFDictionaryValueCallBacks  OFNSObjectDictionaryValueCallbacks;


// Convenience functions
@class NSMutableDictionary;
extern NSMutableDictionary *OFCreateCaseInsensitiveKeyMutableDictionary(void);

// Applier functions
extern void OFPerformSelectorOnKeyApplierFunction(const void *key, const void *value, void *context);   // context==SEL
extern void OFPerformSelectorOnValueApplierFunction(const void *key, const void *value, void *context); // context==SEL

// Conveniences for when the value is an integer
// Making these inline functions (rather than macros) means that the compiler will handle any integer width conversions for us
static inline void OFCFDictionaryAddIntegerValue(CFMutableDictionaryRef theDict, const void *key, intptr_t value)
{
    CFDictionaryAddValue(theDict, key, (void *)value);
}

static inline void OFCFDictionaryAddUIntegerValue(CFMutableDictionaryRef theDict, const void *key, uintptr_t value)
{
    CFDictionaryAddValue(theDict, key, (void *)value);
}

static inline void OFCFDictionarySetIntegerValue(CFMutableDictionaryRef theDict, const void *key, intptr_t value)
{
    CFDictionarySetValue(theDict, key, (void *)value);
}

static inline void OFCFDictionarySetUIntegerValue(CFMutableDictionaryRef theDict, const void *key, uintptr_t value)
{
    CFDictionarySetValue(theDict, key, (void *)value);
}

static inline Boolean OFCFDictionaryGetIntegerValueIfPresent(CFDictionaryRef theDict, const void *key, NSInteger *valuePtr)
{
    const void *value;
    Boolean isPresent = CFDictionaryGetValueIfPresent(theDict, key, &value);
    if (isPresent)
        *valuePtr = (intptr_t)value;
    return isPresent;
}

static inline Boolean OFCFDictionaryGetUIntegerValueIfPresent(CFDictionaryRef theDict, const void *key, NSUInteger *valuePtr)
{
    const void *value;
    Boolean isPresent = CFDictionaryGetValueIfPresent(theDict, key, &value);
    if (isPresent)
        *valuePtr = (uintptr_t)value;
    return isPresent;
}

static inline NSInteger OFCFDictionaryGetIntegerValueWithDefault(CFDictionaryRef theDict, const void *key, NSInteger valueIfAbsent)
{
    const void *value;
    if (CFDictionaryGetValueIfPresent(theDict, key, &value))
        return (intptr_t)value;
    else
        return valueIfAbsent;
}

static inline NSUInteger OFCFDictionaryGetUIntegerValueWithDefault(CFDictionaryRef theDict, const void *key, NSUInteger valueIfAbsent)
{
    const void *value;
    if (CFDictionaryGetValueIfPresent(theDict, key, &value))
        return (uintptr_t)value;
    else
        return valueIfAbsent;
}

// Conveniences for when the key is an integer
static inline Boolean OFCFDictionaryContainsIntegerKey(CFDictionaryRef theDict, intptr_t key)
{
    return CFDictionaryContainsKey(theDict, (const void *)key);
}

static inline Boolean OFCFDictionaryContainsUIntegerKey(CFDictionaryRef theDict, uintptr_t key)
{
    return CFDictionaryContainsKey(theDict, (const void *)key);
}

static inline void OFCFDictionarySetValueForInteger(CFMutableDictionaryRef theDict, intptr_t key, const void *value)
{
    CFDictionarySetValue(theDict, (const void *)key, value);
}

static inline void OFCFDictionarySetValueForUInteger(CFMutableDictionaryRef theDict, uintptr_t key, const void *value)
{
    CFDictionarySetValue(theDict, (const void *)key, value);
}


