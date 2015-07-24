// Copyright 2003-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <OmniFoundation/OFUtilities.h> // OFPredicateBlock

@class NSArray, NSPredicate;

@interface OIInspectionSet : NSObject

- (void)addObject:(id)object;
- (void)addObjectsFromArray:(NSArray *)objects;
- (void)removeObject:(id)object;
- (void)removeObjectsInArray:(NSArray *)toRemove;
- (void)removeAllObjects;

- (BOOL)containsObject:(id)object;
- (NSUInteger)count;

- (NSArray *)allObjects;

- (NSArray *)copyObjectsSatisfyingPredicateBlock:(OFPredicateBlock)predicate;
- (NSArray *)copyObjectsSatisfyingPredicate:(NSPredicate *)predicate;
- (void)removeObjectsSatisfyingPredicate:(NSPredicate *)predicate;

- (NSArray *)objectsSortedByInsertionOrder:(NSArray *)someObjects;
- (NSUInteger)insertionOrderForObject:(id)object; // NSNotFound if not present

@end
