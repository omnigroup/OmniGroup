// Copyright 1997-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFCompression.h>

#import <OmniFoundation/CFData-OFCompression.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@implementation NSData (OFCompression)

- (BOOL)mightBeCompressed;
{
    return OFDataMightBeCompressed((CFDataRef)self);
}

- (NSData *)compressedData:(NSError **)outError;
{
    NSData *result = [NSMakeCollectable(OFDataCreateCompressedData((CFDataRef)self, (CFErrorRef *)outError)) autorelease];
    if (!result && outError)
        [NSMakeCollectable(*(CFErrorRef *)outError) autorelease];
    return result;
}

- (NSData *)decompressedData:(NSError **)outError;
{
    NSData *result = [NSMakeCollectable(OFDataCreateDecompressedData(kCFAllocatorDefault, (CFDataRef)self, (CFErrorRef *)outError)) autorelease];
    if (!result && outError)
        [NSMakeCollectable(*(CFErrorRef *)outError) autorelease];
    return result;
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (NSData *)compressedBzip2Data:(NSError **)outError;
{
    NSData *result = [NSMakeCollectable(OFDataCreateCompressedBzip2Data((CFDataRef)self, (CFErrorRef *)outError)) autorelease];
    if (!result && outError)
        [NSMakeCollectable(*(CFErrorRef *)outError) autorelease];
    return result;
}

- (NSData *)decompressedBzip2Data:(NSError **)outError;
{
    NSData *result = [NSMakeCollectable(OFDataCreateDecompressedBzip2Data(kCFAllocatorDefault, (CFDataRef)self, (CFErrorRef *)outError)) autorelease];
    if (!result && outError)
        [NSMakeCollectable(*(CFErrorRef *)outError) autorelease];
    return result;
}
#endif

- (NSData *)compressedDataWithGzipHeader:(BOOL)includeHeader compressionLevel:(int)level error:(NSError **)outError;
{
    NSData *result = [NSMakeCollectable(OFDataCreateCompressedGzipData((CFDataRef)self, includeHeader, level, (CFErrorRef *)outError)) autorelease];
    if (!result && outError)
        [NSMakeCollectable(*(CFErrorRef *)outError) autorelease];
    return result;
}

- (NSData *)decompressedGzipData:(NSError **)outError;
{
    NSData *result = [NSMakeCollectable(OFDataCreateDecompressedGzip2Data(kCFAllocatorDefault, (CFDataRef)self, (CFErrorRef *)outError)) autorelease];
    if (!result && outError)
        [NSMakeCollectable(*(CFErrorRef *)outError) autorelease];
    return result;
}

@end
