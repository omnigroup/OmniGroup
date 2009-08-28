// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFByteSet.h>

#import <OmniFoundation/NSString-OFExtensions.h>

RCS_ID("$Id$")

@implementation OFByteSet

- copy;
{
    OFByteSet *copy = [[isa alloc] init];

    unsigned int byteIndex;
    for (byteIndex = 0; byteIndex < OFByteSetBitmapRepLength; byteIndex++)
	copy->bitmapRep[byteIndex] = bitmapRep[byteIndex];
    
    return copy;
}

- (BOOL)byteIsMember:(OFByte)aByte;
{
    return isByteInByteSet(aByte, self);
}

- (void)addByte:(OFByte)aByte;
{
    addByteToByteSet(aByte, self);
}

- (void)removeByte:(OFByte)aByte;
{
    removeByteFromByteSet(aByte, self);
}

- (void)addAllBytes;
{
    unsigned int byteIndex;

    for (byteIndex = 0; byteIndex < OFByteSetBitmapRepLength; byteIndex++)
	bitmapRep[byteIndex] = 0xff;
}

- (void)removeAllBytes;
{
    unsigned int byteIndex;

    for (byteIndex = 0; byteIndex < OFByteSetBitmapRepLength; byteIndex++)
	bitmapRep[byteIndex] = 0x00;
}

- (void)addBytesFromData:(NSData *)data;
{
    const OFByte *bytes = (const OFByte *)[data bytes];
    NSUInteger byteIndex, byteCount = [data length];
    for (byteIndex = 0; byteIndex < byteCount; byteIndex++)
	addByteToByteSet(bytes[byteIndex], self);
}

- (void)addBytesFromString:(NSString *)string encoding:(NSStringEncoding)encoding;
{
    [self addBytesFromData:[string dataUsingEncoding:encoding]];
}

- (void)removeBytesFromData:(NSData *)data;
{
    const OFByte *bytes = (const OFByte *)[data bytes];
    NSUInteger byteIndex, byteCount = [data length];
    for (byteIndex = 0; byteIndex < byteCount; byteIndex++)
	removeByteFromByteSet(bytes[byteIndex], self);
}

- (void)removeBytesFromString:(NSString *)string encoding:(NSStringEncoding)encoding;
{
    [self removeBytesFromData:[string dataUsingEncoding:encoding]];
}

- (NSData *)data;
{
    unsigned int byteIndex, byteCount;
    NSMutableData *data;
    OFByte *bytePtr;

    byteCount = 0;
    for (byteIndex = 0; byteIndex < 256; byteIndex++) {
	if (isByteInByteSet(byteIndex, self))
	    byteCount++;
    }
    data = [NSMutableData dataWithLength:byteCount];
    bytePtr = (OFByte *)[data mutableBytes];
    for (byteIndex = 0; byteIndex < 256; byteIndex++) {
	if (isByteInByteSet(byteIndex, self))
	    *bytePtr++ = byteIndex;
    }
    return data;
}

- (NSString *)stringUsingEncoding:(NSStringEncoding)encoding;
{
    return [NSString stringWithData:[self data] encoding:encoding];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;
    NSMutableArray *bytes;
    unsigned int byteIndex;

    debugDictionary = [super debugDictionary];

    bytes = [NSMutableArray arrayWithCapacity:256];
    for (byteIndex = 0; byteIndex < 256; byteIndex++) {
	if (isByteInByteSet(byteIndex, self))
	    [bytes addObject:[NSString stringWithFormat:@"%c", byteIndex]];
    }
    [debugDictionary setObject:bytes forKey:@"bytes"];

    return debugDictionary;
}

@end

@implementation OFByteSet (PredefinedSets)

static OFByteSet *whitespaceByteSet = nil;

+ (OFByteSet *)whitespaceByteSet;
{
    unsigned int byteIndex;

    if (whitespaceByteSet)
	return whitespaceByteSet;

    whitespaceByteSet = [[OFByteSet alloc] init];
    for (byteIndex = 0; byteIndex < 256; byteIndex++)
	if (isspace(byteIndex))
	    [whitespaceByteSet addByte:byteIndex];

    return whitespaceByteSet;
}

@end
