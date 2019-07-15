// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWCursor.h>

@class NSArray, NSData;
@class OWContentType, OWDataStream;

#import <OmniFoundation/OFByte.h>
#import <OmniFoundation/OFBundleRegistryTarget.h>

typedef long OFByteOrder;

@interface OWDataStreamCursor : OWCursor <OFBundleRegistryTarget>
{
    OFByteOrder byteOrder;

    NSUInteger dataOffset;
    OFByte partialByte;
    unsigned int bitsLeft;
}

+ (OWDataStreamCursor *)cursorToRemoveEncoding:(OWContentType *)coding fromCursor:(OWDataStreamCursor *)aCursor;
+ (OWDataStreamCursor *)cursorToApplyEncoding:(OWContentType *)coding toCursor:(OWDataStreamCursor *)aCursor;
+ (BOOL)availableEncoding:(OWContentType *)coding apply:(BOOL)wantToApply remove:(BOOL)wantToRemove tryLoad:(BOOL)loadNow;
+ (NSArray *)availableEncodingsToRemove;


/* In general, the read... methods will raise an exception if the stream is invaild, but the peek... methods will not. I haven't made sure that this is always the case but it is the general rule. */

- (void)setByteOrder:(OFByteOrder)newByteOrder;

- (void)skipBytes:(NSUInteger)byteCount;

- (NSUInteger)currentOffset;
- (NSUInteger)dataLength; // may block
- (BOOL)isAtEOF; // Blocks when no more data is available and -dataLength is not yet known
- (BOOL)haveFinishedReadingData; // Never blocks, can return NO at EOF if -dataLength is not yet known (in which case the next -readData will return nil)

- (void)readBytes:(NSUInteger)byteCount intoBuffer:(void *)buffer;
- (void)peekBytes:(NSUInteger)byteCount intoBuffer:(void *)buffer;

- (void)bufferBytes:(NSUInteger)count;
    // Ensures that 'count' bytes are buffered.
- (BOOL)haveBufferedBytes:(NSUInteger)count;

- (NSUInteger)readMaximumBytes:(NSUInteger)maximum intoBuffer:(void *)buffer;
    // Reads up to 'maximum' bytes into 'buffer', returns the number of bytes actually read.
- (NSUInteger)peekMaximumBytes:(NSUInteger)maximum intoBuffer:(void *)buffer;
    // Peeks up to 'maximum' bytes into 'buffer', returns the number of bytes actually read.
- (NSUInteger)copyBytesToBuffer:(void *)buffer minimumBytes:(NSUInteger)maximum maximumBytes:(NSUInteger)minimum advance:(BOOL)shouldAdvance;
    // Peeks at least 'minimum' and up to 'maximum' bytes into 'buffer', returns the number of bytes actually read; advances cursor if shouldAdvance is true
- (NSData *)readData;
    // Reads the buffered bytes.
- (NSData *)peekData;
    // Peeks at the buffered bytes.

- (NSUInteger)peekUnderlyingBuffer:(void **)returnedBufferPtr;
- (NSUInteger)readUnderlyingBuffer:(void **)returnedBufferPtr;

- (NSData *)readAllData;
    // Reads all remaining data. If the stream is already at EOF, this will return nil (instead of an empty NSData as you might expect).
    
- (NSData *)readBytes:(NSUInteger)byteCount;          // Raises if it reaches EOF
- (NSData *)peekBytes:(NSUInteger)byteCount;          // Raises if it reaches EOF
- (NSData *)peekBytesOrUntilEOF:(NSUInteger)count;    // Returns short data if it reaches EOF

- (OFByte)readByte;
- (OFByte)peekByte;
- (int)readInt;
- (int)peekInt;
- (short)readShort;
- (short)peekShort;
- (long)readLong;
- (long)peekLong;
- (long long)readLongLong;
- (long long)peekLongLong;
- (float)readFloat;
- (float)peekFloat;
- (double)readDouble;
- (double)peekDouble;

- (unsigned int)readBits:(unsigned int)number;
- (int)readSignedBits:(unsigned int)number;
- (void)skipToNextFullByte;

- (NSUInteger)scanUpToByte:(OFByte)byteMatch; // Positions the offset _before_ the byte. Returns the number of bytes skipped. If not found, positions the offset at EOF and raises underflow exception.
- (NSData *)readUpToByte:(OFByte)byteMatch; // Returns all data up to but not including the byte. If not found, reads to EOF and returns the bytes read.

- (OWDataStream *)underlyingDataStream;

- (NSString *)logDescription;

@end

@interface OWDataStreamConcreteCursor : OWDataStreamCursor
{
    OWDataStream *dataStream;
}

- initForDataStream:(OWDataStream *)aStream;
- (OWDataStream *)dataStream;

@end

extern NSException *OWDataStreamCursor_UnderflowException;
// extern NSException *OWDataStreamCursor_EndOfDataException; // apparently unused --wim
extern NSString * const OWDataStreamCursor_UnknownEncodingException;

