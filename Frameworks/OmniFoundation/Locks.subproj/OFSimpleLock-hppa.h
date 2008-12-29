// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/Locks.subproj/OFSimpleLock-hppa.h 68913 2005-10-03 19:36:19Z kc $

#define OFSimpleLockDefined

#import <pthreads.h>

typedef unsigned int OFSimpleLockBoolean;

typedef struct {
    volatile unsigned int lock_data[4];
} OFSimpleLockType;

static inline void OFSimpleLockInit(OFSimpleLockType *simpleLock)
{
    *((volatile int *)(((int)(simpleLock) + 0x0c) & ~0x0f)) = 1;
}

#define OFSimpleLockFree(lock) /**/

static inline OFSimpleLockBoolean
OFSimpleLockTry(OFSimpleLockType *simpleLock)
{
    OFSimpleLockBoolean result;
    volatile int *lock_word;

    lock_word = (volatile int *)(((int)(simpleLock) + 0x0c) & ~0x0f);
    asm volatile (
    	"ldcws 0(%1),%0"
	    : "=r" (result)
	    : "r" (lock_word));
	    
    return result;
}

static inline void OFSimpleLock(OFSimpleLockType *simpleLock)
{
    do {
	while (*((volatile int *)(((int)(simpleLock) + 0x0c) & ~0x0f)) == 0) {
	    sched_yield();
	    continue;
	}
    } while (!OFSimpleLockTry(simpleLock));
}

static inline void OFSimpleUnlock(OFSimpleLockType *simpleLock)
{
    *((volatile int *)(((int)(simpleLock) + 0x0c) & ~0x0f)) = 1;
}
