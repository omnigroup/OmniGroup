// Copyright 2004-2006, 2008, 2010, 2013-2014, 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniBase/rcsid.h>
#import <OmniFoundation/OFVersionNumber.h>

@interface OFVersionNumberTest : OFTestCase
@end

@implementation OFVersionNumberTest

- (void)testVPrefix;
{
    OFVersionNumber *vn;

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2"];
    XCTAssertTrue(vn != nil);
    XCTAssertTrue([vn componentCount] == 2);
    XCTAssertTrue([vn componentAtIndex:0] == 1);
    XCTAssertTrue([vn componentAtIndex:1] == 2);

    vn = [[OFVersionNumber alloc] initWithVersionString:@"V1.2"];
    XCTAssertTrue(vn != nil);
    XCTAssertTrue([vn componentCount] == 2);
    XCTAssertTrue([vn componentAtIndex:0] == 1);
    XCTAssertTrue([vn componentAtIndex:1] == 2);

    vn = [[OFVersionNumber alloc] initWithVersionString:@"vv1.2"];
    XCTAssertTrue(vn == nil); // Only one 'v' allowed
}

- (void)testIgnoringCruftAtEnd;
{
    OFVersionNumber *vn;

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2xyz"];
    XCTAssertTrue(vn != nil);
    XCTAssertTrue([vn componentCount] == 2);
    XCTAssertTrue([vn componentAtIndex:0] == 1);
    XCTAssertTrue([vn componentAtIndex:1] == 2);

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2.xyz"];
    XCTAssertTrue(vn != nil);
    XCTAssertTrue([vn componentCount] == 2);
    XCTAssertTrue([vn componentAtIndex:0] == 1);
    XCTAssertTrue([vn componentAtIndex:1] == 2);

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2 xyz"];
    XCTAssertTrue(vn != nil);
    XCTAssertTrue([vn componentCount] == 2);
    XCTAssertTrue([vn componentAtIndex:0] == 1);
    XCTAssertTrue([vn componentAtIndex:1] == 2);

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2."];
    XCTAssertTrue(vn != nil);
    XCTAssertTrue([vn componentCount] == 2);
    XCTAssertTrue([vn componentAtIndex:0] == 1);
    XCTAssertTrue([vn componentAtIndex:1] == 2);
}

- (void)testInvalid;
{
    XCTAssertNil([[OFVersionNumber alloc] initWithVersionString:@""]);
    XCTAssertNil([[OFVersionNumber alloc] initWithVersionString:@"v"]);
    XCTAssertNil([[OFVersionNumber alloc] initWithVersionString:@"v."]);
    XCTAssertNil([[OFVersionNumber alloc] initWithVersionString:@".1"]);
    XCTAssertNil([[OFVersionNumber alloc] initWithVersionString:@"-.1"]);
    XCTAssertNil([[OFVersionNumber alloc] initWithVersionString:@" v1"]); // We don't allow leading whitespace right now; maybe we should
}

- (void)testVersionStrings;
{
    OFVersionNumber *vn;

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2xyz"];
    XCTAssertEqualObjects([vn originalVersionString], @"v1.2xyz");
    XCTAssertEqualObjects([vn cleanVersionString], @"1.2");
}

- (void)testComparison;
{
    OFVersionNumber *a, *b;

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    XCTAssertTrue([a compareToVersionNumber:b] == NSOrderedSame);
    XCTAssertTrue([b compareToVersionNumber:a] == NSOrderedSame);

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.0"];
    XCTAssertTrue([a compareToVersionNumber:b] == NSOrderedSame);
    XCTAssertTrue([b compareToVersionNumber:a] == NSOrderedSame);

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.0.0"];
    XCTAssertTrue([a compareToVersionNumber:b] == NSOrderedSame);
    XCTAssertTrue([b compareToVersionNumber:a] == NSOrderedSame);

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1.0"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.0.0"];
    XCTAssertTrue([a compareToVersionNumber:b] == NSOrderedSame);
    XCTAssertTrue([b compareToVersionNumber:a] == NSOrderedSame);

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"2"];
    XCTAssertTrue([a compareToVersionNumber:b] == NSOrderedAscending);
    XCTAssertTrue([b compareToVersionNumber:a] == NSOrderedDescending);

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.1"];
    XCTAssertTrue([a compareToVersionNumber:b] == NSOrderedAscending);
    XCTAssertTrue([b compareToVersionNumber:a] == NSOrderedDescending);
    
    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.1.0"];
    XCTAssertTrue([a compareToVersionNumber:b] == NSOrderedAscending);
    XCTAssertTrue([b compareToVersionNumber:a] == NSOrderedDescending);
    
    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.0.1"];
    XCTAssertTrue([a compareToVersionNumber:b] == NSOrderedAscending);
    XCTAssertTrue([b compareToVersionNumber:a] == NSOrderedDescending);
    
    // OBS #35289
    a = [[OFVersionNumber alloc] initWithVersionString:@"121"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"121.1"];
    XCTAssertTrue([a compareToVersionNumber:b] == NSOrderedAscending);
    XCTAssertTrue([b compareToVersionNumber:a] == NSOrderedDescending);
}

@end
