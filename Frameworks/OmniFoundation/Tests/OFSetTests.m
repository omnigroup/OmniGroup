// Copyright 2005-2008, 2010, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

//
// OFSetTests.m - OmniFoundation unit tests
//

#import "OFTestCase.h"

#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFSetTests : OFTestCase
{
}
@end


@implementation OFSetTests

- (void)testSetFromArray
{
    NSArray *a;
    
    a = [NSArray arrayWithObjects:@"one", @"THREE", @"FOUR", @"five", @"two", @"three", @"four", @"Two", @"Three", @"Four", @"five", nil];
    XCTAssertEqualObjects([a setByPerformingSelector:@selector(lowercaseString)], ([NSSet setWithObjects:@"one", @"two", @"three", @"four", @"five", nil]));
    
    a = [NSArray arrayWithObjects:@"one", @"One", @"onE", @"oNe", @"OnE", nil];
    XCTAssertEqualObjects([a setByPerformingSelector:@selector(lowercaseString)], ([NSSet setWithObjects:@"one", nil]));
    
    a = [NSArray arrayWithObjects:@"One", @"onE", @"oNe", @"OnE", @"", nil];
    XCTAssertEqualObjects([a setByPerformingSelector:@selector(lowercaseString)], ([NSSet setWithObjects:@"one", @"", nil]));

    a = [NSArray arrayWithObjects:@"one", nil];
    XCTAssertEqualObjects([a setByPerformingSelector:@selector(lowercaseString)], ([NSSet setWithObjects:@"one", nil]));
    
    a = [NSArray array];
    XCTAssertEqualObjects([a setByPerformingSelector:@selector(lowercaseString)], [NSSet set]);
}

- (void)testSetFromSet
{
    NSSet *a;
    
    a = [NSSet setWithObjects:@"one", @"THREE", @"FOUR", @"five", @"two", @"three", @"four", @"Two", @"Three", @"Four", @"five", nil];
    XCTAssertEqualObjects([a setByPerformingSelector:@selector(lowercaseString)], ([NSSet setWithObjects:@"one", @"two", @"three", @"four", @"five", nil]));
    
    a = [NSSet setWithObjects:@"one", @"One", @"onE", @"oNe", @"OnE", nil];
    XCTAssertEqualObjects([a setByPerformingSelector:@selector(lowercaseString)], ([NSSet setWithObjects:@"one", nil]));
    
    a = [NSSet setWithObjects:@"one", @"One", @"", @"oNe", @"OnE", nil];
    XCTAssertEqualObjects([a setByPerformingSelector:@selector(lowercaseString)], ([NSSet setWithObjects:@"one", @"", nil]));
    
    a = [NSSet setWithObjects:@"one", nil];
    XCTAssertEqualObjects([a setByPerformingSelector:@selector(lowercaseString)], ([NSSet setWithObjects:@"one", nil]));
    
    a = [NSSet set];
    XCTAssertEqualObjects([a setByPerformingSelector:@selector(lowercaseString)], [NSSet set]);
}

- (void)testInsertionSort
{
    NSSet *a;
    
    a = [NSSet setWithObjects:@"one", @"THREE", @"FOUR", @"five", @"two", @"three", @"four", @"Two", @"Three", @"Four", @"five", nil];
    XCTAssertEqualObjects([a sortedArrayUsingSelector:@selector(compare:)], ([NSArray arrayWithObjects:@"FOUR", @"Four", @"THREE", @"Three", @"Two", @"five",@"four",  @"one", @"three", @"two", nil]));
    
    a = [NSSet setWithObjects:@"one", @"THREE", @"five", @"two", @"Two!", @"Thr33", @"Four", @"F!VE", @"ThR44", nil];
    XCTAssertEqualObjects([a sortedArrayUsingSelector:@selector(compare:)], ([NSArray arrayWithObjects:@"F!VE", @"Four", @"THREE", @"ThR44", @"Thr33", @"Two!", @"five", @"one", @"two", nil]));
    XCTAssertEqualObjects([a sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)], ([NSArray arrayWithObjects:@"F!VE", @"five", @"Four", @"one", @"Thr33", @"ThR44", @"THREE", @"two", @"Two!", nil]));
    
    a = [NSSet setWithObjects:@"one", @"One", @"", @"oNe", @"OnE", nil];
    XCTAssertEqualObjects([a sortedArrayUsingSelector:@selector(compare:)], ([NSArray arrayWithObjects:@"", @"OnE", @"One", @"oNe", @"one", nil]));
    
    a = [NSSet setWithObjects:@"one", @"", nil];
    XCTAssertEqualObjects([a sortedArrayUsingSelector:@selector(compare:)], ([NSArray arrayWithObjects:@"", @"one", nil]));
    
    a = [NSSet setWithObjects:@"one", nil];
    XCTAssertEqualObjects([a sortedArrayUsingSelector:@selector(compare:)], ([NSArray arrayWithObjects:@"one", nil]));
    
    a = [NSSet set];
    XCTAssertEqualObjects([a sortedArrayUsingSelector:@selector(compare:)], [NSArray array]);
}

- (void)testInsertionSortRandom
{
    int trial;
    unsigned setsize, setbase;
    
    for(trial = 0; trial < 100; trial ++) {
        if (trial < 10)
            setsize = 213;
        else if (trial < 25)
            setsize = 110;
        else
            setsize = 17;
        
        setbase = ( trial % 5 ) * 71;
                
        NSMutableArray *numbers = [[NSMutableArray alloc] initWithCapacity:setsize];
        unsigned n, c;
        for(n = setbase; n < setbase + setsize; n ++)
            [numbers addObject:[NSNumber numberWithInt:n]];
        
        c = 0;
        NSMutableSet *fillMe = [NSMutableSet set];
        while ([fillMe count] < setsize) {
            [fillMe addObject:[NSNumber numberWithInteger: setbase + (OFRandomNext32() % setsize)]];
            c ++;
            if (c > 100000) {
                NSLog(@"*** %s:%d: aborting after %u random numbers", __FILE__, __LINE__, c);
                break;
            }
        }
        
        XCTAssertEqualObjects([fillMe sortedArrayUsingSelector:@selector(compare:)], numbers,
                              @"Trial %d: setsize=%u (%u probes), setbase=%u", trial, setsize, c, setbase);
        
    }
}

@end

