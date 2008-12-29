// Copyright 1999-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFFastMutableData.h 68913 2005-10-03 19:36:19Z kc $

#import <Foundation/NSData.h>

@interface OFFastMutableData : NSMutableData
{
    OFFastMutableData   *_nextBlock;

    unsigned int         _realLength;
    void                *_realBytes;

    unsigned int         _currentLength;
    void                *_currentBytes;
}
+ (OFFastMutableData *) newFastMutableDataWithLength: (unsigned) length;

- (void) fillWithZeros;

// NSData methods
- (unsigned) length;
- (const void *) bytes;

// NSMutableData methods
- (void *) mutableBytes;


- (void) setStartingOffset: (unsigned) offset;
- (unsigned) startingOffset;

- (void) setLength: (unsigned) length;

@end
