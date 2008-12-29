// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/OFHeap.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFHeapTests : OFTestCase
{
}

@end

@implementation OFHeapTests

// Methods automatically found and invoked by the SenTesting framework

- (void)testHeapSingle
{
    OFHeap *heap;
    NSString *str;

    heap = [[OFHeap alloc] initWithCapacity:0 compareSelector:@selector(compare:)];
    should([heap count] == 0);

    [heap addObject:@"one"];
    should([heap count] == 1);
    should([heap removeObjectLessThanObject:@"aaa"] == nil);
    should([heap count] == 1);
    shouldBeEqual([heap peekObject], @"one");
    should([heap count] == 1);
    str = [heap removeObject];
    should([heap count] == 0);
    shouldBeEqual(str, @"one");
    should([heap removeObjectLessThanObject:@"aaa"] == nil);
    should([heap count] == 0);
    [heap removeAllObjects];
    should([heap count] == 0);
    [heap release];
}

#if 0
- (void)testHeapPermutations
{
    NSString *str;
    int group, element, elementCount;
    
    /* A set of Galois fields which can conveniently generate integers 1..(N-1) in a pseudorandom order */
    static const struct { int field, generator; } groups[] = {
    { 3, 2 },
    { 5, 2 },
    { 5, 3 },
    { 17, 3 },
    { 17, 14 },
    { 31, 21 },
    { 31, 11 },
    { 65537, 118 },
    { 65537, 9095 },
    { 65537, 65432 },
    { 0, 0 }
    };

    for(group = 0; groups[group].field > 0; group ++) {
        OFHeap *heap;
        NSAutoreleasePool *pool;

        pool = [[NSAutoreleasePool alloc] init];

        heap = [[OFHeap alloc] initWithCapacity:0 compareSelector:@selector(compare:)];
        should([heap count] == 0);

        element = groups[group].generator;
        for(elementCount = 0; elementCount < (groups[group].field-1); elementCount ++) {
            should([heap count] == elementCount);
            [heap addObject:[NSString stringWithFormat:@"%06d in (%d,%d)", element, groups[group].field, groups[group].generator]];
            element = ( (unsigned long)element * (unsigned long)groups[group].generator ) % groups[group].field;
        }

        [pool release];

        should([heap count] == (groups[group].field-1));

        for(elementCount = 1; elementCount < (groups[group].field); elementCount ++) {
            pool = [[NSAutoreleasePool alloc] init];

            str = [heap removeObject];
            should([str intValue] == elementCount);

            [pool release];
            should([heap count] == (groups[group].field - elementCount - 1));
        }

        [heap release];
    }
}
#endif

@end

