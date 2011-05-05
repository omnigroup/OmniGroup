// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

// If this pattern works out, we could extend it to more classes. For now, just explicitly add this via +allocWithZone: and OUIAllocateCustomClass().
__private_extern__ id _OUIAllocateCustomClass(Class self, NSZone *zone);
#define OUIAllocateCustomClass do { \
    id result = _OUIAllocateCustomClass(self, zone); \
    return result ? result : [super allocWithZone:zone]; \
} while (0)

__private_extern__ NSString *OUICustomClassOriginalClassName(Class cls);

