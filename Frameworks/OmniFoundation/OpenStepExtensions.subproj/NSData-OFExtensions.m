// Copyright 1998-2005,2007,2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFExtensions.h>

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/NSStream.h>

#import <OmniFoundation/CFData-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniFoundation/NSMutableData-OFExtensions.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFDataBuffer.h>
#import <OmniFoundation/OFRandom.h>

#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <poll.h>

RCS_ID("$Id$")

@implementation NSData (OFExtensions)

+ (NSData *)randomDataOfLength:(NSUInteger)byteCount;
{
    OFByte *bytes = (OFByte *)malloc(byteCount);
    
    for (NSUInteger byteIndex = 0; byteIndex < byteCount; byteIndex++)
        bytes[byteIndex] = OFRandomNext32() & 0xff;

    // Send to self rather than NSData so that we'll get mutable instances when the caller sent the message to NSMutableData
    // clang checker-0.209 incorrectly reports this as a +1 ref <http://llvm.org/bugs/show_bug.cgi?id=4292>
    return objc_msgSend(self, @selector(dataWithBytesNoCopy:length:), bytes, byteCount);
}

+ dataWithDecodedURLString:(NSString *)urlString
{
    if (urlString == nil)
        return [NSData data];
    else
        return [urlString dataUsingCFEncoding:[NSString urlEncoding] allowLossyConversion:NO hexEscapes:@"%"];
}

static inline unichar hex(int i)
{
    static const char hexDigits[16] = {
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'
    };

    return (unichar)hexDigits[i];
}

- (NSUInteger)lengthOfQuotedPrintableStringWithMapping:(const OFQuotedPrintableMapping *)qpMap
{
    const uint8_t *sourceBuffer;
    NSUInteger sourceLength, sourceIndex, quotedPairs;

    sourceLength = [self length];
    if (sourceLength == 0)
        return 0;
    sourceBuffer = [self bytes];

    quotedPairs = 0;

    for (sourceIndex = 0; sourceIndex < sourceLength; sourceIndex++) {
        uint8_t ch = sourceBuffer[sourceIndex];
        if (qpMap->map[ch] == 1)
            quotedPairs ++;
    }

    return sourceLength + ( 2 * quotedPairs );
}

- (NSString *)quotedPrintableStringWithMapping:(const OFQuotedPrintableMapping *)qpMap lengthHint:(NSUInteger)outputLengthHint
{
    NSUInteger sourceLength = [self length];
    if (sourceLength == 0)
        return [NSString string];

    NSString *escapedString;

    const uint8_t *sourceBuffer = [self bytes];

    NSUInteger destinationBufferSize;
    if (outputLengthHint > 0)
        destinationBufferSize = outputLengthHint;
    else
        destinationBufferSize = sourceLength + (sourceLength >> 2) + 12;
    unichar *destinationBuffer = malloc((destinationBufferSize) * sizeof(*destinationBuffer));
    NSUInteger destinationIndex = 0;

    for (NSUInteger sourceIndex = 0; sourceIndex < sourceLength; sourceIndex++) {
        uint8_t ch;
        uint8_t chtype;

        ch = sourceBuffer[sourceIndex];

        if (destinationIndex >= destinationBufferSize - 3) {
            destinationBufferSize += destinationBufferSize >> 2;
            destinationBuffer = realloc(destinationBuffer, (destinationBufferSize) * sizeof(*destinationBuffer));
        }

        chtype = qpMap->map[ ch ];
        if (!chtype) {
            destinationBuffer[destinationIndex++] = ch;
        } else {
            destinationBuffer[destinationIndex++] = qpMap->translations[chtype-1];
            if (chtype == 1) {
                // "1" indicates a quoted-printable rather than a translation
                destinationBuffer[destinationIndex++] = hex((ch & 0xF0) >> 4);
                destinationBuffer[destinationIndex++] = hex(ch & 0x0F);
            }
        }
    }

    escapedString = [[[NSString alloc] initWithCharactersNoCopy:destinationBuffer length:destinationIndex freeWhenDone:YES] autorelease];

    return escapedString;
}

//
// Misc extensions
//

- (NSUInteger)indexOfFirstNonZeroByte;
{
    const OFByte *bytes, *bytePtr;
    NSUInteger byteIndex, byteCount;

    byteCount = [self length];
    bytes = (const uint8_t *)[self bytes];

    for (byteIndex = 0, bytePtr = bytes; byteIndex < byteCount; byteIndex++, bytePtr++) {
	if (*bytePtr != 0)
	    return byteIndex;
    }

    return NSNotFound;
}

- (NSData *)copySHA1Signature;
{
    CFDataRef signature = OFDataCreateSHA1Digest(kCFAllocatorDefault, (CFDataRef)self);
    return NSMakeCollectable(signature);
}

- (NSData *)sha1Signature;
{
    return [[self copySHA1Signature] autorelease];
}

- (NSData *)sha256Signature;
{
    CFDataRef signature = OFDataCreateSHA256Digest(kCFAllocatorDefault, (CFDataRef)self);
    return [NSMakeCollectable(signature) autorelease];
}

- (NSData *)md5Signature;
{
    CFDataRef signature = OFDataCreateMD5Digest(kCFAllocatorDefault, (CFDataRef)self);
    return [NSMakeCollectable(signature) autorelease];
}

- (NSData *)signatureWithAlgorithm:(NSString *)algName;
{
    switch ([algName caseInsensitiveCompare:@"sha1"]) {
        case NSOrderedSame:
            return [self sha1Signature];
        case NSOrderedAscending:
            switch ([algName caseInsensitiveCompare:@"md5"]) {
                case NSOrderedSame:
                    return [self md5Signature];
                default:
                    break;
            }
            break;
        case NSOrderedDescending:
            switch ([algName caseInsensitiveCompare:@"sha256"]) {
                case NSOrderedSame:
                    return [self sha256Signature];
                default:
                    break;
            }
            break;
        default:
            break;
    }
    
    return nil;
}

- (BOOL)hasPrefix:(NSData *)data;
{
    const uint8_t *selfPtr, *ptr, *end;

    if ([self length] < [data length])
        return NO;

    ptr = [data bytes];
    end = ptr + [data length];
    selfPtr = [self bytes];
    
    while(ptr < end) {
        if (*ptr++ != *selfPtr++)
            return NO;
    }
    return YES;
}

- (BOOL)containsData:(NSData *)data
{
    NSUInteger dataLocation = [self indexOfBytes:[data bytes] length:[data length]];
    return (dataLocation != NSNotFound);
}

- (NSRange)rangeOfData:(NSData *)data;
{
    NSUInteger patternLength = [data length];
    NSUInteger patternLocation = [self indexOfBytes:[data bytes] length:patternLength];
    if (patternLocation == NSNotFound)
        return NSMakeRange(NSNotFound, 0);
    else
        return NSMakeRange(patternLocation, patternLength);
}

- (NSUInteger)indexOfBytes:(const void *)patternBytes length:(NSUInteger)patternLength;
{
    return [self indexOfBytes:patternBytes length:patternLength range:NSMakeRange(0, [self length])];
}

- (NSUInteger)indexOfBytes:(const void *)patternBytes length:(NSUInteger)patternLength range:(NSRange)searchRange
{
    const uint8_t *selfBufferStart, *selfPtr, *selfPtrEnd;
    
    NSUInteger selfLength = [self length];
    if (searchRange.location > selfLength ||
        (searchRange.location + searchRange.length) > selfLength) {
        OBRejectInvalidCall(self, _cmd, @"Range {%u,%u} exceeds length %u", searchRange.location, searchRange.length, selfLength);
    }

    if (patternLength == 0)
        return searchRange.location;
    if (patternLength > searchRange.length) {
        // This test is a nice shortcut, but it's also necessary to avoid crashing: zero-length CFDatas will sometimes(?) return NULL for their bytes pointer, and the resulting pointer arithmetic can underflow.
        return NSNotFound;
    }
    
    
    selfBufferStart = [self bytes];
    selfPtr    = selfBufferStart + searchRange.location;
    selfPtrEnd = selfBufferStart + searchRange.location + searchRange.length + 1 - patternLength;
    
    for (;;) {
        if (memcmp(selfPtr, patternBytes, patternLength) == 0)
            return (selfPtr - selfBufferStart);
        
        selfPtr++;
        if (selfPtr == selfPtrEnd)
            break;
        selfPtr = memchr(selfPtr, *(const uint8_t *)patternBytes, (selfPtrEnd - selfPtr));
        if (!selfPtr)
            break;
    }
    return NSNotFound;
}

- propertyList
{
    CFStringRef errorString = NULL;
    CFPropertyListRef propList = CFPropertyListCreateFromXMLData(kCFAllocatorDefault, (CFDataRef)self, kCFPropertyListImmutable, &errorString);
    
    if (propList != NULL)
        return [NSMakeCollectable(propList) autorelease];
    
    NSException *exception = [[NSException alloc] initWithName:NSParseErrorException reason:(NSString *)errorString userInfo:nil];
    [NSMakeCollectable(errorString) autorelease];
    
    [exception autorelease];
    [exception raise];
    /* NOT REACHED */
    return nil;
}


- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically createDirectories:(BOOL)shouldCreateDirectories error:(NSError **)outError;
{
    if (shouldCreateDirectories && ![[NSFileManager defaultManager] createPathToFile:path attributes:nil error:outError])
        return NO;

    return [self writeToFile:path options:atomically ? NSAtomicWrite : 0 error:outError];
}

- (NSData *)dataByAppendingData:(NSData *)anotherData;
{
    if (!anotherData)
        return [[self copy] autorelease];

    NSUInteger myLength = [self length];
    NSUInteger otherLength = [anotherData length];

    if (!otherLength)
        return [[self copy] autorelease];
    if (!myLength)
        return [[anotherData copy] autorelease];

    NSMutableData *buffer = [[NSMutableData alloc] initWithCapacity:myLength + otherLength];
    [buffer appendData:self];
    [buffer appendData:anotherData];
    NSData *result = [buffer copy];
    [buffer release];

    return [result autorelease];
}

@end

