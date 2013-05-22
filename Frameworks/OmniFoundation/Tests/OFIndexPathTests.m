// Copyright 2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFIndexPath.h>
#import <OmniFoundation/NSArray-OFExtensions.h>

#import <SenTestingKit/SenTestingKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFIndexPathTests : SenTestCase
@end

@implementation OFIndexPathTests

- (void)testEmpty;
{
    OFIndexPath *path = [OFIndexPath emptyIndexPath];
    STAssertEquals([path length], 0UL, @"should be have length of 0");
    STAssertEqualObjects([path description], @"", @"should have empty description");
}

- (void)testSingleIndex;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:42];
    STAssertEquals([path length], 1UL, @"should be have length of 1");
    STAssertEqualObjects([path description], @"42", @"should have single component description");
}

- (void)testMultipleIndexes;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    
    STAssertEquals([path length], 3UL, @"should be have length of 3");
    STAssertEqualObjects([path description], @"1.2.3", @"should have multiple component description");
}

- (void)testRemoveLastIndex;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    path = [path indexPathByRemovingLastIndex];
    
    STAssertEquals([path length], 2UL, @"should be have length of 2");
    STAssertEqualObjects([path description], @"1.2", @"should have multiple component description");
}

- (void)testGetIndexes;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    
    NSUInteger indexes[3];
    [path getIndexes:indexes];
    STAssertEquals(indexes[0], 1UL, @"should first index");
    STAssertEquals(indexes[1], 2UL, @"should second index");
    STAssertEquals(indexes[2], 3UL, @"should third index");
}

- (void)testIndexAtPosition;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    
    STAssertEquals([path indexAtPosition:0], 1UL, @"should first index");
    STAssertEquals([path indexAtPosition:1], 2UL, @"should second index");
    STAssertEquals([path indexAtPosition:2], 3UL, @"should third index");
}

- (void)testCompareVsSame;
{
    OFIndexPath *empty = [OFIndexPath emptyIndexPath];
    STAssertEquals([empty compare:empty], NSOrderedSame, NULL);
    
    OFIndexPath *pathA = [OFIndexPath indexPathWithIndex:1];
    OFIndexPath *pathB = [OFIndexPath indexPathWithIndex:1];
    STAssertEquals([pathA compare:pathB], NSOrderedSame, NULL);
    
    STAssertEquals([[pathA indexPathByAddingIndex:2] compare:[pathB indexPathByAddingIndex:2]], NSOrderedSame, NULL);
}

- (void)testCompareVsEmpty;
{
    OFIndexPath *path1 = [OFIndexPath emptyIndexPath];
    OFIndexPath *path2 = [OFIndexPath indexPathWithIndex:42];
    
    STAssertEquals([path1 compare:path2], NSOrderedAscending, NULL);
    STAssertEquals([path2 compare:path1], NSOrderedDescending, NULL);
    
    STAssertEquals([path1 parentsLastCompare:path2], NSOrderedDescending, NULL);
    STAssertEquals([path2 parentsLastCompare:path1], NSOrderedAscending, NULL);
}

- (void)testCompareVsNonEmpty;
{
    OFIndexPath *path1 = [[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:2];
    OFIndexPath *path2 = [path1 indexPathByAddingIndex:3];
    
    STAssertEquals([path1 compare:path2], NSOrderedAscending, NULL);
    STAssertEquals([path2 compare:path1], NSOrderedDescending, NULL);
    
    STAssertEquals([path1 parentsLastCompare:path2], NSOrderedDescending, NULL);
    STAssertEquals([path2 parentsLastCompare:path1], NSOrderedAscending, NULL);
}

- (void)testComparisons;
{
    STAssertTrue([[OFIndexPath emptyIndexPath] compare:[OFIndexPath emptyIndexPath]] == NSOrderedSame, nil);
    STAssertTrue([[OFIndexPath indexPathWithIndex:1] compare:[OFIndexPath indexPathWithIndex:1]] == NSOrderedSame, nil);
    STAssertTrue([[[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:1] compare:[[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:1]] == NSOrderedSame, nil);
    
    STAssertTrue([[OFIndexPath emptyIndexPath] compare:[OFIndexPath indexPathWithIndex:1]] == NSOrderedAscending, nil);
    STAssertTrue([[OFIndexPath indexPathWithIndex:1] compare:[OFIndexPath indexPathWithIndex:2]] == NSOrderedAscending, nil);
    STAssertTrue([[OFIndexPath indexPathWithIndex:1] compare:[[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:1]] == NSOrderedAscending, nil);
    STAssertTrue([[[[[[[[[[[OFIndexPath indexPathWithIndex:10] indexPathByAddingIndex:9] indexPathByAddingIndex:8] indexPathByAddingIndex:7] indexPathByAddingIndex:6] indexPathByAddingIndex:5] indexPathByAddingIndex:4] indexPathByAddingIndex:3] indexPathByAddingIndex:2] indexPathByAddingIndex:1] compare:[OFIndexPath indexPathWithIndex:11]] == NSOrderedAscending, nil);
    
    STAssertTrue([[OFIndexPath indexPathWithIndex:1] compare:[OFIndexPath emptyIndexPath]] == NSOrderedDescending, nil);
    STAssertTrue([[OFIndexPath indexPathWithIndex:2] compare:[OFIndexPath indexPathWithIndex:1]] == NSOrderedDescending, nil);
    STAssertTrue([[[OFIndexPath indexPathWithIndex:1] indexPathByAddingIndex:1] compare:[OFIndexPath indexPathWithIndex:1]] == NSOrderedDescending, nil);
    STAssertTrue([[OFIndexPath indexPathWithIndex:11] compare:[[[[[[[[[[OFIndexPath indexPathWithIndex:10] indexPathByAddingIndex:9] indexPathByAddingIndex:8] indexPathByAddingIndex:7] indexPathByAddingIndex:6] indexPathByAddingIndex:5] indexPathByAddingIndex:4] indexPathByAddingIndex:3] indexPathByAddingIndex:2] indexPathByAddingIndex:1]] == NSOrderedDescending, nil);
    
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
    STAssertEqualObjects(sortedOriginalArray, sortedReversedArray, nil);
}


@end
