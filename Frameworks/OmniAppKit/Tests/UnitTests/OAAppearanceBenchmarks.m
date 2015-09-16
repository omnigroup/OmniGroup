// Copyright 2014-2015 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <XCTest/XCTest.h>
#import "OAAppearanceTestBaseline.h"

#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

extern uint64_t dispatch_benchmark(size_t count, void (^block)(void));

static uint64_t OAAppearanceBenchmarkIterations = 1000000;

@interface OAAppearanceBenchmarks : XCTestCase
@end

@implementation OAAppearanceBenchmarks

- (void)testDynamicAccessorCaching_Float;
{
    OAAppearanceTestBaseline *appearance = [OAAppearanceTestBaseline appearance];
    
    uint64_t keyPathNanoseconds = dispatch_benchmark(OAAppearanceBenchmarkIterations, ^{
        [appearance CGFloatForKeyPath:OAAppearanceTestBaselineTopLevelLeafKey];
    });
    
    uint64_t dynamicAccessorNanoseconds = dispatch_benchmark(OAAppearanceBenchmarkIterations, ^{
        [appearance TopLevelFloat];
    });
    
    XCTAssertTrue(dynamicAccessorNanoseconds < keyPathNanoseconds, @"Expected caching to improve speed of dynamic accessors (%lluns) relative to key-path methods (%lluns)", dynamicAccessorNanoseconds, keyPathNanoseconds);
}

- (void)testDynamicAccessorCaching_EdgeInsets;
{
    OAAppearanceTestBaseline *appearance = [OAAppearanceTestBaseline appearance];
    
    uint64_t keyPathNanoseconds = dispatch_benchmark(OAAppearanceBenchmarkIterations, ^{
        [appearance edgeInsetsForKeyPath:OAAppearanceTestBaselineEdgeInsetKey];
    });
    
    uint64_t dynamicAccessorNanoseconds = dispatch_benchmark(OAAppearanceBenchmarkIterations, ^{
        [appearance EdgeInsets];
    });
    
    XCTAssertTrue(dynamicAccessorNanoseconds < keyPathNanoseconds, @"Expected caching to improve speed of dynamic accessors (%lluns) relative to key-path methods (%lluns)", dynamicAccessorNanoseconds, keyPathNanoseconds);
}

- (void)testDynamicAccessorCaching_Color;
{
    OAAppearanceTestBaseline *appearance = [OAAppearanceTestBaseline appearance];
    
    uint64_t keyPathNanoseconds = dispatch_benchmark(OAAppearanceBenchmarkIterations, ^{
        [appearance colorForKeyPath:OAAppearanceTestBaselineColorKey];
    });
    
    uint64_t dynamicAccessorNanoseconds = dispatch_benchmark(OAAppearanceBenchmarkIterations, ^{
        [appearance Color];
    });
    
    XCTAssertTrue(dynamicAccessorNanoseconds < keyPathNanoseconds, @"Expected caching to improve speed of dynamic accessors (%lluns) relative to key-path methods (%lluns)", dynamicAccessorNanoseconds, keyPathNanoseconds);
}

@end
