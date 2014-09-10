// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import "OFMutableBijection.h"

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFMutableBijectionTests : OFTestCase
@end

@implementation OFMutableBijectionTests

- (void)testAddingObject;
{
    OFMutableBijection *bijection = [OFMutableBijection bijection];
    
    [bijection setObject:@"bar" forKey:@"foo"];
    
    XCTAssertEqual((NSUInteger)1, [bijection count], @"Bijection added wrong number of objects");
    XCTAssertEqualObjects(@"bar", [bijection objectForKey:@"foo"], @"Bijection added object value for key");
}

- (void)testReplacingObject;
{
    OFMutableBijection *bijection = [OFMutableBijection bijectionWithObject:@"bar" forKey:@"foo"];
    
    [bijection setObject:@"baz" forKey:@"foo"];
    
    XCTAssertEqual((NSUInteger)1, [bijection count], @"Bijection unexpectedly changed number of objects");
    XCTAssertEqualObjects(@"baz", [bijection objectForKey:@"foo"], @"Bijection set wrong object for key");
}

- (void)testRemovingObject;
{
    OFMutableBijection *bijection = [OFMutableBijection bijectionWithObject:@"bar" forKey:@"foo"];
    
    [bijection setObject:nil forKey:@"foo"];
    
    XCTAssertEqual((NSUInteger)0, [bijection count], @"Bijection removed wrong number of objects");
    XCTAssertNil([bijection objectForKey:@"foo"], @"Bijection failed to remove object for key");
}

- (void)testInvert;
{
    OFMutableBijection *bijection = [OFMutableBijection bijectionWithObject:@"bar" forKey:@"foo"];
    
    [bijection invert];
    
    XCTAssertEqualObjects(@"foo", [bijection objectForKey:@"bar"], @"Bijection did not maintain key-object mapping through inversion");
}

@end
