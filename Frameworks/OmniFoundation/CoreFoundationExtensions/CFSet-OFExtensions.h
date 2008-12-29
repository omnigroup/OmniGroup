// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <CoreFoundation/CFSet.h>
#import <OmniFoundation/OFCFCallbacks.h>

extern const CFSetCallBacks OFCaseInsensitiveStringSetCallbacks;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern const CFSetCallBacks OFWeaklyRetainedObjectSetCallbacks;
#endif

@class NSMutableSet;
extern NSMutableSet *OFCreateNonOwnedPointerSet(void);
extern NSMutableSet *OFCreatePointerEqualObjectSet(void);
