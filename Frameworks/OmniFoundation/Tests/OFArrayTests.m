// Copyright 2004-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
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
    shouldBeEqual(input, ([NSArray arrayWithObjects:@"gimel", @"waw", @"het", nil]));
    [input sortUsingSelector:@selector(compare:)];
    shouldBeEqual(input, ([NSArray arrayWithObjects:@"gimel", @"het", @"waw", nil]));
    [input addObject:@"nostril"];
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:NO];
    shouldBeEqual(input, ([NSArray arrayWithObjects:@"gimel", @"waw", @"het", @"nostril", nil]));
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:YES];
    shouldBeEqual(input, ([NSArray arrayWithObjects:@"nostril", @"gimel", @"waw", @"het", nil]));
    [input sortBasedOnOrderInArray:[reference reversedArray] identical:NO unknownAtFront:YES];
    shouldBeEqual(input, ([NSArray arrayWithObjects:@"nostril", @"het", @"waw", @"gimel", nil]));
    
    [input removeAllObjects];
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:YES];
    shouldBeEqual(input, empty);
    [input sortBasedOnOrderInArray:reference identical:YES unknownAtFront:YES];
    shouldBeEqual(input, empty);
    [input sortBasedOnOrderInArray:reference identical:YES unknownAtFront:NO];
    shouldBeEqual(input, empty);
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:NO];
    shouldBeEqual(input, empty);
    
    [input sortBasedOnOrderInArray:empty identical:NO unknownAtFront:NO];
    shouldBeEqual(input, empty);

    [input addObject:[NSMutableString stringWithString:@"zayin"]];
    [input sortBasedOnOrderInArray:empty identical:NO unknownAtFront:NO];
    shouldBeEqual(input, [NSArray arrayWithObject:@"zayin"]);
    [input sortBasedOnOrderInArray:empty identical:YES unknownAtFront:YES];
    shouldBeEqual(input, [NSArray arrayWithObject:@"zayin"]);
    
    [input addObject:[reference objectAtIndex:0]];  //aleph
    [input addObject:[reference objectAtIndex:6]];  //het
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:YES];
    shouldBeEqual(input, ([NSArray arrayWithObjects:@"aleph", @"zayin", @"het",nil]));
    [input sortBasedOnOrderInArray:reference identical:YES unknownAtFront:YES];
    shouldBeEqual(input, ([NSArray arrayWithObjects:@"zayin", @"aleph",@"het",nil]));
    [input sortBasedOnOrderInArray:reference identical:YES unknownAtFront:NO];
    shouldBeEqual(input, ([NSArray arrayWithObjects:@"aleph",@"het",@"zayin",nil]));
    
    [input removeAllObjects];
    [input addObjectsFromArray:reference];
    [input reverse];
    [input sortBasedOnOrderInArray:reference identical:NO unknownAtFront:YES];
    shouldBeEqual(input, reference);
    
    [input release];
    [reference release];
    [empty release];
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
    [y autorelease];
    
    x = [NSArray array];
    should([x anyObject] == nil);
    x = [NSArray arrayWithObject:y];
    should([x anyObject] == y);
    x = [NSArray arrayWithObject:@"y"];
    should([x anyObject] != y);
}

- (void)testReplaceByApplying
{
    NSMutableArray *subj;
    NSArray *counting, *Counting, *middle;

    counting = [[[NSArray alloc] initWithObjects:@"one", @"two", @"three", @"four", @"five", nil] autorelease];
    middle = [NSArray arrayWithObjects:@"one", @"TWO", @"THREE", @"FOUR", @"five", nil];
    Counting = [[[NSArray alloc] initWithObjects:@"One", @"Two", @"Three", @"Four", @"Five", nil] autorelease];

    subj = [NSMutableArray array];
    [subj addObjectsFromArray:counting];
    [subj replaceObjectsInRange:(NSRange){1,3} byApplyingSelector:@selector(uppercaseString)];
    shouldBeEqual(subj, middle);

    [subj removeAllObjects];
    [subj addObjectsFromArray:Counting];
    [subj replaceObjectsInRange:(NSRange){0,5} byApplyingSelector:@selector(lowercaseString)];
    shouldBeEqual(subj, counting);
    [subj replaceObjectsInRange:(NSRange){1,4} byApplyingSelector:@selector(uppercaseString)];
    [subj replaceObjectsInRange:(NSRange){4,1} byApplyingSelector:@selector(lowercaseString)];
    shouldBeEqual(subj, middle);
    [subj replaceObjectsInRange:(NSRange){0,4} byApplyingSelector:@selector(lowercaseString)];
    shouldBeEqual(subj, counting);
    [subj replaceObjectsInRange:(NSRange){0,5} byApplyingSelector:@selector(uppercaseFirst)];
    shouldBeEqual(subj, Counting);
}

- (void)testReverse:(NSArray *)counting giving:(NSArray *)gnitnuoc
{
    NSMutableArray *subj;

    subj = [NSMutableArray array];
    [subj addObjectsFromArray:counting];
    shouldBeEqual(subj, [gnitnuoc reversedArray]);
    [subj reverse];
    shouldBeEqual(subj, gnitnuoc);
    shouldBeEqual(subj, [counting reversedArray]);
    shouldBeEqual([subj reversedArray], counting);
    [subj reverse];
    shouldBeEqual(subj, counting);
    shouldBeEqual([subj reversedArray], [counting reversedArray]);
    shouldBeEqual([subj reversedArray], gnitnuoc);
}

- (void)testReversal
{
    NSArray *forward, *backward;
        
    [self testReverse:[[[NSArray alloc] init] autorelease] giving:[[[NSMutableArray alloc] init] autorelease]];
    
    forward = [NSArray arrayWithObject:@"one"];
    [self testReverse:forward giving:forward];
    
    forward = [[NSArray alloc] initWithObjects:@"one", @"two", nil];
    backward = [[NSArray alloc] initWithObjects:@"two", @"one", nil];
    [self testReverse:forward giving:backward];
    [forward release];
    [backward release];
    
    forward = [[NSArray alloc] initWithObjects:@"one", @"two", @"three", nil];
    backward = [[NSArray alloc] initWithObjects:@"three", @"two", @"one", nil];
    [self testReverse:forward giving:backward];
    [forward release];
    [backward release];
    
    forward = [[NSArray alloc] initWithObjects:@"oscillate", @"my", @"metallic", @"sonatas", nil];
    backward = [[NSArray alloc] initWithObjects:@"sonatas", @"metallic", @"my", @"oscillate", nil];
    [self testReverse:forward giving:backward];
    [forward release];
    [backward release];
    
    forward = [[NSArray alloc] initWithObjects:@"one", @"two", @"three", @"four", @"Fibonacci", nil];
    backward = [[NSArray alloc] initWithObjects:@"Fibonacci", @"four", @"three", @"two", @"one", nil];
    [self testReverse:forward giving:backward];
    [forward release];
    [backward release];
}

- (void)testGrouping
{
    NSArray *a;
    OFMultiValueDictionary *grouped;
    
    a = [NSArray arrayWithObjects:@"one", @"THREE", @"FOUR", @"five", @"two", @"three", @"four", @"Two", @"Three", @"Four", @"five", nil];
    
    grouped = [a groupBySelector:@selector(lowercaseString)];
    shouldBeEqual(([NSSet setWithArray:[grouped allKeys]]), 
                  ([NSSet setWithObjects:@"one", @"two", @"three", @"four", @"five", nil]));
    shouldBeEqual(([grouped arrayForKey:@"one"]), 
                  ([NSArray arrayWithObject:@"one"]));
    shouldBeEqual(([grouped arrayForKey:@"two"]), 
                  ([NSArray arrayWithObjects:@"two", @"Two", nil]));
    shouldBeEqual(([grouped arrayForKey:@"three"]), 
                  ([NSArray arrayWithObjects:@"THREE", @"three", @"Three", nil]));
    shouldBeEqual(([grouped arrayForKey:@"four"]), 
                  ([NSArray arrayWithObjects:@"FOUR", @"four", @"Four", nil]));
    shouldBeEqual(([grouped arrayForKey:@"five"]), 
                  ([NSArray arrayWithObjects:@"five", @"five", nil]));

    grouped = [a groupBySelector:@selector(stringByTrimmingCharactersInSet:) withObject:[NSCharacterSet characterSetWithCharactersInString:@"Ttoe"]];
    shouldBeEqual(([NSSet setWithArray:[grouped allKeys]]), 
                  ([NSSet setWithObjects:@"n", @"HREE", @"FOUR", @"fiv", @"four", @"w", @"hr", @"Four", nil]));
    shouldBeEqual(([grouped arrayForKey:@"n"]), 
                  ([NSArray arrayWithObject:@"one"]));
    shouldBeEqual(([grouped arrayForKey:@"HREE"]), 
                  ([NSArray arrayWithObject:@"THREE"]));
    shouldBeEqual(([grouped arrayForKey:@"FOUR"]), 
                  ([NSArray arrayWithObject:@"FOUR"]));
    shouldBeEqual(([grouped arrayForKey:@"fiv"]), 
                  ([NSArray arrayWithObjects:@"five", @"five", nil]));
    shouldBeEqual(([grouped arrayForKey:@"four"]), 
                  ([NSArray arrayWithObject:@"four"]));
    shouldBeEqual(([grouped arrayForKey:@"w"]), 
                  ([NSArray arrayWithObjects:@"two", @"Two", nil]));
    shouldBeEqual(([grouped arrayForKey:@"hr"]), 
                  ([NSArray arrayWithObjects:@"three", @"Three", nil]));
    shouldBeEqual(([grouped arrayForKey:@"Four"]), 
                  ([NSArray arrayWithObject:@"Four"]));
}

- (void)testContains
{
    NSArray *a;
    a = [NSArray arrayWithObjects:@"one", @"THREE", @"FOUR", @"five", @"two", @"three", @"four", @"Two", @"Three", @"Four", @"five", nil];
    
    should((  [a containsObjectsInOrder:[NSArray arrayWithObjects:@"one", @"five", nil]]));
    should((  [a containsObjectsInOrder:[NSArray arrayWithObjects:@"Four", @"five", nil]]));
    shouldnt(([a containsObjectsInOrder:[NSArray arrayWithObjects:@"Four", @"Four", nil]]));
    should((  [a containsObjectsInOrder:[NSArray arrayWithObject:@"two"]]));
    should((  [a containsObjectsInOrder:[NSArray array]]));
    should((  [[NSArray array] containsObjectsInOrder:[NSArray array]]));
    shouldnt(([[NSArray array] containsObjectsInOrder:[NSArray arrayWithObject:@"two"]]));
    shouldnt(([a containsObjectsInOrder:[a arrayByAddingObject:@"six"]]));
    should((  [[a arrayByAddingObject:@"six"] containsObjectsInOrder:a]));
    should((  [a containsObjectsInOrder:a]));
    should((  [a containsObjectsInOrder:[NSArray arrayWithObjects:@"five", nil]]));
    should((  [a containsObjectsInOrder:[NSArray arrayWithObjects:@"five", @"five", nil]]));
    shouldnt(([a containsObjectsInOrder:[NSArray arrayWithObjects:@"five", @"five", @"five", nil]]));
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
    
    a = [[NSMutableArray alloc] init];
    b = [[NSMutableArray alloc] init];
    
    [a autorelease];
    [b autorelease];
    
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
        objs[ix] = n? n : [NSNumber numberWithInt:nums[ix]];
        [a insertObject:objs[ix] inArraySortedUsingSelector:@selector(compare:)];
        should1([a isSortedUsingSelector:@selector(compare:)], ([NSString stringWithFormat:@"Array: %@", a]));
        
        // For NSStrings, we use mutable strings, which guarantees that the instances are distinct.
        dobjs[ix] = [NSMutableString stringWithFormat:@"%+015d", nums[ix]];
        [b insertObject:dobjs[ix] inArraySortedUsingSelector:@selector(compare:)];
        should1([b isSortedUsingSelector:@selector(compare:)], ([NSString stringWithFormat:@"Array: %@", b]));
    }
    should([a count] == NNUM);
    should([[a objectAtIndex:0] intValue] == INT_MIN+1002);
    should([[a objectAtIndex:3] intValue] == 0);
    should([[a objectAtIndex:4] intValue] == 0);
    should([[a objectAtIndex:NNUM-1] intValue] == INT_MAX-1002);

    // The ordering of the 'b' array is different: negative numbers sort after positive numbers, and they sort from -1 ... -10000 (etc)
    should([b count] == NNUM);
    should1([[b objectAtIndex:NNUM-1] intValue] == INT_MIN+1002, [b objectAtIndex:0]);
    should1([[b objectAtIndex:0] intValue] == 0, [b objectAtIndex:3]);
    should1([[b objectAtIndex:1] intValue] == 0, [b objectAtIndex:4]);
    should1([[b objectAtIndex:8] intValue] == INT_MAX-1002, [b objectAtIndex:NNUM-1]);    
    
    for(ix = 0; ix < NNUM; ix++) {
        NSUInteger aix, bix, cix;
        
        aix = [a indexOfObject:[NSNumber numberWithInt:nums[ix]] inArraySortedUsingSelector:@selector(compare:)];
        should1(aix != NSNotFound, ([NSString stringWithFormat:@"Index of %d in %@ returns %u", nums[ix], [a description], aix]));
        should([[a objectAtIndex:aix] intValue] == nums[ix]);
        aix = [a indexOfObjectIdenticalTo:objs[ix] inArraySortedUsingSelector:@selector(compare:)];
        should1(aix != NSNotFound, ([NSString stringWithFormat:@"Index of %@ in %@ returns %u", objs[ix], [a description], aix]));
        should([a objectAtIndex:aix] == objs[ix]);
        bix = [a indexOfObject:[NSNumber numberWithInt:nums[ix] + 1000] inArraySortedUsingSelector:@selector(compare:)];
        should1(bix == NSNotFound, ([NSString stringWithFormat:@"Index of %d in %@ returns %u", nums[ix] + 1000, [a description], bix]));
        cix = [a indexOfObject:[NSNumber numberWithInt:nums[ix] - 1000] inArraySortedUsingSelector:@selector(compare:)];
        should1(cix == NSNotFound, ([NSString stringWithFormat:@"Index of %d in %@ returns %u", nums[ix] - 1000, [a description], cix]));
    }
    for(ix = 0; ix < NNUM; ix++) {
        NSUInteger aix, bix, cix;
        NSString *obj = [NSString stringWithFormat:@"%+015d", nums[ix]];
        
        aix = [b indexOfObject:obj inArraySortedUsingSelector:@selector(compare:)];
        should1(aix != NSNotFound, ([NSString stringWithFormat:@"Index of %d in %@ returns %u", nums[ix], [b description], aix]));
        should([[b objectAtIndex:aix] intValue] == nums[ix]);
        aix = [b indexOfObjectIdenticalTo:obj inArraySortedUsingSelector:@selector(compare:)];
        should1(aix == NSNotFound, ([NSString stringWithFormat:@"Index of %@ in %@ returns %u", dobjs[ix], [b description], aix]));
        shouldBeEqual(obj, dobjs[ix]);
        aix = [b indexOfObjectIdenticalTo:dobjs[ix] inArraySortedUsingSelector:@selector(compare:)];
        should1(aix != NSNotFound, ([NSString stringWithFormat:@"Index of %@ in %@ returns %u", dobjs[ix], [b description], aix]));
        should([b objectAtIndex:aix] == dobjs[ix]);
        bix = [b indexOfObject:[NSString stringWithFormat:@"%+015d", nums[ix] + 1000] inArraySortedUsingSelector:@selector(compare:)];
        should1(bix == NSNotFound, ([NSString stringWithFormat:@"Index of %d in %@ returns %u", nums[ix] + 1000, [b description], bix]));
        cix = [b indexOfObject:[NSString stringWithFormat:@"%+015d", nums[ix] - 1000] inArraySortedUsingSelector:@selector(compare:)];
        should1(cix == NSNotFound, ([NSString stringWithFormat:@"Index of %d in %@ returns %u", nums[ix] - 1000, [b description], cix]));
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
    should([b isSortedUsingSelector:@selector(caseInsensitiveCompare:)]);
    shouldnt([b isSortedUsingSelector:@selector(compare:)]);
    
    // repeat the test with the case-insensitive-sorted values
    for(ix = 0; ix < NNUM; ix++) {
        NSUInteger aix;
        NSString *obj = [NSString stringWithFormat:@"ABCDE%+015d789", nums[ix]];
        
        should([obj caseInsensitiveCompare:dobjs[ix]] == NSOrderedSame);
        shouldnt([obj compare:dobjs[ix]] == NSOrderedSame);

        aix = [b indexOfObject:obj inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)];
        should1(aix != NSNotFound, ([NSString stringWithFormat:@"Index of %d in %@ returns %u", nums[ix], [b description], aix]));
        should(([[[b objectAtIndex:aix] substringWithRange:(NSRange){5,15}] intValue]) == nums[ix]);
        
        aix = [b indexOfObjectIdenticalTo:obj inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)];
        should1(aix == NSNotFound, ([NSString stringWithFormat:@"Index of %@ in %@ returns %u", dobjs[ix], [b description], aix]));
        
        aix = [b indexOfObject:obj inArraySortedUsingSelector:@selector(compare:)];
        should1(aix == NSNotFound, ([NSString stringWithFormat:@"Index of %@ in %@ returns %u", dobjs[ix], [b description], aix]));
        
        aix = [b indexOfObjectIdenticalTo:dobjs[ix] inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)];
        should1(aix != NSNotFound, ([NSString stringWithFormat:@"Index of %@ in %@ returns %u", dobjs[ix], [b description], aix]));
        should([b objectAtIndex:aix] == dobjs[ix]);
    }
    
   // NSLog(@"a = %@", [a description]);
   // NSLog(@"b = %@", [b description]);
    
    NSMutableArray *copyA = [NSMutableArray arrayWithArray:a];
    NSMutableArray *copyB = [NSMutableArray arrayWithArray:b];
    for(ix = 0; ix < NNUM; ix++) {
        unsigned c0, c1;
        
        c0 = [a count];
        [a removeObjectIdenticalTo:objs[ix] fromArraySortedUsingSelector:@selector(compare:)];
        c1 = [a count];
        should(c0 == c1 + 1);
        // Check that duplicate values either are, or are not, still in the array (as appropriate)
        if (num_is_last[ix]) {
            should([a indexOfObjectIdenticalTo:objs[ix]] == NSNotFound);
        } else {
            should([a indexOfObjectIdenticalTo:objs[ix]] != NSNotFound);
        }

        c0 = [b count];
        [b removeObjectIdenticalTo:dobjs[ix] fromArraySortedUsingSelector:@selector(caseInsensitiveCompare:)];
        c1 = [b count];
        should(c0 == c1 + 1);
        should([b indexOfObjectIdenticalTo:dobjs[ix]] == NSNotFound);
        if (num_is_last[ix]) {
            should([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)] == NSNotFound);
        } else {
            should([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(compare:)] == NSNotFound);
            should([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)] != NSNotFound);
        }
    }
    
    // Also try removing them in a different order
    a = copyA;
    b = copyB;
    for(ix = NNUM-1; ix >= 0; ix--) {
        unsigned c0, c1;
        
        c0 = [a count];
        [a removeObjectIdenticalTo:objs[ix] fromArraySortedUsingSelector:@selector(compare:)];
        c1 = [a count];
        should(c0 == c1 + 1);
        // Check that duplicate values either are, or are not, still in the array (as appropriate)
        if (num_is_first[ix]) {
            should([a indexOfObjectIdenticalTo:objs[ix]] == NSNotFound);
        } else {
            should([a indexOfObjectIdenticalTo:objs[ix]] != NSNotFound);
        }
        
        c0 = [b count];
        [b removeObjectIdenticalTo:dobjs[ix] fromArraySortedUsingSelector:@selector(caseInsensitiveCompare:)];
        c1 = [b count];
        should(c0 == c1 + 1);
        should([b indexOfObjectIdenticalTo:dobjs[ix]] == NSNotFound);
        if (num_is_first[ix]) {
            should([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)] == NSNotFound);
        } else {
            should([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(compare:)] == NSNotFound);
            should([b indexOfObject:dobjs[ix] inArraySortedUsingSelector:@selector(caseInsensitiveCompare:)] != NSNotFound);
        }
    }
    
    should([a count] == 0);
    should([b count] == 0);
}

@end


