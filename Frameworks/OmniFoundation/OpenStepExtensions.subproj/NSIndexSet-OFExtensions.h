// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$
//

#import <Foundation/NSIndexSet.h>

@interface NSIndexSet (OFExtensions)

- (NSString *)rangeString;
- initWithRangeString:(NSString *)aString;
+ indexSetWithRangeString:(NSString *)aString;

- (NSRange)rangeGreaterThanOrEqualToIndex:(NSUInteger)index;

- (BOOL)isEmpty;

@end

// A simple iterator over an NSIndexSet
#define OFForEachIndex(indexSetExpression, valueVar) NSIndexSet * valueVar ## _indexSet = (indexSetExpression); for(NSUInteger valueVar = [valueVar ## _indexSet firstIndex]; valueVar != NSNotFound; valueVar = [valueVar ## _indexSet indexGreaterThanIndex:valueVar])

// Similar, but progresses from the largest index to the smallest
#define OFForEachIndexReverse(indexSetExpression, valueVar) NSIndexSet * valueVar ## _indexSet = (indexSetExpression); for(NSUInteger valueVar = [valueVar ## _indexSet lastIndex]; valueVar != NSNotFound; valueVar = [valueVar ## _indexSet indexLessThanIndex:valueVar])

// A faster iterator which uses -getIndexes:... .
#define OFForEachIndexInRange_BufferSize 32
#define OFForEachIndexInRange(indexSetExpression, startIndex, lengthIndex, valueVar, loopBody) { NSIndexSet * valueVar ## _indexSet = (indexSetExpression); NSRange valueVar ## _searchRange = (NSRange){ startIndex, lengthIndex }; NSUInteger valueVar ## _indexCount; do { NSUInteger valueVar ## _indices[OFForEachIndexInRange_BufferSize]; valueVar ## _indexCount = [ (valueVar ## _indexSet) getIndexes: valueVar ## _indices maxCount: OFForEachIndexInRange_BufferSize inIndexRange: & (valueVar ## _searchRange) ]; for(NSUInteger valueVar ## _indexIndex = 0; valueVar ## _indexIndex < valueVar ## _indexCount; valueVar ## _indexIndex ++) { NSUInteger valueVar = valueVar ## _indices[valueVar ## _indexIndex]; loopBody ; } } while ( valueVar ## _indexCount == OFForEachIndexInRange_BufferSize ); }


#define OFForEachIndexFast(indexSetExpression, valueVar, loopBody) OFForEachIndexInRange(indexSetExpression, 0, NSUIntegerMax, loopBody)

