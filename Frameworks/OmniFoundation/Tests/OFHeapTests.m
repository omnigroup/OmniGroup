// Copyright 2002-2009, 2012-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

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

// Methods automatically found and invoked by the XCTest framework

- (void)testHeapSingle
{
    OFHeap *heap = [[OFHeap alloc] init];
    XCTAssertTrue([heap count] == 0);

    [heap addObject:@"one"];
    XCTAssertTrue([heap count] == 1);
    XCTAssertTrue([heap removeObjectLessThanObject:@"aaa"] == nil);
    XCTAssertTrue([heap count] == 1);
    XCTAssertEqual([heap peekObject], @"one");
    XCTAssertTrue([heap count] == 1);
    NSString *str = [heap removeObject];
    XCTAssertTrue([heap count] == 0);
    XCTAssertEqual(str, @"one");
    XCTAssertTrue([heap removeObjectLessThanObject:@"aaa"] == nil);
    XCTAssertTrue([heap count] == 0);
    [heap removeAllObjects];
    XCTAssertTrue([heap count] == 0);
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
        OFHeap *heap = [[OFHeap alloc] init];
        XCTAssertTrue([heap count] == 0);
        
        @autoreleasepool {
            NSUInteger element = groups[group].generator;
            for (NSUInteger elementCount = 0; elementCount < (groups[group].field-1); elementCount ++) {
                XCTAssertTrue([heap count] == elementCount);
                [heap addObject:[NSString stringWithFormat:@"%06lu in (%ld,%ld)", element, groups[group].field, groups[group].generator]];
                element = (element * groups[group].generator ) % groups[group].field;
            }
        }

        XCTAssertTrue([heap count] == (groups[group].field-1));

        for (NSUInteger elementCount = 1; elementCount < (groups[group].field); elementCount ++) {
            @autoreleasepool {
                NSString *str = [heap removeObject];
                XCTAssertTrue([str unsignedLongValue] == elementCount);
            }

            XCTAssertTrue([heap count] == (groups[group].field - elementCount - 1));
        }

    }
}

- (void)testLifetime;
{
    // Make sure ARC handles the guts of OFHeap correctly, when dereferencing a __unsafe_unretained id * into a regular id.
    OFHeap *heap = [OFHeap new];
    
    @autoreleasepool {
        OFHeapTestObject *object = [OFHeapTestObject new];
        [heap addObject:object];
    }
    
    //NSLog(@"starting remove");
    @autoreleasepool {
        OFHeapTestObject *object = [heap removeObject];
        [object class]; // Make sure we don't get a zombie here.
        //NSLog(@"object = %@", object);
    }
    //NSLog(@"finished remove");
    
}

@end

