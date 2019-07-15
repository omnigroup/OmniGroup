// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <CoreFoundation/CFArray.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString, NSArray, NSDictionary, NSSet;
@class ODOObject, ODOEditingContext, ODOModel, ODOAttribute, ODOProperty, ODORelationship, ODOSQLStatement;

@interface ODOEntity : OFObject

@property (nonatomic, readonly) ODOModel *model;
@property (nonatomic, readonly) NSString *name;

@property (nonatomic, readonly) NSString *instanceClassName;
@property (nonatomic, readonly) Class instanceClass;

@property (nonatomic, readonly) NSArray <ODOProperty *> *properties;
@property (nonatomic, readonly) NSDictionary <NSString *, ODOProperty *> *propertiesByName;

- (nullable ODOProperty *)propertyNamed:(NSString *)name;
- (nullable ODOProperty *)propertyWithGetter:(SEL)getter;
- (nullable ODOProperty *)propertyWithSetter:(SEL)setter;

// An array of names that are disjoint from the property names for this entity, but might be passed to -propertyNamed:.
@property (nonatomic, copy) NSArray <NSString *> *nonPropertyNames;

@property (nonatomic, readonly) NSDictionary <NSString *, ODORelationship *> *relationshipsByName;
@property (nonatomic, readonly) NSArray <ODORelationship *> *relationships;
@property (nonatomic, readonly) NSArray <ODORelationship *> *toOneRelationships;
@property (nonatomic, readonly) NSArray <ODORelationship *> *toManyRelationships;

@property (nonatomic, readonly) NSArray <ODOAttribute *> *attributes;
@property (nonatomic, readonly) NSDictionary <NSString *, ODOAttribute *> *attributesByName;

@property (nonatomic, readonly) ODOAttribute *primaryKeyAttribute;

@property (nonatomic, readonly) NSSet <NSString *> *derivedPropertyNameSet;
@property (nonatomic, readonly) NSSet <NSString *> *nonDateModifyingPropertyNameSet;
@property (nonatomic, readonly) NSSet <NSString *> *calculatedTransientPropertyNameSet;

+ (nullable id)insertNewObjectForEntityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context primaryKey:(nullable id)primaryKey;
+ (nullable id)insertNewObjectForEntityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context;
+ (nullable ODOEntity *)entityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context;

@end

NS_ASSUME_NONNULL_END
