// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <CoreFoundation/CFArray.h>

@class NSString, NSArray, NSDictionary, NSSet;
@class ODOObject, ODOEditingContext, ODOModel, ODOAttribute, ODOProperty, ODOSQLStatement;

@interface ODOEntity : OFObject
{
@private
    ODOModel *_nonretained_model; // We are retained by the model.
    NSString *_name;
    
    NSString *_instanceClassName;
    Class _instanceClass;
    
    // These four arrays must be exactly parallel
    NSArray *_properties;
    CFArrayRef _propertyNames;
    CFArrayRef _propertyGetSelectors;
    CFArrayRef _propertySetSelectors;
    
    NSDictionary *_propertiesByName;
    NSDictionary *_relationshipsByName;
    NSArray *_relationships;
    NSArray *_toOneRelationships;
    NSArray *_toManyRelationships;
    
    NSDictionary *_attributesByName;
    ODOAttribute *_primaryKeyAttribute;

    NSArray *_snapshotProperties;
    
    NSArray *_schemaProperties;
    NSString *_insertStatementKey;
    NSString *_updateStatementKey;
    NSString *_deleteStatementKey;
    NSString *_queryByPrimaryKeyStatementKey;
    
    NSSet *_derivedPropertyNameSet;
    NSSet *_nonDateModifyingPropertyNameSet;
}

- (ODOModel *)model;
- (NSString *)name;

- (NSString *)instanceClassName;
- (Class)instanceClass;

- (NSArray *)properties;
- (NSDictionary *)propertiesByName;
- (ODOProperty *)propertyNamed:(NSString *)name;
- (ODOProperty *)propertyWithGetter:(SEL)getter;
- (ODOProperty *)propertyWithSetter:(SEL)setter;

- (NSDictionary *)relationshipsByName;
- (NSArray *)relationships;
- (NSArray *)toOneRelationships;
- (NSArray *)toManyRelationships;

- (NSDictionary *)attributesByName;

- (ODOAttribute *)primaryKeyAttribute;

- (NSSet *)derivedPropertyNameSet;
- (NSSet *)nonDateModifyingPropertyNameSet;

+ (id)insertNewObjectForEntityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context primaryKey:(id)primaryKey;
+ (id)insertNewObjectForEntityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context;
+ (ODOEntity *)entityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context;

@end
