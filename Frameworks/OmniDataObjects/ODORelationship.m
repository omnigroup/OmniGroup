// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODORelationship.h>

#import "ODOProperty-Internal.h"

#import <OmniDataObjects/ODOModel-Creation.h>
#import <OmniDataObjects/ODOEntity.h>
#import <OmniDataObjects/ODOModel.h>

RCS_ID("$Id$")

@implementation ODORelationship

- (void)dealloc;
{
    [_destinationEntity release];
    [_inverseRelationship release];
    [super dealloc];
}

- (BOOL)isToMany;
{
    return ODOPropertyFlags(self).toMany;
}

- (ODOEntity *)destinationEntity;
{
    OBPRECONDITION([_destinationEntity isKindOfClass:[ODOEntity class]]);
    return _destinationEntity;
}

- (ODORelationship *)inverseRelationship;
{
    OBPRECONDITION([_inverseRelationship isKindOfClass:[ODORelationship class]]);
    return _inverseRelationship;
}

- (ODORelationshipDeleteRule)deleteRule;
{
    return _deleteRule;
}

#pragma mark -
#pragma mark Debugging

#ifdef DEBUG
- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@.%@ %@ %@--%@ %@ %@.%@",
            NSStringFromClass([self class]), self,
            [[self entity] name], [self name],
            [NSNumber numberWithInteger:_deleteRule] /*[ODORelationshipDeleteRuleEnumNameTable() nameForEnum:_deleteRule]*/,
            [_inverseRelationship isToMany] ? @"<<" : @"<",
            [self isToMany] ? @">>" : @">",
            [NSNumber numberWithInteger:[_inverseRelationship deleteRule]]/*[ODORelationshipDeleteRuleEnumNameTable() nameForEnum:[_inverseRelationship deleteRule]]*/,
            [[_inverseRelationship entity] name], [_inverseRelationship name]];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:ODOPropertyFlags(self).toMany ? @"true" : @"false" forKey:@"isToMany"];
    [dict setObject:[[self destinationEntity] name] forKey:@"destinationEntity"]; // call access to hit assertion that these are valid
    [dict setObject:[[self inverseRelationship] name] forKey:@"inverseRelationship"];
    return dict;
}
#endif

#pragma mark -
#pragma mark Creation

ODORelationship *ODORelationshipCreate(NSString *name, BOOL optional, BOOL transient, SEL get, SEL set,
                                       BOOL toMany, BOOL shouldPrefetch, ODORelationshipDeleteRule deleteRule, NSString *queryByForeignKeyStatementKey)
{
    OBPRECONDITION(deleteRule > ODORelationshipDeleteRuleInvalid);
    OBPRECONDITION(deleteRule < ODORelationshipDeleteRuleCount);
    
    ODORelationship *rel = [[ODORelationship alloc] init];
    
    struct _ODOPropertyFlags baseFlags;
    memset(&baseFlags, 0, sizeof(baseFlags));
    
    // Add relationship-specific info to the flags
    baseFlags.relationship = YES;
    baseFlags.toMany = toMany;
    
    ODOPropertyInit(rel, name, baseFlags, optional, transient, get, set);

    OBASSERT_IF(shouldPrefetch, !toMany, "Currently only supported for to-one relationships");

    rel->_deleteRule = deleteRule;
    rel->_shouldPrefetch = shouldPrefetch;
    rel->_queryByForeignKeyStatementKey = [queryByForeignKeyStatementKey copy];
    
    return rel;
}

void ODORelationshipBind(ODORelationship *self, ODOEntity *sourceEntity, ODOEntity *destinationEntity, ODORelationship *inverse)
{
    OBPRECONDITION([self isKindOfClass:[ODORelationship class]]);
    OBPRECONDITION(destinationEntity);
    OBPRECONDITION(inverse);
    
    // We don't support many-to-many
    OBPRECONDITION(![self isToMany] || ![inverse isToMany]);
    
    // Both sides can't be calculated; one would (presumably) have to be computed from the other.
    OBPRECONDITION(![self isCalculated] || ![inverse isCalculated]);

    // In a one-to-one, one side must be calculated.
#ifdef OMNI_ASSERTIONS_ON
    if (![self isToMany] && ![inverse isToMany]) {
        OBPRECONDITION([self isCalculated] || [inverse isCalculated]);
    }
    
    // The to-one side of a one-to-many can't be calculated since presumably the to-many side is the calculated side.
    if ([self isToMany]) {
        OBPRECONDITION(![inverse isCalculated]);
    } else if ([inverse isToMany]) {
        OBPRECONDITION(![self isCalculated]);
    }
#endif
    
    ODOPropertyBind(self, sourceEntity);
    
    self->_destinationEntity = [destinationEntity retain];
    self->_inverseRelationship = [inverse retain];

    //
#ifdef OMNI_ASSERTIONS_ON
    if ([self isCalculated]) {
        NSString *setterString = [NSString stringWithFormat:@"set%@%@:", [self.name substringToIndex:1].uppercaseString, [self.name substringFromIndex:1]];
        SEL setter = NSSelectorFromString(setterString);
        Class cls = self->_nonretained_entity.instanceClass;
        OBASSERT(![cls instancesRespondToSelector:setter], @"%@ implements -%@. This is a calculated property; the setter will not be invoked at runtime.", NSStringFromClass(cls), setterString);
    }
#endif
}

@end
