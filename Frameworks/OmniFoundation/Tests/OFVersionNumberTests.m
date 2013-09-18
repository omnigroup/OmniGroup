// Copyright 2004-2006, 2008, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniBase/rcsid.h>
#import <OmniFoundation/OFVersionNumber.h>

RCS_ID("$Id$");

@interface OFVersionNumberTest : OFTestCase
@end

@implementation OFVersionNumberTest

- (void)testVPrefix;
{
    OFVersionNumber *vn;

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2"];
    should(vn != nil);
    should([vn componentCount] == 2);
    should([vn componentAtIndex:0] == 1);
    should([vn componentAtIndex:1] == 2);

    vn = [[OFVersionNumber alloc] initWithVersionString:@"V1.2"];
    should(vn != nil);
    should([vn componentCount] == 2);
    should([vn componentAtIndex:0] == 1);
    should([vn componentAtIndex:1] == 2);

    vn = [[OFVersionNumber alloc] initWithVersionString:@"vv1.2"];
    should(vn == nil); // Only one 'v' allowed
}

- (void)testIgnoringCruftAtEnd;
{
    OFVersionNumber *vn;

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2xyz"];
    should(vn != nil);
    should([vn componentCount] == 2);
    should([vn componentAtIndex:0] == 1);
    should([vn componentAtIndex:1] == 2);

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2.xyz"];
    should(vn != nil);
    should([vn componentCount] == 2);
    should([vn componentAtIndex:0] == 1);
    should([vn componentAtIndex:1] == 2);

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2 xyz"];
    should(vn != nil);
    should([vn componentCount] == 2);
    should([vn componentAtIndex:0] == 1);
    should([vn componentAtIndex:1] == 2);

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2."];
    should(vn != nil);
    should([vn componentCount] == 2);
    should([vn componentAtIndex:0] == 1);
    should([vn componentAtIndex:1] == 2);
}

- (void)testInvalid;
{
    shouldBeEqual([[OFVersionNumber alloc] initWithVersionString:@""], nil);
    shouldBeEqual([[OFVersionNumber alloc] initWithVersionString:@"v"], nil);
    shouldBeEqual([[OFVersionNumber alloc] initWithVersionString:@"v."], nil);
    shouldBeEqual([[OFVersionNumber alloc] initWithVersionString:@".1"], nil);
    shouldBeEqual([[OFVersionNumber alloc] initWithVersionString:@"-.1"], nil);
    shouldBeEqual([[OFVersionNumber alloc] initWithVersionString:@" v1"], nil); // We don't allow leading whitespace right now; maybe we should
}

- (void)testVersionStrings;
{
    OFVersionNumber *vn;

    vn = [[OFVersionNumber alloc] initWithVersionString:@"v1.2xyz"];
    shouldBeEqual([vn originalVersionString], @"v1.2xyz");
    shouldBeEqual([vn cleanVersionString], @"1.2");
}

- (void)testComparison;
{
    OFVersionNumber *a, *b;

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    should([a compareToVersionNumber:b] == NSOrderedSame);
    should([b compareToVersionNumber:a] == NSOrderedSame);

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.0"];
    should([a compareToVersionNumber:b] == NSOrderedSame);
    should([b compareToVersionNumber:a] == NSOrderedSame);

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.0.0"];
    should([a compareToVersionNumber:b] == NSOrderedSame);
    should([b compareToVersionNumber:a] == NSOrderedSame);

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1.0"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.0.0"];
    should([a compareToVersionNumber:b] == NSOrderedSame);
    should([b compareToVersionNumber:a] == NSOrderedSame);

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"2"];
    should([a compareToVersionNumber:b] == NSOrderedAscending);
    should([b compareToVersionNumber:a] == NSOrderedDescending);

    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.1"];
    should([a compareToVersionNumber:b] == NSOrderedAscending);
    should([b compareToVersionNumber:a] == NSOrderedDescending);
    
    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.1.0"];
    should([a compareToVersionNumber:b] == NSOrderedAscending);
    should([b compareToVersionNumber:a] == NSOrderedDescending);
    
    //
    a = [[OFVersionNumber alloc] initWithVersionString:@"1"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"1.0.1"];
    should([a compareToVersionNumber:b] == NSOrderedAscending);
    should([b compareToVersionNumber:a] == NSOrderedDescending);
    
    // OBS #35289
    a = [[OFVersionNumber alloc] initWithVersionString:@"121"];
    b = [[OFVersionNumber alloc] initWithVersionString:@"121.1"];
    should([a compareToVersionNumber:b] == NSOrderedAscending);
    should([b compareToVersionNumber:a] == NSOrderedDescending);
}

@end
