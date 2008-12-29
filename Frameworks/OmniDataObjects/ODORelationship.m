// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODORelationship.h>

#import "ODORelationship-Internal.h"
#import "ODOProperty-Internal.h"

#import <OmniDataObjects/ODOEntity.h>
#import <OmniDataObjects/ODOModel.h>
#import <OmniFoundation/OFEnumNameTable.h>

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
            [ODORelationshipDeleteRuleEnumNameTable() nameForEnum:_deleteRule],
            [_inverseRelationship isToMany] ? @"<<" : @"<",
            [self isToMany] ? @">>" : @">",
            [ODORelationshipDeleteRuleEnumNameTable() nameForEnum:[_inverseRelationship deleteRule]],
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

@end

NSString * const ODORelationshipElementName = @"relationship";
NSString * const ODORelationshipDeleteRuleAttributeName = @"delete";
NSString * const ODORelationshipToManyAttributeName = @"many";
NSString * const ODORelationshipDestinationEntityAttributeName = @"entity";
NSString * const ODORelationshipInverseRelationshipAttributeName = @"inverse";

OFEnumNameTable * ODORelationshipDeleteRuleEnumNameTable(void)
{
    static OFEnumNameTable *table = nil;
    
    if (!table) {
        table = [[OFEnumNameTable alloc] initWithDefaultEnumValue:ODORelationshipDeleteRuleInvalid];
        [table setName:@"--invalid--" forEnumValue:ODORelationshipDeleteRuleInvalid];
        
        [table setName:@"nullify" forEnumValue:ODORelationshipDeleteRuleNullify];
        [table setName:@"cascade" forEnumValue:ODORelationshipDeleteRuleCascade];
        [table setName:@"deny" forEnumValue:ODORelationshipDeleteRuleDeny];
    }
    
    return table;
}


@implementation ODORelationship (Internal)

- (id)initWithCursor:(OFXMLCursor *)cursor entity:(ODOEntity *)entity error:(NSError **)outError;
{
    OBPRECONDITION([[cursor name] isEqualToString:ODORelationshipElementName]);
    
    struct _ODOPropertyFlags baseFlags;
    memset(&baseFlags, 0, sizeof(baseFlags));
    baseFlags.snapshotIndex = ODO_NON_SNAPSHOT_PROPERTY_INDEX; // start out not being in the snapshot properties; this'll get updated later if we are

    // Add relationship-specific info to the flags
    baseFlags.relationship = YES;
    
    NSString *manyString = [cursor attributeNamed:ODORelationshipToManyAttributeName];
    OBASSERT(!manyString || [manyString isEqualToString:@"true"] || [manyString isEqualToString:@"false"]);
    baseFlags.toMany = [manyString isEqualToString:@"true"];
    
    if (![super initWithCursor:cursor entity:entity baseFlags:baseFlags error:outError])
        return nil;

    NSString *deleteRuleName = [cursor attributeNamed:ODORelationshipDeleteRuleAttributeName];
    if ([NSString isEmptyString:deleteRuleName]) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Relationship %@.%@ specified no type.", nil, OMNI_BUNDLE, @"error reason"), [entity name], [self name]];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    _deleteRule = [ODORelationshipDeleteRuleEnumNameTable() enumForName:deleteRuleName];
    if (_deleteRule == ODORelationshipDeleteRuleInvalid) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Relationship %@.%@ specified invalid type of '%@'.", nil, OMNI_BUNDLE, @"error reason"), [entity name], [self name], deleteRuleName];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    NSString *entityName = [cursor attributeNamed:ODORelationshipDestinationEntityAttributeName];
    if ([NSString isEmptyString:entityName]) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Relationship %@.%@ specified no destination entity.", nil, OMNI_BUNDLE, @"error reason"), [entity name], [self name]];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }

    NSString *inverseRelationshipName = [cursor attributeNamed:ODORelationshipInverseRelationshipAttributeName];
    if ([NSString isEmptyString:inverseRelationshipName]) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Relationship %@.%@ specified no inverse relationship.", nil, OMNI_BUNDLE, @"error reason"), [entity name], [self name]];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    // Not all the entities might be loaded yet.  Squirrel these away in the destination entity ivar until -finalizeRelationship:.
    _destinationEntity = (id)[entityName retain];
    _inverseRelationship = (id)[inverseRelationshipName retain];

    return self;
}

- (BOOL)finalizeModelLoading:(NSError **)outError;
{
    OBPRECONDITION([_destinationEntity isKindOfClass:[NSString class]]);
    OBPRECONDITION([_inverseRelationship isKindOfClass:[NSString class]]);
    
    ODOEntity *entity = [self entity];
    ODOModel *model = [entity model];
    OBASSERT(model);
    
    ODOEntity *destination = [[model entitiesByName] objectForKey:(NSString *)_destinationEntity];
    if (!destination) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Relationship %@.%@ specified a destination entity of '%@', but there is no such entity.", nil, OMNI_BUNDLE, @"error reason"), [entity name], [self name], _destinationEntity];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        return NO;
    }
    [_destinationEntity release];
    _destinationEntity = [destination retain]; // This and the inverse relationship make a retain cycle.  Not a problem in real life were we'll load a model once and never dealloc it.
    
    ODORelationship *inverse = [[destination relationshipsByName] objectForKey:(NSString *)_inverseRelationship];
    if (!inverse) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Relationship %@.%@ specified an inverse relationship %@.%@, but there is no such relationship.", nil, OMNI_BUNDLE, @"error reason"), [entity name], [self name], [_destinationEntity name], _inverseRelationship];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        return NO;
    }
    [_inverseRelationship release];
    _inverseRelationship = [inverse retain];

    return YES;
}

@end
