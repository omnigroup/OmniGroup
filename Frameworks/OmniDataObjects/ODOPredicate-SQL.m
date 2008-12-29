// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOPredicate-SQL.h"

#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/ODOEntity.h>

RCS_ID("$Id$")

@implementation NSPredicate (SQL)
- (BOOL)_appendSQL:(NSMutableString *)sql entity:(ODOEntity *)entity constants:(NSMutableArray *)constants error:(NSError **)outError;
{
    // Suck private classes.  We use Foundation's private classes on the Mac and ours on the phone.
    NSString *className = NSStringFromClass([self class]);
    
#if ODO_REPLACE_NSPREDICATE
    if ([className isEqualToString:@"ODOTruePredicate"]) {
        [sql appendString:@"1=1"];
        return YES;
    }
    if ([className isEqualToString:@"ODOFalsePredicate"]) {
        [sql appendString:@"1=0"];
        return YES;
    }
#else
    if ([className isEqualToString:@"NSTruePredicate"]) {
        [sql appendString:@"1=1"];
        return YES;
    }
    if ([className isEqualToString:@"NSFalsePredicate"]) {
        [sql appendString:@"1=0"];
        return YES;
    }
#endif
    
    OBRequestConcreteImplementation(self, _cmd);
    return NO;
}
@end

@interface NSCompoundPredicate (SQL)
@end
@implementation NSCompoundPredicate (SQL)

static BOOL _appendCompound(NSCompoundPredicate *self, NSString *conj, NSMutableString *sql, ODOEntity *entity, NSMutableArray *constants, NSError **outError)
{
    NSArray *predicates = [self subpredicates];
    unsigned int predicateIndex, predicateCount = [predicates count];
    for (predicateIndex = 0; predicateIndex < predicateCount; predicateIndex++) {
        NSPredicate *predicate = [predicates objectAtIndex:predicateIndex];
        if (predicateIndex != 0)
            [sql appendString:conj];
        if (![predicate _appendSQL:sql entity:entity constants:constants error:outError])
            return NO;
    }
    return YES;
}

- (BOOL)_appendSQL:(NSMutableString *)sql entity:(ODOEntity *)entity constants:(NSMutableArray *)constants error:(NSError **)outError;
{
    [sql appendString:@"("];
    switch ([self compoundPredicateType]) {
        case NSNotPredicateType: {
            OBASSERT([[self subpredicates] count] == 1);
            [sql appendString:@"NOT "];
            if (![[[self subpredicates] lastObject] _appendSQL:sql entity:entity constants:constants error:outError])
                return NO;
            break;
        }
        case NSAndPredicateType:
            if (!_appendCompound(self, @" AND ", sql, entity, constants, outError))
                return NO;
            break;
        case NSOrPredicateType:
            if (!_appendCompound(self, @" OR ", sql, entity, constants, outError))
                return NO;
            break;
    }
    [sql appendString:@")"];
    return YES;
}

@end

@interface NSComparisonPredicate (SQL)
@end
@implementation NSComparisonPredicate (SQL)

static NSString * const ODOEqualOp = @" = ";
static NSString * const ODONotEqualOp = @" != ";

static BOOL _appendLHSOpRHS(NSComparisonPredicate *self, NSString *op, NSMutableString *sql, ODOEntity *entity, NSMutableArray *constants, NSError **outError)
{
    NSExpression *lhs = [self leftExpression];
    NSExpression *rhs = [self rightExpression];
    
    // Don't allow NULL on the lhs -- we'd need to do extra work to make this work right
    OBASSERT(([lhs expressionType] != NSConstantValueExpressionType) || OFNOTNULL([lhs constantValue]));
             
    if (![lhs _appendSQL:sql entity:entity constants:constants error:outError])
        return NO;
    
    // comparison against NULL can't use = and !=.
    if ([rhs expressionType] == NSConstantValueExpressionType && OFISNULL([rhs constantValue])) {
        if (op == ODOEqualOp)
            [sql appendString:@" IS NULL"];
        else if (op == ODONotEqualOp)
            [sql appendString:@" IS NOT NULL"];
        else {
            // Unsupported comparison vs. NULL
            OBRequestConcreteImplementation(self, @selector(_appendLHSOpRHS));
            return NO;
        }
    } else {
        [sql appendString:op];
        if (![rhs _appendSQL:sql entity:entity constants:constants error:outError])
            return NO;
    }
    
    return YES;
}

typedef struct {
    BOOL isFirst;
    NSMutableString *sql;
    NSMutableArray *constants;
} AppendInExpressionValueContext;

static void _appendInExpressionValue(const void *value, void *context)
{
    id object = (id)value;
    AppendInExpressionValueContext *ctx = context;
    
    if ([object isKindOfClass:[ODOObject class]])
        object = [[object objectID] primaryKey];
    if (OFISNULL(object))
        object = [NSNull null];
    [ctx->constants addObject:object];
    
    if (ctx->isFirst) {
        ctx->isFirst = NO;
        [ctx->sql appendString:@"?"];
    } else
        [ctx->sql appendString:@", ?"];
}

- (BOOL)_appendSQL:(NSMutableString *)sql entity:(ODOEntity *)entity constants:(NSMutableArray *)constants error:(NSError **)outError;
{
    OBPRECONDITION([self comparisonPredicateModifier] == NSDirectPredicateModifier);
    
    NSPredicateOperatorType opType = [self predicateOperatorType];
    switch (opType) {
        case NSLessThanPredicateOperatorType:
            return _appendLHSOpRHS(self, @" < ", sql, entity, constants, outError);
        case NSLessThanOrEqualToPredicateOperatorType:
            return _appendLHSOpRHS(self, @" <= ", sql, entity, constants, outError);
        case NSGreaterThanPredicateOperatorType:
            return _appendLHSOpRHS(self, @" > ", sql, entity, constants, outError);
        case NSGreaterThanOrEqualToPredicateOperatorType:
            return _appendLHSOpRHS(self, @" >= ", sql, entity, constants, outError);
        case NSEqualToPredicateOperatorType:
            return _appendLHSOpRHS(self, ODOEqualOp, sql, entity, constants, outError);
        case NSNotEqualToPredicateOperatorType:
            return _appendLHSOpRHS(self, ODONotEqualOp, sql, entity, constants, outError);
        case NSInPredicateOperatorType: {
            NSExpression *lhs = [self leftExpression];
            NSExpression *rhs = [self rightExpression];

            if (![lhs _appendSQL:sql entity:entity constants:constants error:outError])
                return NO;
            [sql appendString:@" IN ("];
            
            // 10.5 adds support for fetch request expression for subqueries, but we will support static values, sets and arrays thereof.
            if ([rhs expressionType] != NSConstantValueExpressionType) {
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to create SQL query.", nil, OMNI_BUNDLE, @"error description");
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable convert IN expression with non-constant value; %@.", nil, OMNI_BUNDLE, @"error reason"), rhs];
                ODOError(outError, ODOUnableToCreateSQLStatement, description, reason, nil);
                OBASSERT_NOT_REACHED("Fix me");
                return NO;
            }
            id constant = [rhs constantValue];
            
            AppendInExpressionValueContext ctx;
            memset(&ctx, 0, sizeof(ctx));
            ctx.isFirst = YES;
            ctx.sql = sql;
            ctx.constants = constants;
            
            if ([constant isKindOfClass:[NSSet class]])
                CFSetApplyFunction((CFSetRef)constant, _appendInExpressionValue, &ctx);
            else if ([constant isKindOfClass:[NSArray class]])
                CFArrayApplyFunction((CFArrayRef)constant, CFRangeMake(0, [constant count]), _appendInExpressionValue, &ctx);
            else {
                OBASSERT_NOT_REACHED("What kind did we get?");  // Maybe a naked object or value?
                _appendInExpressionValue(constant, &ctx);
            }
            [sql appendString:@")"];
            return YES;
        }
        default: {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to create SQL query.", nil, OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable convert predicate of type %d (%@).", nil, OMNI_BUNDLE, @"error reason"), opType, self];
            ODOError(outError, ODOUnableToCreateSQLStatement, description, reason, nil);
            OBASSERT_NOT_REACHED("Fix me");
            return NO;
        }
    }
    
    OBRequestConcreteImplementation(self, _cmd);
    return NO;
}

@end

@implementation NSExpression (SQL)

- (BOOL)_appendSQL:(NSMutableString *)sql entity:(ODOEntity *)entity constants:(NSMutableArray *)constants error:(NSError **)outError;
{
    NSExpressionType type = [self expressionType];
    switch (type) {
        case NSKeyPathExpressionType: {
            NSString *keyPath = [self keyPath];
            if ([keyPath containsString:@"."]) {
                // OmniFocusModel needs to use in-memory predicates of the form %K.%K where the joined key is the primary key of the destination.  In this case we can use the foreign key locally.
                NSArray *components = [keyPath componentsSeparatedByString:@"."];
                if ([components count] == 2) {
                    NSString *firstKey = [components objectAtIndex:0];
                    NSString *secondKey = [components objectAtIndex:1];
                    
                    ODOProperty *firstProp = [entity propertyNamed:firstKey];
                    if ([firstProp isKindOfClass:[ODORelationship class]]) {
                        ODOEntity *destEntity = [(ODORelationship *)firstProp destinationEntity];
                        if (OFISEQUAL([[destEntity primaryKeyAttribute] name], secondKey)) {
                            // Phew.  Just use the first key as that is the name of the source entities foreign key.
                            [sql appendString:firstKey];
                            return YES;
                        }
                    }
                }
                
                OBASSERT_NOT_REACHED("Didn't recognize key path form");
            }
            
            [sql appendString:keyPath];
            return YES;
        }
        case NSConstantValueExpressionType: {
            id constant = [self constantValue];
            if (!constant)
                constant = [NSNull null];
            else if ([constant isKindOfClass:[ODOObject class]])
                constant = [[(ODOObject *)constant objectID] primaryKey];

            [constants addObject:constant];
            [sql appendString:@"?"];
            return YES;
        }
        case NSEvaluatedObjectExpressionType: {
            [sql appendString:[[entity primaryKeyAttribute] name]];
            return YES;
        }
        default: {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to create SQL query.", nil, OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable convert expression of type %d (%@).", nil, OMNI_BUNDLE, @"error reason"), type, self];
            ODOError(outError, ODOUnableToCreateSQLStatement, description, reason, nil);
            OBASSERT_NOT_REACHED("Fix me");
            return NO;
        }
    }
}

@end
