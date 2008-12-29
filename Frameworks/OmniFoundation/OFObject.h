// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OFObject.h 104581 2008-09-06 21:18:23Z kc $

#import <OmniBase/OBObject.h>

// Turn this off when building on the iPhone and wanting to track leaks in Instruments.  For public release builds, the inline retain count is a win.  But there is no API on the iPhone SDK like the <Foundation/NSDebug.h> to inform the system of internal retain/release allocation events, so Instruments won't see these events and you can't track down leaks easily.
#define OFOBJECT_USE_INTERNAL_EXTRA_REF_COUNT 1

@interface OFObject : OBObject
{
@private
#if OFOBJECT_USE_INTERNAL_EXTRA_REF_COUNT
    int32_t _extraRefCount; /*" Inline retain count for faster -retain/-release. "*/
#endif
}

@end

#if OFOBJECT_USE_INTERNAL_EXTRA_REF_COUNT
extern id <NSObject> OFCopyObject(OFObject *object, unsigned extraBytes, NSZone *zone);
#else
#define OFCopyObject NSCopyObject
#endif
