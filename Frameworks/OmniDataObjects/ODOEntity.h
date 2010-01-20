// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
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

    NSArray *_attributes;
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

@property(readonly) ODOModel *model;
@property(readonly) NSString *name;

@property(readonly) NSString *instanceClassName;
@property(readonly) Class instanceClass;

@property(readonly) NSArray *properties;
@property(readonly) NSDictionary *propertiesByName;
- (ODOProperty *)propertyNamed:(NSString *)name;
- (ODOProperty *)propertyWithGetter:(SEL)getter;
- (ODOProperty *)propertyWithSetter:(SEL)setter;

@property(readonly) NSDictionary *relationshipsByName;
@property(readonly) NSArray *relationships;
@property(readonly) NSArray *toOneRelationships;
@property(readonly) NSArray *toManyRelationships;

@property(readonly) NSArray *attributes;
@property(readonly) NSDictionary *attributesByName;

@property(readonly) ODOAttribute *primaryKeyAttribute;

@property(readonly) NSSet *derivedPropertyNameSet;
@property(readonly) NSSet *nonDateModifyingPropertyNameSet;

+ (id)insertNewObjectForEntityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context primaryKey:(id)primaryKey;
+ (id)insertNewObjectForEntityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context;
+ (ODOEntity *)entityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context;

@end
