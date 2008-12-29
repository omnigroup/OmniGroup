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


// Uncomment this to track an address in the stack region of the locking thread  When this changes, all code that uses this must be rebuilt from clean (since this is in a header).  Do NOT USE 'DEBUG' here since some framework might be built with it on and some with it off, creating the possibility for memory corruption
//#define OF_SIMPLE_LOCK_DEBUG

typedef unsigned int OFSimpleLockBoolean;

typedef struct {
    OFSimpleLockBoolean  locked;
#ifdef OF_SIMPLE_LOCK_DEBUG
    // This can be used to track down deadlocks
    void                *lockingFrame;
#endif
} OFSimpleLockType;

#define OFSimpleLockIsNotLocked ((OFSimpleLockBoolean)0)
#define OFSimpleLockIsLocked ((OFSimpleLockBoolean)1)

static inline void OFSimpleLockInit(OFSimpleLockType *simpleLock)
{
    simpleLock->locked = OFSimpleLockIsNotLocked;
}

static inline void OFSimpleLockFree(OFSimpleLockType *simpleLock)
{
}

static inline OFSimpleLockBoolean
OFSimpleLockTry(OFSimpleLockType *simpleLock)
{
    OFSimpleLockBoolean result, tmp;
    OFSimpleLockBoolean *x;
    
    // We will read and write the memory attached to this pointer, but will not change the pointer itself.  Thus, this is a read-only argument to the asm below.  Also, we don't care if people get bad results from reading the contents of the lock -- they shouldn't do that.  So we don't declare that we clobber "memory".
    x = &simpleLock->locked;
    
    asm volatile(
        "li     %0,1\n"      // we want to write a one (this is also our success code)
        "lwarx  %1,0,%2\n"   // load the current value in the lock
        "cmpwi  %1,0\n"      // if it is non-zero, we've failed
        "bne    $+16\n"      // branch to failure if necessary
        "stwcx. %0,0,%2\n"   // try to store our one
        "bne-   $-16\n"      // if we lost our reservation, try again
        "b      $+8\n"       // didn't lose our reservation, so we got it!
        "li     %0,0\n"      // failed!
        : "=&r" (result), "=&r" (tmp)
        : "r" (x)
        : "cc");

    // This flushes any speculative loads that this CPU did before we got the lock.  isync is local to this CPU and doesn't cause the same bus traffic that sync does.
    asm volatile ("isync");
    
#ifdef OF_SIMPLE_LOCK_DEBUG
    if (result) {
        *((volatile void **)&simpleLock->lockingFrame) = &result;
    }
#endif
    return result;
}

static inline void OFSimpleLock(OFSimpleLockType *simpleLock)
{
    // The whole reason we use this lock is because we are optimistic
    if (__builtin_expect(OFSimpleLockTry(simpleLock), 1))
        return;
    
    do {
	while (simpleLock->locked) {
	    sched_yield();
	    continue;
	}
    } while (!OFSimpleLockTry(simpleLock));
}

static inline void OFSimpleUnlock(OFSimpleLockType *simpleLock)
{
#ifdef OF_SIMPLE_LOCK_DEBUG
    *((volatile void **)&simpleLock->lockingFrame) = NULL;
#endif

    // Wait for all previously issued writes to complete and become visible to all processors.
    asm volatile("sync");
    
    // Release the lock
    *((volatile int *)&simpleLock->locked) = OFSimpleLockIsNotLocked;
}
