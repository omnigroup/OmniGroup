// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSRange-OFExtensions.h>

#import <XCTest/XCTest.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFRangeExtensionsTests : XCTestCase
@end

@implementation OFRangeExtensionsTests

#define CHECK(range, remove, expected) do { \
    NSRange result = OFRangeByRemovingRange(range, remove); \
    if (!NSEqualRanges(result, expected)) \
        XCTAssertEqualObjects(NSStringFromRange(result), NSStringFromRange(expected)); \
} while(0)

- (void)testEntirelyBefore;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(0, 1), NSMakeRange(9, 5));
}
- (void)testImmediatelyBefore;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(9, 1), NSMakeRange(9, 5));
}

- (void)testOverlapBeginning;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(9, 2), NSMakeRange(9, 4));
    CHECK(NSMakeRange(10, 5), NSMakeRange(0, 12), NSMakeRange(0, 3));
}

- (void)testStartInMiddleAndHitEnd;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(13, 2), NSMakeRange(10, 3));
}

- (void)testStartInMiddleAndExtendPastEnd;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(13, 10), NSMakeRange(10, 3));
}

- (void)testEquals;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(10, 5), NSMakeRange(10, 0));
}

- (void)testStartAtBeginningAndEndInMiddle;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(10, 2), NSMakeRange(10, 3));
}
- (void)testStartAtBeginningAndExtendPastEnd;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(10, 10), NSMakeRange(10, 0));
}

- (void)testStartAtEnd;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(15, 10), NSMakeRange(10, 5));
}

- (void)testEntirelyInMiddle;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(11, 2), NSMakeRange(10, 3));
}

- (void)testRemoveNothing;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(0, 0), NSMakeRange(10, 5)); // before
    CHECK(NSMakeRange(10, 5), NSMakeRange(10, 0), NSMakeRange(10, 5)); // at start
    CHECK(NSMakeRange(10, 5), NSMakeRange(12, 0), NSMakeRange(10, 5)); // middle
    CHECK(NSMakeRange(10, 5), NSMakeRange(15, 0), NSMakeRange(10, 5)); // at end
    CHECK(NSMakeRange(10, 5), NSMakeRange(20, 0), NSMakeRange(10, 5)); // after
}

- (void)testCompletlyOverlaps;
{
    CHECK(NSMakeRange(10, 5), NSMakeRange(5, 20), NSMakeRange(5, 0));
}

@end


