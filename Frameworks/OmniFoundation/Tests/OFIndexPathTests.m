// Copyright 2013-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFIndexPath.h>
#import <OmniFoundation/NSArray-OFExtensions.h>

#import <XCTest/XCTest.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFIndexPathTests : XCTestCase
@end

@implementation OFIndexPathTests

- (void)testEmpty;
{
    OFIndexPath *path = [OFIndexPath emptyIndexPath];
    XCTAssertEqual([path length], 0UL, @"should be have length of 0");
    XCTAssertEqualObjects([path description], @"", @"should have empty description");

    [path enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        XCTAssertFalse(YES, @"block shouldn't get called");
    }];
}

- (void)testSingleIndex;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:42];
    XCTAssertEqual([path length], 1UL, @"should be have length of 1");
    XCTAssertEqualObjects([path description], @"42", @"should have single component description");

    [path enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        XCTAssertEqual(range.location, 42, @"should have single range");
        XCTAssertEqual(range.length, 1, @"should have single range");
    }];
}

- (void)testMultipleIndexes;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    
    XCTAssertEqual([path length], 3UL, @"should be have length of 3");
    XCTAssertEqualObjects([path description], @"1.2.3", @"should have multiple component description");

    [path enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        XCTAssertEqual(range.location, 1, @"should have single range");
        XCTAssertEqual(range.length, 3, @"should have single range");
    }];
}

- (void)testRemoveLastIndex;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    path = [path indexPathByRemovingLastIndex];
    
    XCTAssertEqual([path length], 2UL, @"should be have length of 2");
    XCTAssertEqualObjects([path description], @"1.2", @"should have multiple component description");

    [path enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        XCTAssertEqual(range.location, 1, @"should have single range");
        XCTAssertEqual(range.length, 2, @"should have single range");
    }];
}

- (void)testGetIndexes;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    
    NSUInteger indexes[3];
    [path getIndexes:indexes];
    XCTAssertEqual(indexes[0], 1UL, @"should first index");
    XCTAssertEqual(indexes[1], 2UL, @"should second index");
    XCTAssertEqual(indexes[2], 3UL, @"should third index");
}

- (void)testIndexAtPosition;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    
    XCTAssertEqual([path indexAtPosition:0], 1UL, @"should first index");
    XCTAssertEqual([path indexAtPosition:1], 2UL, @"should second index");
    XCTAssertEqual([path indexAtPosition:2], 3UL, @"should third index");
}

- (void)testCompareVsSame;
{
    OFIndexPath *empty = [OFIndexPath emptyIndexPath];
    XCTAssertEqual([empty compare:empty], NSOrderedSame);
    
    OFIndexPath *pathA = [OFIndexPath indexPathWithIndex:1];
    OFIndexPath *pathB = [OFIndexPath indexPathWithIndex:1];
    XCTAssertEqual([pathA compare:pathB], NSOrderedSame);
    
    XCTAssertEqual([[pathA indexPathByAddingIndex:2] compare:[pathB indexPathByAddingIndex:2]], NSOrderedSame);
}

- (void)testCompareVsEmpty;
{
    OFIndexPath *path1 = [OFIndexPath emptyIndexPath];
    OFIndexPath *path2 = [OFIndexPath indexPathWithIndex:42];
    
    XCTAssertEqual([path1 compare:path2], NSOrderedAscending);
    XCTAssertEqual([path2 compare:path1], NSOrderedDescending);
    
    XCTAssertEqual([path1 parentsLastCompare:path2], NSOrderedDescending);
    XCTAssertEqual([path2 parentsLastCompare:path1], NSOrderedAscending);
}

- (void)testCompareVsNonEmpty;
{
    OFIndexPath *path1 = [[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:2];
    OFIndexPath *path2 = [path1 indexPathByAddingIndex:3];
    
    XCTAssertEqual([path1 compare:path2], NSOrderedAscending);
    XCTAssertEqual([path2 compare:path1], NSOrderedDescending);
    
    XCTAssertEqual([path1 parentsLastCompare:path2], NSOrderedDescending);
    XCTAssertEqual([path2 parentsLastCompare:path1], NSOrderedAscending);
}

- (void)testComparisons;
{
    XCTAssertTrue([[OFIndexPath emptyIndexPath] compare:[OFIndexPath emptyIndexPath]] == NSOrderedSame);
    XCTAssertTrue([[OFIndexPath indexPathWithIndex:1] compare:[OFIndexPath indexPathWithIndex:1]] == NSOrderedSame);
    XCTAssertTrue([[[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:1] compare:[[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:1]] == NSOrderedSame);
    
    XCTAssertTrue([[OFIndexPath emptyIndexPath] compare:[OFIndexPath indexPathWithIndex:1]] == NSOrderedAscending);
    XCTAssertTrue([[OFIndexPath indexPathWithIndex:1] compare:[OFIndexPath indexPathWithIndex:2]] == NSOrderedAscending);
    XCTAssertTrue([[OFIndexPath indexPathWithIndex:1] compare:[[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:1]] == NSOrderedAscending);
    XCTAssertTrue([[[[[[[[[[[OFIndexPath indexPathWithIndex:10] indexPathByAddingIndex:9] indexPathByAddingIndex:8] indexPathByAddingIndex:7] indexPathByAddingIndex:6] indexPathByAddingIndex:5] indexPathByAddingIndex:4] indexPathByAddingIndex:3] indexPathByAddingIndex:2] indexPathByAddingIndex:1] compare:[OFIndexPath indexPathWithIndex:11]] == NSOrderedAscending);
    
    XCTAssertTrue([[OFIndexPath indexPathWithIndex:1] compare:[OFIndexPath emptyIndexPath]] == NSOrderedDescending);
    XCTAssertTrue([[OFIndexPath indexPathWithIndex:2] compare:[OFIndexPath indexPathWithIndex:1]] == NSOrderedDescending);
    XCTAssertTrue([[[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:1] compare:[OFIndexPath indexPathWithIndex:1]] == NSOrderedDescending);
    XCTAssertTrue([[OFIndexPath indexPathWithIndex:11] compare:[[[[[[[[[[OFIndexPath indexPathWithIndex:10] indexPathByAddingIndex:9] indexPathByAddingIndex:8] indexPathByAddingIndex:7] indexPathByAddingIndex:6] indexPathByAddingIndex:5] indexPathByAddingIndex:4] indexPathByAddingIndex:3] indexPathByAddingIndex:2] indexPathByAddingIndex:1]] == NSOrderedDescending);
    
    NSArray *originalArray = [NSArray arrayWithObjects:
                              [OFIndexPath emptyIndexPath],
                              [OFIndexPath emptyIndexPath],
                              [OFIndexPath indexPathWithIndex:1],
                              [[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:1],
                              [[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:2],
                              [OFIndexPath indexPathWithIndex:2],
                              [[OFIndexPath indexPathWithIndex:2] indexPathByAddingIndex:1],
                              [[OFIndexPath indexPathWithIndex:2] indexPathByAddingIndex:2],
                              [OFIndexPath indexPathWithIndex:3],
                              [OFIndexPath indexPathWithIndex:10],
                              [[[[[[[[[[OFIndexPath indexPathWithIndex:10] indexPathByAddingIndex:9] indexPathByAddingIndex:8] indexPathByAddingIndex:7] indexPathByAddingIndex:6] indexPathByAddingIndex:5] indexPathByAddingIndex:4] indexPathByAddingIndex:3] indexPathByAddingIndex:2] indexPathByAddingIndex:1],
                              [OFIndexPath indexPathWithIndex:11],
                              nil];
    NSArray *reversedArray = [originalArray reversedArray];
    NSArray *sortedOriginalArray = [originalArray sortedArrayUsingSelector:@selector(compare:)];
    NSArray *sortedReversedArray = [reversedArray sortedArrayUsingSelector:@selector(compare:)];
#ifdef DEBUG_kc
    NSLog(@"originalArray = %@, reversedArray = %@, sortedOriginalArray = %@, sortedReversedArray = %@", originalArray, reversedArray, sortedOriginalArray, sortedReversedArray);
#endif
    XCTAssertEqualObjects(sortedOriginalArray, sortedReversedArray);
}

- (void)testPlistSerialization;
{
    NSUInteger indexes[] = {1, 3, 5, 7, 9, 11};
    OFIndexPath *indexPath = [OFIndexPath emptyIndexPath];

    for (NSUInteger i = 0; i < sizeof(indexes)/sizeof(NSUInteger); i++) {
        indexPath = [indexPath indexPathByAddingIndex:indexes[i]];
    }
    
    id plist = indexPath.propertyListRepresentation;
    OFIndexPath *deserializedPath = [OFIndexPath indexPathWithPropertyListRepresentation:plist];
    XCTAssertEqualObjects(indexPath, deserializedPath);
}

@end
