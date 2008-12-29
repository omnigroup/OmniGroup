// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/CoreFoundationExtensions/CFData-OFExtensions.h 102833 2008-07-15 00:56:16Z bungi $

#import <CoreFoundation/CFData.h>

extern CFDataRef OFDataCreateSHA1Digest(CFAllocatorRef allocator, CFDataRef data);
extern CFDataRef OFDataCreateMD5Digest(CFAllocatorRef allocator, CFDataRef data);
