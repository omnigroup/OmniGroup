// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODOEntity.h>
#import <OmniDataObjects/ODOModel.h>

extern void ODOPropertyBind(ODOProperty *self, ODOEntity *entity);

extern ODOAttribute *ODOAttributeCreate(NSString *name, BOOL optional, BOOL transient, SEL get, SEL set,
                                        ODOAttributeType type, Class valueClass, NSObject <NSCopying> *defaultValue, BOOL isPrimaryKey);

extern ODORelationship *ODORelationshipCreate(NSString *name, BOOL optional, BOOL transient, SEL get, SEL set,
                                              BOOL toMany, BOOL shouldPrefetch, ODORelationshipDeleteRule deleteRule, NSString *queryByForeignKeyStatementKey);
extern void ODORelationshipBind(ODORelationship *self, ODOEntity *sourceEntity, ODOEntity *destinationEntity, ODORelationship *inverse);

extern ODOEntity *ODOEntityCreate(NSString *name, NSString *insertKey, NSString *updateKey, NSString *deleteKey, NSString *pkQueryKey,
                                  NSString *instanceClassName, NSArray *properties, NSUInteger prefetchOrder);

extern void ODOEntityBind(ODOEntity *self, ODOModel *model);

extern ODOModel *ODOModelCreate(NSString *name, NSArray *entities);
extern void ODOModelFinalize(ODOModel *model);
