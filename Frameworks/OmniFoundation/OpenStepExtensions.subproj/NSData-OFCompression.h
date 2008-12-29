// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
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
- (NSData *)compressedData;
- (NSData *)decompressedData;

// Specific algorithms
- (NSData *)compressedBzip2Data;
- (NSData *)decompressedBzip2Data;

- (NSData *)compressedDataWithGzipHeader:(BOOL)includeHeader compressionLevel:(int)level;
- (NSData *)decompressedGzipData;

@end
