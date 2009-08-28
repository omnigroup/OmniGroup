// Copyright 1999-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFastMutableData.h>

#import <OmniFoundation/OFSimpleLock.h>

RCS_ID("$Id$")


static OFSimpleLockType lock;
static OFFastMutableData *freeList = nil;
static NSUInteger pageSizeMinusOne = 0;

#ifdef PRINT_STATS
static NSUInteger totalBlockCount = 0;
static NSUInteger totalBlockSize = 0;
#endif

static inline NSUInteger _OFRoundToPageSize(NSUInteger byteCount)
{
    return (byteCount + pageSizeMinusOne) & ~pageSizeMinusOne;
}

@implementation OFFastMutableData
/*" Often an algorithm that deals with streams of data may need a lot of temporary data buffers.  OmniSampler shows that a great deal of time can be wasted in these cases in the overhead of allocating and deallocating memory from the kernel and clearing it.

OFFastMutableData is an an attempt to get rid of this overhead.  We maintain a pool of available buffers and we never zero them when they are allocated.

Right now we don't have optimized retain counting for these instances.  The major expense seems to be in the system call and in zeroing the bytes.

Also, the current algorithm never frees buffers.  This can lead to memory space being wasted if the buffer sizes or usage changes during a program.  It might be better to have pools of fast mutable data objects.  An algorithm could create a pool and use it for a while and when it was done, clean up all of the instances.
"*/


+ (void)initialize;
{
    OBINITIALIZE;
    
    pageSizeMinusOne = NSPageSize() - 1;
    OFSimpleLockInit(&lock);
}

/*"
Returns a new retained OFFastMutableData with the requested length.
"*/
+ (OFFastMutableData *)newFastMutableDataWithLength:(NSUInteger)length;
{    
    OFSimpleLock(&lock);

#ifdef PRINT_STATS
    NSLog(@"Requested length = %d", length);
#endif

    // Search through the free list looking for a block of good enough length.
    // Don't try to do any best fit matching or anything like that.
    OFFastMutableData *block = freeList;
    OFFastMutableData **blockp = &freeList;
    while (block && block->_realLength < length) {
        blockp = &block->_nextBlock;
        block  = block->_nextBlock;
    }

    if (block) {
        // Remove the block from the chain.  The external ref count is zero
        // (ie, -retainCount -> 1 as it should).
        *blockp = block->_nextBlock;
        block->_nextBlock = NULL;
#ifdef PRINT_STATS
        NSLog(@"  Found block of length %d at 0x%08x", block->_realLength, block);
#endif
    } else {
        // Allocate a new block with a realLength rounded up to the next
        // page size.
        NSUInteger pageRoundedLength = _OFRoundToPageSize(length);

        block = (id)NSAllocateObject(self, 0, NULL);
        block->_nextBlock = NULL;
        block->_realLength = pageRoundedLength;
        block->_realBytes = NSAllocateMemoryPages(pageRoundedLength);

#ifdef PRINT_STATS
        totalBlockCount++;
        totalBlockSize += pageRoundedLength;

        NSLog(@"  No block found -- allocated one of length %d at 0x%08x.  total count = %d, size = %d",
              block->_realLength, block, totalBlockCount, totalBlockSize);
#endif
    }

    // Set up the initial bytes/length range
    block->_currentLength = length;
    block->_currentBytes = block->_realBytes;
    
    OFSimpleUnlock(&lock);

    return block;
}

/*"
Raises an exception.  You should always get instances of OFFastMutableData via +newFastMutableDataWithLength:.
"*/
+ (id)allocWithZone:(NSZone *)zone;
{
    [NSException raise:NSInternalInconsistencyException format:@"You must allocated instances of OFFastMutableData via +newFastMutableDataWithLength:"];
    return nil;
}

/*"
Makes the instance available for later reuse.  Does not actually deallocate the instance.
"*/
- (void)dealloc;
{
    // Don't actually deallocate the object.  Just put it back on the free list.
    OFSimpleLock(&lock);
    _currentLength = 0; // we aren't allocated right now
    _currentBytes = NULL;
    _nextBlock = freeList;
    freeList = self;

#ifdef PRINT_STATS
    {
        NSUInteger freeListCount = 0;
        NSUInteger freeListSize = 0;
        OFFastMutableData *block;

        block = freeList;
        while (block) {
            freeListCount++;
            freeListSize += block->_realLength;
            block = block->_nextBlock;
        }
        NSLog(@"Put block 0x%08x back on free list, free list count = %d, free list size = %d",
              self, freeListCount, freeListSize);
    }
#endif

    OFSimpleUnlock(&lock);
	
    // 10.4 emits a warning here if there is no call to super.  We don't want it since we are doing a free list.
    return;
    [super dealloc];
}

#pragma mark API

/*"
Sets the contents of the instance to zeros.  This is the only time when OFFastMutableData instances are zeroed since this is typically not necessary.
"*/
- (void)fillWithZeros;
{
    // We could do '_realLength' here, but we'll define that we don't need to
    memset(_currentBytes, 0, _currentLength);
}

/*" Sets the offset into the receiver that will be used.  This is very useful if you have a data object and you want to efficiently chop of some leading bytes.  This will modify the length of the data as well. "*/
- (void)setStartingOffset:(NSUInteger)offset;
{
    if (offset > _currentLength)
        [NSException raise:NSInvalidArgumentException
                    format:@"Offset of %d is greater than length of %d", offset, _currentLength];
    
    // figure out the old end of the data
    void *end = _currentBytes + _currentLength;
    
    // update the starting point of the data
    _currentBytes  = _realBytes + offset;
    
    // keep the new end of the data at the same address as the old end
    _currentLength = end - _currentBytes;
}

- (NSUInteger)startingOffset;
{
    return _currentBytes - _realBytes;
}

#pragma mark NSData subclass

/*" Returns the current length of the instance. "*/
- (NSUInteger)length;
{
    return _currentLength;
}

/*" Returns a pointer to the contents of the data object. "*/
- (const void *)bytes;
{
    return _currentBytes;
}

#pragma mark NSMutableData subclass

/*" Returns a pointer to the contents of the data object that is suitable for making modifications to the contents. "*/
- (void *)mutableBytes;
{
    return _currentBytes;
}

/*" Increases the length of the receiver.  The new bytes may or may not actually contain zeros. "*/
- (void)setLength:(NSUInteger)length;
{
    // We need to leave the offset between _realBytes and _currentBytes the same.
    NSUInteger startingOffset = _currentBytes - _realBytes;
    
    if (length <= _realLength - startingOffset)
        _currentLength = length;
    else {
        // Need to grow the memory we have
        NSUInteger newRealSize = _OFRoundToPageSize(length + startingOffset);
        void *newRealBytes = NSAllocateMemoryPages(newRealSize);
        
        NSCopyMemoryPages(_realBytes + startingOffset, newRealBytes + startingOffset, _currentLength);
        
        NSDeallocateMemoryPages(_realBytes, _realLength);
        _realBytes = newRealBytes;
        _realLength = newRealSize;
        
        _currentBytes = _realBytes + startingOffset;
        _currentLength = length;
    }
}

#pragma mark NSCopying

// Copying stuff -- calling these methods on OFFastMutableData usually indicates
// that optimizatin efforts are being thwarted.

/*" Logs a message and then makes the copy.  You typically do not want to call this method on OFFastMutableData instances since the result will not be a fast data object (defeating the purpose of using this class in the first place). "*/
- (id)copyWithZone:(NSZone *)zone;
{
    NSLog(@"-[OFFastMutableData copyWithZone:] called.  This is going to slow stuff down.");
    return [super copyWithZone: zone];
}

/*" Logs a message and then makes the copy.  You typically do not want to call this method on OFFastMutableData instances since the result will not be a fast data object (defeating the purpose of using this class in the first place). "*/
- (id)mutableCopyWithZone:(NSZone *)zone;
{
    NSLog(@"-[OFFastMutableData mutableCopyWithZone:] called.  This is going to slow stuff down.");
    return [super mutableCopyWithZone: zone];
}

@end
