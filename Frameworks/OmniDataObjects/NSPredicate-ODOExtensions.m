// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniDataObjects/NSPredicate-ODOExtensions.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

// Same as 'SELF <op> %@'
NSPredicate *ODOCompareSelfToValuePredicate(NSPredicateOperatorType op, id value)
{
    NSExpression *selfExpression = [NSExpression expressionForEvaluatedObject];
    NSExpression *valueExpression = [NSExpression expressionForConstantValue:value];
    return [[[NSComparisonPredicate alloc] initWithLeftExpression:selfExpression rightExpression:valueExpression modifier:0 type:op options:0] autorelease];
}

// Same as '%K <op> %@'
NSPredicate *ODOKeyPathCompareToValuePredicate(NSString *keyPath, NSPredicateOperatorType op, id _Nullable value)
{
    NSExpression *keyPathExpression = [NSExpression expressionForKeyPath:keyPath];
    NSExpression *valueExpression = [NSExpression expressionForConstantValue:value];
    
    // TODO: Options.  Support for case-insensitivity/diacritic.  I don't think we search by name in SQL anywhere (string comparisons are for primary keys), but might eventually.
    return [[[NSComparisonPredicate alloc] initWithLeftExpression:keyPathExpression rightExpression:valueExpression modifier:NSDirectPredicateModifier type:op options:0] autorelease];
}

// Same as '%K = %@'
NSPredicate *ODOKeyPathEqualToValuePredicate(NSString *keyPath, id _Nullable value)
{
    return ODOKeyPathCompareToValuePredicate(keyPath, NSEqualToPredicateOperatorType, value);
}

// Same as '%K = YES'
NSPredicate *ODOKeyPathTruePredicate(NSString *keyPath)
{
    return ODOKeyPathEqualToValuePredicate(keyPath, [NSNumber numberWithBool:YES]);
}

// Same as '%K = NO'
NSPredicate *ODOKeyPathFalsePredicate(NSString *keyPath)
{
    return ODOKeyPathEqualToValuePredicate(keyPath, [NSNumber numberWithBool:NO]);
}

NSPredicate *ODOMakeCompoundPredicate(NSCompoundPredicateType type, NSPredicate *firstPredicate, va_list args)
{
    OBPRECONDITION(firstPredicate != nil);
    
    NSMutableArray *predicates = [NSMutableArray arrayWithObject:firstPredicate];
    NSPredicate *predicate;
    while ((predicate = va_arg(args, NSPredicate *)))
        [predicates addObject:predicate];

    return [[[NSCompoundPredicate alloc] initWithType:type subpredicates:predicates] autorelease];
}

NSPredicate *ODOAndPredicates(NSPredicate *firstPredicate, ...)
{
    va_list argList;
    va_start(argList, firstPredicate);
    NSPredicate *result = ODOMakeCompoundPredicate(NSAndPredicateType, firstPredicate, argList);
    va_end(argList);
    return result;
}

NSPredicate *ODOOrPredicates(NSPredicate *firstPredicate, ...)
{
    va_list argList;
    va_start(argList, firstPredicate);
    NSPredicate *result = ODOMakeCompoundPredicate(NSOrPredicateType, firstPredicate, argList);
    va_end(argList);
    return result;
}

BOOL ODOIsTruePredicate(NSPredicate *predicate)
{
    OBPRECONDITION(predicate != nil);
    if (predicate == nil) {
        return NO;
    }
    
    static NSPredicate *truePredicate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        truePredicate = [NSPredicate predicateWithValue:YES];
    });
    
    return [predicate isEqual:truePredicate];
}

NS_ASSUME_NONNULL_END
