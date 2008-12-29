// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/CoreFoundationExtensions/CFPropertyList-OFExtensions.h 68913 2005-10-03 19:36:19Z kc $

#include <CoreFoundation/CFData.h>
#include <CoreFoundation/CFPropertyList.h>

/* This simply creates a CFStream, writes the property list using CFPropertyListWriteToStream(), and returns the resulting bytes. if an error occurs, an exception is raised. */
CFDataRef OFCreateDataFromPropertyList(CFAllocatorRef allocator, CFPropertyListRef plist, CFPropertyListFormat format);

