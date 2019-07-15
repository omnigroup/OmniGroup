// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWDataStreamProcessor.h>

@class OWDataStream;

@interface OWMultipartDataStreamProcessor : OWDataStreamProcessor
{
    unsigned char *delimiter;
    NSUInteger delimiterLength, inputBufferSize;
    NSUInteger delimiterSkipTable[256];
}

// This method is overridden by concrete subclasses
- (void)processDataStreamPart:(OWDataStream *)aDataStream headers:(OWHeaderDictionary *)partHeaders;

@end
