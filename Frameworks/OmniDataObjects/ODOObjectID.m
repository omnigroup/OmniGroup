// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODOEntity.h>

#import <OmniDataObjects/ODOAttribute.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOObjectID.m 104581 2008-09-06 21:18:23Z kc $")

@implementation ODOObjectID

- initWithEntity:(ODOEntity *)entity primaryKey:(id)primaryKey;
{
    OBPRECONDITION(entity);
    OBPRECONDITION(primaryKey);
    OBPRECONDITION([primaryKey isKindOfClass:[[entity primaryKeyAttribute] valueClass]]);
    
    _entity = [entity retain];
    _primaryKey = [primaryKey copy];
    
    return self;
}

- (void)dealloc;
{
    [_entity release];
    [_primaryKey release];
    [super dealloc];
}

- (ODOEntity *)entity;
{
    OBPRECONDITION(_entity);
    return _entity;
}

- (id)primaryKey;
{
    OBPRECONDITION(_primaryKey);
    return _primaryKey;
}

- (NSURL *)URIRepresentation;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

#ifdef DEBUG
- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(unsigned int)level;
{
    return [self shortDescription];
}
- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@/%@>", NSStringFromClass([self class]), self, [_entity name], _primaryKey];
}
#endif

#pragma mark -
#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

#pragma mark -
#pragma mark Comparison

- (unsigned)hash;
{
    return [_primaryKey hash] ^ (uintptr_t)_entity; // Hash values not archivable due to pointer case.  Could use [[_entity name] hash]...
}

- (BOOL)isEqual:(id)otherObject;
{
    if (![otherObject isKindOfClass:[ODOObjectID class]])
        return NO;
    
    ODOObjectID *otherID = otherObject;
    return _entity == otherID->_entity && [_primaryKey isEqual:otherID->_primaryKey];
}

@end
