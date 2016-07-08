// Copyright 2013-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OmniBase.h>

#import "OFTestCase.h"

#import "OFOrderedMutableDictionary.h"

RCS_ID("$Id$");

@interface OFOrderedMutableDictionaryTest : OFTestCase

@end

@implementation OFOrderedMutableDictionaryTest

- (void)testKeyAtIndex;
{
    OFOrderedMutableDictionary<NSString *, NSNumber *> *dict = [OFOrderedMutableDictionary dictionaryWithObjectsAndKeys:@0, @"foo", @1, @"bar", nil];
    XCTAssertEqualObjects([dict keyAtIndex:0], @"foo", @"Expected to find key");
    XCTAssertEqualObjects([dict keyAtIndex:1], @"bar", @"Expected to find key");
    XCTAssertThrows([dict keyAtIndex:2], @"Expected asking for key beyond the count to throw");
}

- (void)testSetObjectWithKeyAndIndexOutOfBounds;
{
    OFOrderedMutableDictionary<NSString *, NSNumber *> *dict = [OFOrderedMutableDictionary dictionaryWithObjectsAndKeys:@0, @"foo", @1, @"bar", nil];
    XCTAssertThrows([dict setObject:@2 index:100 forKey:@"baz"], @"Expected exception inserting object past end of ordered dictionary");
}

- (void)testInitializers;
{
    OFOrderedMutableDictionary<NSString *, NSNumber *> *directInit = [[OFOrderedMutableDictionary alloc] init];
    XCTAssertNotNil(directInit);
    [directInit setObject:@1 forKey:@"foo"];
    
    OFOrderedMutableDictionary<NSString *, NSNumber *> *capacityInit = [[OFOrderedMutableDictionary alloc] initWithCapacity:1];
    XCTAssertNotNil(capacityInit);
    [capacityInit setObject:@1 forKey:@"foo"];
    
    OFOrderedMutableDictionary<NSString *, NSNumber *> *keyObjectInit = [[OFOrderedMutableDictionary alloc] initWithObjects:@[ @1 ] forKeys:@[ @"foo" ]];
    XCTAssertNotNil(keyObjectInit);
    
    XCTAssertEqualObjects(@1, directInit[@"foo"]);
    XCTAssertEqualObjects(@1, capacityInit[@"foo"]);
    XCTAssertEqualObjects(@1, keyObjectInit[@"foo"]);
}

@end
