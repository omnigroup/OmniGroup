// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOModel.h>

#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOModel-Creation.h>

#import "ODOEntity-Internal.h"
#import "ODODatabase-Internal.h"
#import "ODOObject-Accessors.h"
#import "ODOModel-Internal.h"

@import Foundation;

RCS_ID("$Id$");

@implementation ODOModel

static CFMutableDictionaryRef ClassToEntity = nil;
static CFMutableDictionaryRef EntityToClass = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    ClassToEntity = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerDictionaryKeyCallbacks, &OFNSObjectDictionaryValueCallbacks);
    EntityToClass = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &OFNonOwnedPointerDictionaryValueCallbacks);
}

// Not very happy with this registration API; see commentary at +[ODOObject resolveInstanceMethod:] for the involved issues
+ (void)registerClass:(Class)cls forEntity:(ODOEntity *)entity;
{
    // We require a 1-1 mapping from entity to class (for those with custom classes) AND we require only 'leaf' classes be associated with an entity (the latter restriction isn't enforced here).
    OBPRECONDITION(CFDictionaryGetValue(ClassToEntity, cls) == nil);
    OBPRECONDITION(CFDictionaryGetValue(EntityToClass, entity) == Nil);
    
    CFDictionarySetValue(ClassToEntity, cls, entity);
    CFDictionarySetValue(EntityToClass, entity, cls);
}

+ (ODOEntity *)entityForClass:(Class)cls;
{
    return (ODOEntity *)CFDictionaryGetValue(ClassToEntity, cls);
}

ODOModel * ODOModelCreate(NSString *modelName, NSArray *entities)
{
    ODOModel *model = nil;
    
    // Make sure that our poking model classes doesn't cause their +initialize to ask for a shared model that is still in the process of loading...
    // Typically this is not a concern because clients will use the auto-generated <<Prefix>>Model function, which uses dispatch_once, which intentionally crashes if re-entered.
    // We still want to prevent per-thread re-entrancy here for the case of creating models by hand, as may be the case for unit tests.
    
#ifdef OMNI_ASSERTIONS_ON
    static __thread BOOL _isCreatingModel = NO;
    OBPRECONDITION(_isCreatingModel == NO);
    _isCreatingModel = YES;
#endif

    @try {
        model = [[ODOModel alloc] init];
        model->_name = [modelName copy];
        
        NSMutableDictionary <NSString *, ODOEntity *> *entitiesByName = [NSMutableDictionary dictionary];
        for (ODOEntity *entity in entities) {
            NSString *entityName = [entity name];
            OBASSERT(![entityName hasPrefix:@"ODO"]); // All entity names beginning with ODO are reserved
            OBASSERT([entitiesByName objectForKey:entityName] == nil);
            [entitiesByName setObject:entity forKey:entityName];
        }
        model->_entitiesByName = [[NSDictionary alloc] initWithDictionary:entitiesByName];
    } @finally {
#ifdef OMNI_ASSERTIONS_ON
        _isCreatingModel = NO;
#endif
    }

    return model;
}

void ODOModelFinalize(ODOModel *model)
{
    for (NSString *key in model->_entitiesByName) {
        ODOEntity *entity = model->_entitiesByName[key];
        [entity finalizeModelLoading];
        Class cls = [entity instanceClass];
        if (cls != [ODOObject class]) {
            [ODOModel registerClass:cls forEntity:entity];
#if !LAZY_DYNAMIC_ACCESSORS
            ODOObjectCreateDynamicAccessorsForEntity(entity);
#endif
        }
    }
    
    model->_entitiesByImplementationClass = [[NSMapTable strongToWeakObjectsMapTable] retain];
    [model->_entitiesByName enumerateKeysAndObjectsUsingBlock:^(NSString *entityName, ODOEntity *entity, BOOL *stop) {
        [model->_entitiesByImplementationClass setObject:entity forKey:entity.instanceClass];
    }];

#ifdef OMNI_ASSERTIONS_ON
    // Only 'leaf' instance classes should be registered.
    for (ODOEntity *entity in [model->_entitiesByName objectEnumerator]) {
        Class cls = [entity.instanceClass superclass];
        while (cls) {
            OBASSERT([ODOModel entityForClass:cls] == Nil);
            cls = [cls superclass];
        }
    }
#endif

    NSMutableArray <ODOEntity *> *prefetchEntities = [NSMutableArray array];

    [model->_entitiesByName enumerateKeysAndObjectsUsingBlock:^(NSString *entityName, ODOEntity *entity, BOOL *stop) {
        // Tell each model class that the model is loaded.
        [entity.instanceClass entityLoaded:entity];

        if (entity.prefetchOrder != NSNotFound) {
            [prefetchEntities addObject:entity];
        }
    }];

    [prefetchEntities sortUsingComparator:^(ODOEntity *entity1, ODOEntity *entity2) {
        NSUInteger order1 = entity1.prefetchOrder;
        NSUInteger order2 = entity2.prefetchOrder;

        if (order1 < order2) {
            return NSOrderedAscending;
        }
        if (order1 > order2) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];

    model->_prefetchEntities = [prefetchEntities copy];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
- (void)dealloc;
{
    // See the @dynamic support in ODOObject, including +resolveInstanceMethod:
    OBRejectUnusedImplementation(self, _cmd);
    [_name release];
    [_entitiesByName release];
    [_entitiesByImplementationClass release];
    [super dealloc];
}
#pragma clang diagnostic pop

- (NSDictionary<NSString *, ODOEntity *> *)entitiesByName;
{
    OBPRECONDITION(_entitiesByName);
    return _entitiesByName;
}

- (ODOEntity *)entityNamed:(NSString *)name;
{
    return [_entitiesByName objectForKey:name];
}

- (ODOEntity *)entityForClass:(Class)implementationClass;
{
    return [_entitiesByImplementationClass objectForKey:implementationClass];
}

#ifdef DEBUG
- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:_name forKey:@"name"];
    NSMutableArray *entityDescriptions = [NSMutableArray array];
    for (ODOEntity *entity in [_entitiesByName objectEnumerator])
        [entityDescriptions addObject:[entity debugDictionary]];
    [dict setObject:entityDescriptions forKey:@"entities"];
    return dict;
}
#endif

@end
