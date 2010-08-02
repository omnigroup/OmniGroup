// Copyright 1997-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <CoreFoundation/CFData.h>
#import <OmniBase/objc.h>

extern CFDataRef OFDataCreateSHA1Digest(CFAllocatorRef allocator, CFDataRef data) CF_RETURNS_RETAINED;
extern CFDataRef OFDataCreateSHA256Digest(CFAllocatorRef allocator, CFDataRef data) CF_RETURNS_RETAINED;
extern CFDataRef OFDataCreateMD5Digest(CFAllocatorRef allocator, CFDataRef data) CF_RETURNS_RETAINED;
