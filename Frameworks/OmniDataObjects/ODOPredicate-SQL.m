// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOPredicate-SQL.h>

#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/ODOEntity.h>
#import <OmniDataObjects/ODOPredicate-SQL.h>
#import <OmniFoundation/OFBinding.h>

@import Foundation;

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

#define ODO_STARTS_WITH "ODOStartsWith"
const char * const ODOComparisonPredicateStartsWithFunctionName = ODO_STARTS_WITH;
#define ODO_CONTAINS "ODOContains"
const char * const ODOComparisonPredicateContainsFunctionName = ODO_CONTAINS;

@implementation ODOSQLTable
{
    __unsafe_unretained ODOEntity *_currentEntity; // retained by model/caller
    NSUInteger _nextAliasIndex;
    NSMutableDictionary <NSString *, NSString *> *_entityNameToAlias;
}

- initWithEntity:(ODOEntity *)entity;
{
    self = [super init];
    
    _currentEntity = entity; // unretained.
    _entityNameToAlias = [[NSMutableDictionary alloc] init];
    _entityNameToAlias[entity.name] = @"t0";
    _nextAliasIndex = 1;
    return self;
}

- (void)dealloc;
{
    // _currentEntity is unretained
    [_entityNameToAlias release];
    [super dealloc];
}

- (void)withEntities:(NSArray <ODOEntity *> *)entities perform:(void (NS_NOESCAPE ^)(void))action;
{
    for (ODOEntity *entity in entities) {
        NSString *alias = [[NSString alloc] initWithFormat:@"t%ld", _nextAliasIndex];
        _nextAliasIndex++;

        OBASSERT(_entityNameToAlias[entity.name] == nil);
        _entityNameToAlias[entity.name] = alias;

        [alias release];
    }

    ODOEntity *previousEntity = _currentEntity;
    _currentEntity = [entities lastObject];

    action();

    _currentEntity = previousEntity;

    for (ODOEntity *entity in entities) {
        [_entityNameToAlias removeObjectForKey:entity.name];
    }
}

- (NSString *)currentAlias;
{
    return [self aliasForEntity:_currentEntity];
}

- (nullable NSString *)aliasForEntity:(ODOEntity *)entity;
{
    return _entityNameToAlias[entity.name];
}

@end

@implementation NSPredicate (ODO_SQL)
- (BOOL)appendSQL:(NSMutableString *)sql table:(ODOSQLTable *)table constants:(NSMutableArray *)constants error:(NSError **)outError;
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

@interface NSCompoundPredicate (ODO_SQL)
@end
@implementation NSCompoundPredicate (ODO_SQL)

#ifdef DEBUG
- (NSString *)description;
{
    NSString *operator = @"";
    switch (self.compoundPredicateType) {
        case NSNotPredicateType: operator = @"not"; break;
        case NSAndPredicateType: operator = @"and"; break;
        case NSOrPredicateType: operator = @"or"; break;
    }
    return [NSString stringWithFormat:@"%@ %@", operator, self.subpredicates];
}
#endif

static BOOL _appendCompound(NSArray *predicates, NSString *conj, NSMutableString *sql, ODOSQLTable *table, NSMutableArray *constants, NSError **outError)
{
    BOOL first = YES;
    for (NSPredicate *predicate in predicates) {
        if (!first)
            [sql appendString:conj];
        first = NO;
        if (![predicate appendSQL:sql table:table constants:constants error:outError])
            return NO;
    }
    return YES;
}

- (BOOL)appendSQL:(NSMutableString *)sql table:(ODOSQLTable *)table constants:(NSMutableArray *)constants error:(NSError **)outError;
{
    // NSCompoundPredicate is documented to return TRUE when there are zero subpredicates.
    NSArray *subpredicates = [self subpredicates];
    if ([subpredicates count] == 0) {
        [sql appendString:@"1=1"];
        return YES;
    }
    
    switch ([self compoundPredicateType]) {
        case NSNotPredicateType: {
            // TODO: The behavior of mulitple NOT subpredicates isn't documented. Treating it as 'not any'.
            [sql appendString:@"NOT ("];
            if (!_appendCompound(subpredicates, @" AND ", sql, table, constants, outError))
                return NO;
            break;
        }
        case NSAndPredicateType:
            [sql appendString:@"("];
            if (!_appendCompound(subpredicates, @" AND ", sql, table, constants, outError))
                return NO;
            break;
        case NSOrPredicateType:
            [sql appendString:@"("];
            if (!_appendCompound(subpredicates, @" OR ", sql, table, constants, outError))
                return NO;
            break;
    }
    [sql appendString:@")"];
    return YES;
}

@end

@interface NSComparisonPredicate (ODO_SQL)
@end
@implementation NSComparisonPredicate (ODO_SQL)

static NSString * const ODOEqualOp = @" = ";
static NSString * const ODONotEqualOp = @" != ";

static BOOL _appendLHSOpRHS(NSComparisonPredicate *self, NSString *op, NSMutableString *sql, ODOSQLTable *table, NSMutableArray *constants, NSError **outError)
{
    NSExpression *lhs = [self leftExpression];
    NSExpression *rhs = [self rightExpression];
    
    // Don't allow NULL on the lhs -- we'd need to do extra work to make this work right
    OBASSERT(([lhs expressionType] != NSConstantValueExpressionType) || OFNOTNULL([lhs constantValue]));
             
    if (![lhs appendSQL:sql table:table constants:constants error:outError])
        return NO;
    
    // comparison against NULL can't use = and !=.
    if ([rhs expressionType] == NSConstantValueExpressionType && OFISNULL([rhs constantValue])) {
        if (op == ODOEqualOp)
            [sql appendString:@" IS NULL"];
        else if (op == ODONotEqualOp)
            [sql appendString:@" IS NOT NULL"];
        else {
            // Unsupported comparison vs. NULL
            OBFinishPorting; // Want to throw an exception, but can't use OBRequestConcreteImplementation in a function
            return NO;
        }
    } else {
        [sql appendString:op];
        if (![rhs appendSQL:sql table:table constants:constants error:outError])
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
    else if ([object isKindOfClass:[ODOObjectID class]])
        object = [object primaryKey];
    else if (OFISNULL(object))
        object = [NSNull null];
    [ctx->constants addObject:object];
    
    if (ctx->isFirst) {
        ctx->isFirst = NO;
        [ctx->sql appendString:@"?"];
    } else
        [ctx->sql appendString:@", ?"];
}

static BOOL _appendStringCompareFunction(NSComparisonPredicate *self, NSMutableString *sql, ODOSQLTable *table, NSString *functionName, NSMutableArray *constants, NSError **outError)
{
    NSExpression *lhs = [self leftExpression];
    NSExpression *rhs = [self rightExpression];
    
    [sql appendString:functionName];
    [sql appendString:@"("];
    if (![lhs appendSQL:sql table:table constants:constants error:outError])
        return NO;
    [sql appendString:@", "];
    
    if (![rhs appendSQL:sql table:table constants:constants error:outError])
        return NO;
    
    [sql appendFormat:@", %ld)", [self options]];
    return YES;
}

- (BOOL)appendSQL:(NSMutableString *)sql table:(ODOSQLTable *)table constants:(NSMutableArray *)constants error:(NSError **)outError;
{
    OBPRECONDITION([self comparisonPredicateModifier] == NSDirectPredicateModifier);
    
    NSPredicateOperatorType opType = [self predicateOperatorType];
    switch (opType) {
        case NSLessThanPredicateOperatorType:
            return _appendLHSOpRHS(self, @" < ", sql, table, constants, outError);
        case NSLessThanOrEqualToPredicateOperatorType:
            return _appendLHSOpRHS(self, @" <= ", sql, table, constants, outError);
        case NSGreaterThanPredicateOperatorType:
            return _appendLHSOpRHS(self, @" > ", sql, table, constants, outError);
        case NSGreaterThanOrEqualToPredicateOperatorType:
            return _appendLHSOpRHS(self, @" >= ", sql, table, constants, outError);
        case NSEqualToPredicateOperatorType:
            return _appendLHSOpRHS(self, ODOEqualOp, sql, table, constants, outError);
        case NSNotEqualToPredicateOperatorType:
            return _appendLHSOpRHS(self, ODONotEqualOp, sql, table, constants, outError);
        case NSInPredicateOperatorType: {
            NSExpression *lhs = [self leftExpression];
            NSExpression *rhs = [self rightExpression];

            if (![lhs appendSQL:sql table:table constants:constants error:outError])
                return NO;
            [sql appendString:@" IN ("];
            
            // 10.5 adds support for fetch request expression for subqueries, but we will support static values, sets and arrays thereof.
            if ([rhs expressionType] != NSConstantValueExpressionType) {
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to create SQL query.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable convert IN expression with non-constant value; %@.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), rhs];
                ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
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
        case NSBeginsWithPredicateOperatorType:
            return _appendStringCompareFunction(self, sql, table, (id)CFSTR(ODO_STARTS_WITH), constants, outError);
        case NSContainsPredicateOperatorType:
            return _appendStringCompareFunction(self, sql, table, (id)CFSTR(ODO_CONTAINS), constants, outError);
        default: {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to create SQL query.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable convert predicate of type %lu (%@).", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), opType, self];
            ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
            OBASSERT_NOT_REACHED("Fix me");
            return NO;
        }
    }
    
    OBRequestConcreteImplementation(self, _cmd);
    return NO;
}

@end

@implementation NSExpression (ODO_SQL)

- (BOOL)appendSQL:(NSMutableString *)sql table:(ODOSQLTable *)table constants:(NSMutableArray *)constants error:(NSError **)outError;
{
    NSExpressionType type = [self expressionType];
    switch (type) {
        case NSKeyPathExpressionType: {
            NSString *tableAlias = table.currentAlias;
            NSString *keyPath = [self keyPath];
            if ([keyPath rangeOfString:@"."].length > 0) {
                // OmniFocusModel needs to use in-memory predicates of the form %K.%K where the joined key is the primary key of the destination.  In this case we can use the foreign key locally.
                NSArray *components = [keyPath componentsSeparatedByString:@"."];
                if ([components count] == 2) {
                    NSString *firstKey = [components objectAtIndex:0];
                    NSString *secondKey = [components objectAtIndex:1];
                    
                    ODOProperty *firstProp = [table.currentEntity propertyNamed:firstKey];
                    if ([firstProp isKindOfClass:[ODORelationship class]]) {
                        ODOEntity *destEntity = [(ODORelationship *)firstProp destinationEntity];
                        if (OFISEQUAL([[destEntity primaryKeyAttribute] name], secondKey)) {
                            // Phew.  Just use the first key as that is the name of the source entities foreign key.
                            [sql appendString:tableAlias];
                            [sql appendString:@"."];
                            [sql appendString:firstKey];
                            return YES;
                        }
                    }
                }
                
                OBASSERT_NOT_REACHED("Didn't recognize key path form");
            }
            
            [sql appendString:tableAlias];
            [sql appendString:@"."];
            [sql appendString:keyPath];
            return YES;
        }
        case NSConstantValueExpressionType: {
            id constant = [self constantValue];
            if (!constant)
                constant = [NSNull null];
            else if ([constant isKindOfClass:[ODOObject class]])
                constant = [[(ODOObject *)constant objectID] primaryKey];
            else if ([constant isKindOfClass:[ODOProperty class]]) {
                // Not really a constant but an attribute reference in place of a key path (so that we can have expression with attributes joining across entities).
                ODOProperty *property = (ODOProperty *)constant;
                [sql appendString:[table aliasForEntity:property.entity]];
                [sql appendString:@"."];
                [sql appendString:property.name];
                return YES;
            }

            [constants addObject:constant];
            [sql appendString:@"?"];
            return YES;
        }
        case NSEvaluatedObjectExpressionType: {
            [sql appendString:[[table.currentEntity primaryKeyAttribute] name]];
            return YES;
        }

        default:
            break;
    }

    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to create SQL query.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable convert expression of type %lu (%@).", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), type, self];
    ODOError(outError, ODOUnableToCreateSQLStatement, description, reason);
    OBASSERT_NOT_REACHED("Fix me");
    return NO;
}

@end

@implementation ODORelationshipMatchingCountPredicate

- initWithSourceEntity:(ODOEntity *)sourceEntity relationshipKeyPath:(NSString *)relationshipKeyPath destinationPredicate:(nullable NSPredicate *)destinationPredicate comparison:(NSPredicateOperatorType)comparison comparisonValue:(NSUInteger)comparisonValue;
{
    _sourceEntity = [sourceEntity retain];
    _relationshipKeyPath = [relationshipKeyPath copy];
    _destinationPredicate = [destinationPredicate copy];
    _comparison = comparison;
    _comparisonValue = comparisonValue;

    return self;
}

- (void)dealloc;
{
    [_sourceEntity release];
    [_relationshipKeyPath release];
    [_destinationPredicate release];
    [super dealloc];
}

static NSString * _Nullable _opString(NSPredicateOperatorType op)
{
    switch (op) {
        case NSLessThanPredicateOperatorType:
            return @" < ";
        case NSLessThanOrEqualToPredicateOperatorType:
            return @" <= ";
        case NSGreaterThanPredicateOperatorType:
            return @" > ";
        case NSGreaterThanOrEqualToPredicateOperatorType:
            return @" >= ";
        case NSEqualToPredicateOperatorType:
            return ODOEqualOp;
        case NSNotEqualToPredicateOperatorType:
            return ODONotEqualOp;
        default:
            OBASSERT_NOT_REACHED("Unsupported predicate operator");
            return nil;
    }
}

- (BOOL)appendSQL:(NSMutableString *)sql table:(ODOSQLTable *)table constants:(NSMutableArray *)constants error:(NSError **)outError;
{
    NSMutableArray <ODOEntity *> *entities = [NSMutableArray array];
    NSMutableArray <NSPredicate *> *joinPredicates = [NSMutableArray array];

    // We should have an alias for the current entity already. Collect intermediate entities to make aliases for and build join predicates.
    ODOEntity *currentEntity = _sourceEntity;
    OBASSERT([table aliasForEntity:currentEntity] != nil);

    for (NSString *key in OFKeysForKeyPath(_relationshipKeyPath)) {
        ODORelationship *relationship = currentEntity.relationshipsByName[key];
        assert(relationship);

        ODOProperty *foreignKeyProperty;
        ODOProperty *primaryKeyProperty;

        if (relationship.isToMany) {
            foreignKeyProperty = relationship.destinationEntity.relationshipsByName[relationship.inverseRelationship.name];
            primaryKeyProperty = currentEntity.primaryKeyAttribute;
        } else {
            foreignKeyProperty = currentEntity.relationshipsByName[relationship.name];
            primaryKeyProperty = relationship.destinationEntity.primaryKeyAttribute;
        }

        // Our predicate SQL generation will handle attributes instead of key paths for this case.
        assert(foreignKeyProperty);
        assert(primaryKeyProperty);
        [joinPredicates addObject:[NSPredicate predicateWithFormat:@"%@ = %@", primaryKeyProperty, foreignKeyProperty]];

        currentEntity = relationship.destinationEntity;
        [entities addObject:currentEntity];
    }


    __block BOOL success = YES;

    [table withEntities:entities perform:^{
        // TODO: for "> 0", write "EXISTS (SELECT ...)"? sqlite's optimizer might do this automatically.
        [sql appendString:@"(SELECT COUNT(*) FROM"];

        BOOL firstEntity = YES;
        for (ODOEntity *entity in entities) {
            if (firstEntity) {
                firstEntity = NO;
                [sql appendFormat:@" %@ %@", entity.name, [table aliasForEntity:entity]];
            } else {
                [sql appendFormat:@", %@ %@", entity.name, [table aliasForEntity:entity]];
            }
        }

        [sql appendString:@" WHERE "];

        NSPredicate *joinPredicate;
        if (joinPredicates.count > 0) {
            joinPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:joinPredicates];
        } else {
            joinPredicate = joinPredicates.firstObject;
        }
        success = [joinPredicate appendSQL:sql table:table constants:constants error:outError];
        if (!success) {
            return;
        }

        if (_destinationPredicate) {
            [sql appendString:@" AND ("];
            success = [_destinationPredicate appendSQL:sql table:table constants:constants error:outError];
            [sql appendString:@")"];
        }
        [sql appendString:@")"];

        NSString *opString = _opString(_comparison);
        if (!opString) {
            success = NO;
            return;
        }

        [sql appendFormat:@"%@ ?", opString];
        [constants addObject:@(_comparisonValue)];
    }];

    return success;
}

- (BOOL)evaluateWithObject:(nullable id)object substitutionVariables:(nullable NSDictionary<NSString *,id> *)bindings;
{
    NSSet *destinationObjects = [object valueForKeyPath:_relationshipKeyPath];

    NSUInteger destinationCount;
    if (_destinationPredicate) {
        destinationCount = 0;
        for (id destinationObject in destinationObjects) {
            if ([_destinationPredicate evaluateWithObject:destinationObject]) {
                destinationCount++;
            }
        }
    } else {
        destinationCount = [destinationObjects count];
    }

    switch (_comparison) {
        case NSLessThanPredicateOperatorType:
            return destinationCount < _comparisonValue;

        case NSLessThanOrEqualToPredicateOperatorType:
            return destinationCount <= _comparisonValue;

        case NSGreaterThanPredicateOperatorType:
            return destinationCount > _comparisonValue;

        case NSGreaterThanOrEqualToPredicateOperatorType:
            return destinationCount >= _comparisonValue;

        case NSEqualToPredicateOperatorType:
            return destinationCount == _comparisonValue;

        case NSNotEqualToPredicateOperatorType:
            return destinationCount != _comparisonValue;

        default:
            OBASSERT_NOT_REACHED("Unsupported predicate operator %ld", _comparison);
            return NO;
    }
}

- (NSString *)predicateFormat;
{
    return [NSString stringWithFormat:@"ODO_RELATIONSHIP_MATCHING_COUNT(%@.%@ (%@) %@ %ld)",
            _sourceEntity.name,
            _relationshipKeyPath,
            _destinationPredicate,
            _opString(_comparison),
            _comparisonValue];
}

@end


NS_ASSUME_NONNULL_END
