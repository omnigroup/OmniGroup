// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWStream.h>

@class NSData, NSFileHandle, NSLock, NSMutableArray, NSMutableData;
@class OFCondition;
@class OWDataStreamCursor;

#import <Foundation/NSByteOrder.h>
#import <Foundation/NSString.h> // For NSStringEncoding
#import <CoreFoundation/CFString.h> // For CFStringEncoding
#import <OmniFoundation/OFByte.h>
#import <pthread.h>

typedef struct _OWDataStreamBufferDescriptor {
    OFByte *buffer;
    size_t bufferSize;
    volatile size_t bufferUsed;
    struct _OWDataStreamBufferDescriptor * volatile next;
} OWDataStreamBufferDescriptor;

enum OWStringEncodingProvenance {
        // these are ordered: later enums in this list can override earlier ones.
        OWStringEncodingProvenance_Default,             // Global default encoding
        OWStringEncodingProvenance_Preference,          // App preference
        OWStringEncodingProvenance_MetaTag,             // Specified in META tag
        OWStringEncodingProvenance_ProtocolHeader,      // Specified in HTTP header
        OWStringEncodingProvenance_WindowPreference,    // Window-specific override
        OWStringEncodingProvenance_Generated            // We created this stream from character data and we KNOW what encoding we're using, so there
};

@interface OWDataStream : OWStream
{
    /* NSConditionLock isn't very convenient in the case where you have multiple readers */
    /* This mutex applies to readLength, OWDataStream.m:299, lengthChangedInvocations, and flags.endOfData */
    pthread_mutex_t lengthMutex;
    /* This condition is signaled when any of readLength, dataLength, or flags.endOfData is changed */
    pthread_cond_t lengthChangedCondition;
    
    OWDataStreamBufferDescriptor *_first, *_last;
    NSUInteger dataLength;      // total number of bytes in stream, if EOF reached or if known ahead of time
    NSUInteger readLength;      // total number of bytes written to stream (available for reading) so far

    // Support for the string-writing convenience methods
    CFStringEncoding writeEncoding;
    
    struct {
        unsigned int endOfData:1;                          // protected by lengthMutex
        unsigned int hasThrownAwayData:1;                  // protected by _lock
        unsigned int shouldPreservePartialFile:1;
    } flags;

    NSMutableArray *lengthChangedInvocations;              // protected by lengthMutex

    NSString *saveFilename;
    NSFileHandle *saveFileHandle;                          // protected by _lock
    NSMutableDictionary *finalFileAttributes;
    unsigned long long startPositionInFile;
    
    unsigned int savedInBuffer;
    OWDataStreamBufferDescriptor *savedBuffer;
}

- init;
- initWithLength:(NSUInteger)newLength;

- (id)createCursor;
    // Returns a new OWDataStreamCursor.

- (void)setWriteEncoding:(CFStringEncoding)anEncoding;
- (void)writeData:(NSData *)newData;
- (void)writeString:(NSString *)string;
- (void)writeFormat:(NSString *)formatString, ... NS_FORMAT_FUNCTION(1,2);

- (NSUInteger)appendToUnderlyingBuffer:(void **)returnedBufferPtr;
    // Returns the number of bytes which can be safely written to the returned pointer (always >0)
- (void)wroteBytesToUnderlyingBuffer:(NSUInteger)count;    
    // Tell the data stream how many bytes you actually wrote

- (NSData *)bufferedData;
- (NSUInteger)bufferedDataLength;

- (NSUInteger)accessUnderlyingBuffer:(void **)returnedBufferPtr startingAtLocation:(NSUInteger)dataOffset;
    // Returns 0 if there isn't any remaining data, otherwise returns a portion of a _OWDataStreamBuffer


- (NSUInteger)dataLength;
    // May block until the stream ends if its length is not known ahead of time
- (BOOL)knowsDataLength;

- (BOOL)getBytes:(void *)buffer range:(NSRange)range;
    // Returns NO if there isn't enough data for the range requested
- (NSData *)dataWithRange:(NSRange)range;
    // Returns nil if there isn't enough data for the range requested

- (BOOL)waitForMoreData;
- (BOOL)waitForBufferedDataLength:(NSUInteger)length;
    // Returns NO if the stream ends and isn't long enough.

- (void)scheduleInvocationAtEOF:(OFInvocation *)anInvocation inQueue:(OFMessageQueue *)aQueue; // TODO - move this up to OWStream eventually

//

- (BOOL)pipeToFilename:(NSString *)aFilename contentType:(OWContentType *)myType shouldPreservePartialFile:(BOOL)shouldPreserve;
- (BOOL)pipeToFilename:(NSString *)aFilename withAttributes:(NSDictionary *)requestedFileAttributes shouldPreservePartialFile:(BOOL)shouldPreserve;
    // Returns YES if data is piped to aFilename, returns NO if data is saved to disk, but to some other filename (use -filename to find out where).  Raises an exception if it can't save.
- (void)appendToFilename:(NSString *)aFilename;
    // Raises if the file is already being saved or hasThrownAwayData or can't seek to the startPositionInFile, etc.
- (NSString *)filename;
- (BOOL)hasThrownAwayData;
- (void)raiseIfInvalid;
- (NSUInteger)bytesWrittenToFile;
- (unsigned long long)startPositionInFile;
- (void)setStartPositionInFile:(unsigned long long)newStartPosition;

- (BOOL)isEqualToDataStream:(OWDataStream *)anotherStream;
- (NSData *)md5Signature;

@end

extern const NSUInteger OWDataStreamUnknownLength;
extern NSString * const OWDataStreamNoLongerValidException;

