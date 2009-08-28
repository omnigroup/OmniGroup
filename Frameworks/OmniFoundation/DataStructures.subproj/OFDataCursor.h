// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

// OFDataCursor assumes an immutable data object.

@class NSData;
@class OFByteSet;

typedef enum {
    OFDataCursorSeekFromCurrent,
    OFDataCursorSeekFromEnd,
    OFDataCursorSeekFromStart
} OFDataCursorSeekPosition;

#import <Foundation/NSString.h> // For NSStringEncoding
#import <OmniFoundation/OFByte.h>

@interface OFDataCursor : OFObject
{
    NSData *data;
    CFByteOrder byteOrder;
    NSStringEncoding stringEncoding;

    size_t dataLength;
    const OFByte *startPosition, *endPosition;
    const OFByte *currentPosition;
}

- initWithData:(NSData *)someData;

- (void)setByteOrder:(CFByteOrder)newByteOrder;
- (CFByteOrder)byteOrder;

- (BOOL)hasMoreData;
- (size_t)seekToOffset:(off_t)offset fromPosition:(OFDataCursorSeekPosition)position;
- (size_t)currentOffset;
- (void)rewind;

- (void)readBytes:(size_t)byteCount intoBuffer:(void *)buffer;
- (void)peekBytes:(size_t)byteCount intoBuffer:(void *)buffer;
- (void)skipBytes:(size_t)byteCount;

- (size_t)readMaximumBytes:(size_t)byteCount intoBuffer:(void *)buffer;
- (size_t)peekMaximumBytes:(size_t)byteCount intoBuffer:(void *)buffer;
- (size_t)skipMaximumBytes:(size_t)byteCount;

- (size_t)offsetToByte:(OFByte)aByte;
- (size_t)offsetToByteInSet:(OFByteSet *)aByteSet;

- (long int)readLongInt;
- (long int)peekLongInt;
- (void)skipLongInt;
- (short int)readShortInt;
- (short int)peekShortInt;
- (void)skipShortInt;
- (long long int)readLongLongInt;
- (long long int)peekLongLongInt;
- (void)skipLongLongInt;
- (float)readFloat;
- (float)peekFloat;
- (void)skipFloat;
- (double)readDouble;
- (double)peekDouble;
- (void)skipDouble;
- (OFByte)readByte;
- (OFByte)peekByte;
- (void)skipByte;

- (long int)readCompressedLongInt;
- (long int)peekCompressedLongInt;
- (void)skipCompressedLongInt;
- (long long int)readCompressedLongLongInt;
- (long long int)peekCompressedLongLongInt;
- (void)skipCompressedLongLongInt;

- (NSData *)readDataOfLength:(size_t)aLength;
- (NSData *)peekDataOfLength:(size_t)aLength;
- (NSData *)readDataUpToByte:(OFByte)aByte;
- (NSData *)peekDataUpToByte:(OFByte)aByte;
- (NSData *)readDataUpToByteInSet:(OFByteSet *)aByteSet;
- (NSData *)peekDataUpToByteInSet:(OFByteSet *)aByteSet;
- (NSString *)readStringOfLength:(size_t)aLength;
- (NSString *)peekStringOfLength:(size_t)aLength;
- (NSString *)readStringUpToByte:(OFByte)aByte;
- (NSString *)peekStringUpToByte:(OFByte)aByte;
- (NSString *)readStringUpToByteInSet:(OFByteSet *)aByteSet;
- (NSString *)peekStringUpToByteInSet:(OFByteSet *)aByteSet;

- (NSData *)readAllData;
- (NSString *)readLine;
- (NSString *)peekLine;
- (void)skipLine;

@end
