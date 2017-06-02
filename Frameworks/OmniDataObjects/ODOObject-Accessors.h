// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOObject.h>

#import <OmniDataObjects/ODOProperty.h>

NS_ASSUME_NONNULL_BEGIN

void ODOObjectWillAccessValueForKey(ODOObject *self, NSString * _Nullable key) OB_HIDDEN;

typedef NS_OPTIONS(NSUInteger, ODOObjectPrimitiveValueForPropertyOptions) {
    ODOObjectPrimitiveValueForPropertyOptionAllowCalculationOfLazyTransientValues = 1 << 0,
    ODOObjectPrimitiveValueForPropertyOptionDefault = (ODOObjectPrimitiveValueForPropertyOptionAllowCalculationOfLazyTransientValues),
};

_Nullable id ODOObjectPrimitiveValueForProperty(ODOObject *object, ODOProperty *prop) OB_HIDDEN;
_Nullable id ODOObjectPrimitiveValueForPropertyWithOptions(ODOObject *object, ODOProperty *prop, ODOObjectPrimitiveValueForPropertyOptions options) OB_HIDDEN;
void ODOObjectSetPrimitiveValueForProperty(ODOObject *object, _Nullable id value, ODOProperty *prop) OB_HIDDEN;

_Nullable id ODODynamicValueForProperty(ODOObject *object, ODOProperty *prop) OB_HIDDEN;
void ODODynamicSetValueForProperty(ODOObject *object, SEL _cmd, ODOProperty *prop, id value) OB_HIDDEN;

_Nullable id ODOGetScalarValueForProperty(ODOObject *object, ODOProperty *prop) OB_HIDDEN;
void ODOSetScalarValueForProperty(ODOObject *object, ODOProperty *prop, _Nullable id value) OB_HIDDEN;

_Nullable id ODOGetterForUnknownOffset(ODOObject *self, SEL _cmd) OB_HIDDEN;
void ODOSetterForUnknownOffset(ODOObject *self, SEL _cmd, _Nullable id value) OB_HIDDEN;

const char * ODOGetterSignatureForProperty(ODOProperty *prop) OB_HIDDEN;
const char * ODOSetterSignatureForProperty(ODOProperty *prop) OB_HIDDEN;

const char * ODOPropertyAttributesForProperty(ODOProperty *prop) OB_HIDDEN;

IMP ODOGetterForProperty(ODOProperty *prop) OB_HIDDEN;
IMP ODOSetterForProperty(ODOProperty *prop) OB_HIDDEN;

void ODOObjectSetInternalValueForProperty(ODOObject *self, _Nullable id value, ODOProperty *prop) OB_HIDDEN;

#if !LAZY_DYNAMIC_ACCESSORS
void ODOObjectCreateDynamicAccessorsForEntity(ODOEntity *entity) OB_HIDDEN;
#endif

NS_ASSUME_NONNULL_END
