// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSDictionary;
@class ODOEntity;

@interface ODOModel : OFObject
{
@private
    NSString *_name;
    NSDictionary *_entitiesByName;
}

+ (void)registerClass:(Class)cls forEntity:(ODOEntity *)entity;
+ (ODOEntity *)entityForClass:(Class)cls;

@property(readonly) NSDictionary *entitiesByName;

- (ODOEntity *)entityNamed:(NSString *)name;

@end
