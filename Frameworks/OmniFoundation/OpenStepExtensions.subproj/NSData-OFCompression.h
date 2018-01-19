// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSData.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (OFCompression)

// Compression
- (BOOL)mightBeCompressed;
- (nullable NSData *)compressedData:(NSError **)outError;
- (nullable NSData *)decompressedData:(NSError **)outError;

// Specific algorithms
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (nullable NSData *)compressedBzip2Data:(NSError **)outError;
- (nullable NSData *)decompressedBzip2Data:(NSError **)outError;
#endif

- (nullable NSData *)compressedDataWithGzipHeader:(BOOL)includeHeader compressionLevel:(int)level error:(NSError **)outError;
- (nullable NSData *)decompressedGzipData:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
