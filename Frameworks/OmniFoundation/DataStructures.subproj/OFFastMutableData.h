// Copyright 1999-2005, 2010, 2012 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSData.h>

@interface OFFastMutableData : NSMutableData
{
    struct _OFFastMutableBuffer *_buffer;
}

+ (OFFastMutableData *)newFastMutableDataWithLength:(NSUInteger)length;

- (void)fillWithZeros;

- (void)setStartingOffset:(NSUInteger)offset;
- (NSUInteger)startingOffset;

@end
