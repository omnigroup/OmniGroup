// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOAttribute.h>

#import "ODOProperty-Internal.h"

static inline ODOAttributeSetterBehavior _ODOAttributeSetterBehavior(ODOAttribute *attribute)
{
    OBPRECONDITION([attribute isKindOfClass:[ODOAttribute class]]);
    return attribute->_setterBehavior;
}

static inline void ODOASSERT_ATTRIBUTE_OF_TYPE(ODOProperty *prop, ODOAttributeType attrType)
{
#ifdef OMNI_ASSERTIONS_ON
    OBPRECONDITION(prop != nil);
    OBASSERT([prop isKindOfClass:[ODOAttribute class]]);
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    OBASSERT(flags.relationship == NO);
    
    ODOAttribute *attr = (ODOAttribute *)prop;
    OBASSERT(![attr isPrimaryKey]);
    OBASSERT(attr.type == attrType);
#endif
}

