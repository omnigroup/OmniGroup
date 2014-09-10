// Copyright 2008, 2012-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSIndexSet-OFExtensions.h>

#import <XCTest/XCTest.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFIndexSetTests : XCTestCase
{
}

@end

@implementation OFIndexSetTests

- (void)testEmptySets
{
    NSString *r = [[NSIndexSet indexSet] rangeString];
    XCTAssertEqualObjects(r, @"");
    
    NSIndexSet *empty = [[NSIndexSet alloc] initWithRangeString:@""];
    XCTAssertEqual([empty count], (NSUInteger)0);
    XCTAssertEqual([empty firstIndex], (NSUInteger)NSNotFound);

    empty = [[NSMutableIndexSet alloc] initWithRangeString:@""];
    XCTAssertEqual([empty count], (NSUInteger)0);
    XCTAssertEqual([empty firstIndex], (NSUInteger)NSNotFound);
    XCTAssertTrue([empty isKindOfClass:[NSMutableIndexSet class]]);
}

- (void)testIsolatedIndices
{
    NSUInteger ix;
    
    for(ix = 0; ix < 10; ix ++) {
        NSIndexSet *orig = [[NSIndexSet alloc] initWithIndex:ix];
        NSString *r = [orig rangeString];
        
        XCTAssertEqualObjects(r, ([NSString stringWithFormat:@"%lu", ix]));
        
        NSIndexSet *roundtrip1 = [[NSIndexSet alloc] initWithRangeString:r];
        XCTAssertEqual([roundtrip1 count], (NSUInteger)1);
        XCTAssertEqualObjects(roundtrip1, orig);
        XCTAssertEqual([roundtrip1 lastIndex], ix);
        
        NSMutableIndexSet *roundtrip2 = [[NSMutableIndexSet alloc] initWithRangeString:r];
        XCTAssertEqual([roundtrip2 count], (NSUInteger)1);
        XCTAssertEqualObjects(roundtrip2, orig);
        XCTAssertTrue([roundtrip2 isKindOfClass:[NSMutableIndexSet class]]);
        
    }
}

- (void)testSimpleRange
{
    NSRange aRange;
    
    for(aRange.location = 0; aRange.location < 3; aRange.location ++) {
        for (aRange.length = 2; aRange.length < 5; aRange.length ++) {
            NSIndexSet *st = [[NSIndexSet alloc] initWithIndexesInRange:aRange];
            NSString *rs = [NSString stringWithFormat:@"%lu-%lu", aRange.location, aRange.location + aRange.length - 1];
            
            XCTAssertEqualObjects([st rangeString], rs);
            XCTAssertEqualObjects([NSIndexSet indexSetWithRangeString:rs], st);
            
        }
    }
}

- (void)testComplexRange
{
    NSUInteger starts[4] = { 0, 1, 2, 1023 };
    NSUInteger gaps[4] = { 1, 2, 3, 64 };
    int startIx, gapIx, len;
    
    for(startIx = 0; startIx < 4; startIx ++) {
        for(gapIx = 0; gapIx < 4; gapIx ++) {
            for(len = 1; len < 515; len ++) {
                NSMutableString *buf = [NSMutableString string];
                if (len == 1)
                    [buf appendFormat:@"%lu,%lu", starts[startIx], starts[startIx] + 1 + gaps[gapIx]];
                else
                    [buf appendFormat:@"%lu-%lu,%lu-%lu",
                     starts[startIx], starts[startIx] + len - 1,
                     starts[startIx] + len + gaps[gapIx], starts[startIx] + len + gaps[gapIx] + len - 1];
                
                NSMutableIndexSet *st = [[NSMutableIndexSet alloc] init];
                [st addIndexesInRange:(NSRange){ starts[startIx], len }];
                [st addIndexesInRange:(NSRange){ starts[startIx] + len + gaps[gapIx], len }];
                
                XCTAssertEqualObjects([st rangeString], buf);
                
                NSIndexSet *ris = [NSIndexSet indexSetWithRangeString:buf];
                XCTAssertEqualObjects(ris, st);
                XCTAssertEqual([ris count], (NSUInteger)(2 * len));
                
                [buf appendFormat:@",%lu", starts[startIx] + len + gaps[gapIx] + len + 1];
                [st addIndex:starts[startIx] + len + gaps[gapIx] + len + 1];
                
                XCTAssertEqualObjects([st rangeString], buf);
                
                ris = [NSIndexSet indexSetWithRangeString:buf];
                XCTAssertEqualObjects(ris, st);
                XCTAssertEqual([ris count], (NSUInteger)(2 * len + 1));
            }
        }
    }
    
}

@end


