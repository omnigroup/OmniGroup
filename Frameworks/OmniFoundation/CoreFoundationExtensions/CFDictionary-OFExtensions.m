// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFDictionary-OFExtensions.h>

#import <OmniFoundation/CFString-OFExtensions.h>
#import <OmniFoundation/OFCFCallbacks.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")


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
const CFDictionaryValueCallBacks OFIntegerDictionaryValueCallbacks = {
    0, // version
    0, // retain
    0, // release
    OFIntegerCopyDescription,
    0, // equal
};


const CFDictionaryKeyCallBacks OFCaseInsensitiveStringKeyDictionaryCallbacks = {
    0,    // version
    OFNSObjectRetainCopy,
    OFNSObjectRelease,
    OFCFTypeCopyDescription,
    OFCaseInsensitiveStringIsEqual,
    OFCaseInsensitiveStringHash
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

// Convenience functions

NSMutableDictionary *OFCreateCaseInsensitiveKeyMutableDictionary(void)
{
    return (NSMutableDictionary *) CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                          &OFCaseInsensitiveStringKeyDictionaryCallbacks,
                                          &OFNSObjectDictionaryValueCallbacks);
}

void OFPerformSelectorOnKeyApplierFunction(const void *key, const void *value, void *context)
{
    [(id)key performSelector:(SEL)context];
}

void OFPerformSelectorOnValueApplierFunction(const void *key, const void *value, void *context)
{
    [(id)value performSelector:(SEL)context];
}
