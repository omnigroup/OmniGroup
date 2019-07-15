// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWDataStreamCursor.h>

@class NSMutableData;

@interface OWDataStreamFilterCursor : OWDataStreamCursor
{
    NSMutableData *bufferedData;
    NSUInteger bufferedDataStart, bufferedDataValidLength;
    BOOL canFillMoreBuffer, haveStartedFilter;
}

// API

// Subclass' responsibility.
- (void)processBegin;
- (void)fillBuffer:(void *)buffer length:(NSUInteger)bufferLength filledToIndex:(NSUInteger *)bufferFullp;

// A concrete subclass of OWDataStreamFilterCursor must provide implementations for the following methods:
//    -fillBuffer:length:filledToIndex:
//    -underlyingDataStream
//    -scheduleInQueue:invocation:
//
// In addition, it might want to extend -processBegin to perform its own setup.

extern NSString * const OWDataStreamCursor_SeekExceptionName;

@end
