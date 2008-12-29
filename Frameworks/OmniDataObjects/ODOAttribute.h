// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOProperty.h>

// types explicitly distinguish between bit sizes to ensure data store independence of the underlying operating system
typedef enum {
    ODOAttributeTypeInvalid = -1,
    ODOAttributeTypeUndefined, // only makes sense for transient attributes
    ODOAttributeTypeInt16,
    ODOAttributeTypeInt32,
    ODOAttributeTypeInt64,
    ODOAttributeTypeDecimal,
    ODOAttributeTypeFloat32,
    ODOAttributeTypeFloat64,
    ODOAttributeTypeString,
    ODOAttributeTypeBoolean,
    ODOAttributeTypeDate,
    ODOAttributeTypeData,
} ODOAttributeType;

@interface ODOAttribute : ODOProperty
{
@private
    ODOAttributeType _type;
    id _defaultValue;
    BOOL _isPrimaryKey;
    Class _valueClass;
}

- (ODOAttributeType)type;
- (id)defaultValue;
- (Class)valueClass;

@end
