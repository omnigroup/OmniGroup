// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOPredicate.h> // Get the #defines for NSPredicate or ODOPredicate and friends
#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSCompoundPredicate.h>

NS_ASSUME_NONNULL_BEGIN

@class ODOEntity;

extern NSPredicate *ODOCompareSelfToValuePredicate(NSPredicateOperatorType op, id value);

extern NSPredicate *ODOKeyPathEqualToValuePredicate(NSString *keyPath, id _Nullable value);
extern NSPredicate *ODOKeyPathNotEqualToValuePredicate(NSString *keyPath, id _Nullable value);
extern NSPredicate *ODOKeyPathCompareToValuePredicate(NSString *keyPath, NSPredicateOperatorType op, id _Nullable value);
extern NSPredicate *ODOKeyPathTruePredicate(NSString *keyPath);
extern NSPredicate *ODOKeyPathFalsePredicate(NSString *keyPath);

extern NSPredicate *ODOAndPredicates(NSPredicate *firstPredicate, ...) NS_REQUIRES_NIL_TERMINATION;
extern NSPredicate *ODOOrPredicates(NSPredicate *firstPredicate, ...) NS_REQUIRES_NIL_TERMINATION;

// Helpers that will build the predicate if needed, or return the single predicate if the array only has one object
extern NSPredicate *ODOAndPredicateFromPredicates(NSArray <NSPredicate *> *predicates);
extern NSPredicate *ODOOrPredicateFromPredicates(NSArray <NSPredicate *> *predicates);

extern BOOL ODOIsTruePredicate(NSPredicate *predicate);
extern BOOL ODOIsFalsePredicate(NSPredicate *predicate);

@interface NSPredicate (ODOExtensions)

typedef BOOL (^ODOCompiledPredicate)(id object);

/// Returns a block that can be used to evaluate the predicate, but only accepts instances of the instanceClass of the specified entity.
- (ODOCompiledPredicate)copyCompiledPredicateWithEntity:(ODOEntity *)entity NS_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END
