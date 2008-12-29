// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/Locks.subproj/OFSimpleLock-pthreads.h 68913 2005-10-03 19:36:19Z kc $

#define OFSimpleLockDefined

#import <pthread.h>

typedef pthread_mutex_t OFSimpleLockType;

static inline void OFSimpleLockInit(OFSimpleLockType *simpleLock)
{
    // Only allow mutexing within this process
    pthread_mutex_init(simpleLock, NULL);
}

static inline void OFSimpleLockFree(OFSimpleLockType *simpleLock)
{
    pthread_mutex_destroy(simpleLock);
}

static inline void OFSimpleLock(OFSimpleLockType *simpleLock)
{
    pthread_mutex_lock(simpleLock);
}

static inline void OFSimpleLockTry(OFSimpleLockType *simpleLock)
{
    pthread_mutex_trylock(simpleLock);
}

static inline void OFSimpleUnlock(OFSimpleLockType *simpleLock)
{
    pthread_mutex_unlock(simpleLock);
}
