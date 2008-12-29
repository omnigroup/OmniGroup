// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFSparseArray.h 104581 2008-09-06 21:18:23Z kc $

#import <OmniFoundation/OFObject.h>

@class NSArray, NSMutableArray;

@interface OFSparseArray : OFObject
{
    NSMutableArray *values;
    unsigned int valuesLength;
    id defaultValue;
}

- initWithCapacity:(NSUInteger)aCapacity;
- (unsigned int)count;
- (id)objectAtIndex:(unsigned int)anIndex;
- (void)setObject:(id)anObject atIndex:(unsigned int)anIndex;
- (void)setDefaultValue:(id)aDefaultValue;
- (NSArray *)valuesArray;

@end
