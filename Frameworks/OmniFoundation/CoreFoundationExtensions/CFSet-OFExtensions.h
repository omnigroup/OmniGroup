// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/CoreFoundationExtensions/CFSet-OFExtensions.h 104581 2008-09-06 21:18:23Z kc $

#import <CoreFoundation/CFSet.h>

extern const CFSetCallBacks OFCaseInsensitiveStringSetCallbacks;

extern const CFSetCallBacks OFNonOwnedPointerSetCallbacks;
extern const CFSetCallBacks OFIntegerSetCallbacks;
extern const CFSetCallBacks OFPointerEqualObjectSetCallbacks;
extern const CFSetCallBacks OFNonOwnedObjectCallbacks;
extern const CFSetCallBacks OFNSObjectSetCallbacks;
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
extern const CFSetCallBacks OFWeaklyRetainedObjectSetCallbacks;
#endif

@class NSMutableSet;
extern NSMutableSet *OFCreateNonOwnedPointerSet(void);
extern NSMutableSet *OFCreatePointerEqualObjectSet(void);
