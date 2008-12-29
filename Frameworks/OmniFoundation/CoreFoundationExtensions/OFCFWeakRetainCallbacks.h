// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <CoreFoundation/CFBase.h>

// Callbacks for NSObjects responding to the OFWeakRetain protocol
extern const void *OFNSObjectWeakRetain(CFAllocatorRef allocator, const void *value);
extern void        OFNSObjectWeakRelease(CFAllocatorRef allocator, const void *value);

