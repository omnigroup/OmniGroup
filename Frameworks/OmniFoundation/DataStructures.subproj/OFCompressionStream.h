// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSStream.h>
#import <OmniFoundation/OFTransformStream.h>

#import <bzlib.h>

@interface OFBzip2DecompressTransform : NSObject <OFStreamTransformer>
{
    bz_stream bz2;
    BOOL streamInit;
    
    BOOL bzSmallSizeHint;
    int bzVerbosity;
    
    struct OFTransformStreamBuffer buf;
}

@end

@interface OFBzip2CompressTransform : NSObject <OFStreamTransformer>
{
    bz_stream bz2;

    short streamState;
    short bzCompressionLevel;
    short bzVerbosity;
    
    struct OFTransformStreamBuffer buf;
}

@end

@interface NSInputStream (OFStreamCompression)

@end

#if 0  // TODO
@interface NSOutputStream (OFStreamCompression)

@end
#endif

// Properties
OmniFoundation_EXTERN NSString * const OFStreamCompressionLevelKey;    // For gzip or bzip2 streams (0=fast, 9=thorough)
OmniFoundation_EXTERN NSString * const OFStreamBzipSmallSizeHintKey;
