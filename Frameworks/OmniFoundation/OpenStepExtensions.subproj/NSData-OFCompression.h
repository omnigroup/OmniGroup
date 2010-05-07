// Copyright 1997-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSData.h>

@interface NSData (OFCompression)

// Compression
- (BOOL)mightBeCompressed;
- (NSData *)compressedData:(NSError **)outError;
- (NSData *)decompressedData:(NSError **)outError;

// Specific algorithms
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (NSData *)compressedBzip2Data:(NSError **)outError;
- (NSData *)decompressedBzip2Data:(NSError **)outError;
#endif

- (NSData *)compressedDataWithGzipHeader:(BOOL)includeHeader compressionLevel:(int)level error:(NSError **)outError;
- (NSData *)decompressedGzipData:(NSError **)outError;

@end
