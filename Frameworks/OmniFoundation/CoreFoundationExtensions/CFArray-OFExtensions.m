// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFArray-OFExtensions.h>

#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/CoreFoundationExtensions/CFArray-OFExtensions.m 66043 2005-07-25 21:17:05Z kc $");

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

const CFArrayCallBacks OFIntegerArrayCallbacks = {
    0,     // version;
    NULL,  // retain;
    NULL,  // release;
    OFIntegerCopyDescription, // copyDescription
    NULL,  // equal
};


NSMutableArray *OFCreateNonOwnedPointerArray(void)
{
    return (NSMutableArray *)CFArrayCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerArrayCallbacks);
}

NSMutableArray *OFCreateIntegerArray(void)
{
    return (NSMutableArray *)CFArrayCreateMutable(kCFAllocatorDefault, 0, &OFIntegerArrayCallbacks);
}

