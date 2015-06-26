// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFSet-OFExtensions.h>

#import <OmniFoundation/CFString-OFExtensions.h>
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

NSMutableSet *OFCreateNonOwnedPointerSet(void)
{
    return (OB_BRIDGE_TRANSFER NSMutableSet *)CFSetCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerSetCallbacks);
}

NSMutableSet *OFCreatePointerEqualObjectSet(void)
{
    return (OB_BRIDGE_TRANSFER NSMutableSet *)CFSetCreateMutable(kCFAllocatorDefault, 0, &OFPointerEqualObjectSetCallbacks);
}
