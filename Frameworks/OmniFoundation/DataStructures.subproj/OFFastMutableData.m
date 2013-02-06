// Copyright 1999-2005, 2007, 2010, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFastMutableData.h>

#import <OmniFoundation/OFSimpleLock.h>

RCS_ID("$Id$")

typedef struct _OFFastMutableBuffer {
    struct _OFFastMutableBuffer *_nextBuffer;
    
    NSUInteger _realLength;
    void *_realBytes;
    
    NSUInteger _currentLength;
    void *_currentBytes;
} OFFastMutableBuffer;

static OFSimpleLockType lock;
static OFFastMutableBuffer *freeList = nil;
static NSUInteger pageSizeMinusOne = 0;

//#define PRINT_STATS
#ifdef PRINT_STATS
static NSUInteger totalBufferCount = 0;
static NSUInteger totalBufferSize = 0;
#endif

static inline NSUInteger _OFRoundToPageSize(NSUInteger byteCount)
{
    return (byteCount + pageSizeMinusOne) & ~pageSizeMinusOne;
}

@implementation OFFastMutableData
/*" Often an algorithm that deals with streams of data may need a lot of temporary data buffers.  OmniSampler shows that a great deal of time can be wasted in these cases in the overhead of allocating and deallocating memory from the kernel and clearing it.

OFFastMutableData is an an attempt to get rid of this overhead.  We maintain a pool of available buffers and we never zero them when they are allocated.

Right now we don't have optimized retain counting for these instances.  The major expense seems to be in the system call and in zeroing the bytes. Also, as of at least 10.8, NSObject instances that *ever* have their retain count go to zero cannot be resurrected by returning them again. Their -retainCount returns -1 (for what that's worth), even if you retain them again.

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

    // Search through the free list looking for a buffer of good enough length.
    // Don't try to do any best fit matching or anything like that.
    OFFastMutableBuffer *buffer = freeList;
    OFFastMutableBuffer **bufferp = &freeList;
    while (buffer && buffer->_realLength < length) {
        bufferp = &buffer->_nextBuffer;
        buffer  = buffer->_nextBuffer;
    }

    if (buffer) {
        // Remove the buffer from the chain and use it.
        *bufferp = buffer->_nextBuffer;
        buffer->_nextBuffer = NULL;
#ifdef PRINT_STATS
        NSLog(@"  Using buffer %p with length %d", buffer, buffer->_realLength);
#endif
    } else {
        // Allocate a new buffer with a realLength rounded up to the next page size.
        NSUInteger pageRoundedLength = _OFRoundToPageSize(length);

        buffer = calloc(1, sizeof(*buffer));
        buffer->_realLength = pageRoundedLength;
        buffer->_realBytes = NSAllocateMemoryPages(pageRoundedLength);

#ifdef PRINT_STATS
        totalBufferCount++;
        totalBufferSize += pageRoundedLength;

        NSLog(@"  Made new buffer %p.  total count = %d, size = %d", buffer, buffer->_realLength, totalBufferCount, totalBufferSize);
#endif
    }

    // Set up the initial bytes/length range
    buffer->_currentLength = length;
    buffer->_currentBytes  = buffer->_realBytes;
    
    OFSimpleUnlock(&lock);

    // Fill out the instance
    OFFastMutableData *instance = (OFFastMutableData *)NSAllocateObject(self, 0, NULL);
    instance->_buffer = buffer;
    
    return instance;
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
 Returns the internal buffer to the free list.
"*/
- (void)dealloc;
{
    // Put our buffer back on the free list
    OFSimpleLock(&lock);
    
    _buffer->_currentLength = 0; // we aren't allocated right now
    _buffer->_currentBytes = NULL;
    _buffer->_nextBuffer = freeList;
    freeList = _buffer;

#ifdef PRINT_STATS
    {
        NSUInteger freeListCount = 0;
        NSUInteger freeListSize = 0;
        OFFastMutableBuffer *buffer;

        buffer = freeList;
        while (buffer) {
            freeListCount++;
            freeListSize += buffer->_realLength;
            buffer = buffer->_nextBuffer;
        }
        NSLog(@"Put buffer %p back on free list, free list count = %d, free list size = %d",
              self, freeListCount, freeListSize);
    }
#endif

    OFSimpleUnlock(&lock);
	
    [super dealloc];
}

/*"
Sets the contents of the instance to zeros.  This is the only time when OFFastMutableData instances are zeroed since this is typically not necessary.
"*/
- (void)fillWithZeros;
{
    // We could do '_realLength' here, but we'll define that we don't need to
    memset(_buffer->_currentBytes, 0, _buffer->_currentLength);
}

/*" Sets the offset into the receiver that will be used.  This is very useful if you have a data object and you want to efficiently chop of some leading bytes.  This will modify the length of the data as well. "*/
- (void)setStartingOffset:(NSUInteger)offset;
{
    if (offset > _buffer->_currentLength)
        [NSException raise:NSInvalidArgumentException format:@"Offset of %ld is greater than length of %ld", offset, _buffer->_currentLength];

    // figure out the old end of the data
    void *end = _buffer->_currentBytes + _buffer->_currentLength;

    // update the starting point of the data
    _buffer->_currentBytes = _buffer->_realBytes + offset;

    // keep the new end of the data at the same address as the old end
    _buffer->_currentLength = end - _buffer->_currentBytes;
}

- (NSUInteger)startingOffset;
{
    return _buffer->_currentBytes - _buffer->_realBytes;
}

#pragma mark NSData subclass

/*" Returns the current length of the instance. "*/
- (NSUInteger)length;
{
    return _buffer->_currentLength;
}

/*" Returns a pointer to the contents of the data object. "*/
- (const void *)bytes;
{
    return _buffer->_currentBytes;
}

#pragma mark NSMutableData subclass

/*" Returns a pointer to the contents of the buffer object that is suitable for making modifications to the contents. "*/
- (void *)mutableBytes;
{
    return _buffer->_currentBytes;
}

/*" Increases the length of the receiver.  The new bytes may or may not actually contain zeros. "*/
- (void)setLength:(NSUInteger)length;
{
    // We need to leave the offset between _realBytes and _currentBytes the same.
    NSUInteger startingOffset = _buffer->_currentBytes - _buffer->_realBytes;

    if (length <= _buffer->_realLength - startingOffset)
        _buffer->_currentLength = length;
    else {
        // Need to grow the memory we have
        NSUInteger newRealSize = _OFRoundToPageSize(length + startingOffset);
        void *newRealBytes = NSAllocateMemoryPages(newRealSize);

        NSCopyMemoryPages(_buffer->_realBytes + startingOffset, newRealBytes + startingOffset, _buffer->_currentLength);

        NSDeallocateMemoryPages(_buffer->_realBytes, _buffer->_realLength);
        _buffer->_realBytes = newRealBytes;
        _buffer->_realLength = newRealSize;

        _buffer->_currentBytes = _buffer->_realBytes + startingOffset;
        _buffer->_currentLength = length;
    }
}

#pragma mark NSCopying

// Copying stuff -- calling these methods on OFFastMutableData usually indicates
// that optimizatin efforts are being thwarted.

/*" Logs a message and then makes the copy.  You typically do not want to call this method on OFFastMutableData instances since the result will not be a fast data object (defeating the purpose of using this class in the first place). "*/
- (id)copyWithZone:(NSZone *)zone;
{
    NSLog(@"-[OFFastMutableData copyWithZone:] called.  This is going to slow stuff down.");
    return [super copyWithZone:zone];
}

/*" Logs a message and then makes the copy.  You typically do not want to call this method on OFFastMutableData instances since the result will not be a fast data object (defeating the purpose of using this class in the first place). "*/
- (id)mutableCopyWithZone:(NSZone *)zone;
{
    NSLog(@"-[OFFastMutableData mutableCopyWithZone:] called.  This is going to slow stuff down.");
    return [super mutableCopyWithZone:zone];
}

@end
