// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <CoreFoundation/CFData.h>

extern CFDataRef OFDataCreateSHA1Digest(CFAllocatorRef allocator, CFDataRef data);
extern CFDataRef OFDataCreateSHA256Digest(CFAllocatorRef allocator, CFDataRef data);
extern CFDataRef OFDataCreateMD5Digest(CFAllocatorRef allocator, CFDataRef data);
