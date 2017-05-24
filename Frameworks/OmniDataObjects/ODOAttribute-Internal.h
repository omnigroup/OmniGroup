// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOAttribute.h>

static inline ODOAttributeSetterBehavior _ODOAttributeSetterBehavior(ODOAttribute *attribute)
{
    OBPRECONDITION([attribute isKindOfClass:[ODOAttribute class]]);
    return attribute->_setterBehavior;
}
