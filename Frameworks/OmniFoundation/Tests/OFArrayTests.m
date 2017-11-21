// Copyright 2004-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFMultiValueDictionary.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFSortedArrayManipulations : OFTestCase
{
}


@end

@implementation OFSortedArrayManipulations

// Test cases

- (void)testOrderByArray
{
    NSArray *reference, *empty;
    NSMutableArray *input;
    
    
    reference = [[NSArray alloc] initWithObjects:@"aleph", @"beth", @"gimel", @"he", @"waw", @"zayin", @"het", nil];
    empty = [[NSArray alloc] init];
    input = [[NSMutableArray alloc] initWithObjects:@"waw", @"het", @"gimel", nil];
    
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:NO];
    XCTAssertEqualObjects(input, ([NSArray arrayWithObjects:@"gimel", @"waw", @"het", nil]));
    [input sortUsingSelector:@selector(compare:)];
    XCTAssertEqualObjects(input, ([NSArray arrayWithObjects:@"gimel", @"het", @"waw", nil]));
    [input addObject:@"nostril"];
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:NO];
    XCTAssertEqualObjects(input, ([NSArray arrayWithObjects:@"gimel", @"waw", @"het", @"nostril", nil]));
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:YES];
    XCTAssertEqualObjects(input, ([NSArray arrayWithObjects:@"nostril", @"gimel", @"waw", @"het", nil]));
    [input sortBasedOnOrderInArray:[reference reversedArray] identical:NO unknownAtFront:YES];
    XCTAssertEqualObjects(input, ([NSArray arrayWithObjects:@"nostril", @"het", @"waw", @"gimel", nil]));
    
    [input removeAllObjects];
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:YES];
    XCTAssertEqualObjects(input, empty);
    [input sortBasedOnOrderInArray:reference identical:YES unknownAtFront:YES];
    XCTAssertEqualObjects(input, empty);
    [input sortBasedOnOrderInArray:reference identical:YES unknownAtFront:NO];
    XCTAssertEqualObjects(input, empty);
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:NO];
    XCTAssertEqualObjects(input, empty);
    
    [input sortBasedOnOrderInArray:empty identical:NO unknownAtFront:NO];
    XCTAssertEqualObjects(input, empty);

    [input addObject:[NSMutableString stringWithString:@"zayin"]];
    [input sortBasedOnOrderInArray:empty identical:NO unknownAtFront:NO];
    XCTAssertEqualObjects(input, [NSArray arrayWithObject:@"zayin"]);
    [input sortBasedOnOrderInArray:empty identical:YES unknownAtFront:YES];
    XCTAssertEqualObjects(input, [NSArray arrayWithObject:@"zayin"]);
    
    [input addObject:[reference objectAtIndex:0]];  //aleph
    [input addObject:[reference objectAtIndex:6]];  //het
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:YES];
    XCTAssertEqualObjects(input, ([NSArray arrayWithObjects:@"aleph", @"zayin", @"het",nil]));
    [input sortBasedOnOrderInArray:reference identical:YES unknownAtFront:YES];
    XCTAssertEqualObjects(input, ([NSArray arrayWithObjects:@"zayin", @"aleph",@"het",nil]));
    [input sortBasedOnOrderInArray:reference identical:YES unknownAtFront:NO];
    XCTAssertEqualObjects(input, ([NSArray arrayWithObjects:@"aleph",@"het",@"zayin",nil]));
    
    [input removeAllObjects];
    [input addObjectsFromArray:reference];
    [input reverse];
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:YES];
    XCTAssertEqualObjects(input, reference);
    
}

@end


@interface OFArrayConveniencesTests : OFTestCase
{
}

@end

@implementation OFArrayConveniencesTests

// Test cases

- (void)testChooseAny
{
    NSArray *x;
    NSObject *y;
    
    y = [[NSObject alloc] init];
    
    x = [NSArray array];
    XCTAssertTrue([x anyObject] == nil);
    x = [NSArray arrayWithObject:y];
    XCTAssertTrue([x anyObject] == y);
    x = [NSArray arrayWithObject:@"y"];
    XCTAssertTrue([x anyObject] != y);
}

- (void)testReplaceByApplying
{
    NSMutableArray *subj;
    NSArray *counting, *Counting, *middle;

    counting = [[NSArray alloc] initWithObjects:@"one", @"two", @"three", @"four", @"five", nil];
    middle = [NSArray arrayWithObjects:@"one", @"TWO", @"THREE", @"FOUR", @"five", nil];
    Counting = [[NSArray alloc] initWithObjects:@"One", @"Two", @"Three", @"Four", @"Five", nil];

    subj = [NSMutableArray array];
    [subj addObjectsFromArray:counting];
    [subj replaceObjectsInRange:(NSRange){1,3} byApplyingSelector:@selector(uppercaseString)];
    XCTAssertEqualObjects(subj, middle);

    [subj removeAllObjects];
    [subj addObjectsFromArray:Counting];
    [subj replaceObjectsInRange:(NSRange){0,5} byApplyingSelector:@selector(lowercaseString)];
    XCTAssertEqualObjects(subj, counting);
    [subj replaceObjectsInRange:(NSRange){1,4} byApplyingSelector:@selector(uppercaseString)];
    [subj replaceObjectsInRange:(NSRange){4,1} byApplyingSelector:@selector(lowercaseString)];
    XCTAssertEqualObjects(subj, middle);
    [subj replaceObjectsInRange:(NSRange){0,4} byApplyingSelector:@selector(lowercaseString)];
    XCTAssertEqualObjects(subj, counting);
    [subj replaceObjectsInRange:(NSRange){0,5} byApplyingSelector:@selector(uppercaseFirst)];
    XCTAssertEqualObjects(subj, Counting);
}

- (void)testReverse:(NSArray *)counting giving:(NSArray *)gnitnuoc
{
    NSMutableArray *subj;

    subj = [NSMutableArray array];
    [subj addObjectsFromArray:counting];
    XCTAssertEqualObjects(subj, [gnitnuoc reversedArray]);
    [subj reverse];
    XCTAssertEqualObjects(subj, gnitnuoc);
    XCTAssertEqualObjects(subj, [counting reversedArray]);
    XCTAssertEqualObjects([subj reversedArray], counting);
    [subj reverse];
    XCTAssertEqualObjects(subj, counting);
    XCTAssertEqualObjects([subj reversedArray], [counting reversedArray]);
    XCTAssertEqualObjects([subj reversedArray], gnitnuoc);
}

- (void)testReversal
{
    NSArray *forward, *backward;
        
    [self testReverse:[[NSArray alloc] init] giving:[[NSMutableArray alloc] init]];
    
    forward = [NSArray arrayWithObject:@"one"];
    [self testReverse:forward giving:forward];
    
    forward = [[NSArray alloc] initWithObjects:@"one", @"two", nil];
    backward = [[NSArray alloc] initWithObjects:@"two", @"one", nil];
    [self testReverse:forward giving:backward];
    
    forward = [[NSArray alloc] initWithObjects:@"one", @"two", @"three", nil];
    backward = [[NSArray alloc] initWithObjects:@"three", @"two", @"one", nil];
    [self testReverse:forward giving:backward];
    
    forward = [[NSArray alloc] initWithObjects:@"oscillate", @"my", @"metallic", @"sonatas", nil];
    backward = [[NSArray alloc] initWithObjects:@"sonatas", @"metallic", @"my", @"oscillate", nil];
    [self testReverse:forward giving:backward];
    
    forward = [[NSArray alloc] initWithObjects:@"one", @"two", @"three", @"four", @"Fibonacci", nil];
    backward = [[NSArray alloc] initWithObjects:@"Fibonacci", @"four", @"three", @"two", @"one", nil];
    [self testReverse:forward giving:backward];
}

- (void)testGrouping
{
    NSArray *a;
    OFMultiValueDictionary *grouped;
    
    a = [NSArray arrayWithObjects:@"one", @"THREE", @"FOUR", @"five", @"two", @"three", @"four", @"Two", @"Three", @"Four", @"five", nil];
    
    grouped = [a groupByKeyBlock:^(NSString *string){ return [string lowercaseString]; }];
    XCTAssertEqualObjects(([NSSet setWithArray:[grouped allKeys]]),
                  ([NSSet setWithObjects:@"one", @"two", @"three", @"four", @"five", nil]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"one"]),
                  ([NSArray arrayWithObject:@"one"]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"two"]),
                  ([NSArray arrayWithObjects:@"two", @"Two", nil]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"three"]),
                  ([NSArray arrayWithObjects:@"THREE", @"three", @"Three", nil]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"four"]),
                  ([NSArray arrayWithObjects:@"FOUR", @"four", @"Four", nil]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"five"]),
                  ([NSArray arrayWithObjects:@"five", @"five", nil]));

    grouped = [a groupByKeyBlock:^(NSString *string){ return [string stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"Ttoe"]]; }];
    XCTAssertEqualObjects(([NSSet setWithArray:[grouped allKeys]]),
                  ([NSSet setWithObjects:@"n", @"HREE", @"FOUR", @"fiv", @"four", @"w", @"hr", @"Four", nil]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"n"]),
                  ([NSArray arrayWithObject:@"one"]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"HREE"]),
                  ([NSArray arrayWithObject:@"THREE"]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"FOUR"]),
                  ([NSArray arrayWithObject:@"FOUR"]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"fiv"]),
                  ([NSArray arrayWithObjects:@"five", @"five", nil]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"four"]),
                  ([NSArray arrayWithObject:@"four"]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"w"]),
                  ([NSArray arrayWithObjects:@"two", @"Two", nil]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"hr"]),
                  ([NSArray arrayWithObjects:@"three", @"Three", nil]));
    XCTAssertEqualObjects(([grouped arrayForKey:@"Four"]),
                  ([NSArray arrayWithObject:@"Four"]));
}

- (void)testContains
{
    NSArray *a;
    a = [NSArray arrayWithObjects:@"one", @"THREE", @"FOUR", @"five", @"two", @"three", @"four", @"Two", @"Three", @"Four", @"five", nil];
    
    XCTAssertTrue((  [a containsObjectsInOrder:[NSArray arrayWithObjects:@"one", @"five", nil]]));
    XCTAssertTrue((  [a containsObjectsInOrder:[NSArray arrayWithObjects:@"Four", @"five", nil]]));
    XCTAssertFalse(([a containsObjectsInOrder:[NSArray arrayWithObjects:@"Four", @"Four", nil]]));
    XCTAssertTrue((  [a containsObjectsInOrder:[NSArray arrayWithObject:@"two"]]));
    XCTAssertTrue((  [a containsObjectsInOrder:[NSArray array]]));
    XCTAssertTrue((  [[NSArray array] containsObjectsInOrder:[NSArray array]]));
    XCTAssertFalse(([[NSArray array] containsObjectsInOrder:[NSArray arrayWithObject:@"two"]]));
    XCTAssertFalse(([a containsObjectsInOrder:[a arrayByAddingObject:@"six"]]));
    XCTAssertTrue((  [[a arrayByAddingObject:@"six"] containsObjectsInOrder:a]));
    XCTAssertTrue((  [a containsObjectsInOrder:a]));
    XCTAssertTrue((  [a containsObjectsInOrder:[NSArray arrayWithObjects:@"five", nil]]));
    XCTAssertTrue((  [a containsObjectsInOrder:[NSArray arrayWithObjects:@"five", @"five", nil]]));
    XCTAssertFalse(([a containsObjectsInOrder:[NSArray arrayWithObjects:@"five", @"five", @"five", nil]]));
}

- (void)testSortedUsingSelector
{
#define NNUM 12
    int nums[NNUM] = { 100, -100, 47, INT_MAX-1002, 0, 1002+INT_MIN, -1, 0, 1, 2, 1, 0 };
    BOOL num_is_last[NNUM]  = { YES, YES, YES, YES,  NO, YES, YES,  NO,  NO, YES, YES, YES };
    BOOL num_is_first[NNUM] = { YES, YES, YES, YES, YES, YES, YES,  NO, YES, YES,  NO,  NO };
    NSNumber *objs[NNUM];            // A bunch of comparable objects.
    NSMutableString *dobjs[NNUM];    // Distinct (but possibly equal) objects.
    int ix;
    NSMutableArray *a, *b;
    
    a = [NSMutableArray array];
    b = [NSMutableArray array];
    
    for(ix = 0; ix < NNUM; ix++) {
        
        // For NSNumbers, make sure we use the same number instance for the same integer value. NSNumber does this for us anyway, to some extent at least, but we don't want to rely on that particular optimization.
        NSNumber *n = nil;
        int ixx;
        for(ixx = 0; ixx < ix; ixx ++) {
            if (nums[ixx] == nums[ix]) {
                n = objs[ixx];
                break;
            }
        }
        objs[ix] = (n != nil) ? n : [NSNumber numberWithInt:nums[ix]];
        [a insertObject:objs[ix] inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue([a isSortedUsingSelector:@selector(compare:)], @"Array: %@", a);
        
        // For NSStrings, we use mutable strings, which guarantees that the instances are distinct.
        dobjs[ix] = [NSMutableString stringWithFormat:@"%+015d", nums[ix]];
        [b insertObject:dobjs[ix] inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue([b isSortedUsingSelector:@selector(compare:)], @"Array: %@", b);
    }
    XCTAssertTrue([a count] == NNUM);
    XCTAssertTrue([[a objectAtIndex:0] intValue] == INT_MIN+1002);
    XCTAssertTrue([[a objectAtIndex:3] intValue] == 0);
    XCTAssertTrue([[a objectAtIndex:4] intValue] == 0);
    XCTAssertTrue([[a objectAtIndex:NNUM-1] intValue] == INT_MAX-1002);

    // The ordering of the 'b' array is different: negative numbers sort after positive numbers, and they sort from -1 ... -10000 (etc)
    XCTAssertTrue([b count] == NNUM);
    XCTAssertTrue([[b objectAtIndex:NNUM-1] intValue] == INT_MIN+1002, @"%@", [b objectAtIndex:0]);
    XCTAssertTrue([[b objectAtIndex:0] intValue] == 0, @"%@", [b objectAtIndex:3]);
    XCTAssertTrue([[b objectAtIndex:1] intValue] == 0, @"%@", [b objectAtIndex:4]);
    XCTAssertTrue([[b objectAtIndex:8] intValue] == INT_MAX-1002, @"%@", [b objectAtIndex:NNUM-1]);
    
    for(ix = 0; ix < NNUM; ix++) {
        NSUInteger aix, bix, cix;
        
        aix = [a indexOfObject:[NSNumber numberWithInt:nums[ix]] inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue(aix != NSNotFound, @"Index of %d in %@ returns %lu", nums[ix], [a description], aix);
        XCTAssertTrue([[a objectAtIndex:aix] intValue] == nums[ix]);
        aix = [a indexOfObjectIdenticalTo:objs[ix] inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue(aix != NSNotFound, @"Index of %@ in %@ returns %lu", objs[ix], [a description], aix);
        XCTAssertTrue([a objectAtIndex:aix] == objs[ix]);
        bix = [a indexOfObject:[NSNumber numberWithInt:nums[ix] + 1000] inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue(bix == NSNotFound, @"Index of %d in %@ returns %lu", nums[ix] + 1000, [a description], bix);
        cix = [a indexOfObject:[NSNumber numberWithInt:nums[ix] - 1000] inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue(cix == NSNotFound, @"Index of %d in %@ returns %lu", nums[ix] - 1000, [a description], cix);
    }
    for(ix = 0; ix < NNUM; ix++) {
        NSUInteger aix, bix, cix;
        NSString *obj = [NSString stringWithFormat:@"%+015d", nums[ix]];
        
        aix = [b indexOfObject:obj inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue(aix != NSNotFound, @"Index of %d in %@ returns %lu", nums[ix], [b description], aix);
        XCTAssertTrue([[b objectAtIndex:aix] intValue] == nums[ix]);
        aix = [b indexOfObjectIdenticalTo:obj inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue(aix == NSNotFound, @"Index of %@ in %@ returns %lu", dobjs[ix], [b description], aix);
        XCTAssertEqualObjects(obj, dobjs[ix]);
        aix = [b indexOfObjectIdenticalTo:dobjs[ix] inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue(aix != NSNotFound, @"Index of %@ in %@ returns %lu", dobjs[ix], [b description], aix);
        XCTAssertTrue([b objectAtIndex:aix] == dobjs[ix]);
        bix = [b indexOfObject:[NSString stringWithFormat:@"%+015d", nums[ix] + 1000] inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue(bix == NSNotFound, @"Index of %d in %@ returns %lu", nums[ix] + 1000, [b description], bix);
        cix = [b indexOfObject:[NSString stringWithFormat:@"%+015d", nums[ix] - 1000] inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue(cix == NSNotFound, @"Index of %d in %@ returns %lu", nums[ix] - 1000, [b description], cix);
    }
    
    // Modify objects in-place: append some stuff, and prepend some stuff. The stuff we append/prepend is constant except for case.
    [b makeObjectsPerformSelector:@selector(appendString:) withObject:@"789"];
    for(ix = 0; ix < NNUM; ix++) {
        NSMutableString *obj = dobjs[ix];
        int bit;
        
        for(bit = 0; bit < 5; bit++) {
            NSString *ch = [NSString stringWithCharacter:('a' + bit)];
            if ( (1<<bit) & ix )
                ch = [ch uppercaseString];
            [obj replaceCharactersInRange:(NSRange){bit, 0} withString:ch];
        }
    }
    XCTAssertTrue([b isSortedUsingSelector:@selector(caseInsensitiveCompare:)]);
    XCTAssertFalse([b isSortedUsingSelector:@selector(compare:)]);
    
    // repeat the test with the case-insensitive-sorted values
    for(ix = 0; ix < NNUM; ix++) {
        NSUInteger aix;
        NSString *obj = [NSString stringWithFormat:@"ABCDE%+015d789", nums[ix]];
        
        XCTAssertTrue([obj caseInsensitiveCompare:dobjs[ix]] == NSOrderedSame);
        XCTAssertFalse([obj compare:dobjs[ix]] == NSOrderedSame);

        aix = [b indexOfObject:obj inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)];
        XCTAssertTrue(aix != NSNotFound, @"Index of %d in %@ returns %lu", nums[ix], [b description], aix);
        XCTAssertTrue(([[[b objectAtIndex:aix] substringWithRange:(NSRange){5,15}] intValue]) == nums[ix]);
        
        aix = [b indexOfObjectIdenticalTo:obj inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)];
        XCTAssertTrue(aix == NSNotFound, @"Index of %@ in %@ returns %lu", dobjs[ix], [b description], aix);
        
        aix = [b indexOfObject:obj inArraySortedUsingSelector:@selector(compare:)];
        XCTAssertTrue(aix == NSNotFound, @"Index of %@ in %@ returns %lu", dobjs[ix], [b description], aix);
        
        aix = [b indexOfObjectIdenticalTo:dobjs[ix] inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)];
        XCTAssertTrue(aix != NSNotFound, @"Index of %@ in %@ returns %lu", dobjs[ix], [b description], aix);
        XCTAssertTrue([b objectAtIndex:aix] == dobjs[ix]);
    }
    
   // NSLog(@"a = %@", [a description]);
   // NSLog(@"b = %@", [b description]);
    
    NSMutableArray *copyA = [NSMutableArray arrayWithArray:a];
    NSMutableArray *copyB = [NSMutableArray arrayWithArray:b];
    for(ix = 0; ix < NNUM; ix++) {
        NSUInteger c0, c1;
        
        c0 = [a count];
        [a removeObjectIdenticalTo:objs[ix] fromArraySortedUsingSelector:@selector(compare:)];
        c1 = [a count];
        XCTAssertTrue(c0 == c1 + 1);
        // Check that duplicate values either are, or are not, still in the array (as appropriate)
        if (num_is_last[ix]) {
            XCTAssertTrue([a indexOfObjectIdenticalTo:objs[ix]] == NSNotFound);
        } else {
            XCTAssertTrue([a indexOfObjectIdenticalTo:objs[ix]] != NSNotFound);
        }

        c0 = [b count];
        [b removeObjectIdenticalTo:dobjs[ix] fromArraySortedUsingSelector:@selector(caseInsensitiveCompare:)];
        c1 = [b count];
        XCTAssertTrue(c0 == c1 + 1);
        XCTAssertTrue([b indexOfObjectIdenticalTo:dobjs[ix]] == NSNotFound);
        if (num_is_last[ix]) {
            XCTAssertTrue([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)] == NSNotFound);
        } else {
            XCTAssertTrue([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(compare:)] == NSNotFound);
            XCTAssertTrue([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)] != NSNotFound);
        }
    }
    
    // Also try removing them in a different order
    a = copyA;
    b = copyB;
    for(ix = NNUM-1; ix >= 0; ix--) {
        NSUInteger c0, c1;
        
        c0 = [a count];
        [a removeObjectIdenticalTo:objs[ix] fromArraySortedUsingSelector:@selector(compare:)];
        c1 = [a count];
        XCTAssertTrue(c0 == c1 + 1);
        // Check that duplicate values either are, or are not, still in the array (as appropriate)
        if (num_is_first[ix]) {
            XCTAssertTrue([a indexOfObjectIdenticalTo:objs[ix]] == NSNotFound);
        } else {
            XCTAssertTrue([a indexOfObjectIdenticalTo:objs[ix]] != NSNotFound);
        }
        
        c0 = [b count];
        [b removeObjectIdenticalTo:dobjs[ix] fromArraySortedUsingSelector:@selector(caseInsensitiveCompare:)];
        c1 = [b count];
        XCTAssertTrue(c0 == c1 + 1);
        XCTAssertTrue([b indexOfObjectIdenticalTo:dobjs[ix]] == NSNotFound);
        if (num_is_first[ix]) {
            XCTAssertTrue([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)] == NSNotFound);
        } else {
            XCTAssertTrue([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(compare:)] == NSNotFound);
            XCTAssertTrue([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)] != NSNotFound);
        }
    }
    
    XCTAssertTrue([a count] == 0);
    XCTAssertTrue([b count] == 0);
}

@end

static NSString * const kA = @"a";
static NSString * const kB = @"b";
static NSString * const kC = @"c";
static NSString * const kX = @"x";

@interface OFArrayBlockPredicateTests : OFTestCase
{
    NSArray *a, *ab, *abc;
}
@end
@implementation OFArrayBlockPredicateTests

- (void)setUp;
{
    [super setUp];
    a = [[NSArray alloc] initWithObjects:kA, nil];
    ab = [[NSArray alloc] initWithObjects:kA, kB, nil];
    abc = [[NSArray alloc] initWithObjects:kA, kB, kC, nil];
}
- (void)tearDown;
{
    a = nil;
    ab = nil;
    abc = nil;
    [super tearDown];
}

static OFPredicateBlock truePredicate = ^BOOL(id obj) {
    return YES;
};
static OFPredicateBlock ifEquals(id value) {
    return [^BOOL(id obj) {
        return [obj isEqual:value];
    } copy];
}
//static OFPredicateBlock ifIn(NSArray *array) {
//    return [[^BOOL(id obj) {
//        return [array containsObject:obj];
//    } copy] autorelease];
//}

- (void)testSimpleFirst;
{
    id notFound = nil;
    
    XCTAssertEqualObjects([[NSArray array] first:truePredicate], notFound);
    
    XCTAssertEqualObjects([a first:ifEquals(kA)], kA);
    XCTAssertEqualObjects([a first:ifEquals(kB)], notFound);

    XCTAssertEqualObjects([ab first:ifEquals(kA)], kA);
    XCTAssertEqualObjects([ab first:ifEquals(kB)], kB);
    XCTAssertEqualObjects([ab first:ifEquals(kC)], notFound);
    
    XCTAssertEqualObjects([abc first:ifEquals(kA)], kA);
    XCTAssertEqualObjects([abc first:ifEquals(kB)], kB);
    XCTAssertEqualObjects([abc first:ifEquals(kC)], kC);
    XCTAssertEqualObjects([abc first:ifEquals(kX)], notFound);
}

- (void)testSimpleLast;
{
    id notFound = nil;
    
    XCTAssertEqualObjects([[NSArray array] first:truePredicate], notFound);
    
    XCTAssertEqualObjects([a last:ifEquals(kA)], kA);
    XCTAssertEqualObjects([a last:ifEquals(kB)], notFound);
    
    XCTAssertEqualObjects([ab last:ifEquals(kA)], kA);
    XCTAssertEqualObjects([ab last:ifEquals(kB)], kB);
    XCTAssertEqualObjects([ab last:ifEquals(kC)], notFound);
    
    XCTAssertEqualObjects([abc last:ifEquals(kA)], kA);
    XCTAssertEqualObjects([abc last:ifEquals(kB)], kB);
    XCTAssertEqualObjects([abc last:ifEquals(kC)], kC);
    XCTAssertEqualObjects([abc last:ifEquals(kX)], notFound);
}

@end
