// Copyright 2000-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/OFBTree.h>
#import <OmniFoundation/OFRandom.h>
#import <stdio.h>
#import <mach/mach.h>
#import <mach/mach_error.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

void *mallocAllocator(OFBTree *btree)
{
    return malloc(btree->nodeSize);
}

void mallocDeallocator(OFBTree *btree, void *node)
{
    free(node);
}

void *pageAllocator(struct _OFBTree *tree)
{
    kern_return_t	err;
    vm_address_t	addr;
    
    err = vm_allocate(mach_task_self(), &addr, vm_page_size, 1);
    if (err) {
        mach_error("vm_allocate", err);
        abort();
    }
    return (void *)addr;
}

void pageDeallocator(OFBTree *btree, void *node)
{
    kern_return_t	err;
    err = vm_deallocate(mach_task_self(), (vm_address_t)node, vm_page_size);
    if (err) {
        mach_error("vm_deallocate", err);
        abort();
    }
}

int testComparator(const OFBTree *btree, const void *a, const void *b)
{
    int avalue = *(const int *)a;
    int bvalue = *(const int *)b;
    return avalue - bvalue;
}

void permute(NSUInteger *numbers, NSUInteger count)
{
    NSUInteger i, j, tmp;
    
    // loop through the vector spwaping each element with another random element
    for (i = 0; i < count; i++) {
        j = OFRandomNext32() % count;
        tmp = numbers[i];
        numbers[i] = numbers[j];
        numbers[j] = tmp;
    }
}

@interface OFBTreeTests : OFTestCase
{
}

@end

@implementation OFBTreeTests

struct expectedEnumeration {
    const int *nums;
    int numCount;
    int pos;
    OFBTreeTests *tester;
    NSString *marker;
};

void checkEnumerator(const OFBTree *tree, void *element, void *arg)
{
    struct expectedEnumeration *expectation = arg;
    int elt = *(int *)element;
    OFBTreeTests *self = expectation->tester;

    should1(expectation->pos < expectation->numCount, expectation->marker);
    should1(elt == expectation->nums[expectation->pos], expectation->marker);
    expectation->pos ++;
}

#define CHECK_ENUMERATION(bTree, numbers...) { static const int nums[] = { numbers }; struct expectedEnumeration ctxt; ctxt.nums = nums; ctxt.numCount = ( sizeof(nums) / sizeof(nums[0]) ); ctxt.pos = 0; ctxt.tester = self; ctxt.marker = [NSString stringWithFormat:@"(Enumeration check at line %d of %s)", __LINE__, __FILE__]; OFBTreeEnumerate(&bTree, checkEnumerator, (void *)&ctxt); should1(ctxt.pos == ctxt.numCount, ctxt.marker); }

// Methods automatically found and invoked by the SenTesting framework

- (void)testBTreeSimple
{
    OFBTree btree;
    int i;

    OFBTreeInit(&btree, sizeof(int) * 16, sizeof(int), mallocAllocator, mallocDeallocator, testComparator);

    i = 1;
    OFBTreeInsert(&btree, &i);
    i = 2;
    OFBTreeInsert(&btree, &i);
    i = 3;
    OFBTreeInsert(&btree, &i);
    i = 4;
    OFBTreeInsert(&btree, &i);
    i = 5;
    OFBTreeInsert(&btree, &i);
    i = 6;
    OFBTreeInsert(&btree, &i);
    i = 7;
    OFBTreeInsert(&btree, &i);
    i = 8;
    OFBTreeInsert(&btree, &i);
    i = 9;
    OFBTreeInsert(&btree, &i);
    i = 10;
    OFBTreeInsert(&btree, &i);

    CHECK_ENUMERATION(btree, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10);

    should(6 == *(int *)OFBTreeFindNear(&btree, NULL, 6, NO));
    should(10 == *(int *)OFBTreeFindNear(&btree, NULL, 10, NO));
    should(NULL == OFBTreeFindNear(&btree, NULL, 11, NO));
    should(4 == *(int *)OFBTreeFindNear(&btree, NULL, -7, NO));
    should(1 == *(int *)OFBTreeFindNear(&btree, NULL, -10, NO));
    should(NULL == OFBTreeFindNear(&btree, NULL, -11, NO));
    
    i = 4;
    should(4 == *(int *)OFBTreeFind(&btree, &i));
    i = 7;
    should(7 == *(int *)OFBTreeFind(&btree, &i));

    i = 4;
    should(3 == *(int *)OFBTreePrevious(&btree, &i));
    should(5 == *(int *)OFBTreeNext(&btree, &i));
    i = 10;
    should(9 == *(int *)OFBTreePrevious(&btree, &i));
    should(NULL == OFBTreeNext(&btree, &i));
    i = 1;
    should(NULL == OFBTreePrevious(&btree, &i));
    should(2 == *(int *)OFBTreeNext(&btree, &i));

    i = 6;
    OFBTreeDelete(&btree, &i);
    i = 2;
    OFBTreeDelete(&btree, &i);

    CHECK_ENUMERATION(btree, 1, 3, 4, 5, 7, 8, 9, 10);

    i = 1;
    OFBTreeDelete(&btree, &i);
    CHECK_ENUMERATION(btree, 3, 4, 5, 7, 8, 9, 10);
    i = 10;
    OFBTreeDelete(&btree, &i);
    CHECK_ENUMERATION(btree, 3, 4, 5, 7, 8, 9);
    
    i = 5;
    should(3 == *(int *)OFBTreeFindNear(&btree, &i, -2, NO));
    should(4 == *(int *)OFBTreeFindNear(&btree, &i, -2, YES));
    should(7 == *(int *)OFBTreeFindNear(&btree, &i, 1, NO));
    should(7 == *(int *)OFBTreeFindNear(&btree, &i, 1, YES));
    i = 9;
    should(3 == *(int *)OFBTreeFindNear(&btree, &i, -5, NO));
    should(3 == *(int *)OFBTreeFindNear(&btree, &i, -6, YES));
    i = 6;
    should(3 == *(int *)OFBTreeFindNear(&btree, &i, -3, NO));
    should(9 == *(int *)OFBTreeFindNear(&btree, &i, 3, NO));
    i = 1;
    should(9 == *(int *)OFBTreeFindNear(&btree, &i, 6, NO));
    should(NULL == OFBTreeFindNear(&btree, &i, 0, NO));
    
    i = 7;
    OFBTreeDelete(&btree, &i);
    i = 5;
    OFBTreeDelete(&btree, &i);
    CHECK_ENUMERATION(btree, 3, 4, 8, 9);
    
    OFBTreeDestroy(&btree);
}

- (void)testBTreeLarge
{
    OFBTree btree;
    NSUInteger *numbers, i, seed;

    if (![[self class] shouldRunSlowUnitTests]) {
        NSLog(@"*** SKIPPING slow test [%@ %@]", [self class], NSStringFromSelector(_cmd));
        return;
    }
    
#define INSERT_COUNT 1000000

    seed = time(NULL);
    srandom((unsigned)seed);
    numbers = malloc(sizeof(*numbers) * INSERT_COUNT);

    OFBTreeInit(&btree, vm_page_size, sizeof(*numbers), pageAllocator, pageDeallocator, testComparator);

    NSLog(@"Inserting 1..%d in random order (seed = %ld)\n", INSERT_COUNT, seed);
    // fill the vector
    for (i = 0; i < INSERT_COUNT; i++)
        numbers[i] = i+1;

    // Insert them all in random order
    permute(numbers, INSERT_COUNT);
    for (i = 0; i < INSERT_COUNT; i++) {
        OFBTreeInsert(&btree, &numbers[i]);
    }

    NSLog(@"Testing btree lookups and traversals");
    // Finding 1..N in random order
    permute(numbers, INSERT_COUNT);
    for (i = 0; i < INSERT_COUNT; i++) {
        NSUInteger *v = OFBTreeFind(&btree, &numbers[i]);
        should(v != NULL);
        STAssertEquals(numbers[i], *v, @"i=%d numbers[i]=%d", i, numbers[i]);
        
        NSUInteger *p = OFBTreeNext(&btree, &numbers[i]);
        if (numbers[i] == INSERT_COUNT) {
            should(p == NULL);
        } else {
            should(p != NULL);
            STAssertEquals(numbers[i]+1, *p, @"i=%d numbers[i]=%d", i, numbers[i]);
        }
        
        p = OFBTreePrevious(&btree, &numbers[i]);
        if (numbers[i] == 1) {
            should(p == NULL);
        } else {
            should(p != NULL);
            STAssertEquals(numbers[i]-1, *p, @"i=%d numbers[i]=%d", i, numbers[i]);
        }
        
        /* This is pretty slow, since OFBTreeFindNear() is doing a linear traversal of the tree, but it should make sure that OFBTreeFindNear() doesn't have any problems traversing things */
        
        int offset = -100;
        p = OFBTreeFindNear(&btree, &numbers[i], offset, NO);
        if (numbers[i] > (unsigned)-offset) {
            STAssertTrue(p != NULL, @"i=%d numbers[i]=%d offset=%d", i, numbers[i], offset);
            STAssertEquals(numbers[i]+offset, *p, @"i=%d numbers[i]=%d offset=%d", i, numbers[i], offset);
        } else {
            STAssertTrue(p == NULL, @"i=%d numbers[i]=%d offset=%d", i, numbers[i], offset);
        }

        offset = 100;
        p = OFBTreeFindNear(&btree, &numbers[i], offset, NO);
        if (numbers[i] <= (INSERT_COUNT-(unsigned)offset)) {
            STAssertTrue(p != NULL, @"i=%d numbers[i]=%d offset=%d", i, numbers[i], offset);
            STAssertEquals(numbers[i]+offset, *p, @"i=%d numbers[i]=%d offset=%d", i, numbers[i], offset);
        } else {
            STAssertTrue(p == NULL, @"i=%d numbers[i]=%d offset=%d", i, numbers[i], offset);
        }
    }

    // Removing 1..N in random order
    NSLog(@"Deleting btree contents in random order");
    permute(numbers, INSERT_COUNT);
    for (i = 0; i < INSERT_COUNT; i++) {
        void *p = OFBTreeNext(&btree, &numbers[i]);
        should(p == NULL || *(unsigned int *)p > numbers[i]);
        p = OFBTreePrevious(&btree, &numbers[i]);
        should(p == NULL || *(unsigned int *)p < numbers[i]);
        
        should(OFBTreeDelete(&btree, &numbers[i]));
        if (i > 0) {
            should(OFBTreeFind(&btree, &numbers[i-1]) == NULL);
        }
        if (i+1 < INSERT_COUNT) {
            void *v = OFBTreeFind(&btree, &numbers[i+1]);
            should(v != NULL && *(unsigned int *)v == numbers[i+1]);
        }
    }

    // I'm too lazy to write a real test, but this will segfault if the tree is not empty
    OFBTreeEnumerate(&btree, NULL, NULL);

    // Finding 1..N in random order
    permute(numbers, INSERT_COUNT);
    for (i = 0; i < INSERT_COUNT; i++) {
        should(OFBTreeFind(&btree, &numbers[i]) == NULL);
    }
    
    // Clean up
    OFBTreeDestroy(&btree);
    free(numbers);
}

@end

