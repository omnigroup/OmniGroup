// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSDictionary;
@class NSMapTable;
@class ODOEntity;

@interface ODOModel : OFObject
{
@private
    NSString *_name;
    NSDictionary<NSString *, ODOEntity *> *_entitiesByName;
    NSMapTable<Class, ODOEntity *> *_entitiesByImplementationClass;
}

+ (void)registerClass:(Class)cls forEntity:(ODOEntity *)entity;
+ (ODOEntity *)entityForClass:(Class)cls;

@property(readonly) NSDictionary <NSString *, ODOEntity *> *entitiesByName;

- (ODOEntity *)entityNamed:(NSString *)name;
- (ODOEntity *)entityForClass:(Class)implementationClass;

@end
