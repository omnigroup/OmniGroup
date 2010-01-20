// Copyright 1997-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <CoreFoundation/CFData.h>

// Compression
extern Boolean OFDataMightBeCompressed(CFDataRef data);
extern CFDataRef OFDataCreateCompressedData(CFDataRef data, CFErrorRef *outError);
extern CFDataRef OFDataCreateDecompressedData(CFAllocatorRef decompressedDataAllocator, CFDataRef data, CFErrorRef *outError);

// Specific algorithms
extern CFDataRef OFDataCreateCompressedBzip2Data(CFDataRef data, CFErrorRef *outError);
extern CFDataRef OFDataCreateDecompressedBzip2Data(CFAllocatorRef decompressedDataAllocator, CFDataRef data, CFErrorRef *outError);

extern CFDataRef OFDataCreateCompressedGzipData(CFDataRef data, Boolean includeHeader, int level, CFErrorRef *outError);
extern CFDataRef OFDataCreateDecompressedGzip2Data(CFAllocatorRef decompressedDataAllocator, CFDataRef data, CFErrorRef *outError);
