// Copyright 1998-2005, 2007-2008, 2010-2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFExtensions.h>

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/NSStream.h>

#import <OmniFoundation/CFPropertyList-OFExtensions.h>
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
    return [OFRandomCreateDataOfLength(byteCount) autorelease];
}

+ dataWithDecodedURLString:(NSString *)urlString
{
    if (urlString == nil)
        return [NSData data];
    else
        return [urlString dataUsingCFEncoding:[NSString urlEncoding] allowLossyConversion:NO hexEscapes:@"%"];
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
        OBRejectInvalidCall(self, _cmd, @"Range %@ exceeds length %"PRIuNS, NSStringFromRange(searchRange), selfLength);
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
    CFErrorRef errorRef = NULL;
    CFPropertyListRef propList = CFPropertyListCreateWithData(kCFAllocatorDefault, (CFDataRef)self, kCFPropertyListImmutable, NULL, &errorRef);
    if (propList != NULL)
        return CFBridgingRelease(propList);
    
    NSError *error = CFBridgingRelease(errorRef);
    NSException *exception = [NSException exceptionWithName:NSParseErrorException
                                                     reason:[error localizedDescription]
                                                   userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
    
    [exception raise];
    /* NOT REACHED */
    return nil;
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically createDirectories:(BOOL)shouldCreateDirectories error:(NSError **)outError;
{
    if (shouldCreateDirectories && ![[NSFileManager defaultManager] createPathToFile:path attributes:nil error:outError])
        return NO;

    return [self writeToFile:path options:atomically ? NSDataWritingAtomic : 0 error:outError];
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

