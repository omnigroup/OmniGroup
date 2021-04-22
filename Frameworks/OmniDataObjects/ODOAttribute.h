// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOProperty.h>

// types explicitly distinguish between bit sizes to ensure data store independence of the underlying operating system
typedef NS_ENUM(NSInteger, ODOAttributeType) {
    ODOAttributeTypeInvalid = -1,
    ODOAttributeTypeUndefined, // only makes sense for transient attributes
    ODOAttributeTypeInt16,
    ODOAttributeTypeInt32,
    ODOAttributeTypeInt64,
    ODOAttributeTypeFloat32,
    ODOAttributeTypeFloat64,
    ODOAttributeTypeString,
    ODOAttributeTypeBoolean,
    ODOAttributeTypeDate,
    ODOAttributeTypeXMLDateTime,
    ODOAttributeTypeData,
};

enum {
    ODOAttributeTypeCount = ODOAttributeTypeData + 1
};

typedef NS_ENUM(NSInteger, ODOAttributeSetterBehavior) {
    ODOAttributeSetterBehaviorCopy,
    ODOAttributeSetterBehaviorRetain,
    ODOAttributeSetterBehaviorDetermineAtRuntime,
};

@interface ODOAttribute : ODOProperty {
  @package
    ODOAttributeType _type;
    NSObject <NSCopying> *_defaultValue;
    BOOL _isPrimaryKey;
    Class _valueClass;
    ODOAttributeSetterBehavior _setterBehavior;
}

@property (nonatomic, readonly) ODOAttributeType type;
@property (nonatomic, readonly) NSObject <NSCopying> *defaultValue;
@property (nonatomic, readonly) Class valueClass;

@property (nonatomic, readonly, getter=isPrimaryKey) BOOL primaryKey;

@end
