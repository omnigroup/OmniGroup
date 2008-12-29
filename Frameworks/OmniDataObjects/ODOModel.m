// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOModel.h>

#import "ODOEntity-Internal.h"
#import "ODODatabase-Internal.h"

RCS_ID("$Id$")

NSString * const ODOModelRootElementName = @"model";
NSString * const ODOModelNamespaceURLString = @"http://www.omnigroup.com/namespace/xodo/1.0";

@implementation ODOModel

static NSMutableSet *InternedNames = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    InternedNames = [[NSMutableSet alloc] init];
}

+ (NSString *)internName:(NSString *)name;
{
    // Only immutable strings should be passed in.
    OBPRECONDITION(name == [[name copy] autorelease]);
    
    NSString *intern = [InternedNames member:name];
    if (!intern) {
        [InternedNames addObject:name];
        intern = name;
    }

    return intern;
}

- (id)initWithContentsOfFile:(NSString *)path error:(NSError **)outError;
{
    _path = [path copy];
    
    OFXMLDocument *doc = [[OFXMLDocument alloc] initWithContentsOfFile:path whitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior] error:outError];
    if (!doc) {
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Couldn't create OFXMLDocument.", nil, OMNI_BUNDLE, @"error reason");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    OFXMLCursor *cursor = [[[OFXMLCursor alloc] initWithDocument:doc] autorelease];
    [doc release];
    
    if (OFNOTEQUAL([cursor name], ODOModelRootElementName)) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Wrong root element name.  Was expecting '%@' but found '%@'.", nil, OMNI_BUNDLE, @"error reason"), ODOModelRootElementName, [cursor name]];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    
    if (OFNOTEQUAL([cursor attributeNamed:@"xmlns"], ODOModelNamespaceURLString)) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Wrong root element namespace.  Was expecting '%@' but found '%@'.", nil, OMNI_BUNDLE, @"error reason"), ODOModelNamespaceURLString, [cursor attributeNamed:@"xmlns"]];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
        
    NSMutableDictionary *entitiesByName = [NSMutableDictionary dictionary];
    while ([cursor openNextChildElementNamed:ODOEntityElementName]) {
        ODOEntity *entity = [[ODOEntity alloc] initWithCursor:cursor model:self error:outError];
        if (!entity) {
            [self release];
            return nil;
        }
        
        NSString *name = [entity name];
        
        if ([name isEqualToString:ODODatabaseMetadataTableName]) {
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Entity name '%@' is reserved.", nil, OMNI_BUNDLE, @"error reason"), ODODatabaseMetadataTableName];
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
            ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
            [self release];
            return nil;
        }
        
        if ([entitiesByName objectForKey:name]) {
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Model '%@' has multiple properties named '%@'.", nil, OMNI_BUNDLE, @"error reason"), path, name];
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
            ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
            [self release];
            return nil;
        }
        
        [entitiesByName setObject:entity forKey:name];
        [cursor closeElement];
    }
    
    _entitiesByName = [[NSDictionary alloc] initWithDictionary:entitiesByName];

    NSEnumerator *entityEnum = [_entitiesByName objectEnumerator];
    ODOEntity *entity;
    while ((entity = [entityEnum nextObject])) {
        if (![entity finalizeModelLoading:outError]) {
            [self release];
            return nil;
        }
    }

    // TODO: Make sure that for all relationships, relationship.inverse.inverse is the relationship.  This will verify that two relationships don't both claim the same relationship as their inverse.
    
    return self;
}

- (void)dealloc;
{
    [_path release];
    [_entitiesByName release];
    [super dealloc];
}

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
    [dict setObject:_path forKey:@"path"];
    [dict setObject:[[_entitiesByName allValues] arrayByPerformingSelector:_cmd] forKey:@"entities"];
    return dict;
}
#endif

@end
