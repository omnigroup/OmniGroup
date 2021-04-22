// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <CoreData/CoreData.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

static NSString * const ODOPropertyNameAttributeName = @"name";
static NSString * const ODOPropertyOptionalAttributeName = @"optional";
static NSString * const ODOPropertyTransientAttributeName = @"transient";

static NSString * const ODOAttributeElementName = @"attribute";
static NSString * const ODOAttributeTypeAttributeName = @"type";
static NSString * const ODOAttributeDefaultValueAttributeName = @"default";
static NSString * const ODOAttributePrimaryKeyAttributeName = @"primary";

static NSString * const ODORelationshipElementName = @"relationship";
static NSString * const ODORelationshipDeleteRuleAttributeName = @"delete";
static NSString * const ODORelationshipToManyAttributeName = @"many";
static NSString * const ODORelationshipDestinationEntityAttributeName = @"entity";
static NSString * const ODORelationshipInverseRelationshipAttributeName = @"inverse";

static NSString * const ODOEntityElementName = @"entity";
static NSString * const ODOEntityNameAttributeName = @"name";
static NSString * const ODOEntityInstanceClassAttributeName = @"class";

static OFEnumNameTable *ODOAttributeTypeEnumNameTable(void)
{
    static OFEnumNameTable *table = nil;
    
    if (!table) {
        table = [[OFEnumNameTable alloc] initWithDefaultEnumValue:ODOAttributeTypeInvalid];
        [table setName:@"--invalid--" forEnumValue:ODOAttributeTypeInvalid];
        
        [table setName:@"undefined" forEnumValue:ODOAttributeTypeUndefined];
        [table setName:@"int16" forEnumValue:ODOAttributeTypeInt16];
        [table setName:@"int32" forEnumValue:ODOAttributeTypeInt32];
        [table setName:@"int64" forEnumValue:ODOAttributeTypeInt64];
        [table setName:@"float32" forEnumValue:ODOAttributeTypeFloat32];
        [table setName:@"float64" forEnumValue:ODOAttributeTypeFloat64];
        [table setName:@"string" forEnumValue:ODOAttributeTypeString];
        [table setName:@"boolean" forEnumValue:ODOAttributeTypeBoolean];
        [table setName:@"date" forEnumValue:ODOAttributeTypeDate];
        [table setName:@"xmldatetime" forEnumValue:ODOAttributeTypeXMLDateTime];
        [table setName:@"data" forEnumValue:ODOAttributeTypeData];
    }
    
    return table;
}

static OFEnumNameTable *ODORelationshipDeleteRuleEnumNameTable(void)
{
    static OFEnumNameTable *table = nil;
    if (!table) {
        table = [[OFEnumNameTable alloc] initWithDefaultEnumValue:ODORelationshipDeleteRuleInvalid];
        [table setName:@"--invalid--" forEnumValue:ODORelationshipDeleteRuleInvalid];

        [table setName:@"nullify" forEnumValue:ODORelationshipDeleteRuleNullify];
        [table setName:@"cascade" forEnumValue:ODORelationshipDeleteRuleCascade];
        [table setName:@"deny" forEnumValue:ODORelationshipDeleteRuleDeny];
    }
    
    return table;
}

static void _setPropertyAttributes(NSEntityDescription *entity, NSPropertyDescription *prop, OFXMLDocument *doc)
{
    [doc setAttribute:ODOPropertyNameAttributeName string:[prop name]];
    
    if ([prop isOptional])
        [doc setAttribute:ODOPropertyOptionalAttributeName string:@"true"];
    if ([prop isTransient])
        [doc setAttribute:ODOPropertyTransientAttributeName string:@"true"];
    
    if ([[prop validationPredicates] count] > 0) {
        NSLog(@"Dropping property %@.%@ validation predicates: %@.", [entity name], [prop name], [prop validationPredicates]);
    }
    if ([[prop validationWarnings] count] > 0) {
        NSLog(@"Dropping property %@.%@ warning predicates: %@.", [entity name], [prop name], [prop validationWarnings]);
    }
}

static void _appendAttribute(NSEntityDescription *entity, NSAttributeDescription *attr, OFXMLDocument *doc)
{
    [doc pushElement:ODOAttributeElementName];
    {
        _setPropertyAttributes(entity, attr, doc);
        
        NSAttributeType type = [attr attributeType];
        ODOAttributeType oType;
        
        switch (type) {
            case NSUndefinedAttributeType:
                oType = ODOAttributeTypeUndefined;
                break;
            case NSInteger16AttributeType:
                oType = ODOAttributeTypeInt16;
                break;
            case NSInteger32AttributeType:
                oType = ODOAttributeTypeInt32;
                break;
            case NSInteger64AttributeType:
                oType = ODOAttributeTypeInt64;
                break;
            case NSDoubleAttributeType:
                oType = ODOAttributeTypeFloat64;
                break;
            case NSFloatAttributeType:
                oType = ODOAttributeTypeInt32;
                break;
            case NSStringAttributeType:
                oType = ODOAttributeTypeString;
                break;
            case NSBooleanAttributeType:
                oType = ODOAttributeTypeBoolean;
                break;
            case NSDateAttributeType:
                oType = ODOAttributeTypeDate;
                break;
            case NSBinaryDataAttributeType:
                oType = ODOAttributeTypeData;
                break;
            default:
                NSLog(@"Attribute %@.%@ has unknown type %lu.", [entity name], [attr name], type);
                exit(1);
        }

        [doc setAttribute:ODOAttributeTypeAttributeName string:[ODOAttributeTypeEnumNameTable() nameForEnum:oType]];
        
        // We don't support NSTransformableAttributeType, so this isn't interesting.
        //[doc setAttribute:@"class" string:[attr attributeValueClassName]];
        
        id defaultValue = [attr defaultValue];
        if (OFNOTNULL(defaultValue)) {
            switch (type) {
                case NSInteger32AttributeType:
                    [doc setAttribute:ODOAttributeDefaultValueAttributeName integer:[defaultValue intValue]];
                    break;
                case NSBooleanAttributeType:
                    [doc setAttribute:ODOAttributeDefaultValueAttributeName string:[defaultValue boolValue] ? @"true" : @"false"];
                    break;
                default:
                    NSLog(@"Default value not supported for attribute %@.%@ with type %lu.", [entity name], [attr name], type);
                    exit(1);
            }
        }
    }
    [doc popElement];
}

static void _appendRelationship(NSEntityDescription *entity, NSRelationshipDescription *rel, OFXMLDocument *doc)
{
    NSUInteger minCount = [rel minCount];
    NSUInteger maxCount = [rel maxCount];
    
    if (minCount > 1 || maxCount > 1) {
        NSLog(@"Not supporting relationships with other than basic cardinality options.  %@.%@ has %lu/%lu", [entity name], [rel name], minCount, maxCount);
        exit(1);
    }
    
    NSRelationshipDescription *inverse = [rel inverseRelationship];
    if (!inverse) {
        NSLog(@"Not supporting one-way relationships.");
        exit(1);
    }
    if ([rel isToMany] && [inverse isToMany]) {
        NSLog(@"Not supporting many-to-many relationships.");
        exit(1);
    }
    
    [doc pushElement:ODORelationshipElementName];
    {
        _setPropertyAttributes(entity, rel, doc);

        NSEntityDescription *dest = [rel destinationEntity];
        if (!dest) {
            NSLog(@"Relationship %@.%@ has no destination.", [entity name], [rel name]);
            exit(1);
        }
        [doc setAttribute:ODORelationshipDestinationEntityAttributeName string:[dest name]];

        if ([rel isToMany])
            [doc setAttribute:ODORelationshipToManyAttributeName string:@"true"]; // false is default
        
        ODORelationshipDeleteRule deleteRule;
        switch ([rel deleteRule]) {
            case NSNullifyDeleteRule:
                deleteRule = ODORelationshipDeleteRuleNullify;
                break;
            case NSCascadeDeleteRule:
                deleteRule = ODORelationshipDeleteRuleCascade;
                break;
            case NSDenyDeleteRule:
                deleteRule = ODORelationshipDeleteRuleDeny;
                break;
            default:
                NSLog(@"Relationship %@.%@ has unsupported delete rule %lu.", [entity name], [rel name], [rel deleteRule]);
                exit(1);
        }
        [doc setAttribute:ODORelationshipDeleteRuleAttributeName string:[ODORelationshipDeleteRuleEnumNameTable() nameForEnum:deleteRule]];
        [doc setAttribute:ODORelationshipInverseRelationshipAttributeName string:[inverse name]];
    }
    [doc popElement];
}

static void _appendEntity(NSEntityDescription *entity, OFXMLDocument *doc)
{
    if ([entity isAbstract]) {
        NSLog(@"Not supporting abstract entities");
        exit(1);
    }
    if ([[entity subentities] count] > 0 || [entity superentity]) {
        NSLog(@"Not supporting entity inheritance.");
        exit(1);
    }
    if ([[entity userInfo] count] > 0) {
        NSLog(@"Not supporting entity user info.");
        exit(1);
    }
    
    [doc pushElement:ODOEntityElementName];
    {
        [doc setAttribute:ODOEntityNameAttributeName string:[entity name]];
        [doc setAttribute:ODOEntityInstanceClassAttributeName string:[entity managedObjectClassName]];
        
        // Add a primary key attribute; might be edited later, but the model isn't valid without one.  ODOObject uses a string.
        [doc pushElement:ODOAttributeElementName];
        {
            [doc setAttribute:ODOPropertyNameAttributeName string:@"pk"];
            [doc setAttribute:ODOAttributeTypeAttributeName string:[ODOAttributeTypeEnumNameTable() nameForEnum:ODOAttributeTypeString]];
            [doc setAttribute:ODOAttributePrimaryKeyAttributeName string:@"true"];
        }
        [doc popElement];
        
        NSDictionary *attributesByName = [entity attributesByName];
        NSArray *attributeNames = [[attributesByName allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger attributeIndex, attributeCount = [attributeNames count];
        for (attributeIndex = 0; attributeIndex < attributeCount; attributeIndex++) {
            NSString *name = [attributeNames objectAtIndex:attributeIndex];
            _appendAttribute(entity, [attributesByName objectForKey:name], doc);
        }

        NSDictionary *relationshipsByName = [entity relationshipsByName];
        NSArray *relationshipNames = [[relationshipsByName allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger relationshipIndex, relationshipCount = [relationshipNames count];
        for (relationshipIndex = 0; relationshipIndex < relationshipCount; relationshipIndex++) {
            NSString *name = [relationshipNames objectAtIndex:relationshipIndex];
            _appendRelationship(entity, [relationshipsByName objectForKey:name], doc);
        }
    }
    [doc popElement];
}

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    if (argc != 3) {
        fprintf(stderr, "usage: %s source.mom output.xodo\n", argv[0]);
        exit(1);
    }
    
    NSString *sourcePath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[1] length:strlen(argv[1])];
    NSString *outputPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[2] length:strlen(argv[2])];

    if ([sourcePath isEqualToString:outputPath]) {
        NSLog(@"Source and output paths can't be the same!");
        exit(1);
    }
    
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:sourcePath]];
    if (!model) {
        NSLog(@"Unable to load source model from '%@'", sourcePath);
        exit(1);
    }
    
    if ([[model configurations] count] > 0) {
        NSLog(@"Model configurations not supported.");
        exit(1);
    }
    
    // No way to get a list of all the fetch templates or we'd verify there aren't any
    
    NSError *error = nil;
    OFXMLDocument *doc = [[OFXMLDocument alloc] initWithRootElementName:@"model"
                                                           namespaceURL:[NSURL URLWithString:@"http://www.omnigroup.com/namespace/xodo/1.0"]
                                                     whitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior]
                                                         stringEncoding:kCFStringEncodingUTF8
                                                                  error:&error];
    if (!doc) {
        NSLog(@"Unable to create XML document: %@", [error toPropertyList]);
        exit(1);
    }
    
    // Sort by name?
    NSDictionary *entitiesByName = [model entitiesByName];
    NSArray *entityNames = [[entitiesByName allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger entityIndex, entityCount = [entityNames count];
    for (entityIndex = 0; entityIndex < entityCount; entityIndex++) {
        NSString *name = [entityNames objectAtIndex:entityIndex];
        _appendEntity([entitiesByName objectForKey:name], doc);
    }
    [model release];
    
    NSData *data = [doc xmlData:&error];
    [doc release];
    if (![data writeToURL:[NSURL fileURLWithPath:outputPath] options:NSDataWritingAtomic error:&error]) {
        NSLog(@"Unable to write XML document: %@", [error toPropertyList]);
        exit(1);
    }

    [pool release];
    return 0;
}
