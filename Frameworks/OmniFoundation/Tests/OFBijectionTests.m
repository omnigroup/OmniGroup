// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFBijection.h>

RCS_ID("$Id$");

@interface OFBijectionTests : OFTestCase
@end

@implementation OFBijectionTests

- (void)testEmptyBijection;
{
    OFBijection *bijection = [OFBijection bijection];
    
    STAssertNotNil(bijection, @"New empty bijection was nil");
    STAssertEquals((NSUInteger)0, [bijection count], @"New empty bijection wasn't actually empty");
}

- (void)testSingleItemBijection;
{
    OFBijection *bijection = [OFBijection bijectionWithObject:@"bar" forKey:@"foo"];
    
    STAssertNotNil(bijection, @"New single-item bijection was nil");
    STAssertEquals((NSUInteger)1, [bijection count], @"New single-item bijection had wrong count");
    
    STAssertEqualObjects(@"bar", [bijection objectForKey:@"foo"], @"Single-item bijection did not map key to object");
    STAssertEqualObjects(@"foo", [bijection keyForObject:@"bar"], @"Single-item bijection did not map object back to key");
}

- (void)testMultipleItemBijection;
{
    NSArray *testKeys = @[ @1, @2, @3 ];
    NSArray *testObjects = @[ @"one", @"two", @"three" ];
    
    OFBijection *bijection = [OFBijection bijectionWithObjects:testObjects forKeys:testKeys];
    
    STAssertNotNil(bijection, @"New multiple-item bijection was nil");
    STAssertEquals([testKeys count], [bijection count], @"New multiple-item bijection had wrong count");
    
    for (NSUInteger i = 0; i < [testKeys count]; i++) {
        STAssertEqualObjects(testObjects[i], [bijection objectForKey:testKeys[i]], @"Multiple-item bijection provided wrong object for key");
        STAssertEqualObjects(testKeys[i], [bijection keyForObject:testObjects[i]], @"Multiple-item bijection provided wrong key for object");
    }
}

- (void)testVariadicBijection;
{
    OFBijection *bijection = [OFBijection bijectionWithObjectsAndKeys:@"one", @1, @"two", @2, @"three", @3, nil];
    
    STAssertNotNil(bijection, @"New bijection from variadic constructor was nil");
    STAssertEquals((NSUInteger)3, [bijection count], @"New bijection from variadic constructor had wrong count");
    
    [@{ @1 : @"one", @2 : @"two", @3 : @"three" } enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        STAssertEqualObjects(obj, [bijection objectForKey:key], @"Bijection from variadic constructor provided wrong object for key");
        STAssertEqualObjects(key, [bijection keyForObject:obj], @"Bijection from variadic constructor provided wrong key for object");
    }];
}

- (void)testBijectionEquality;
{
    NSArray *keys = @[ @1, @2, @3 ];
    NSArray *objects = @[ @"one", @"two", @"three" ];
    
    OFBijection *bijectionA = [OFBijection bijectionWithObjects:objects forKeys:keys];
    OFBijection *bijectionB = [OFBijection bijectionWithObjects:objects forKeys:keys];
    
    STAssertEqualObjects(bijectionA, bijectionB, @"Bijections with same objects weren't equal");
}

- (void)testBijectionInequality;
{
    OFBijection *bijectionA = [OFBijection bijectionWithObject:@"one" forKey:@1];
    OFBijection *bijectionB = [OFBijection bijectionWithObject:@"two" forKey:@2];
    
    STAssertFalse([bijectionA isEqualToBijection:bijectionB], @"Bijections with different objects were equal");
}

- (void)testInvertedBijection;
{
    NSArray *keys = @[ @1, @2, @3 ];
    NSArray *objects = @[ @"one", @"two", @"three" ];
    
    OFBijection *bijection = [OFBijection bijectionWithObjects:objects forKeys:keys];
    OFBijection *inverse = [bijection invertedBijection];
    
    for (NSUInteger i = 0; i < keys.count; i++) {
        id key = keys[i];
        id object = objects[i];
        
        STAssertEqualObjects(key, [inverse objectForKey:object], @"Inverted bijection changed key-object mapping");
    }
}

@end
