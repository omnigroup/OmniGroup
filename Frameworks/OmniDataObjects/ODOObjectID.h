// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/OBObject.h>

@class NSURL;
@class ODOEntity;

@interface ODOObjectID : OBObject <NSCopying>
{
@private
    ODOEntity *_entity;
    id _primaryKey;
}

- initWithEntity:(ODOEntity *)entity primaryKey:(id)primaryKey;

- (ODOEntity *)entity;
- (id)primaryKey;

@end
