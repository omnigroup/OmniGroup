// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniInspector/OIInspectionSet.h 104581 2008-09-06 21:18:23Z kc $

#import <OmniFoundation/OFObject.h>

@class NSArray, NSMutableSet, NSPredicate;

typedef BOOL (*OIInspectionSetPredicateFunction)(id anObject, void *context);

#import <CoreFoundation/CFDictionary.h> // For CFMutableDictionaryRef

@interface OIInspectionSet : OFObject
{
    CFMutableDictionaryRef objects;
    NSUInteger insertionSequence;
}

- (void)addObject:(id)object;
- (void)addObjectsFromArray:(NSArray *)objects;
- (void)removeObject:(id)object;
- (void)removeObjectsInArray:(NSArray *)toRemove;

- (BOOL)containsObject:(id)object;
- (NSUInteger)count;

- (NSArray *)allObjects;

- (NSArray *)copyObjectsSatisfyingPredicate:(NSPredicate *)predicate;
- (void)removeObjectsSatisfyingPredicate:(NSPredicate *)predicate;
- (NSArray *)copyObjectsSatisfyingPredicateFunction:(OIInspectionSetPredicateFunction)predicate context:(void *)context;

- (NSArray *)objectsSortedByInsertionOrder:(NSArray *)someObjects;
- (NSUInteger)insertionOrderForObject:(id)object; // NSNotFound if not present

@end
