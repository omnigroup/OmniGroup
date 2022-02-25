// Copyright 2008-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniDataObjects/NSPredicate-ODOExtensions.h>

#import <OmniDataObjects/ODOEntity.h>
#import <OmniDataObjects/ODOProperty.h>

#import "ODOObject-Accessors.h"

@import OmniFoundation;

OB_REQUIRE_ARC

NS_ASSUME_NONNULL_BEGIN

// Detect when a compound predicate is created with a single subpredicate. This is useful sometimes, but sadly system frameworks often hit this.
#if 0 && defined(DEBUG)

static id (*original_initWithTypeSubpredicates)(NSCompoundPredicate *self, SEL _cmd, NSCompoundPredicateType type, NSArray<NSPredicate *> *subpredicates)  = NULL;

static id replacement_initWithTypeSubpredicates(NSCompoundPredicate *self, SEL _cmd, NSCompoundPredicateType type, NSArray<NSPredicate *> *subpredicates)
{
    // Possibly use ODO{And,Or}PredicateFromPredicates below if this is hit
    OBASSERT_IF(type != NSNotPredicateType, [subpredicates count] > 1, "Avoid creating extra wrappers that just slow down evaluation");
    return original_initWithTypeSubpredicates(self, _cmd, type, subpredicates);
}

static void Initialize(void) __attribute__((constructor));
static void Initialize(void)
{
    original_initWithTypeSubpredicates = (typeof(original_initWithTypeSubpredicates))OBReplaceMethodImplementation([NSCompoundPredicate class], @selector(initWithType:subpredicates:), (IMP)replacement_initWithTypeSubpredicates);
}

#endif


// Same as 'SELF <op> %@'
NSPredicate *ODOCompareSelfToValuePredicate(NSPredicateOperatorType op, id value)
{
    NSExpression *selfExpression = [NSExpression expressionForEvaluatedObject];
    NSExpression *valueExpression = [NSExpression expressionForConstantValue:value];
    return [[NSComparisonPredicate alloc] initWithLeftExpression:selfExpression rightExpression:valueExpression modifier:0 type:op options:0];
}

// Same as '%K <op> %@'
NSPredicate *ODOKeyPathCompareToValuePredicate(NSString *keyPath, NSPredicateOperatorType op, id _Nullable value)
{
    NSExpression *keyPathExpression = [NSExpression expressionForKeyPath:keyPath];
    NSExpression *valueExpression = [NSExpression expressionForConstantValue:value];
    
    // TODO: Options.  Support for case-insensitivity/diacritic.  I don't think we search by name in SQL anywhere (string comparisons are for primary keys), but might eventually.
    return [[NSComparisonPredicate alloc] initWithLeftExpression:keyPathExpression rightExpression:valueExpression modifier:NSDirectPredicateModifier type:op options:0];
}

// Same as '%K = %@'
NSPredicate *ODOKeyPathEqualToValuePredicate(NSString *keyPath, id _Nullable value)
{
    return ODOKeyPathCompareToValuePredicate(keyPath, NSEqualToPredicateOperatorType, value);
}

// Same as '%K != %@'
NSPredicate *ODOKeyPathNotEqualToValuePredicate(NSString *keyPath, id _Nullable value)
{
    return ODOKeyPathCompareToValuePredicate(keyPath, NSNotEqualToPredicateOperatorType, value);
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

static NSArray <NSPredicate *> *ODOGatherPredicates(NSPredicate *firstPredicate, va_list args)
{
    OBPRECONDITION(firstPredicate != nil);
    
    NSMutableArray *predicates = [NSMutableArray arrayWithObject:firstPredicate];
    NSPredicate *predicate;
    while ((predicate = va_arg(args, NSPredicate *)))
        [predicates addObject:predicate];

    return predicates;
}

NSPredicate *ODOAndPredicates(NSPredicate *firstPredicate, ...)
{
    va_list argList;
    va_start(argList, firstPredicate);
    NSArray <NSPredicate *> *predicates = ODOGatherPredicates(firstPredicate, argList);
    va_end(argList);

    return ODOAndPredicateFromPredicates(predicates);
}

NSPredicate *ODOOrPredicates(NSPredicate *firstPredicate, ...)
{
    va_list argList;
    va_start(argList, firstPredicate);
    NSArray <NSPredicate *> *predicates = ODOGatherPredicates(firstPredicate, argList);
    va_end(argList);

    return ODOOrPredicateFromPredicates(predicates);
}

NSPredicate *ODOAndPredicateFromPredicates(NSArray <NSPredicate *> *predicates)
{
    if ([predicates count] == 1) {
        return predicates.firstObject;
    }
    return [NSCompoundPredicate andPredicateWithSubpredicates:predicates];
}

NSPredicate *ODOOrPredicateFromPredicates(NSArray <NSPredicate *> *predicates)
{
    if ([predicates count] == 1) {
        return predicates.firstObject;
    }
    return [NSCompoundPredicate orPredicateWithSubpredicates:predicates];
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

BOOL ODOIsFalsePredicate(NSPredicate *predicate)
{
    OBPRECONDITION(predicate != nil);
    if (predicate == nil) {
        return NO;
    }

    static NSPredicate *falsePredicate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        falsePredicate = [NSPredicate predicateWithValue:NO];
    });

    return [predicate isEqual:falsePredicate];
}

static inline ODOCompiledPredicate _CheckPredicate(ODOCompiledPredicate compiled, NSPredicate *original)
{
#ifdef DEBUG
    return [^(id object){
        BOOL compiledResult = compiled(object);
        BOOL originalResult = [original evaluateWithObject:object];
        OBASSERT(compiledResult == originalResult);
        return compiledResult;
    } copy];
#else
    return [compiled copy];
#endif
}

#define CheckPredicate(compiled) _CheckPredicate(compiled, self)

@implementation NSPredicate (ODOExtensions)

- (ODOCompiledPredicate)copyCompiledPredicateWithEntity:(id)entity;
{
    if (ODOIsTruePredicate(self)) {
        return CheckPredicate(^(id object){
            return YES;
        });
    }
    if (ODOIsFalsePredicate(self)) {
        return CheckPredicate(^(id object){
            return NO;
        });
    }

#ifdef DEBUG
    NSLog(@"🟪 Unable to compile predicate %@", self);
#endif
    return CheckPredicate(^(id object){
        return [self evaluateWithObject:object];
    });
}

@end

@interface NSCompoundPredicate (ODOExtensions)
@end
@implementation NSCompoundPredicate (ODOExtensions)

- (ODOCompiledPredicate)copyCompiledPredicateWithEntity:(id)entity;
{
    NSArray <ODOCompiledPredicate> *compiledSubpredicates = [self.subpredicates arrayByPerformingBlock:^id(NSPredicate *subpredicate){
        return [subpredicate copyCompiledPredicateWithEntity:entity];
    }];

    NSUInteger subpredicateCount = [compiledSubpredicates count];

    switch (self.compoundPredicateType) {
        case NSNotPredicateType: {
            OBASSERT(subpredicateCount == 1);
            ODOCompiledPredicate subpredicate = compiledSubpredicates[0];
            return CheckPredicate(^BOOL(id object){
                return !subpredicate(object);
            });
            break;
        }
        case NSAndPredicateType:
            switch (subpredicateCount) {
                case 0:
                    return ^(id object){
                        return YES; // See NSCompoundPredicate documentation
                    };
                case 1:
                    return compiledSubpredicates[0];
                case 2: {
                    ODOCompiledPredicate subpredicate0 = compiledSubpredicates[0];
                    ODOCompiledPredicate subpredicate1 = compiledSubpredicates[1];
                    return CheckPredicate(^BOOL(id object){
                        return subpredicate0(object) && subpredicate1(object);
                    });
                }
                case 3: {
                    ODOCompiledPredicate subpredicate0 = compiledSubpredicates[0];
                    ODOCompiledPredicate subpredicate1 = compiledSubpredicates[1];
                    ODOCompiledPredicate subpredicate2 = compiledSubpredicates[2];
                    return CheckPredicate(^BOOL(id object){
                        return subpredicate0(object) && subpredicate1(object) && subpredicate2(object);
                    });
                }
                default:
                    return CheckPredicate(^(id object){
                        for (ODOCompiledPredicate subpredicate in compiledSubpredicates) {
                            if (!subpredicate(object)) {
                                return NO;
                            }
                        }
                        return YES;
                    });
            }
            break;
        case NSOrPredicateType:
            switch (subpredicateCount) {
                case 0:
                    return ^(id object){
                        return NO; // See NSCompoundPredicate documentation
                    };
                case 1:
                    return compiledSubpredicates[0];
                case 2: {
                    ODOCompiledPredicate subpredicate0 = compiledSubpredicates[0];
                    ODOCompiledPredicate subpredicate1 = compiledSubpredicates[1];
                    return CheckPredicate(^BOOL(id object){
                        return subpredicate0(object) || subpredicate1(object);
                    });
                }
                case 3: {
                    ODOCompiledPredicate subpredicate0 = compiledSubpredicates[0];
                    ODOCompiledPredicate subpredicate1 = compiledSubpredicates[1];
                    ODOCompiledPredicate subpredicate2 = compiledSubpredicates[2];
                    return CheckPredicate(^BOOL(id object){
                        return subpredicate0(object) || subpredicate1(object) || subpredicate2(object);
                    });
                }
                default:
                    return CheckPredicate(^(id object){
                        for (ODOCompiledPredicate subpredicate in compiledSubpredicates) {
                            if (subpredicate(object)) {
                                return YES;
                            }
                        }
                        return NO;
                    });
            }
            break;
    }
}

@end

@interface NSExpression (ODOExtensions)

typedef id _Nullable (^ODOCompiledExpressionEvaluator)(id _Nullable object);
- (ODOCompiledExpressionEvaluator)copyCompiledExpressionEvaluatorWithEntity:(ODOEntity *)entity NS_RETURNS_RETAINED;

@end
@implementation NSExpression (ODOExtensions)

static inline ODOCompiledExpressionEvaluator _CheckExpression(ODOCompiledExpressionEvaluator compiled, NSExpression *original)
{
#ifdef DEBUG
    return [^id(id object){
        id compiledResult = compiled(object);
        id originalResult = [original expressionValueWithObject:object context:nil];
        OBASSERT(OFISEQUAL(compiledResult, originalResult));
        return compiledResult;
    } copy];
#else
    return [compiled copy];
#endif
}

#define CheckExpression(compiled) _CheckExpression(compiled, self)

- (ODOCompiledExpressionEvaluator)copyCompiledExpressionEvaluatorWithEntity:(ODOEntity *)entity;
{
    switch (self.expressionType) {
        case NSKeyPathExpressionType: {
            ODOProperty *property = [entity propertyNamed:self.keyPath];
            if (!property) {
                break;
            }
            return CheckExpression(^(id object){
                return ODOObjectPrimitiveValueForProperty(object, property);
            });
        }
        case NSConstantValueExpressionType: {
            id constant = self.constantValue;
            return CheckExpression(^(id object){
                return constant;
            });
        }
        default:
            break;
    }

#ifdef DEBUG
    NSLog(@"🟪 Unable to compile expression %@", self);
#endif

    return [^(id object){
        [self expressionValueWithObject:object context:nil];
    } copy];
}

@end

@interface NSComparisonPredicate (ODOExtensions)
@end
@implementation NSComparisonPredicate (ODOExtensions)

- (ODOCompiledPredicate)copyCompiledPredicateWithEntity:(id)entity;
{
    // customSelector is only 'custom' if the operator is NSCustomSelectorPredicateOperatorType. Other
    if (self.comparisonPredicateModifier != NSDirectPredicateModifier) {
        return [super copyCompiledPredicateWithEntity:entity];
    }

    // It might be worth adding a scalar path at some point, but the majority of the 'scalar' values we are likely to hit are things that end up as tagged pointers anyway so not bothering until it shows up as a performance issue.

    ODOCompiledExpressionEvaluator leftEvaluator = [self.leftExpression copyCompiledExpressionEvaluatorWithEntity:entity];
    ODOCompiledExpressionEvaluator rightEvaluator = [self.rightExpression copyCompiledExpressionEvaluatorWithEntity:entity];

    switch (self.predicateOperatorType) {
        case NSLessThanPredicateOperatorType:
            return CheckPredicate(^BOOL(id object){
                return [leftEvaluator(object) compare:rightEvaluator(object)] == NSOrderedAscending;
            });
        case NSEqualToPredicateOperatorType:
            return CheckPredicate(^BOOL(id object){
                return OFISEQUAL(leftEvaluator(object), rightEvaluator(object));
            });
        case NSNotEqualToPredicateOperatorType:
            return CheckPredicate(^BOOL(id object){
                return OFNOTEQUAL(leftEvaluator(object), rightEvaluator(object));
            });
        case NSInPredicateOperatorType:
            return CheckPredicate(^BOOL(id object){
                id lhs = leftEvaluator(object);
                return lhs != nil && [rightEvaluator(object) containsObject:lhs];
            });
        default:
            return [super copyCompiledPredicateWithEntity:entity];
    }
}

@end

NS_ASSUME_NONNULL_END
