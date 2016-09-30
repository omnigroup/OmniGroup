// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWSGMLTagType.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWSGMLTag.h>
#import <OWF/OWSGMLAttribute.h>

RCS_ID("$Id$")

@implementation OWSGMLTagType

+ (unsigned int)idAttributeIndex;
{
    return 0;
}

+ (unsigned int)classAttributeIndex;
{
    return 1;
}

+ (unsigned int)styleAttributeIndex;
{
    return 2;
}

- initWithName:(NSString *)aName dtdIndex:(unsigned int)anIndex;
{
    if (!(self = [super init]))
        return nil;
    name = [aName copy];
    dtdIndex = anIndex;
    masterAttributesTagType = nil;
    attributeNames = [[NSMutableArray alloc] init];
    attributeTrie = [[OFTrie alloc] initCaseSensitive:NO];

    // Add core attributes to all tags:

    /* http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd
    
    <!-- core attributes common to most elements
    id       document-wide unique id
    class    space separated list of classes
    style    associated style info
    title    advisory title/amplification
    -->
    
    <!ENTITY % coreattrs
    "id          ID             #IMPLIED
    class       CDATA          #IMPLIED
    style       %StyleSheet;   #IMPLIED
    title       %Text;         #IMPLIED"
    >
    */
    [self addAttributeNamed:@"id"];
    [self addAttributeNamed:@"class"];
    [self addAttributeNamed:@"style"];
    [self addAttributeNamed:@"title"];

    // We don't currently add the language stuff, but we might want to...
    
    /*
    <!-- internationalization attributes
    lang        language code (backwards compatible)
    xml:lang    language code (as per XML 1.0 spec)
    dir         direction for weak/neutral text
    -->
    <!ENTITY % i18n
    "lang        %LanguageCode; #IMPLIED
    xml:lang    %LanguageCode; #IMPLIED
    dir         (ltr|rtl)      #IMPLIED"
    >
    */

    return self;
}

- (NSString *)name;
{
    return name;
}

- (unsigned int)dtdIndex;
{
    return dtdIndex;
}

- (OWSGMLTagType *)masterAttributesTagType;
{
    if (masterAttributesTagType != nil)
        return [masterAttributesTagType masterAttributesTagType];
    return self;
}

- (NSArray *)attributeNames;
{
    if (masterAttributesTagType != nil)
        return [masterAttributesTagType attributeNames];
    return attributeNames;
}

- (OFTrie *)attributeTrie
{
    if (masterAttributesTagType != nil)
        return [masterAttributesTagType attributeTrie];
    return attributeTrie;
}

- (void)shareAttributesWithTagType:(OWSGMLTagType *)aTagType;
{
    aTagType = [aTagType masterAttributesTagType];
    if (aTagType == self)
        return;

    masterAttributesTagType = aTagType;
    for (NSString *attributeName in attributeNames)
         [masterAttributesTagType addAttributeNamed:attributeName];

    attributeNames = nil;
    attributeTrie = nil;
}

- (NSUInteger)addAttributeNamed:(NSString *)attributeName;
{
    if (masterAttributesTagType != nil)
        return [masterAttributesTagType addAttributeNamed:attributeName];

    if ([attributeNames containsObject:attributeName])
        return [attributeNames indexOfObject:attributeName];

    NSUInteger newAttributeIndex = [attributeNames count];
    OWSGMLAttribute *attribute = [[OWSGMLAttribute alloc] initWithOffset:newAttributeIndex];
    [attributeNames addObject:attributeName];
    [attributeTrie addBucket:attribute forString:attributeName];
    return newAttributeIndex;
}

- (NSUInteger)indexOfAttribute:(NSString *)attributeName;
{
    if (masterAttributesTagType != nil)
        return [masterAttributesTagType addAttributeNamed:attributeName];

    return [attributeNames indexOfObject:attributeName];
}

- (NSUInteger)attributeCount;
{
    if (masterAttributesTagType != nil)
        return [masterAttributesTagType attributeCount];
    else
        return [attributeNames count];
}

- (BOOL)hasAttributeNamed:(NSString *)attributeName;
{
    if (masterAttributesTagType != nil)
        return [masterAttributesTagType hasAttributeNamed:attributeName];

    return [attributeNames containsObject:attributeName];
}

- (void)setContentHandling:(OWSGMLTagContentHandlingType)newContentHandling;
{
    contentHandling = newContentHandling;
}

- (OWSGMLTagContentHandlingType)contentHandling;
{
    return contentHandling;
}

- (OWSGMLTag *)attributelessStartTag;
{
    if (!attributelessStartTag)
        attributelessStartTag = [OWSGMLTag newTagWithTokenType:OWSGMLTokenTypeStartTag tagType:self];
    return attributelessStartTag;
}

- (OWSGMLTag *)attributelessEndTag;
{   
    if (!attributelessEndTag)
        attributelessEndTag = [OWSGMLTag newTagWithTokenType:OWSGMLTokenTypeEndTag tagType:self];
    return attributelessEndTag;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];

    if (name != nil)
        [debugDictionary setObject:name forKey:@"name"];
    [debugDictionary setObject:[NSString stringWithFormat:@"%d", dtdIndex] forKey:@"dtdIndex"];
    if (masterAttributesTagType != nil)
        [debugDictionary setObject:masterAttributesTagType forKey:@"masterAttributesTagType"];
    if (attributeNames != nil)
        [debugDictionary setObject:attributeNames forKey:@"attributeNames"];
    if (attributeTrie != nil)
        [debugDictionary setObject:attributeTrie forKey:@"attributeTrie"];

    return debugDictionary;
}

@end
