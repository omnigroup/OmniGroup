// Copyright 2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFIndexPath.h>

#import <SenTestingKit/SenTestingKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFIndexPathTests : SenTestCase
@end

@implementation OFIndexPathTests

- (void)testEmpty;
{
    OFIndexPath *path = [OFIndexPath emptyIndexPath];
    STAssertEquals([path length], 0ULL, @"should be have length of 0");
    STAssertEqualObjects([path description], @"", @"should have empty description");
}

- (void)testSingleIndex;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:42];
    STAssertEquals([path length], 1ULL, @"should be have length of 1");
    STAssertEqualObjects([path description], @"42", @"should have single component description");
}

- (void)testMultipleIndexes;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    
    STAssertEquals([path length], 3ULL, @"should be have length of 3");
    STAssertEqualObjects([path description], @"1.2.3", @"should have multiple component description");
}

- (void)testRemoveLastIndex;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    path = [path indexPathByRemovingLastIndex];
    
    STAssertEquals([path length], 2ULL, @"should be have length of 2");
    STAssertEqualObjects([path description], @"1.2", @"should have multiple component description");
}

- (void)testGetIndexes;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    
    NSUInteger indexes[3];
    [path getIndexes:indexes];
    STAssertEquals(indexes[0], 1ULL, @"should first index");
    STAssertEquals(indexes[1], 2ULL, @"should second index");
    STAssertEquals(indexes[2], 3ULL, @"should third index");
}

- (void)testIndexAtPosition;
{
    OFIndexPath *path = [OFIndexPath indexPathWithIndex:1];
    path = [path indexPathByAddingIndex:2];
    path = [path indexPathByAddingIndex:3];
    
    STAssertEquals([path indexAtPosition:0], 1ULL, @"should first index");
    STAssertEquals([path indexAtPosition:1], 2ULL, @"should second index");
    STAssertEquals([path indexAtPosition:2], 3ULL, @"should third index");
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

@end
