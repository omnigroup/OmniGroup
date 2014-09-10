// Copyright 1997-2005, 2010, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFDictionary-OFExtensions.h>

#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/CFString-OFExtensions.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

const CFDictionaryKeyCallBacks OFCaseInsensitiveStringKeyDictionaryCallbacks = {
    0,    // version
    OFNSObjectRetainCopy,
    OFNSObjectRelease,
    OFCFTypeCopyDescription,
    OFCaseInsensitiveStringIsEqual,
    OFCaseInsensitiveStringHash
};

// Convenience functions

NSMutableDictionary *OFCreateCaseInsensitiveKeyMutableDictionary(void)
{
    return (OB_BRIDGE NSMutableDictionary *)CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                                      &OFCaseInsensitiveStringKeyDictionaryCallbacks,
                                                                      &OFNSObjectDictionaryValueCallbacks);
}
