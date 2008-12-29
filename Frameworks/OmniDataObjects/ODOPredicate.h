// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOPredicate.h 104583 2008-09-06 21:23:18Z kc $

// The actual device doesn't have NSPredicate and friends.  We need to use these on the Mac to be compatible with NS*Controller and OOTreeController, but we need to implement them ourselves on the phone with _different_ names (in case Apple adds them later).  But, they _are_ in the simulator and there isn't a good way to avoid those definitions there.  So, we'll only do this when building for the device.
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
#define ODO_REPLACE_NSPREDICATE 1
#else
#define ODO_REPLACE_NSPREDICATE 0
#endif

#if ODO_REPLACE_NSPREDICATE

#import <OmniFoundation/OFObject.h>

@class NSArray, NSMutableDictionary;

#define NSExpression ODOExpression
#define NSExpressionType ODOExpressionType
#define NSConstantValueExpressionType ODOConstantValueExpressionType
#define NSEvaluatedObjectExpressionType ODOEvaluatedObjectExpressionType
#define NSVariableExpressionType ODOVariableExpressionType
#define NSKeyPathExpressionType ODOKeyPathExpressionType

#define NSPredicate ODOPredicate

#define NSCompoundPredicate ODOCompoundPredicate
#define NSCompoundPredicateType ODOCompoundPredicateType
#define NSNotPredicateType ODONotPredicateType
#define NSAndPredicateType ODOAndPredicateType
#define NSOrPredicateType ODOOrPredicateType

#define NSComparisonPredicate ODOComparisonPredicate
#define NSPredicateOperatorType ODOPredicateOperatorType
#define NSLessThanPredicateOperatorType ODOLessThanPredicateOperatorType
#define NSLessThanOrEqualToPredicateOperatorType ODOLessThanOrEqualToPredicateOperatorType
#define NSGreaterThanPredicateOperatorType ODOGreaterThanPredicateOperatorType
#define NSGreaterThanOrEqualToPredicateOperatorType ODOGreaterThanOrEqualToPredicateOperatorType
#define NSEqualToPredicateOperatorType ODOEqualToPredicateOperatorType
#define NSNotEqualToPredicateOperatorType ODONotEqualToPredicateOperatorType
#define NSInPredicateOperatorType ODOInPredicateOperatorType

#define NSComparisonPredicateModifier ODOComparisonPredicateModifier
#define NSDirectPredicateModifier ODODirectPredicateModifier

typedef enum {
    NSConstantValueExpressionType = 0, // Expression that always returns the same value
    NSEvaluatedObjectExpressionType, // Expression that always returns the parameter object itself
    NSVariableExpressionType, // Expression that always returns whatever is stored at 'variable' in the bindings dictionary
    NSKeyPathExpressionType, // Expression that returns something that can be used as a key path
//    NSFunctionExpressionType // Expression that returns the result of evaluating a symbol
} NSExpressionType;

@interface  NSExpression : OFObject
{
@private
    NSExpressionType _type;
    id _support;
}
+ (NSExpression *)expressionForEvaluatedObject;
+ (NSExpression *)expressionForConstantValue:(id)obj;
+ (NSExpression *)expressionForKeyPath:(NSString *)keyPath;
- (NSExpressionType)expressionType;
- (id)constantValue;
- (NSString *)keyPath;
- (id)expressionValueWithObject:(id)object context:(NSMutableDictionary *)context;
- (void)appendDescription:(NSMutableString *)desc;
@end

@interface NSPredicate : OFObject
{
}
+ (NSPredicate *)predicateWithValue:(BOOL)value;
- (BOOL)evaluateWithObject:(id)object;
- (void)appendDescription:(NSMutableString *)desc;
@end


typedef enum {
    NSNotPredicateType = 0, 
    NSAndPredicateType,
    NSOrPredicateType,
} NSCompoundPredicateType;
@interface  NSCompoundPredicate : NSPredicate
{
@private
    NSCompoundPredicateType _type;
    NSArray *_subpredicates;
}
+ (NSPredicate *)andPredicateWithSubpredicates:(NSArray *)subpredicates;
- (id)initWithType:(NSCompoundPredicateType)type subpredicates:(NSArray *)subpredicates;
- (NSCompoundPredicateType)compoundPredicateType;
- (NSArray *)subpredicates;
@end


enum {
    NSDirectPredicateModifier = 0, // Do a direct comparison
};
typedef NSUInteger NSComparisonPredicateModifier;

typedef enum {
    NSLessThanPredicateOperatorType = 0, // compare: returns NSOrderedAscending
    NSLessThanOrEqualToPredicateOperatorType, // compare: returns NSOrderedAscending || NSOrderedSame
    NSGreaterThanPredicateOperatorType, // compare: returns NSOrderedDescending
    NSGreaterThanOrEqualToPredicateOperatorType, // compare: returns NSOrderedDescending || NSOrderedSame
    NSEqualToPredicateOperatorType, // isEqual: returns true
    NSNotEqualToPredicateOperatorType, // isEqual: returns false
    //    NSMatchesPredicateOperatorType,
    //    NSLikePredicateOperatorType,
    //    NSBeginsWithPredicateOperatorType,
    //    NSEndsWithPredicateOperatorType,
    NSInPredicateOperatorType, // rhs contains lhs returns true
    //    NSCustomSelectorPredicateOperatorType
} NSPredicateOperatorType;


@interface  NSComparisonPredicate : NSPredicate
{
@private
    NSPredicateOperatorType _type;
    NSExpression *_lhs;
    NSExpression *_rhs;
}

- (id)initWithLeftExpression:(NSExpression *)lhs rightExpression:(NSExpression *)rhs modifier:(NSComparisonPredicateModifier)modifier type:(NSPredicateOperatorType)type options:(unsigned)options;
- (NSPredicateOperatorType)predicateOperatorType;
- (NSComparisonPredicateModifier)comparisonPredicateModifier;
- (NSExpression *)leftExpression;
- (NSExpression *)rightExpression;
@end

#else
    #import <Foundation/NSPredicate.h>
    #import <Foundation/NSCompoundPredicate.h>
    #import <Foundation/NSComparisonPredicate.h>
    #import <Foundation/NSExpression.h>
#endif

extern NSMutableArray *ODOFilteredArrayUsingPredicate(NSArray *array, NSPredicate *predicate);
extern unsigned int ODOCountInArrayMatchingPredicate(NSArray *array, NSPredicate *predicate);
