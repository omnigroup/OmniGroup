// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOPredicate.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOPredicate.m 104583 2008-09-06 21:23:18Z kc $")

#if ODO_REPLACE_NSPREDICATE

@interface ODOTruePredicate : NSPredicate
@end
@implementation ODOTruePredicate
- (BOOL)evaluateWithObject:(id)object;
{
    return YES;
}
- (void)appendDescription:(NSMutableString *)desc;
{
    [desc appendString:@"TRUE"];
}
@end
@interface ODOFalsePredicate : NSPredicate
@end
@implementation ODOFalsePredicate
- (BOOL)evaluateWithObject:(id)object;
{
    return NO;
}
- (void)appendDescription:(NSMutableString *)desc;
{
    [desc appendString:@"FALSE"];
}
@end

@implementation NSPredicate

+ (NSPredicate *)predicateWithValue:(BOOL)value;
{
    return value ? [[[ODOTruePredicate alloc] init] autorelease] : [[[ODOFalsePredicate alloc] init] autorelease];
}
- (BOOL)evaluateWithObject:(id)object;
{
    OBRequestConcreteImplementation(self, _cmd);
    return NO;
}
- (void)appendDescription:(NSMutableString *)desc;
{
    OBRequestConcreteImplementation(self, _cmd);
}
- (NSString *)description;
{
    NSMutableString *result = [NSMutableString string];
    [self appendDescription:result];
    return result;
}

@end

@implementation  NSCompoundPredicate

+ (NSPredicate *)andPredicateWithSubpredicates:(NSArray *)subpredicates;
{
    return [[[self alloc] initWithType:NSAndPredicateType subpredicates:subpredicates] autorelease];
}

- (id)initWithType:(NSCompoundPredicateType)type subpredicates:(NSArray *)subpredicates;
{
    OBPRECONDITION([subpredicates count] > 0);
    OBPRECONDITION(type != NSNotPredicateType || [subpredicates count] == 1); // Not only valid with a single predicate
    _type = type;
    _subpredicates = [[NSArray alloc] initWithArray:subpredicates];
    return self;
}

- (void)dealloc;
{
    [_subpredicates release];
    [super dealloc];
}

- (NSCompoundPredicateType)compoundPredicateType;
{
    return _type;
}

- (NSArray *)subpredicates;
{
    return _subpredicates;
}

- (BOOL)evaluateWithObject:(id)object;
{
    unsigned int predicateIndex = [_subpredicates count];
    switch (_type) {
        case NSAndPredicateType: {
            while (predicateIndex--)
                if (![[_subpredicates objectAtIndex:predicateIndex] evaluateWithObject:object])
                    return NO;
            return YES;
        }
        case NSOrPredicateType: {
            while (predicateIndex--)
                if ([[_subpredicates objectAtIndex:predicateIndex] evaluateWithObject:object])
                    return YES;
            return NO;
        }
        case NSNotPredicateType: {
            return ![[_subpredicates objectAtIndex:0] evaluateWithObject:object];
        }
        default:
            OBRequestConcreteImplementation(self, _cmd);
            return NO;
    }
}

- (void)appendDescription:(NSMutableString *)desc;
{
    unsigned int predicateIndex, predicateCount = [_subpredicates count];
    switch (_type) {
        case NSAndPredicateType: {
            [desc appendString:@"("];
            for (predicateIndex = 0; predicateIndex < predicateCount; predicateIndex++) {
                if (predicateIndex != 0)
                    [desc appendString:@" AND "];
                [[_subpredicates objectAtIndex:predicateIndex] appendDescription:desc];
            }
            [desc appendString:@")"];
            return;
        }
        case NSOrPredicateType: {
            [desc appendString:@"("];
            for (predicateIndex = 0; predicateIndex < predicateCount; predicateIndex++) {
                if (predicateIndex != 0)
                    [desc appendString:@" OR "];
                [[_subpredicates objectAtIndex:predicateIndex] appendDescription:desc];
            }
            [desc appendString:@")"];
            return;
        }
        case NSNotPredicateType: {
            [desc appendString:@"(NOT "];
            [[_subpredicates objectAtIndex:0] appendDescription:desc];
            [desc appendString:@")"];
            return;
        }
        default:
            OBRequestConcreteImplementation(self, _cmd);
            return;
    }
}

@end

@implementation  NSComparisonPredicate
- (id)initWithLeftExpression:(NSExpression *)lhs rightExpression:(NSExpression *)rhs modifier:(NSComparisonPredicateModifier)modifier type:(NSPredicateOperatorType)type options:(unsigned)options;
{
    OBPRECONDITION(lhs);
    OBPRECONDITION(rhs);
    OBPRECONDITION(modifier == NSDirectPredicateModifier);
    OBPRECONDITION(type >= 0);
    OBPRECONDITION(type <= NSInPredicateOperatorType); // last element of the enum
    OBPRECONDITION(options == 0);
    
    _type = type;
    _lhs = [lhs retain];
    _rhs = [rhs retain];
    
    return self;
}
- (void)dealloc;
{
    [_lhs release];
    [_rhs release];
    [super dealloc];
}
- (NSPredicateOperatorType)predicateOperatorType;
{
    return _type;
}
- (NSComparisonPredicateModifier)comparisonPredicateModifier;
{
    return NSDirectPredicateModifier;
}
- (NSExpression *)leftExpression;
{
    return _lhs;
}
- (NSExpression *)rightExpression;
{
    return _rhs;
}

typedef struct {
    id search;
    BOOL contained;
} ContainsApplierContext;

// Map objects to primary keys so we can do things like "object = key1" or "object in (key1, key2)" or "key in (object1, object2)" or any combination thereof.
static id _mapValueForComparison(id value)
{
    if ([value isKindOfClass:[ODOObject class]])
        return [[value objectID] primaryKey];
    if (OFISNULL(value))
        return nil;
    return value;
}

static void _containsApplier(const void *value, void *context)
{
    id object = (id)value;
    ContainsApplierContext *ctx = context;
    
    // Sure'd be cool if we could have a 'stop' return value for appliers
    if (ctx->contained)
        return;
    
    object = _mapValueForComparison(object);
    if (OFISEQUAL(object, ctx->search))
        ctx->contained = YES;
}

- (BOOL)evaluateWithObject:(id)object;
{
    id lhsValue = [_lhs expressionValueWithObject:object context:nil];
    id rhsValue = [_rhs expressionValueWithObject:object context:nil];

    switch (_type) {
        case NSLessThanPredicateOperatorType:
            return [lhsValue compare:rhsValue] == NSOrderedAscending;
        case NSLessThanOrEqualToPredicateOperatorType: {
            NSComparisonResult rc = [lhsValue compare:rhsValue];
            return rc == NSOrderedAscending || rc == NSOrderedSame;
        }
        case NSGreaterThanPredicateOperatorType:
            return [lhsValue compare:rhsValue] == NSOrderedDescending;
        case NSGreaterThanOrEqualToPredicateOperatorType: {
            NSComparisonResult rc = [lhsValue compare:rhsValue];
            return rc == NSOrderedDescending || rc == NSOrderedSame;
        }
        case NSEqualToPredicateOperatorType:
            return OFISEQUAL(lhsValue, rhsValue);
        case NSNotEqualToPredicateOperatorType:
            return OFNOTEQUAL(lhsValue, rhsValue);
        case NSInPredicateOperatorType: {
            // The value is the lhs ("foo IN bar").
            lhsValue = _mapValueForComparison(lhsValue);
            
            OBASSERT(!rhsValue || [rhsValue isKindOfClass:[NSArray class]] || [rhsValue isKindOfClass:[NSSet class]]);
            ContainsApplierContext ctx;
            memset(&ctx, 0, sizeof(ctx));
            ctx.search = lhsValue;
            [rhsValue applyFunction:_containsApplier context:&ctx];
            return ctx.contained;
        }
            
    }
    OBRequestConcreteImplementation(self, _cmd);
    return NO;
}

- (void)appendDescription:(NSMutableString *)desc;
{
    NSString *comparisonString = nil;
    
    switch (_type) {
        case NSLessThanPredicateOperatorType:
            comparisonString = @" < ";
            break;
        case NSLessThanOrEqualToPredicateOperatorType:
            comparisonString = @" <= ";
            break;
        case NSGreaterThanPredicateOperatorType:
            comparisonString = @" > ";
            break;
        case NSGreaterThanOrEqualToPredicateOperatorType:
            comparisonString = @" >= ";
            break;
        case NSEqualToPredicateOperatorType:
            comparisonString = @" = ";
            break;
        case NSNotEqualToPredicateOperatorType:
            comparisonString = @" != ";
            break;
        case NSInPredicateOperatorType: {
            comparisonString = @" IN ";
            break;
        }
            
    }

    [_lhs appendDescription:desc];
    [desc appendString:comparisonString];
    [_rhs appendDescription:desc];
}

- (NSString *)description;
{
    NSMutableString *result = [NSMutableString string];
    [self appendDescription:result];
    return result;
}
@end

@implementation  NSExpression

+ (NSExpression *)expressionForEvaluatedObject;
{
    NSExpression *expression = [[[NSExpression alloc] init] autorelease];
    expression->_type = NSEvaluatedObjectExpressionType;
    expression->_support = nil;
    return expression;
}

+ (NSExpression *)expressionForConstantValue:(id)obj;
{
    NSExpression *expression = [[[NSExpression alloc] init] autorelease];
    expression->_type = NSConstantValueExpressionType;
    expression->_support = [obj retain];
    return expression;
}

+ (NSExpression *)expressionForKeyPath:(NSString *)keyPath;
{
    NSExpression *expression = [[[NSExpression alloc] init] autorelease];
    expression->_type = NSKeyPathExpressionType;
    expression->_support = [keyPath copy];
    return expression;
}

- (void)dealloc;
{
    [_support release];
    [super dealloc];
}

- (NSExpressionType)expressionType;
{
    return _type;
}

- (id)constantValue;
{
    if (_type != NSConstantValueExpressionType) {
        OBRejectInvalidCall(self, _cmd, @"Not a constant value expression!");
        return nil;
    }
    return _support;
}

- (NSString *)keyPath;
{
    if (_type != NSKeyPathExpressionType) {
        OBRejectInvalidCall(self, _cmd, @"Not a key path expression!");
        return nil;
    }
    return _support;
}

- (id)expressionValueWithObject:(id)object context:(NSMutableDictionary *)context;
{
    switch (_type) {
        case NSConstantValueExpressionType:
            return _support;
        case NSEvaluatedObjectExpressionType:
            OBASSERT(_support == nil);
            return object;
        case NSKeyPathExpressionType:
            return [object valueForKeyPath:_support];
        default:
            OBRequestConcreteImplementation(self, _cmd);
            return nil;
    }
}

- (void)appendDescription:(NSMutableString *)desc;
{
    switch (_type) {
        case NSConstantValueExpressionType:
            [desc appendString:_support ? [_support description] : @"NULL"];
            break;
        case NSEvaluatedObjectExpressionType:
            [desc appendString:@"SELF"];
            break;
        case NSKeyPathExpressionType:
            [desc appendString:_support];
            break;
        default:
            OBRequestConcreteImplementation(self, _cmd);
            return;
    }
}

@end

#endif // ODO_REPLACE_NSPREDICATE

NSMutableArray *ODOFilteredArrayUsingPredicate(NSArray *array, NSPredicate *predicate)
{
    NSMutableArray *result = [NSMutableArray array];
    unsigned objectIndex, objectCount = [array count];
    
    for (objectIndex = 0; objectIndex < objectCount; objectIndex++) {
	id object = [array objectAtIndex:objectIndex];
	if ([predicate evaluateWithObject:object])
	    [result addObject:object];
    }
    return result;
}

unsigned int ODOCountInArrayMatchingPredicate(NSArray *array, NSPredicate *predicate)
{
    unsigned int matches = 0;
    unsigned int objectIndex = [array count];
    
    while (objectIndex--) {
        if ([predicate evaluateWithObject:[array objectAtIndex:objectIndex]])
            matches++;
    }
    return matches;
}
