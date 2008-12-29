// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFDataBuffer.h 98560 2008-03-12 17:28:00Z bungi $


#import <Foundation/NSData.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSByteOrder.h>
#import <math.h>

#import <CoreFoundation/CFString.h>
#import <CoreFoundation/CFData.h>

#import <OmniFoundation/OFByte.h>
#import <OmniBase/assertions.h>

#import <stdio.h>

typedef struct {
    /*" The full contents of the buffer "*/
    NSMutableData  *data;
    
    /*" The current pointer of the data object "*/
    OFByte         *buffer;
    
    /*" The current start of the writable area "*/
    OFByte         *writeStart;
    
    /*" The end of the buffer (buffer + bufferSize) "*/
    OFByte         *bufferEnd;
    
    /*" The endianness in which to write host data types "*/
    CFByteOrder     byteOrder;
} OFDataBuffer;

static inline void
OFDataBufferInit(OFDataBuffer *dataBuffer)
{
    dataBuffer->data = [[NSMutableData alloc] init];
    dataBuffer->buffer = NULL;
    dataBuffer->writeStart = NULL;
    dataBuffer->bufferEnd = NULL;
    dataBuffer->byteOrder = CFByteOrderUnknown;
}

static inline void
OFDataBufferRelease(OFDataBuffer *dataBuffer)
{
    [dataBuffer->data release];
    dataBuffer->data = nil;
    dataBuffer->buffer = NULL;
    dataBuffer->writeStart = NULL;
    dataBuffer->bufferEnd = NULL;
    dataBuffer->byteOrder = CFByteOrderUnknown;
}

static inline size_t
OFDataBufferSpaceOccupied(OFDataBuffer *dataBuffer)
{
    return dataBuffer->writeStart - dataBuffer->buffer;
}

static inline size_t
OFDataBufferSpaceAvailable(OFDataBuffer *dataBuffer)
{
    return dataBuffer->bufferEnd - dataBuffer->writeStart;
}

static inline size_t
OFDataBufferSpaceCapacity(OFDataBuffer *dataBuffer)
{
    return dataBuffer->bufferEnd - dataBuffer->buffer;
}

static inline void
OFDataBufferSetCapacity(OFDataBuffer *dataBuffer, size_t capacity)
{
    size_t occupied;

    occupied = OFDataBufferSpaceOccupied(dataBuffer);
    [dataBuffer->data setLength: capacity];
    dataBuffer->buffer = (OFByte *)[dataBuffer->data mutableBytes];
    dataBuffer->writeStart = dataBuffer->buffer + occupied;
    dataBuffer->bufferEnd  = dataBuffer->buffer + capacity;
}

static inline void
OFDataBufferSizeToFit(OFDataBuffer *dataBuffer)
{
    OFDataBufferSetCapacity(dataBuffer, OFDataBufferSpaceOccupied(dataBuffer));
}

static inline NSData *
OFDataBufferData(OFDataBuffer *dataBuffer)
{
    // For backwards compatibility (and just doing what the caller expects)
    // this must size the buffer to the expected size.
    OFDataBufferSizeToFit(dataBuffer);
    return dataBuffer->data;
}

// Backwards compatibility
static inline void
OFDataBufferFlush(OFDataBuffer *dataBuffer)
{
    OFDataBufferSizeToFit(dataBuffer);
}

static inline OFByte *
OFDataBufferGetPointer(OFDataBuffer *dataBuffer, size_t spaceNeeded)
{
    size_t newSize;
    size_t occupied;
    
    if (OFDataBufferSpaceAvailable(dataBuffer) >= spaceNeeded)
        return dataBuffer->writeStart;
        
    // Otherwise, we have to grow the internal data and reset all our pointers
    occupied = OFDataBufferSpaceOccupied(dataBuffer);
    newSize = 2 * OFDataBufferSpaceCapacity(dataBuffer);
    if (newSize < occupied + spaceNeeded)
        newSize = 2 * (occupied + spaceNeeded);

    OFDataBufferSetCapacity(dataBuffer, newSize);        
    
    return dataBuffer->writeStart;
}

static inline void
OFDataBufferDidAppend(OFDataBuffer *dataBuffer, size_t spaceUsed)
{
    OBPRECONDITION(spaceUsed <= OFDataBufferSpaceAvailable(dataBuffer));
    
    dataBuffer->writeStart += spaceUsed;
}

static inline char
OFDataBufferHexCharacterForDigit(int digit)
{
    if (digit < 10)
	return digit + '0';
    else
	return digit + 'a' - 10;
}

static inline void
OFDataBufferAppendByte(OFDataBuffer *dataBuffer, OFByte aByte)
{
    OFByte *ptr;
    
    ptr = OFDataBufferGetPointer(dataBuffer, sizeof(OFByte));
    *ptr = aByte;
    OFDataBufferDidAppend(dataBuffer, sizeof(OFByte));
}
 
static inline void
OFDataBufferAppendHexForByte(OFDataBuffer *dataBuffer, OFByte aByte)
{
    OFByte *ptr;
    
    ptr = OFDataBufferGetPointer(dataBuffer, 2 *sizeof(OFByte));
    ptr[0] = OFDataBufferHexCharacterForDigit((aByte & 0xf0) >> 4);
    ptr[1] = OFDataBufferHexCharacterForDigit(aByte & 0x0f);
    OFDataBufferDidAppend(dataBuffer, 2 * sizeof(OFByte));
}

static inline void
OFDataBufferAppendCString(OFDataBuffer *dataBuffer, const char *str)
{
    const char *characterPtr;
    
    for (characterPtr = str; *characterPtr; characterPtr++)
	OFDataBufferAppendByte(dataBuffer, *characterPtr);
}
 
static inline void
OFDataBufferAppendBytes(OFDataBuffer *dataBuffer, const OFByte *bytes, unsigned int length)
{
    OFByte *ptr;
    unsigned int byteIndex;
    
    ptr = OFDataBufferGetPointer(dataBuffer, length);

    // The compiler is smart enough to optimize this
    for (byteIndex = 0; byteIndex < length; byteIndex++)
        ptr[byteIndex] = bytes[byteIndex];
    
    OFDataBufferDidAppend(dataBuffer, length);
}
 

#define OFDataBufferSwapBytes(value, swapType)				\
    switch (dataBuffer->byteOrder) {					\
        case CFByteOrderUnknown:      					\
            break;	   						\
        case CFByteOrderLittleEndian:      					\
            value = NSSwapHost ## swapType ## ToLittle(value);		\
            break;							\
        case CFByteOrderBigEndian:						\
            value = NSSwapHost ## swapType ## ToBig(value);		\
            break;							\
    }

#define OFDataBufferAppendOfType(cType, nameType, swapType)	 	\
static inline void OFDataBufferAppend ## nameType      			\
	(OFDataBuffer *dataBuffer, cType value)				\
{									\
    OFDataBufferSwapBytes(value, swapType);    				\
    OFDataBufferAppendBytes(dataBuffer, (OFByte *)&value, sizeof(cType));	\
}

OFDataBufferAppendOfType(long int, LongInt, Long)
OFDataBufferAppendOfType(short int, ShortInt, Short)
OFDataBufferAppendOfType(unichar, Unichar, Short)
OFDataBufferAppendOfType(long long int, LongLongInt, LongLong)

#undef OFDataBufferAppendOfType
#undef OFDataBufferSwapBytes

static inline void OFDataBufferAppendFloat(OFDataBuffer *dataBuffer, float value)
{
    NSSwappedFloat swappedValue;

    switch (dataBuffer->byteOrder) {
        case CFByteOrderUnknown:
            swappedValue = NSConvertHostFloatToSwapped(value);
            break;
        case CFByteOrderLittleEndian:
            swappedValue = NSSwapHostFloatToLittle(value);
            break;
        case CFByteOrderBigEndian:
            swappedValue = NSSwapHostFloatToBig(value);
            break;
    }
    OFDataBufferAppendBytes(dataBuffer, (OFByte *)&swappedValue, sizeof(float));
}

static inline void OFDataBufferAppendDouble(OFDataBuffer *dataBuffer, double value)
{
    NSSwappedDouble swappedValue;

    switch (dataBuffer->byteOrder) {
        case CFByteOrderUnknown:
            swappedValue = NSConvertHostDoubleToSwapped(value);
            break;
        case CFByteOrderLittleEndian:
            swappedValue = NSSwapHostDoubleToLittle(value);
            break;
        case CFByteOrderBigEndian:
            swappedValue = NSSwapHostDoubleToBig(value);
            break;
    }
    OFDataBufferAppendBytes(dataBuffer, (const OFByte *)&swappedValue, sizeof(double));
}

#define OF_COMPRESSED_INT_BITS_OF_DATA    7
#define OF_COMPRESSED_INT_CONTINUE_MASK   0x80
#define OF_COMPRESSED_INT_DATA_MASK       0x7f

static inline void OFDataBufferAppendCompressedLongInt(OFDataBuffer *dataBuffer, unsigned long int value)
{
    do {
        OFByte sevenBitsPlusContinueFlag = 0;

        sevenBitsPlusContinueFlag = value & OF_COMPRESSED_INT_DATA_MASK;
        value >>= OF_COMPRESSED_INT_BITS_OF_DATA;
        if (value != 0)
            sevenBitsPlusContinueFlag |= OF_COMPRESSED_INT_CONTINUE_MASK;
        OFDataBufferAppendByte(dataBuffer, sevenBitsPlusContinueFlag);
    } while (value != 0);
}

static inline void OFDataBufferAppendCompressedLongLongInt(OFDataBuffer *dataBuffer, unsigned long long int value)
{
    do {
        OFByte sevenBitsPlusContinueFlag = 0;

        sevenBitsPlusContinueFlag = value & OF_COMPRESSED_INT_DATA_MASK;
        value >>= OF_COMPRESSED_INT_BITS_OF_DATA;
        if (value != 0)
            sevenBitsPlusContinueFlag |= OF_COMPRESSED_INT_CONTINUE_MASK;
        OFDataBufferAppendByte(dataBuffer, sevenBitsPlusContinueFlag);
    } while (value != 0);
}

static inline void
OFDataBufferAppendHexWithReturnsForBytes(OFDataBuffer *dataBuffer, const OFByte *bytes, unsigned int length)
{
    unsigned int byteIndex;
    
    byteIndex = 0;
    while (byteIndex < length) {
	OFDataBufferAppendHexForByte(dataBuffer, bytes[byteIndex]);
	byteIndex++;
	if ((byteIndex % 40) == 0)
	    OFDataBufferAppendByte(dataBuffer, '\n');
    }
}

 
static inline void
OFDataBufferAppendInteger(OFDataBuffer *dataBuffer, int integer)
{
    int divisor;
    
    if (integer < 0) {
	integer *= -1;
	OFDataBufferAppendByte(dataBuffer, '-');
    }
    
    divisor = (int)log10((double)integer);
    if (divisor < 0)
	divisor = 0;
    divisor = (int)pow(10.0, (double)divisor);
    while (1) {
	OFDataBufferAppendByte(dataBuffer, (integer / divisor) + '0');
	if (divisor <= 1)
	    break;
	integer %= divisor;
	divisor /= 10;
    }
}
 
static inline void
OFDataBufferAppendData(OFDataBuffer *dataBuffer, NSData *data)
{
    OFDataBufferAppendBytes(dataBuffer, (const OFByte *)[data bytes], [data length]);
}

static inline void
OFDataBufferAppendHexWithReturnsForData(OFDataBuffer *dataBuffer, NSData *data)
{
    OFDataBufferAppendHexWithReturnsForBytes(dataBuffer, (const OFByte *)[data bytes], [data length]);
}

static inline void
OFDataBufferAppendString(OFDataBuffer *dataBuffer, CFStringRef string, CFStringEncoding encoding)
{
    OFByte *ptr;
    CFIndex characterCount, usedBufLen;
    
    OBPRECONDITION(string);
    
    characterCount = CFStringGetLength(string);

    // In UTF-8, characters can take up to 4 bytes.  We'll assume the worst case here.
    ptr = OFDataBufferGetPointer(dataBuffer, 4 * characterCount);

    CFIndex charactersWritten = CFStringGetBytes(string, CFRangeMake(0, characterCount), encoding, 0/*lossByte*/, false/*isExternalRepresentation*/, ptr, 4 * characterCount, &usedBufLen);
    if (charactersWritten != characterCount) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"OFDataBufferAppendString was supposed to write %d characters but only wrote %d", characterCount, charactersWritten];
    }
    
    OFDataBufferDidAppend(dataBuffer, usedBufLen);
}

static inline void
OFDataBufferAppendBytecountedUTF8String(OFDataBuffer *dataBuffer, OFDataBuffer *scratchBuffer, CFStringRef string)
{
    UInt8 *bytePointer;
    CFIndex charactersWritten, stringLength, maximumLength, stringLengthInBuffer;

    stringLength = CFStringGetLength(string);
    maximumLength = 4 * stringLength; // In UTF-8, characters can take up to 4 bytes.  We'll assume the worst case here.
    bytePointer = OFDataBufferGetPointer(scratchBuffer, maximumLength);
    charactersWritten = CFStringGetBytes(string, CFRangeMake(0, stringLength), kCFStringEncodingUTF8, 0/*lossByte*/, false/*isExternalRepresentation*/, bytePointer, maximumLength, &stringLengthInBuffer);
    if (charactersWritten != stringLength)
        [NSException raise: NSInternalInconsistencyException
                    format: @"OFDataBufferAppendBytecountedUTF8String was supposed to write %d characters but only wrote %d", stringLength, charactersWritten];
    OFDataBufferAppendCompressedLongInt(dataBuffer, stringLengthInBuffer);
    OFDataBufferAppendBytes(dataBuffer, bytePointer, stringLengthInBuffer);
}

static inline void
OFDataBufferAppendUnicodeString(OFDataBuffer *dataBuffer, CFStringRef string)
{
    OFByte       *ptr;
    CFIndex       characterCount, usedBufLen;
    
    characterCount = CFStringGetLength(string);
    ptr = OFDataBufferGetPointer(dataBuffer, sizeof(unichar) * characterCount);
    CFIndex charactersWritten = CFStringGetBytes(string, CFRangeMake(0, characterCount), kCFStringEncodingUnicode, 0/*lossByte*/, false/*isExternalRepresentation*/, ptr, sizeof(unichar) * characterCount, &usedBufLen);
    if (charactersWritten != characterCount) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"OFDataBufferAppendUnicodeString was supposed to write %d characters but only wrote %d", characterCount, charactersWritten];
    }

    OFDataBufferDidAppend(dataBuffer, usedBufLen);
}

static inline void
OFDataBufferAppendUnicodeByteOrderMark(OFDataBuffer *dataBuffer)
{
    unichar BOM = 0xFEFF;  /* zero width non breaking space a.k.a. byte-order mark */
    
    // We don't use OFDataBufferAppendUnichar() here because that will byteswap the value, and the point of this routine is to indicate the byteorder of a buffer we're writing to with OFDataBufferAppendUnicodeString(), which does *not* byteswap.
    OFDataBufferAppendBytes(dataBuffer, (const OFByte *)&BOM, sizeof(BOM));
}

//
// XML Support
//

extern void OFDataBufferAppendXMLQuotedString(OFDataBuffer *dataBuffer, CFStringRef string);

