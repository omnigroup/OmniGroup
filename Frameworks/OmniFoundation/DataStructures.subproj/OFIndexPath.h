// Copyright 2008-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>


@interface OFIndexPath : OFObject

+ (OFIndexPath *)emptyIndexPath;
+ (OFIndexPath *)indexPathWithIndex:(NSUInteger)anIndex;

- (OFIndexPath *)indexPathByAddingIndex:(NSUInteger)anIndex;
- (OFIndexPath *)indexPathByRemovingLastIndex;

- (NSUInteger)indexAtPosition:(NSUInteger)position;
- (NSUInteger)length;

- (void)getIndexes:(NSUInteger *)indexes;
- (void)enumerateIndexesUsingBlock:(void (^)(NSUInteger index, BOOL *stop))block;

- (NSComparisonResult)compare:(OFIndexPath *)otherObject;
- (NSComparisonResult)parentsLastCompare:(OFIndexPath *)otherObject;

@end
