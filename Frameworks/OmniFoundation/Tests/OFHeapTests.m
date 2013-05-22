// Copyright 2002-2009, 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/OFHeap.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFHeapTestObject : NSObject
@end
@implementation OFHeapTestObject

//- (void)dealloc;
//{
//    NSLog(@"Deallocated");
//    [super dealloc];
//}

@end

@interface OFHeapTests : OFTestCase
@end

@implementation OFHeapTests

// Methods automatically found and invoked by the SenTesting framework

- (void)testHeapSingle
{
    OFHeap *heap = [[OFHeap alloc] init];
    should([heap count] == 0);

    [heap addObject:@"one"];
    should([heap count] == 1);
    should([heap removeObjectLessThanObject:@"aaa"] == nil);
    should([heap count] == 1);
    shouldBeEqual([heap peekObject], @"one");
    should([heap count] == 1);
    NSString *str = [heap removeObject];
    should([heap count] == 0);
    shouldBeEqual(str, @"one");
    should([heap removeObjectLessThanObject:@"aaa"] == nil);
    should([heap count] == 0);
    [heap removeAllObjects];
    should([heap count] == 0);
    [heap release];
}

- (void)testHeapPermutations
{    
    /* A set of Galois fields which can conveniently generate integers 1..(N-1) in a pseudorandom order */
    static const struct { NSUInteger field, generator; } groups[] = {
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

    for (NSUInteger group = 0; groups[group].field > 0; group ++) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

        OFHeap *heap = [[OFHeap alloc] init];
        should([heap count] == 0);

        NSUInteger element = groups[group].generator;
        for (NSUInteger elementCount = 0; elementCount < (groups[group].field-1); elementCount ++) {
            should([heap count] == elementCount);
            [heap addObject:[NSString stringWithFormat:@"%06lu in (%ld,%ld)", element, groups[group].field, groups[group].generator]];
            element = (element * groups[group].generator ) % groups[group].field;
        }

        [pool drain];

        should([heap count] == (groups[group].field-1));

        for (NSUInteger elementCount = 1; elementCount < (groups[group].field); elementCount ++) {
            pool = [[NSAutoreleasePool alloc] init];

            NSString *str = [heap removeObject];
            should([str unsignedLongValue] == elementCount);

            [pool drain];
            should([heap count] == (groups[group].field - elementCount - 1));
        }

        [heap release];
    }
}

- (void)testLifetime;
{
    // Make sure ARC handles the guts of OFHeap correctly, when dereferencing a __unsafe_unretained id * into a regular id.
    OFHeap *heap = [OFHeap new];
    
    @autoreleasepool {
        OFHeapTestObject *object = [OFHeapTestObject new];
        [heap addObject:object];
        [object release];
    }
    
    //NSLog(@"starting remove");
    @autoreleasepool {
        OFHeapTestObject *object = [heap removeObject];
        [object class]; // Make sure we don't get a zombie here.
        //NSLog(@"object = %@", object);
    }
    //NSLog(@"finished remove");
    
    [heap release];
}

@end

