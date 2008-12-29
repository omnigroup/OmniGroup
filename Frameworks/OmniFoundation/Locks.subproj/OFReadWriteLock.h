// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <pthread.h>

typedef struct _OFReadWriteLockTable {
    unsigned int                currentCount;
    unsigned int                maxCount;
    struct OFReadWriteLockData *lockData;
} OFReadWriteLockTable;

@protocol OFReadWriteLocking
/*" The OFReadWriteLocking protocol defines a set of methods for controlling concurrent access to a shared resource from multiple threads, some of which may change the resource and some of which may only examine it.  To ensure consistency in the readers, no readers are allowed when updates are occuring in the resource, but to help efficiency, multiple readers may examine the resource at the same time. "*/

/*" Blocks until there are no pending writers.  If there are other readers, they can all have shared ownership of the lock at the same time. "*/
- (void) lockForReading;

/*" Removes the caller as a currently active reader.  You must have previously called -lockForReading. "*/
- (void) unlockForReading;

/*" Blocks until there are no active readers.  If other threads attempt to aquire a read lock while there is a writer pending, the writer has priority.  Note that if you have a read-lock, you cannot upgrade to a write lock. "*/
- (void) lockForWriting;

/*" Removes the caller as the active writer. "*/
- (void) unlockForWriting;

@end

@interface OFReadWriteLock : NSObject <OFReadWriteLocking>
{
    /*" The actual mutual exclusion structure. "*/
    pthread_mutex_t _mutex;

    /*" The condition structure used for readers to wait on the mutex. "*/
    pthread_cond_t _readCondition;

    /*" The condition structure used for writers to wait on the mutex. "*/
    pthread_cond_t _writeCondition;

    /*" Private data describing the current readers. "*/
    OFReadWriteLockTable _readerTable;

    /*" Private data describing the current writers. "*/
    OFReadWriteLockTable _writerTable;
}

- (unsigned int) readLockCount;
- (BOOL) isWriteLocked;
- (unsigned int) pendingWriteLockCount;
- (unsigned int) lockCount;

@end
