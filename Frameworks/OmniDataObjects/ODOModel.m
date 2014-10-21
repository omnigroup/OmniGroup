// Copyright 2008-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOModel.h>

#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOModel-Creation.h>
#import <OmniDataObjects/ODOObject-Accessors.h>

#import "ODOEntity-Internal.h"
#import "ODODatabase-Internal.h"

RCS_ID("$Id$")

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

ODOModel *ODOModelCreate(NSString *name, NSArray *entities)
{
    ODOModel *model;
    
    // Make sure that our poking model classes doesn't cause their +initialize to ask for a shared model that is still in the process of loading...
#ifdef OMNI_ASSERTIONS_ON
    static BOOL CreatingModel = NO;
    OBPRECONDITION(CreatingModel == NO);
    CreatingModel = YES;
    @try {
#endif
        model = [[ODOModel alloc] init];
        
        model->_name = [name copy];
        
        NSMutableDictionary *entitiesByName = [NSMutableDictionary dictionary];
        for (ODOEntity *entity in entities) {
            NSString *name = [entity name];
            
            OBASSERT(![name hasPrefix:@"ODO"]); // All entity names beginning with ODO are reserved
            OBASSERT([entitiesByName objectForKey:name] == nil);
            [entitiesByName setObject:entity forKey:name];
        }
        model->_entitiesByName = [[NSDictionary alloc] initWithDictionary:entitiesByName];
#ifdef OMNI_ASSERTIONS_ON
    } @finally {
        CreatingModel = NO;
    }
#endif
    return model;
}

void ODOModelFinalize(ODOModel *model)
{
    for (ODOEntity *entity in [model->_entitiesByName objectEnumerator]) {
        [entity finalizeModelLoading];
        Class cls = [entity instanceClass];
        if (cls != [ODOObject class]) {
            [ODOModel registerClass:cls forEntity:entity];
#if !LAZY_DYNAMIC_ACCESSORS
            ODOObjectCreateDynamicAccessorsForEntity(entity);
#endif
        }
    }
    
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
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
- (void)dealloc;
{
    // See the @dynamic support in ODOObject, including +resolveInstanceMethod:
    OBRejectUnusedImplementation(self, _cmd);
    [_name release];
    [_entitiesByName release];
    [super dealloc];
}
#pragma clang diagnostic pop

- (NSDictionary *)entitiesByName;
{
    OBPRECONDITION(_entitiesByName);
    return _entitiesByName;
}

- (ODOEntity *)entityNamed:(NSString *)name;
{
    return [_entitiesByName objectForKey:name];
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
