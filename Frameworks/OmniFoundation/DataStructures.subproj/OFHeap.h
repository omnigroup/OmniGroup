// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <Foundation/NSObjCRuntime.h> // for NSComparisonResult

@class OFHeap;

// Functions used as the comparison in an OFHeap should return NSOrderedAscending if
// object1 should be above the heap as compared to object2.  That is, the 'least'
// object will be returned from the heap first.
typedef NSComparisonResult (*OFHeapComparisonFunction)(OFHeap *heap, __strong void *userInfo, id object1, id object2);


@interface OFHeap : OFObject
{
    __strong id *_objects;
    NSUInteger _count, _capacity;
    OFHeapComparisonFunction _comparisonFunction;
    __strong void *_userInfo;
}

- initWithCapacity:(NSUInteger)newCapacity compareFunction:(OFHeapComparisonFunction)comparisonFunction userInfo:(__strong void *)userInfo;

- initWithCapacity:(NSUInteger)newCapacity compareSelector:(SEL)comparisonSelector;

- (NSUInteger)count;

- (void)addObject:(id)anObject;

- (id)removeObject;
- (id)removeObjectLessThanObject:(id)object;

- (void)removeAllObjects;

- (id)peekObject;

@end
