// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOPredicate.h> // Get the #defines for NSPredicate or ODOPredicate and friends
#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSCompoundPredicate.h>

NS_ASSUME_NONNULL_BEGIN

extern NSPredicate *ODOCompareSelfToValuePredicate(NSPredicateOperatorType op, id value);

extern NSPredicate *ODOKeyPathEqualToValuePredicate(NSString *keyPath, id _Nullable value);
extern NSPredicate *ODOKeyPathCompareToValuePredicate(NSString *keyPath, NSPredicateOperatorType op, id _Nullable value);
extern NSPredicate *ODOKeyPathTruePredicate(NSString *keyPath);
extern NSPredicate *ODOKeyPathFalsePredicate(NSString *keyPath);

extern NSPredicate *ODOMakeCompoundPredicate(NSCompoundPredicateType type, NSPredicate *firstPredicate, va_list args);
extern NSPredicate *ODOAndPredicates(NSPredicate *firstPredicate, ...) NS_REQUIRES_NIL_TERMINATION;
extern NSPredicate *ODOOrPredicates(NSPredicate *firstPredicate, ...) NS_REQUIRES_NIL_TERMINATION;

extern BOOL ODOIsTruePredicate(NSPredicate *predicate);

NS_ASSUME_NONNULL_END
