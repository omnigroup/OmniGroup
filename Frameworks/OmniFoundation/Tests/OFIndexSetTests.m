// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSIndexSet-OFExtensions.h>

#import <SenTestingKit/SenTestingKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFIndexSetTests : SenTestCase
{
}

@end

@implementation OFIndexSetTests

- (void)testEmptySets
{
    NSString *r = [[NSIndexSet indexSet] rangeString];
    STAssertEqualObjects(r, @"", nil);
    
    NSIndexSet *empty = [[NSIndexSet alloc] initWithRangeString:@""];
    STAssertEquals([empty count], (NSUInteger)0, nil);
    STAssertEquals([empty firstIndex], (NSUInteger)NSNotFound, nil);
    [empty release];

    empty = [[NSMutableIndexSet alloc] initWithRangeString:@""];
    STAssertEquals([empty count], (NSUInteger)0, nil);
    STAssertEquals([empty firstIndex], (NSUInteger)NSNotFound, nil);
    STAssertTrue([empty isKindOfClass:[NSMutableIndexSet class]], nil);
    [empty release];
}

- (void)testIsolatedIndices
{
    NSUInteger ix;
    
    for(ix = 0; ix < 10; ix ++) {
        NSIndexSet *orig = [[NSIndexSet alloc] initWithIndex:ix];
        NSString *r = [orig rangeString];
        
        STAssertEqualObjects(r, ([NSString stringWithFormat:@"%u", ix]), nil);
        
        NSIndexSet *roundtrip1 = [[NSIndexSet alloc] initWithRangeString:r];
        STAssertEquals([roundtrip1 count], (NSUInteger)1, nil);
        STAssertEqualObjects(roundtrip1, orig, nil);
        STAssertEquals([roundtrip1 lastIndex], ix, nil);
        
        NSMutableIndexSet *roundtrip2 = [[NSMutableIndexSet alloc] initWithRangeString:r];
        STAssertEquals([roundtrip2 count], (NSUInteger)1, nil);
        STAssertEqualObjects(roundtrip2, orig, nil);
        STAssertTrue([roundtrip2 isKindOfClass:[NSMutableIndexSet class]], nil);
        
        [roundtrip1 release];
        [roundtrip2 release];
        [orig release];
    }
}

- (void)testSimpleRange
{
    NSRange aRange;
    
    for(aRange.location = 0; aRange.location < 3; aRange.location ++) {
        for (aRange.length = 2; aRange.length < 5; aRange.length ++) {
            NSIndexSet *st = [[NSIndexSet alloc] initWithIndexesInRange:aRange];
            NSString *rs = [NSString stringWithFormat:@"%u-%u", aRange.location, aRange.location + aRange.length - 1];
            
            STAssertEqualObjects([st rangeString], rs, nil);
            STAssertEqualObjects([NSIndexSet indexSetWithRangeString:rs], st, nil);
            
            [st release];
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
                    [buf appendFormat:@"%u,%u", starts[startIx], starts[startIx] + 1 + gaps[gapIx]];
                else
                    [buf appendFormat:@"%u-%u,%u-%u",
                     starts[startIx], starts[startIx] + len - 1,
                     starts[startIx] + len + gaps[gapIx], starts[startIx] + len + gaps[gapIx] + len - 1];
                
                NSMutableIndexSet *st = [[NSMutableIndexSet alloc] init];
                [st addIndexesInRange:(NSRange){ starts[startIx], len }];
                [st addIndexesInRange:(NSRange){ starts[startIx] + len + gaps[gapIx], len }];
                
                STAssertEqualObjects([st rangeString], buf, nil);
                
                NSIndexSet *ris = [NSIndexSet indexSetWithRangeString:buf];
                STAssertEqualObjects(ris, st, nil);
                STAssertEquals([ris count], (NSUInteger)(2 * len), nil);
                
                [buf appendFormat:@",%u", starts[startIx] + len + gaps[gapIx] + len + 1];
                [st addIndex:starts[startIx] + len + gaps[gapIx] + len + 1];
                
                STAssertEqualObjects([st rangeString], buf, nil);
                
                ris = [NSIndexSet indexSetWithRangeString:buf];
                STAssertEqualObjects(ris, st, nil);
                STAssertEquals([ris count], (NSUInteger)(2 * len + 1), nil);
                [st release];
            }
        }
    }
    
}

@end


