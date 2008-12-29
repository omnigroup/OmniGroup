// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSimpleLock.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")


#if defined(__i386__) || defined(__x86_64__) || defined(__amd64__)

/*
 
 See:
 
 Intel appnote AP-949 "Using Spin-Loops on Intel Pentium 4 Processor and Intel Xeon Processor".
 
 Chynoweth, Michael and Lee, Mary R. "Implementing Scalable Atomic Locks for Intel(R) EM64T or IA32 Architectures".
 
*/

/* These are all the same architecture as far as our locking code is concerned. */

void OFSimpleLock_i386_contentious(OFSimpleLockType *simpleLock)
{
    do {
	while (simpleLock->locked) {
	    sched_yield();
            asm volatile("pause");
	}
    } while (!OFSimpleLockTry(simpleLock));
}

#endif

