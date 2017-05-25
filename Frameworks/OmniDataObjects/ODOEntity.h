// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <CoreFoundation/CFArray.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString, NSArray, NSDictionary, NSSet;
@class ODOObject, ODOEditingContext, ODOModel, ODOAttribute, ODOProperty, ODOSQLStatement;

@interface ODOEntity : OFObject

@property (nonatomic, readonly) ODOModel *model;
@property (nonatomic, readonly) NSString *name;

@property (nonatomic, readonly) NSString *instanceClassName;
@property (nonatomic, readonly) Class instanceClass;

@property (nonatomic, readonly) NSArray *properties;
@property (nonatomic, readonly) NSDictionary *propertiesByName;

- (nullable ODOProperty *)propertyNamed:(NSString *)name;
- (nullable ODOProperty *)propertyWithGetter:(SEL)getter;
- (nullable ODOProperty *)propertyWithSetter:(SEL)setter;

@property (nonatomic, readonly) NSDictionary *relationshipsByName;
@property (nonatomic, readonly) NSArray *relationships;
@property (nonatomic, readonly) NSArray *toOneRelationships;
@property (nonatomic, readonly) NSArray *toManyRelationships;

@property (nonatomic, readonly) NSArray *attributes;
@property (nonatomic, readonly) NSDictionary *attributesByName;

@property (nonatomic, readonly) ODOAttribute *primaryKeyAttribute;

@property (nonatomic, readonly) NSSet *derivedPropertyNameSet;
@property (nonatomic, readonly) NSSet *nonDateModifyingPropertyNameSet;
@property (nonatomic, readonly) NSSet *calculatedTransientPropertyNameSet;

+ (nullable id)insertNewObjectForEntityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context primaryKey:(nullable id)primaryKey;
+ (nullable id)insertNewObjectForEntityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context;
+ (nullable ODOEntity *)entityForName:(NSString *)entityName inEditingContext:(ODOEditingContext *)context;

@end

NS_ASSUME_NONNULL_END
