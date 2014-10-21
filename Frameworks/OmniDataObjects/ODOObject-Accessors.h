// Copyright 2008-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOObject.h>

#import <OmniDataObjects/ODOProperty.h>

const char *ODOObjectGetterSignature(void) OB_HIDDEN;
const char *ODOObjectSetterSignature(void) OB_HIDDEN;

void ODOObjectWillAccessValueForKey(ODOObject *self, NSString *key) OB_HIDDEN;

id ODOObjectPrimitiveValueForProperty(ODOObject *object, ODOProperty *prop) OB_HIDDEN;
void ODOObjectSetPrimitiveValueForProperty(ODOObject *object, id value, ODOProperty *prop) OB_HIDDEN;

id ODODynamicValueForProperty(ODOObject *object, ODOProperty *prop) OB_HIDDEN;
void ODODynamicSetValueForProperty(ODOObject *object, SEL _cmd, ODOProperty *prop, id value) OB_HIDDEN;

id ODOGetterForUnknownOffset(ODOObject *self, SEL _cmd) OB_HIDDEN;
void ODOSetterForUnknownOffset(ODOObject *self, SEL _cmd, id value) OB_HIDDEN;

ODOPropertyGetter ODOGetterForProperty(ODOProperty *prop) OB_HIDDEN;
ODOPropertySetter ODOSetterForProperty(ODOProperty *prop) OB_HIDDEN;

void ODOObjectSetInternalValueForProperty(ODOObject *self, id value, ODOProperty *prop) OB_HIDDEN;

#if !LAZY_DYNAMIC_ACCESSORS
void ODOObjectCreateDynamicAccessorsForEntity(ODOEntity *entity) OB_HIDDEN;
#endif
