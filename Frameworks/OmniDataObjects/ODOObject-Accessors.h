// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOObject.h>

#import <OmniDataObjects/ODOProperty.h>

__private_extern__ const char *ODOObjectGetterSignature(void);
__private_extern__ const char *ODOObjectSetterSignature(void);

__private_extern__ void ODOObjectWillAccessValueForKey(ODOObject *self, NSString *key);

__private_extern__ id ODOObjectPrimitiveValueForProperty(ODOObject *object, ODOProperty *prop);
__private_extern__ void ODOObjectSetPrimitiveValueForProperty(ODOObject *object, id value, ODOProperty *prop);

__private_extern__ id ODODynamicValueForProperty(ODOObject *object, ODOProperty *prop);
__private_extern__ void ODODynamicSetValueForProperty(ODOObject *object, SEL _cmd, ODOProperty *prop, id value);

__private_extern__ id ODOGetterForUnknownOffset(ODOObject *self, SEL _cmd);
__private_extern__ void ODOSetterForUnknownOffset(ODOObject *self, SEL _cmd, id value);

__private_extern__ ODOPropertyGetter ODOGetterForProperty(ODOProperty *prop);
__private_extern__ ODOPropertySetter ODOSetterForProperty(ODOProperty *prop);

__private_extern__ void ODOObjectSetInternalValueForProperty(ODOObject *self, id value, ODOProperty *prop);

#if !LAZY_DYNAMIC_ACCESSORS
__private_extern__ void ODOObjectCreateDynamicAccessorsForEntity(ODOEntity *entity);
#endif
