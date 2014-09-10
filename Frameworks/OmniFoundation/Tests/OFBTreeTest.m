// Copyright 2000-2008, 2010-2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFBTree.h>
#import <OmniFoundation/OFRandom.h>
#import <stdio.h>
#import <mach/mach.h>
#import <mach/mach_error.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

static void *mallocAllocator(OFBTree *btree)
{
    return malloc(btree->nodeSize);
}

static void mallocDeallocator(OFBTree *btree, void *node)
{
    free(node);
}

static void *pageAllocator(struct _OFBTree *tree)
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

static void pageDeallocator(OFBTree *btree, void *node)
{
    kern_return_t	err;
    err = vm_deallocate(mach_task_self(), (vm_address_t)node, vm_page_size);
    if (err) {
        mach_error("vm_deallocate", err);
        abort();
    }
}

static int testComparator(const OFBTree *btree, const void *a, const void *b)
{
    int avalue = *(const int *)a;
    int bvalue = *(const int *)b;
    return avalue - bvalue;
}

static void permute(NSUInteger *numbers, NSUInteger count)
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
    __unsafe_unretained NSString *marker;
};

#define CHECK_ENUMERATION(bTree, numbers...) do { \
    static const int nums[] = { numbers }; \
    __block struct expectedEnumeration expectation; \
    expectation.nums = nums; \
    expectation.numCount = ( sizeof(nums) / sizeof(nums[0]) ); \
    expectation.pos = 0; \
    expectation.marker = [NSString stringWithFormat:@"(Enumeration check at line %d of %s)", __LINE__, __FILE__]; \
    OFBTreeEnumerate(&bTree, ^(const OFBTree *tree, void *element){ \
        int elt = *(int *)element; \
        XCTAssertTrue(expectation.pos < expectation.numCount, @"%@", expectation.marker); \
        XCTAssertTrue(elt == expectation.nums[expectation.pos], @"%@", expectation.marker); \
        expectation.pos ++; \
    }); \
    XCTAssertTrue(expectation.pos == expectation.numCount, @"%@", expectation.marker); \
} while(0)

// Methods automatically found and invoked by the XCTest framework

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

    XCTAssertTrue(6 == *(int *)OFBTreeFindNear(&btree, NULL, 6, NO));
    XCTAssertTrue(10 == *(int *)OFBTreeFindNear(&btree, NULL, 10, NO));
    XCTAssertTrue(NULL == OFBTreeFindNear(&btree, NULL, 11, NO));
    XCTAssertTrue(4 == *(int *)OFBTreeFindNear(&btree, NULL, -7, NO));
    XCTAssertTrue(1 == *(int *)OFBTreeFindNear(&btree, NULL, -10, NO));
    XCTAssertTrue(NULL == OFBTreeFindNear(&btree, NULL, -11, NO));
    
    i = 4;
    XCTAssertTrue(4 == *(int *)OFBTreeFind(&btree, &i));
    i = 7;
    XCTAssertTrue(7 == *(int *)OFBTreeFind(&btree, &i));

    i = 4;
    XCTAssertTrue(3 == *(int *)OFBTreePrevious(&btree, &i));
    XCTAssertTrue(5 == *(int *)OFBTreeNext(&btree, &i));
    i = 10;
    XCTAssertTrue(9 == *(int *)OFBTreePrevious(&btree, &i));
    XCTAssertTrue(NULL == OFBTreeNext(&btree, &i));
    i = 1;
    XCTAssertTrue(NULL == OFBTreePrevious(&btree, &i));
    XCTAssertTrue(2 == *(int *)OFBTreeNext(&btree, &i));

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
    XCTAssertTrue(3 == *(int *)OFBTreeFindNear(&btree, &i, -2, NO));
    XCTAssertTrue(4 == *(int *)OFBTreeFindNear(&btree, &i, -2, YES));
    XCTAssertTrue(7 == *(int *)OFBTreeFindNear(&btree, &i, 1, NO));
    XCTAssertTrue(7 == *(int *)OFBTreeFindNear(&btree, &i, 1, YES));
    i = 9;
    XCTAssertTrue(3 == *(int *)OFBTreeFindNear(&btree, &i, -5, NO));
    XCTAssertTrue(3 == *(int *)OFBTreeFindNear(&btree, &i, -6, YES));
    i = 6;
    XCTAssertTrue(3 == *(int *)OFBTreeFindNear(&btree, &i, -3, NO));
    XCTAssertTrue(9 == *(int *)OFBTreeFindNear(&btree, &i, 3, NO));
    i = 1;
    XCTAssertTrue(9 == *(int *)OFBTreeFindNear(&btree, &i, 6, NO));
    XCTAssertTrue(NULL == OFBTreeFindNear(&btree, &i, 0, NO));
    
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
        XCTAssertTrue(v != NULL);
        XCTAssertEqual(numbers[i], *v, @"i=%ld numbers[i]=%ld", i, numbers[i]);
        
        NSUInteger *p = OFBTreeNext(&btree, &numbers[i]);
        if (numbers[i] == INSERT_COUNT) {
            XCTAssertTrue(p == NULL);
        } else {
            XCTAssertTrue(p != NULL);
            XCTAssertEqual(numbers[i]+1, *p, @"i=%ld numbers[i]=%ld", i, numbers[i]);
        }
        
        p = OFBTreePrevious(&btree, &numbers[i]);
        if (numbers[i] == 1) {
            XCTAssertTrue(p == NULL);
        } else {
            XCTAssertTrue(p != NULL);
            XCTAssertEqual(numbers[i]-1, *p, @"i=%ld numbers[i]=%ld", i, numbers[i]);
        }
        
        /* This is pretty slow, since OFBTreeFindNear() is doing a linear traversal of the tree, but it should make sure that OFBTreeFindNear() doesn't have any problems traversing things */
        
        int offset = -100;
        p = OFBTreeFindNear(&btree, &numbers[i], offset, NO);
        if (numbers[i] > (unsigned)-offset) {
            XCTAssertTrue(p != NULL, @"i=%ld numbers[i]=%ld offset=%d", i, numbers[i], offset);
            XCTAssertEqual(numbers[i]+offset, *p, @"i=%ld numbers[i]=%ld offset=%d", i, numbers[i], offset);
        } else {
            XCTAssertTrue(p == NULL, @"i=%ld numbers[i]=%ld offset=%d", i, numbers[i], offset);
        }

        offset = 100;
        p = OFBTreeFindNear(&btree, &numbers[i], offset, NO);
        if (numbers[i] <= (INSERT_COUNT-(unsigned)offset)) {
            XCTAssertTrue(p != NULL, @"i=%ld numbers[i]=%ld offset=%d", i, numbers[i], offset);
            XCTAssertEqual(numbers[i]+offset, *p, @"i=%ld numbers[i]=%ld offset=%d", i, numbers[i], offset);
        } else {
            XCTAssertTrue(p == NULL, @"i=%ld numbers[i]=%ld offset=%d", i, numbers[i], offset);
        }
    }

    // Removing 1..N in random order
    NSLog(@"Deleting btree contents in random order");
    permute(numbers, INSERT_COUNT);
    for (i = 0; i < INSERT_COUNT; i++) {
        void *p = OFBTreeNext(&btree, &numbers[i]);
        XCTAssertTrue(p == NULL || *(unsigned int *)p > numbers[i]);
        p = OFBTreePrevious(&btree, &numbers[i]);
        XCTAssertTrue(p == NULL || *(unsigned int *)p < numbers[i]);
        
        XCTAssertTrue(OFBTreeDelete(&btree, &numbers[i]));
        if (i > 0) {
            XCTAssertTrue(OFBTreeFind(&btree, &numbers[i-1]) == NULL);
        }
        if (i+1 < INSERT_COUNT) {
            void *v = OFBTreeFind(&btree, &numbers[i+1]);
            XCTAssertTrue(v != NULL && *(unsigned int *)v == numbers[i+1]);
        }
    }

    // I'm too lazy to write a real test, but this will segfault if the tree is not empty
    OFBTreeEnumerate(&btree, NULL);

    // Finding 1..N in random order
    permute(numbers, INSERT_COUNT);
    for (i = 0; i < INSERT_COUNT; i++) {
        XCTAssertTrue(OFBTreeFind(&btree, &numbers[i]) == NULL);
    }
    
    // Clean up
    OFBTreeDestroy(&btree);
    free(numbers);
}

@end

