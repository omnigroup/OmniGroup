// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBitField.h>

#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSMutableData-OFExtensions.h>

RCS_ID("$Id$")

static const uint8_t bitsPerByte[256];
static const unsigned int firstBitInByte[256];

@implementation OFBitField

- initWithLength:(NSUInteger)newLength;
{
    NSUInteger realLength;

    if (![super init])
        return nil;

    realLength = newLength / CHAR_BIT;
    if (newLength % CHAR_BIT)
	realLength++;
    data = [[NSMutableData allocWithZone:[self zone]] initWithLength:realLength];
    return self;
}

- initWithData:(NSData *)someData type:(NSString *)string;
{
    if (![super init])
        return nil;
    data = [someData mutableCopyWithZone:[self zone]];
    return self;
}

- (void)dealloc
{
    [data release];
    [super dealloc];
}

- (NSData *)dataForType:(NSString *)typeString;
{
    return data;
}

- (NSNumber *)valueAtIndex:(NSUInteger)anIndex;
{
    return [self boolValueAtIndex:anIndex] ? [NSNumber numberWithBool:YES] : [NSNumber numberWithBool:NO];
}


- (void)setValue:(NSNumber *)aBooleanNumber atIndex:(NSUInteger)anIndex;
{
    [self setBoolValue:[aBooleanNumber boolValue] atIndex:anIndex];
}

- (BOOL)boolValueAtIndex:(NSUInteger)anIndex;
{
    NSUInteger theByteIndex = anIndex / CHAR_BIT;
    unsigned int theBitIndex = anIndex % CHAR_BIT;
    unsigned char value;

    if (theByteIndex >= [data length])
	[NSException raise:NSRangeException format:@""];

    value = ((unsigned char *)[data bytes])[theByteIndex];
    value &= (1 << theBitIndex);

    return value? YES : NO;
}

- (void)setBoolValue:(BOOL)aBool atIndex:(NSUInteger)anIndex;
{
    NSUInteger theByteIndex = anIndex / CHAR_BIT;
    unsigned int theBitIndex = anIndex % CHAR_BIT;
    unsigned char *byte;

    if (theByteIndex >= [data length])
	[NSException raise:NSRangeException format:@"Bit index (%u) is past end of bitfield (length %u)", (unsigned)theByteIndex, (unsigned)[self length]];

    byte = &((unsigned char *)[data mutableBytes])[theByteIndex];
    if (aBool)
	*byte |= (1 << theBitIndex);
    else
	*byte &= ~(1 << theBitIndex);
}

- (NSUInteger)length;
{
    return [data length] * CHAR_BIT;
}

- (void)setLength:(NSUInteger)newLength;
{
    NSUInteger realLength;

    realLength = newLength / CHAR_BIT;
    if (newLength % CHAR_BIT)
	realLength++;

    if ([data length] != realLength)
	[data setLength:realLength];
}

- objectAtIndex:(NSUInteger)anIndex;
{
    return [self valueAtIndex:anIndex];
}

- copyWithZone:(NSZone *)zone;
{
    return [[[self class] allocWithZone:zone] initWithData:data type:nil];
}

- (NSString *)description;
{
    return [data description];
}

- (BOOL)isEqual:(id)anObject;
{
    return [anObject isKindOfClass:[OFBitField class]] && [self isEqualToBitField:anObject];
}

- (BOOL)isEqualToBitField:(OFBitField *)aBitField;
{
    return [data isEqualToData:[aBitField dataForType:nil]];
}

- (NSUInteger) firstBitSet;
{
    unsigned char *bytes;
    NSUInteger     byteIndex, byteCount;
    
    bytes = [data mutableBytes];
    byteCount = [data length];

    for (byteIndex = 0; byteIndex < byteCount; byteIndex++) {
        if (*bytes)
            break;
        bytes++;
    }

    if (byteIndex == byteCount)
        return NSNotFound;

    return byteIndex * CHAR_BIT + firstBitInByte[*bytes];
}

- (NSUInteger) numberOfBitsSet;
{
    unsigned char *bytes;
    NSUInteger     byteCount, bitCount;

    bytes     = [data mutableBytes];
    byteCount = [data length];
    bitCount  = 0;

    while (byteCount--) {
        bitCount += bitsPerByte[*bytes];
        bytes++;
    }

    return byteCount;
}

- (void)resetBitsTo:(BOOL)aBool;
{
    memset((char *)[data mutableBytes], aBool ? 0xff : 0, (int)[data length]);
}

- (NSData *)deltaValue:(OFBitField *)aBitField;
{
    NSMutableData *deltaData;
    unsigned char *bytes;
    const unsigned char *otherBytes;
    unsigned long int length;

    OBPRECONDITION(aBitField != nil);
    OBPRECONDITION([aBitField isKindOfClass:[OFBitField class]]);
    OBPRECONDITION([aBitField length] == [self length]);

    deltaData = [[data mutableCopy] autorelease];
    length = [data length];

    bytes = (unsigned char *)[deltaData mutableBytes];
    otherBytes = (const unsigned char *)[[aBitField dataForType:nil] bytes];

    // This is inefficient.  Should xor words until we run out and then xor bytes.
    while (length--)
	*bytes++ ^= *otherBytes++;

    if ([deltaData indexOfFirstNonZeroByte] == NSNotFound)
	deltaData = nil;

    OBPOSTCONDITION(deltaData || [self isEqualToBitField:aBitField]);

    return deltaData;
}


- (void)andWithData:(NSData *)aData;
{
    [data andWithData:aData];
}

- (void)orWithData:(NSData *)aData;
{
    [data orWithData: aData];
}

- (void)xorWithData:(NSData *)aData;
{
    [data xorWithData:aData];
}

@end


/*

 Program to generate the bitsPerByte table.

#include <stdio.h>

int main(int argc, char *argv[])
{
    unsigned int i, j, k, c;

    for (i = 0; i < 256/8; i++) {
        for (j = 0; j < 8; j++) {
            k = i*8+j;
            c = 0;
            while (k) {
                if (k & 1)
                    c++;
                k >>= 1;
            }
            printf("%d, ", c);
        }
        printf("\n");
    }

    return 0;
}
*/

static const uint8_t bitsPerByte[256] = {
    0, 1, 1, 2, 1, 2, 2, 3,
    1, 2, 2, 3, 2, 3, 3, 4,
    1, 2, 2, 3, 2, 3, 3, 4,
    2, 3, 3, 4, 3, 4, 4, 5,
    1, 2, 2, 3, 2, 3, 3, 4,
    2, 3, 3, 4, 3, 4, 4, 5,
    2, 3, 3, 4, 3, 4, 4, 5,
    3, 4, 4, 5, 4, 5, 5, 6,
    1, 2, 2, 3, 2, 3, 3, 4,
    2, 3, 3, 4, 3, 4, 4, 5,
    2, 3, 3, 4, 3, 4, 4, 5,
    3, 4, 4, 5, 4, 5, 5, 6,
    2, 3, 3, 4, 3, 4, 4, 5,
    3, 4, 4, 5, 4, 5, 5, 6,
    3, 4, 4, 5, 4, 5, 5, 6,
    4, 5, 5, 6, 5, 6, 6, 7,
    1, 2, 2, 3, 2, 3, 3, 4,
    2, 3, 3, 4, 3, 4, 4, 5,
    2, 3, 3, 4, 3, 4, 4, 5,
    3, 4, 4, 5, 4, 5, 5, 6,
    2, 3, 3, 4, 3, 4, 4, 5,
    3, 4, 4, 5, 4, 5, 5, 6,
    3, 4, 4, 5, 4, 5, 5, 6,
    4, 5, 5, 6, 5, 6, 6, 7,
    2, 3, 3, 4, 3, 4, 4, 5,
    3, 4, 4, 5, 4, 5, 5, 6,
    3, 4, 4, 5, 4, 5, 5, 6,
    4, 5, 5, 6, 5, 6, 6, 7,
    3, 4, 4, 5, 4, 5, 5, 6,
    4, 5, 5, 6, 5, 6, 6, 7,
    4, 5, 5, 6, 5, 6, 6, 7,
    5, 6, 6, 7, 6, 7, 7, 8,
};

/*
 Program to generate the firstBitInByte table.  Bits are numbered starting from the least significant bit.
 
#include <stdio.h>

int main(int argc, char *argv[])
{
    unsigned int i, j, k, c;

    for (i = 0; i < 256/8; i++) {
        for (j = 0; j < 8; j++) {
            k = i*8+j;
            c = 0;
            if (!k) {
                printf("-1, ");
            } else while (k) {
                if (k & 1) {
                    printf("%d, ", c);
                    break;
                }
                c++;
                k >>= 1;
            }
        }
        printf("\n");
    }

    return 0;
}
*/


static const unsigned int firstBitInByte[256] = {
    -1, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    4, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    5, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    4, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    6, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    4, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    5, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    4, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    7, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    4, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    5, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    4, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    6, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    4, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    5, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0,
    4, 0, 1, 0, 2, 0, 1, 0,
    3, 0, 1, 0, 2, 0, 1, 0, 
};
