// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFReadWriteLock.h>

RCS_ID("$Id$")

NSString *OFReadWriteLockUsageException = @"OFReadWriteLockUsageException";

struct OFReadWriteLockData {
    pthread_t     thread;
    unsigned int  recursionCount;
};

static inline void _OFReadWriteLockInsertOrIncrement(OFReadWriteLockTable *table, pthread_t thread)
{
    unsigned int tableIndex;
    BOOL         didLock = NO;

    // Search for our record and update it if found
    tableIndex = table->currentCount;
    while (tableIndex--) {
        if (table->lockData[tableIndex].thread == thread) {
            table->lockData[tableIndex].recursionCount++;
            didLock = YES;
            break;
        }
    }

    if (!didLock) {
        // We're not in the table at all.  Insert a record
        if (table->currentCount >= table->maxCount) {
            table->maxCount *= 2;
            table->lockData = NSZoneRealloc(NSZoneFromPointer(table->lockData), table->lockData, sizeof(*table->lockData) * table->maxCount);
        }

        table->lockData[table->currentCount].thread         = thread;
        table->lockData[table->currentCount].recursionCount = 1;
        table->currentCount++;
    }
}

static inline void _OFReadWriteLockDecrementAndRemoveIfUnlocked(OFReadWriteLockTable *table, pthread_t thread, BOOL unlockQuick)
{
    unsigned int tableIndex;
    BOOL         didUnlock = NO;

    // Search for our reader record and decrement it
    tableIndex = table->currentCount;
    while (tableIndex--) {
        if (table->lockData[tableIndex].thread != thread)
            continue;

        // Make sure we don't wrap negative.
        OBASSERT(table->lockData[tableIndex].recursionCount);

        table->lockData[tableIndex].recursionCount--;
        if (!table->lockData[tableIndex].recursionCount) {
            // This was the last recursion -- remove this entry from the table.
            if (unlockQuick) {
                // Just move the last entry into the vacated spot.
                table->currentCount--;
                table->lockData[tableIndex] = table->lockData[table->currentCount];
            } else {
                // Rather than just move the last entry into the vacated spot, we'll
                // move all the entries up.  This is for the writer case to guarantee
                // that we don't starve out any threads.
                while (tableIndex < table->currentCount) {
                    table->lockData[tableIndex] = table->lockData[tableIndex+1];
                    tableIndex++;
                }
                table->currentCount--;
            }
        }
        
        didUnlock = YES;
        break;
    }

    if (!didUnlock)
        [NSException raise: OFReadWriteLockUsageException
                format: @"Attempted to call unlock a OFReadWriteLock without a corresponding lock call of the same type."];
}

static inline void _OFReadWriteLockCheckForDeadlock(OFReadWriteLockTable *table,
                                                    pthread_t thread,
                                                    const char *lockType,
                                                    pthread_mutex_t *lock)
{
    unsigned int tableIndex = table->currentCount;
    while (tableIndex--) {
        if (table->lockData[tableIndex].thread != thread)
            continue;

        // Unlock the mutex that we have locked.  No action took place, so we don't need
        // to signal/broadcast.  This will let other threads continue even though this
        // thread screwed up.
        pthread_mutex_unlock(lock);
        
        [NSException raise: NSInternalInconsistencyException
                    format: @"This thread already has a %s lock, cannot obtain both types of locks in the same thread at the same time.", lockType];
    }
}


@implementation OFReadWriteLock
/*"
OFReadWriteLock provides a mechanism by which multiple readers can obtain access to a resource at the same time but only a single writer may obtain access to that resource.  The writer and readers cannot have ownership of the lock at the same time.  This lock is useful when the resource being guarded will usually be read-only but will occasionally be updated.  Rather than using an NSLock (which only allows a single owner at any time, this will allow the readers to proceed through the critical section with little contention.

Note that OFReadWriteLock does <b>not</b> allow upgrading read-locks to write-locks atomically.  You might imagine a scenario where if there is a single active reader and it is attempting to upgrade to a write-lock, that would be permitted.  This is not possible to implement in general though.  Consider the case were two threads have obtained read-locks.  If at some later point both of the threads attempt to upgrade to write-locks, the application will deadlock and the two threads wait on each other.

It would be possible to implement this if there was a method '-lockForReadingWithPotentialForUpgradeToWriteLock'.  This method would allow other readers until the point that the thread upgraded to a write lock, but no other thread would be allowed to take out a write lock or a potentially upgrading write lock.  This would be more complicated, though, so we've not bothered implemented this yet.
"*/

- init;
{
    NSZone *zone;
    int rc;
    
    if ([super init] == nil)
        return nil;

    zone = [self zone];

    rc = pthread_mutex_init(&_mutex, NULL);
    if (rc)
        perror("pthread_mutex_init");

    rc = pthread_cond_init(&_readCondition, NULL);
    if (rc)
        perror("pthread_cond_init");
    rc = pthread_cond_init(&_writeCondition, NULL);
    if (rc)
        perror("pthread_cond_init");

    // For now we'll just start out with a max of 4.  On Mach, we could look at the current
    // number of threads that are alive and use that number, but I don't know if the Mach
    // emulation layer on NT and PDO is that sophisticated.  Plus, not all threads will
    // use these locks, so this guess is probably good enough.

    _readerTable.currentCount = 0;
    _readerTable.maxCount     = 4;
    _readerTable.lockData     = NSZoneMalloc(zone, sizeof(*_readerTable.lockData) * _readerTable.maxCount);

    _writerTable.currentCount = 0;
    _writerTable.maxCount     = 4;
    _writerTable.lockData     = NSZoneMalloc(zone, sizeof(*_writerTable.lockData) * _writerTable.maxCount);
    
    return self;
}

- (void) dealloc;
{
    NSZone *zone;

    OBPRECONDITION(!_readerTable.currentCount);
    OBPRECONDITION(!_writerTable.currentCount);

    pthread_cond_destroy(&_readCondition);
    pthread_cond_destroy(&_writeCondition);
    pthread_mutex_destroy(&_mutex);

    zone = [self zone];
    NSZoneFree(zone, _readerTable.lockData);
    NSZoneFree(zone, _writerTable.lockData);
    
    [super dealloc];
}

/*" Returns the number of threads that read locks.  Each thread might have multiple read locks.  To make any decisions based on this, there must be a higher-level lock controlling access to the receiver, of course. "*/
- (unsigned int) readLockCount;
{
    unsigned int readLockCount;
    
    pthread_mutex_lock(&_mutex);
    readLockCount = _readerTable.currentCount;
    pthread_mutex_unlock(&_mutex);

    return readLockCount;
}

/*" Returns YES if there is an active writer.  To make any decisions based on this, there must be a higher-level lock controlling access to the receiver, of course. "*/
- (BOOL) isWriteLocked;
{
    BOOL isWriteLocked;

    pthread_mutex_lock(&_mutex);
    isWriteLocked = (_readerTable.currentCount == 0) && (_writerTable.currentCount != 0);
    pthread_mutex_unlock(&_mutex);

    return isWriteLocked;
}

/*" Returns the number of write lock requests that are pending but not granted yet.  To make any decisions based on this, there must be a higher-level lock controlling access to the receiver, of course. "*/
- (unsigned int) pendingWriteLockCount;
{
    unsigned int pendingWriteLockCount;

    pthread_mutex_lock(&_mutex);
    pendingWriteLockCount = _writerTable.currentCount;
    if (_readerTable.currentCount == 0)
        // then the first writer is actually active, not pending
        pendingWriteLockCount--;
    pthread_mutex_unlock(&_mutex);

    return pendingWriteLockCount;
}

/*" Returns the total number of locks and lock requests.  This is equivalent to the sum of -readLockCount, -pendingWriteLockCount, plus an additional one if -isWriteLocked is currently YES.  To make any decisions based on this, there must be a higher-level lock controlling access to the receiver, of course. "*/
- (unsigned int) lockCount;
{
    unsigned int lockCount;

    pthread_mutex_lock(&_mutex);
    lockCount = _readerTable.currentCount + _writerTable.currentCount;
    pthread_mutex_unlock(&_mutex);

    return lockCount;
}

//
// OFReadWriteLocking protocol
//

- (void) lockForReading;
{
    pthread_t    thread = pthread_self();

    pthread_mutex_lock(&_mutex);

    // Wait for all writers to finish, EXCEPT POSSIBLY us.  It is logically
    // possible to do a read while in the middle of a write, but the converse
    // is not permissible.  If we have the write lock, then we can go ahead
    // and obtain a read-lock (no one else will be able to do anything though).
    while (_writerTable.currentCount != 0 && _writerTable.lockData[0].thread != thread)
        pthread_cond_wait(&_readCondition, &_mutex);        

    _OFReadWriteLockInsertOrIncrement(&_readerTable, thread);
    
    // Release exclusive access.  The action we've taken here
    // cannot make any more threads able to gain the lock, so
    // we won't signal or broadcast.
    pthread_mutex_unlock(&_mutex);
}


- (void) unlockForReading;
{
    pthread_t    thread = pthread_self();
    BOOL         wakeWriters = NO;

    // We need to gain exclusive access to update the reader count.
    pthread_mutex_lock(&_mutex);

    _OFReadWriteLockDecrementAndRemoveIfUnlocked(&_readerTable, thread, YES);

    // If there are no more readers and there are writers pending, we need to wake them.
    if (!_readerTable.currentCount && _writerTable.currentCount)
        wakeWriters = YES;

    // We want to wake up the FIRST writer.  The pthreads API in MacOS X has such a primitive!
    if (wakeWriters)
        pthread_cond_signal_thread_np(&_writeCondition, _writerTable.lockData[0].thread);

    pthread_mutex_unlock(&_mutex);
}

- (void) lockForWriting;
{
    pthread_t    thread = pthread_self();

    pthread_mutex_lock(&_mutex);

    // Flag that there is a writer waiting (preventing any more readers from registering).
    _OFReadWriteLockInsertOrIncrement(&_writerTable, thread);

    // Wait until any current readers have finished.  INCLUDING OURSELVES.  It is
    // logically possible to do a read while in the middle of a write, but the
    // converse is not permissible.
    while (_readerTable.currentCount) {
        // Make sure we are not in the reader table (since we'd deadlock).
        _OFReadWriteLockCheckForDeadlock(&_readerTable, thread, "read", &_mutex);

        pthread_cond_wait(&_writeCondition, &_mutex);
    }
    
    // Wait until we are the first writer in the queue.  This is guaranteed to happen
    // eventually due to the implementation of _OFReadWriteLockDecrementAndRemoveIfUnlocked.
    while (_writerTable.lockData[0].thread != thread)
        pthread_cond_wait(&_writeCondition, &_mutex);

    pthread_mutex_unlock(&_mutex);
}

- (void) unlockForWriting;
{
    BOOL      lastWriter;
    pthread_t thread = pthread_self();

    pthread_mutex_lock(&_mutex);

    _OFReadWriteLockDecrementAndRemoveIfUnlocked(&_writerTable, thread, NO);
    
    lastWriter = (_writerTable.currentCount == 0);

    // If we were the last writer that was waiting for access there could
    // be lots of readers waiting.  Wake up all threads waiting on the
    // condition.
    if (lastWriter)
        pthread_cond_broadcast(&_readCondition);
    else
        // There are more writers.  The pthreads API lets us just wait up the first one
        // which is more efficient than waking them all up and having all but one go
        // back to sleep.
        pthread_cond_signal_thread_np(&_writeCondition, _writerTable.lockData[0].thread);

    pthread_mutex_unlock(&_mutex);
}

@end
