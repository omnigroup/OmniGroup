// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Content.subproj/OWDataStreamFilterCursor.h 68913 2005-10-03 19:36:19Z kc $

#import <OWF/OWDataStreamCursor.h>

@class NSMutableData;

@interface OWDataStreamFilterCursor : OWDataStreamCursor
{
    NSMutableData *bufferedData;
    unsigned int bufferedDataStart, bufferedDataValidLength;
    BOOL canFillMoreBuffer, haveStartedFilter;
}

// API

// Subclass' responsibility.
- (void)processBegin;
- (void)fillBuffer:(void *)buffer length:(unsigned)bufferLength filledToIndex:(unsigned *)bufferFullp;

// A concrete subclass of OWDataStreamFilterCursor must provide implementations for the following methods:
//    -fillBuffer:length:filledToIndex:
//    -underlyingDataStream
//    -scheduleInQueue:invocation:
//
// In addition, it might want to extend -processBegin to perform its own setup.

OWF_EXTERN NSString *OWDataStreamCursor_SeekExceptionName;

@end
