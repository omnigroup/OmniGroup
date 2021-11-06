// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOEntity.h>
#import <OmniDataObjects/ODOObject.h> // For ODOObjectSetDefaultAttributeValues

#import "ODOStorageType.h"

#include <assert.h>

@interface ODOEntity () {
@package
    ODOModel *_nonretained_model; // We are retained by the model.
    NSString *_name;
    
    NSString *_instanceClassName;
    Class _instanceClass;
    
    // These four arrays must be exactly parallel
    NSArray *_properties;
    NSArray <NSString *> *_propertyNames;
    CFArrayRef _propertyGetSelectors;
    CFArrayRef _propertySetSelectors;

    NSArray <NSString *> *_nonPropertyNames;

    NSDictionary *_propertiesByName;
    NSDictionary *_relationshipsByName;
    NSArray <ODORelationship *> *_relationships;
    NSArray <ODORelationship *> *_toOneRelationships;
    NSArray <ODORelationship *> *_toManyRelationships;
    NSArray <ODORelationship *> *_prefetchRelationships;
    NSUInteger _prefetchOrder;

    NSArray *_attributes;
    NSDictionary *_attributesByName;
    ODOAttribute *_primaryKeyAttribute;
    
    size_t _snapshotSize;
    NSArray <__kindof ODOProperty *> *_snapshotProperties;
    NSArray <__kindof ODOProperty *> *_nonDerivedSnapshotProperties;
    NSArray <ODOAttribute *> *_snapshotAttributes;
    
    NSUInteger _snapshotPropertyCount;
    ODOStorageKey *_snapshotStorageKeys;
    
    NSArray *_schemaProperties;
    NSString *_insertStatementKey;
    NSString *_updateStatementKey;
    NSString *_deleteStatementKey;
    NSString *_queryByPrimaryKeyStatementKey;
    
    NSSet *_derivedPropertyNameSet;
    NSSet *_nonDateModifyingPropertyNameSet;
    NSSet *_calculatedTransientPropertyNameSet;

    NSArray <ODOObjectSetDefaultAttributeValues> *_defaultAttributeValueActions;
}

@end

#pragma mark -

static inline ODOStorageKey ODOEntityStorageKeyForSnapshotIndex(ODOEntity *self, NSUInteger snapshotIndex)
{
    assert(snapshotIndex < self->_snapshotPropertyCount);
    return self->_snapshotStorageKeys[snapshotIndex];
}

@interface ODOEntity (Internal)

- (void)finalizeModelLoading;

@property(nonatomic,readonly) NSArray <ODORelationship *> *prefetchRelationships;
@property(nonatomic,readonly) NSUInteger prefetchOrder;

@property(readonly) size_t snapshotSize;

@property(readonly) NSArray <__kindof ODOProperty *> *snapshotProperties;
@property(readonly) NSArray <__kindof ODOProperty *> *nonDerivedSnapshotProperties;

- (ODOProperty *)propertyWithSnapshotIndex:(NSUInteger)snapshotIndex;

@property(readonly) NSArray <__kindof ODOAttribute *> *snapshotAttributes;

@property(readonly) NSArray <ODOObjectSetDefaultAttributeValues> *defaultAttributeValueActions;

@end
