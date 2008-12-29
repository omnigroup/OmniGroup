// Copyright 2006-2007 Omni Development, Inc.  All rights reserved.
//
//  OFUnitValueTests.m
//  OmniFoundation
//
//  Copyright 2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//


#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <SenTestingKit/SenTestingKit.h>
#import <SenTestingKit/SenTestCase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniFoundation/OFDimensionedValue.h>
#import <OmniFoundation/OFUnit.h>
#import <OmniFoundation/OFUnits.h>

RCS_ID("$Id$");

@interface OFUnitValueTests : SenTestCase
{
}

@end


@implementation OFUnitValueTests

- (void)testDistanceParsing
{
    OFUnits *u = [OFUnits loadUnitsNamed:@"distance" inBundle:[NSBundle bundleForClass:[OFUnits class]]];
    OFDimensionedValue *a, *b, *c, *d, *e, *f, *g;
    OFUnit *meter, *kilometer, *point, *pica, *inch, *foot;
    
    a = [u parseString:@"1 km" defaultUnit:nil];
    STAssertTrue([[a dimension] hasName:@"kilometer"], @"");
    kilometer = [a dimension];
    STAssertEqualObjects([a value], [NSNumber numberWithInt:1], @"");
    STAssertEqualObjects([a value], [NSNumber numberWithFloat:1.0], @"");
    STAssertEqualObjects([u storageStringForValue:a], @"1 km", @"");
    
    b = [u parseString:@"1 m" defaultUnit:nil];
    STAssertTrue([[b dimension] hasName:@"m"], @"");
    meter = [b dimension];
    STAssertEqualObjects([b value], [NSNumber numberWithInt:1], @"");
    STAssertEqualObjects([b value], [NSNumber numberWithFloat:1.0], @"");
    STAssertEqualObjects([u storageStringForValue:b], @"1 m", @"");
    
    c = [u parseString:@"1 kilometer 1 meter" defaultUnit:nil];
    STAssertEqualObjects([u getValue:c inUnit:meter], [NSNumber numberWithInt:1001], @"");
    STAssertEqualObjects([u storageStringForValue:c], @"1001 m", @"");
    
    d = [u parseString:@"48 pt" defaultUnit:nil];
    point = [u unitFromString:@"point"];
    STAssertNotNil(point, @"");
    pica = [u unitFromString:@"pica"];
    STAssertNotNil(pica, @"");
    foot = [u unitFromString:@"feet"];
    STAssertNotNil(foot, @"");
    inch = [u unitFromString:@"inches"];
    STAssertNotNil(inch, @"");
    STAssertEqualObjects([u getValue:d inUnit:point], [NSNumber numberWithInt:48], @"");
    STAssertEqualObjects([u getValue:d inUnit:pica], [NSNumber numberWithInt:4], @"");
    STAssertEqualObjects([u getValue:d inUnit:inch], [NSNumber numberWithRatio:OFRationalInverse(OFRationalFromDouble(6./4.))], @"");
    
    e = [u parseString:@"2/3 foot" defaultUnit:nil];
    STAssertTrue([[e dimension] hasName:@"feet"], @"");
    STAssertEqualObjects([u getValue:e inUnit:inch], [NSNumber numberWithInt:8], @"");
    
    f = [u parseString:@"5' 2\"" defaultUnit:nil];
    STAssertEqualObjects([u getValue:f inUnit:inch], [NSNumber numberWithInt: 62 ], @"");  // and eyes of blue
    STAssertEqualObjects([u getValue:f inUnit:foot], [NSNumber numberWithRatio: 62:12 ], @"");
    
    g = [u parseString:@"-2/3" defaultUnit:pica];
    STAssertTrue([g dimension] == pica, @"");
    STAssertEqualObjects([u getValue:g inUnit:inch], [NSNumber numberWithRatio: -2:18 ], @"");
}

@end
