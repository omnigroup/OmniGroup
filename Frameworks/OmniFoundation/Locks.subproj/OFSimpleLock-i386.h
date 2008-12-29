// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#define OFSimpleLockDefined

#import <pthread.h>

typedef unsigned int OFSimpleLockBoolean;

typedef struct {
    OFSimpleLockBoolean locked;
} OFSimpleLockType;

#define OFSimpleLockIsNotLocked ((OFSimpleLockBoolean)0)
#define OFSimpleLockIsLocked ((OFSimpleLockBoolean)1)

static inline void OFSimpleLockInit(OFSimpleLockType *simpleLock)
{
    simpleLock->locked = OFSimpleLockIsNotLocked;
}

#define OFSimpleLockFree(lock) /**/

static inline OFSimpleLockBoolean
OFSimpleLockTry(OFSimpleLockType *simpleLock)
{
    OFSimpleLockBoolean result;

    /* A LOCK prefix isn't needed: the XCHG instructions always assert a lock (a bus lock, or a cache lock if possible) */
    asm volatile(
    	"xchgl %1,%0"
	    : "=r" (result), "=m" (simpleLock->locked)
	    : "0" (OFSimpleLockIsLocked), "i" (OFSimpleLockIsLocked));
	    
    return result != OFSimpleLockIsLocked;
}

extern void OFSimpleLock_i386_contentious(OFSimpleLockType *simpleLock);

static inline void OFSimpleLock(OFSimpleLockType *simpleLock)
{
    if (__builtin_expect(!OFSimpleLockTry(simpleLock), 0)) {
#ifdef OFSimpleLockForceInline
        do {
            while (simpleLock->locked) {
                sched_yield();
                asm volatile("pause");
            }
        } while (!OFSimpleLockTry(simpleLock));
#else        
        OFSimpleLock_i386_contentious(simpleLock);
#endif
    }
}

static inline void OFSimpleUnlock(OFSimpleLockType *simpleLock)
{
    OFSimpleLockBoolean result;
    
    asm volatile(
	"xchgl %1,%0"
	    : "=r" (result), "=m" (simpleLock->locked)
	    : "0" (OFSimpleLockIsNotLocked));
}
