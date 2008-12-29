// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFSet-OFExtensions.h>

#import <OmniFoundation/CFString-OFExtensions.h>
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/OFCFWeakRetainCallbacks.h>
#endif
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")


const CFSetCallBacks
OFCaseInsensitiveStringSetCallbacks = {
    0,   // version
    OFCFTypeRetain,
    OFCFTypeRelease,
    OFCFTypeCopyDescription,
    OFCaseInsensitiveStringIsEqual,
    OFCaseInsensitiveStringHash,
};

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
const CFSetCallBacks OFWeaklyRetainedObjectSetCallbacks = {
    0,   // version
    OFNSObjectWeakRetain,
    OFNSObjectWeakRelease,
    OFNSObjectCopyDescription,
    OFNSObjectIsEqual,
    OFNSObjectHash,
};
#endif

NSMutableSet *OFCreateNonOwnedPointerSet(void)
{
    return (NSMutableSet *)CFSetCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerSetCallbacks);
}

NSMutableSet *OFCreatePointerEqualObjectSet(void)
{
    return (NSMutableSet *)CFSetCreateMutable(kCFAllocatorDefault, 0, &OFPointerEqualObjectSetCallbacks);
}
