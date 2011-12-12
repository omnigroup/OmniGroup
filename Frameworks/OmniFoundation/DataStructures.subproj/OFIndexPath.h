// Copyright 2008-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>


@interface OFIndexPath : OFObject
{
    OFIndexPath *_parent;
    NSUInteger _index, _length;
}

+ (OFIndexPath *)emptyIndexPath;
+ (OFIndexPath *)indexPathWithIndex:(NSUInteger)anIndex;

- (OFIndexPath *)indexPathByAddingIndex:(NSUInteger)anIndex;
- (OFIndexPath *)indexPathByRemovingLastIndex;

- (NSUInteger)indexAtPosition:(NSUInteger)position;
- (NSUInteger)length;

- (void)getIndexes:(NSUInteger *)indexes;

- (NSComparisonResult)compare:(OFIndexPath *)otherObject;
- (NSComparisonResult)parentsLastCompare:(OFIndexPath *)otherObject;

@end
