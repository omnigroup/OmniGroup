// Copyright 2012-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniBase/macros.h>
#import <OmniBase/rcsid.h>

#import <OmniFoundation/OFOffsetMutableArray.h>

RCS_ID("$Id$");

@interface OFOffsetMutableArrayTests :  OFTestCase
@end

@implementation OFOffsetMutableArrayTests

- (void)testCreation;
{
    OFOffsetMutableArray *target;
    
    target = [[[OFOffsetMutableArray alloc] init] autorelease];
    STAssertEqualObjects(target, @[], @"New empty offset array should be equivalent to a regular empty array");
    
    target = [[[OFOffsetMutableArray alloc] initWithArray:@[]] autorelease];
    STAssertEqualObjects(target, @[], @"New empty offset array (from empty array) should be equivalent to a regular empty array");
}

- (void)testZeroOffset;
{
    OFOffsetMutableArray *target;
    NSArray *template = @[ @1, @2, @3 ];
    
    target = [[[OFOffsetMutableArray alloc] initWithArray:template] autorelease];
    STAssertEqualObjects(target, template, @"New offset array from non-empty array should be equivalent to that array");
    STAssertEqualObjects(target.unadjustedArray, template, @"For zero offset, the unadjusted array should be equivalent to the original array");
    
    target = [[[OFOffsetMutableArray alloc] init] autorelease];
    [target addObjectsFromArray:template];
    STAssertEqualObjects(target, template, @"New offset array with items added from array should be equivalent to that array");
    STAssertEqualObjects(target.unadjustedArray, template, @"For zero offset, the unadjusted array (after adding items) should be equivalent to the original array");
}

- (void)testNonzeroOffset;
{
    OFOffsetMutableArray *target;
    NSArray *template = @[ @1, @2, @3, @4, @5 ];
    
    target = [[[OFOffsetMutableArray alloc] initWithArray:template] autorelease];
    for (NSUInteger offset = 0; offset < template.count; offset++) {
        target.offset = offset;
        STAssertEqualObjects(target, [template subarrayWithRange:NSMakeRange(offset, template.count - offset)], @"Offset arrays should be equivalent to their underlying arrays shifted to the left");
        STAssertEqualObjects(target.unadjustedArray, template, @"Regardless of offset, the unadjusted array should be equivalent to the original array");
    }
}

- (void)testNonzeroOffsetMutation;
{
    OFOffsetMutableArray *target = [[[OFOffsetMutableArray alloc] init] autorelease];
    target.offset = 1;
    
    [target addObject:@"foo"];
    STAssertEquals(target.count, (NSUInteger)0, @"Items shifted out of an offset array shouldn't contribute to the count");
    
    [target addObjectsFromArray:@[ @"bar", @"baz" ]];
    STAssertEquals(target.count, (NSUInteger)2, @"Items added after reaching an offset array's offset should appear in the count");
    
    target.offset = 3;
    STAssertEqualObjects(target, @[], @"Items shifted out of an offset array by adjusting the offset should effectively 'disappear'");
}

- (void)testRelativeMutatorMethods;
{
    NSArray *template = @[ @1, @2, @3 ];
    OFOffsetMutableArray *target = [[[OFOffsetMutableArray alloc] initWithArray:template] autorelease];
    target.offset = template.count;
    
    STAssertEqualObjects(target, @[], @"Offset array shifted by its unadjusted array's count should appear empty");
    
    for (NSUInteger i = 0; i < template.count; i++)
        [target removeLastObject];
    
    STAssertEqualObjects(target, @[], @"Offset array shifted by more than its unadjusted array's count should appear empty");
    STAssertEqualObjects(target.unadjustedArray, @[], @"Relative mutator methods (like -removeLastObject) should still operate on the unadjusted array, even if the offset array appears empty before the mutation");
    
    for (id anObj in template)
        [target addObject:anObj];
    
    STAssertEqualObjects(target, @[], @"Offset array shifted by its unadjusted array's count should appear empty");
    STAssertEqualObjects(target.unadjustedArray, template, @"Relative mutator methods (like -addObject:) should still operate on the unadjusted array, even if the offset array appears empty before the mutation");
}

- (void)testAbsoluteMutatorMethods;
{
    NSArray *template = @[ @1, @2, @3, @4, @5 ];
    OFOffsetMutableArray *target = [[[OFOffsetMutableArray alloc] init] autorelease];
    
    for (id anObj in template) {
        [target insertObject:anObj atIndex:0];
        target.offset += 1;
        
        STAssertEqualObjects(target, @[], @"Inserting an object, then shifting, should leave the offset array empty");
        STAssertEqualObjects(target.unadjustedArray, [template subarrayWithRange:NSMakeRange(0, [template indexOfObject:anObj] + 1)], @"Inserting an object successfully should always modify the unadjusted array");
    }
    
    for (NSUInteger offset = 1; offset <= template.count; offset++) {
        target = [[[OFOffsetMutableArray alloc] initWithArray:template] autorelease];
        target.offset = offset;
        
        [target insertObject:@6 atIndex:template.count - offset];
        STAssertEqualObjects(target.unadjustedArray, [template arrayByAddingObject:@6], @"Object insertion indexes should shift with the offset of the array");
    }
}

- (void)testIndexOfObject;
{
    NSArray *template = @[ @1, @2, @3, @4, @5 ];
    OFOffsetMutableArray *target = [[[OFOffsetMutableArray alloc] initWithArray:template] autorelease];
    
    for (id anObj in template)
        STAssertEquals([target indexOfObject:anObj], [template indexOfObject:anObj], @"Unshifted arrays should match object indexes with their underlying arrays");
    STAssertEquals([target indexOfObject:@6], (NSUInteger)NSNotFound, @"Unshifted arrays should still return NSNotFound for elements they don't contain");
    
    for (NSUInteger offset = 1; offset <= template.count; offset++) { // <= is deliberate here; what happens when the offset is greater than the number of items in the array?
        target.offset = offset;
        
        for (id anObj in [template subarrayWithRange:NSMakeRange(offset, template.count - offset)])
            STAssertEquals([target indexOfObject:anObj], [template indexOfObject:anObj] - offset, @"Shifted arrays should find objects at indexes shifted by their offset, where they exist");
        
        for (id anObj in [template subarrayWithRange:NSMakeRange(0, offset)])
            STAssertEquals([target indexOfObject:anObj], (NSUInteger)NSNotFound, @"Shifted arrays should return NSNotFound for indexes of objects shifted off the end of the array");
    }
}

- (void)testObjectAtIndex;
{
    NSArray *template = @[ @1, @2, @3, @4, @5 ];
    OFOffsetMutableArray *target = [[[OFOffsetMutableArray alloc] initWithArray:template] autorelease];
    
    for (NSUInteger offset = 0; offset <= template.count; offset++) { // <= is deliberate here; what happens when the offset is greater than the number of items in the array?
        target.offset = offset;
        
        for (NSUInteger idx = 0; idx < template.count - offset; idx++)
            STAssertEquals([target objectAtIndex:idx], [template objectAtIndex:idx + offset], @"Shifted arrays should return objects at indexes shifted by their offset");
        
        for (NSUInteger idx = template.count - offset; idx < template.count; idx++)
            STAssertThrowsSpecificNamed([target objectAtIndex:idx], NSException, @"NSRangeException", @"Shifted arrays should throw NSRangeExceptions when asked for objects beyond their (shifted) count.");
    }
}

@end
