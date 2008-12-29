// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFDataCursor.h 89466 2007-08-01 23:35:13Z kc $

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

    unsigned int dataLength;
    const OFByte *startPosition, *endPosition;
    const OFByte *currentPosition;
}

- initWithData:(NSData *)someData;

- (void)setByteOrder:(CFByteOrder)newByteOrder;
- (CFByteOrder)byteOrder;

- (BOOL)hasMoreData;
- (unsigned int)seekToOffset:(int)offset fromPosition:(OFDataCursorSeekPosition)position;
- (unsigned int)currentOffset;
- (void)rewind;

- (void)readBytes:(unsigned int)byteCount intoBuffer:(void *)buffer;
- (void)peekBytes:(unsigned int)byteCount intoBuffer:(void *)buffer;
- (void)skipBytes:(unsigned int)byteCount;

- (unsigned int)readMaximumBytes:(unsigned int)byteCount intoBuffer:(void *)buffer;
- (unsigned int)peekMaximumBytes:(unsigned int)byteCount intoBuffer:(void *)buffer;
- (unsigned int)skipMaximumBytes:(unsigned int)byteCount;

- (unsigned int)offsetToByte:(OFByte)aByte;
- (unsigned int)offsetToByteInSet:(OFByteSet *)aByteSet;

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

- (NSData *)readDataOfLength:(unsigned int)aLength;
- (NSData *)peekDataOfLength:(unsigned int)aLength;
- (NSData *)readDataUpToByte:(OFByte)aByte;
- (NSData *)peekDataUpToByte:(OFByte)aByte;
- (NSData *)readDataUpToByteInSet:(OFByteSet *)aByteSet;
- (NSData *)peekDataUpToByteInSet:(OFByteSet *)aByteSet;
- (NSString *)readStringOfLength:(unsigned int)aLength;
- (NSString *)peekStringOfLength:(unsigned int)aLength;
- (NSString *)readStringUpToByte:(OFByte)aByte;
- (NSString *)peekStringUpToByte:(OFByte)aByte;
- (NSString *)readStringUpToByteInSet:(OFByteSet *)aByteSet;
- (NSString *)peekStringUpToByteInSet:(OFByteSet *)aByteSet;

- (NSData *)readAllData;
- (NSString *)readLine;
- (NSString *)peekLine;
- (void)skipLine;

@end
