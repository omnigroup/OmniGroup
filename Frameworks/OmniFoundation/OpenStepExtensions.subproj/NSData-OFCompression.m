// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFCompression.h>

#import <OmniFoundation/CFData-OFCompression.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation NSData (OFCompression)

- (BOOL)mightBeCompressed;
{
    return OFDataMightBeCompressed((CFDataRef)self);
}

- (nullable NSData *)compressedData:(NSError **)outError;
{
    CFErrorRef error = NULL;
    CFDataRef result = OFDataCreateCompressedData((OB_BRIDGE CFDataRef)self, outError? &error : NULL);
    if (!result) {
        if (outError)
            *outError = CFBridgingRelease(error);
        return nil;
    }
    return CFBridgingRelease(result);
}

- (nullable NSData *)decompressedData:(NSError **)outError;
{
    CFErrorRef error = NULL;
    CFDataRef result = OFDataCreateDecompressedData(kCFAllocatorDefault, (OB_BRIDGE CFDataRef)self, outError? &error : NULL);
    if (!result) {
        if (outError)
            *outError = CFBridgingRelease(error);
        return nil;
    }
    return CFBridgingRelease(result);
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (nullable NSData *)compressedBzip2Data:(NSError **)outError;
{
    CFErrorRef error = NULL;
    NSData *result = CFBridgingRelease(OFDataCreateCompressedBzip2Data((OB_BRIDGE CFDataRef)self, outError? &error : NULL));
    if (!result) {
        if (outError)
            *outError = CFBridgingRelease(error);
        return nil;
    }
    return result;
}

- (nullable NSData *)decompressedBzip2Data:(NSError **)outError;
{
    CFErrorRef error = NULL;
    NSData *result = CFBridgingRelease(OFDataCreateDecompressedBzip2Data(kCFAllocatorDefault, (OB_BRIDGE CFDataRef)self, outError? &error : NULL));
    if (!result) {
        if (outError)
            *outError = CFBridgingRelease(error);
        return nil;
    }
    return result;
}
#endif

- (nullable NSData *)compressedDataWithGzipHeader:(BOOL)includeHeader compressionLevel:(int)level error:(NSError **)outError;
{
    CFErrorRef error = NULL;
    NSData *result = CFBridgingRelease(OFDataCreateCompressedGzipData((OB_BRIDGE CFDataRef)self, includeHeader, level, outError? &error : NULL));
    if (!result) {
        if (outError)
            *outError = CFBridgingRelease(error);
        return nil;
    }
    return result;
}

- (nullable NSData *)decompressedGzipData:(NSError **)outError;
{
    CFErrorRef error = NULL;
    NSData *result = CFBridgingRelease(OFDataCreateDecompressedGzip2Data(kCFAllocatorDefault, (OB_BRIDGE CFDataRef)self, outError? &error : NULL));
    if (!result) {
        if (outError)
            *outError = CFBridgingRelease(error);
        return nil;
    }
    return result;
}

@end

NS_ASSUME_NONNULL_END
