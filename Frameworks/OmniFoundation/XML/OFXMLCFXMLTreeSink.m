// Copyright 2004-2005, 2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// http://www.omnigroup.com/DeveloperResources/OmniSourceLicense.html.

#import <OmniFoundation/OFXMLCFXMLTreeSink.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSMutableString-OFExtensions.h>

RCS_ID("$Id$");


@implementation OFXMLCFXMLTreeSink

static void learnNamespace(const void *attributeName, const void *attributeValue, void *context);
static NSCharacterSet *attributeDangerChars, *textDangerChars;

+ (void)initialize
{
    OBINITIALIZE;
    
    attributeDangerChars = [[NSCharacterSet characterSetWithCharactersInString:@"\"&'"] retain];
    textDangerChars = [[NSCharacterSet characterSetWithCharactersInString:@"<&>"] retain];
}

- init
{
    return [self initWithCFXMLTree:NULL];
}

- initWithCFXMLTree:(CFXMLTreeRef)toplevel
{
    if (![super init])
        return nil;
    
    if (toplevel == NULL) {
        CFXMLNodeRef rootNodeInfo = CFXMLNodeCreate(kCFAllocatorDefault, kCFXMLNodeTypeDocumentFragment, NULL, NULL, kCFXMLNodeCurrentVersion);
        topNode = CFXMLTreeCreateWithNode(kCFAllocatorDefault, rootNodeInfo);
        CFRelease(rootNodeInfo);
    } else {
        topNode = toplevel;
        CFRetain(topNode);
    }
    
    currentEltTree = topNode;
#ifdef DEBUG
    currentElt = self;
#endif
    
    return self;
}

- (void)dealloc
{
    CFRelease(topNode);
    [encodingName release];
    [super dealloc];
}

- (void)learnAncestralNamespaces
{
    CFXMLTreeRef anElement = topNode;
    
    while (anElement != NULL) {
        CFXMLNodeRef nodeInfo = CFXMLTreeGetNode(anElement);
        
        if (nodeInfo && (CFXMLNodeGetTypeCode(nodeInfo) == kCFXMLNodeTypeElement)) {
            const CFXMLElementInfo *nodeInfoPtr = CFXMLNodeGetInfoPtr(nodeInfo);
            if (nodeInfoPtr != NULL && nodeInfoPtr->attributes != NULL)
                CFDictionaryApplyFunction(nodeInfoPtr->attributes, learnNamespace, self);
        } 
        
        anElement = CFTreeGetParent(anElement);
    }
}

- (CFXMLTreeRef)topNode;
{
    return topNode;
}

- (NSData *)xmlData
{
    NSData *outData = (NSData *)CFXMLTreeCreateXMLData(kCFAllocatorDefault, topNode);
    [outData autorelease];
    return outData;
}

- (void)addCFXMLNode:(CFXMLNodeRef)newNode
{
    CFXMLTreeRef newTree = CFXMLTreeCreateWithNode(kCFAllocatorDefault, newNode);
    CFTreeAppendChild(currentEltTree, newTree);
    CFRelease(newTree);  // Retained by parent.
}

/* XMLMaker API */

- (OFXMLMakerElement *)openElement:(NSString *)elementName xmlns:(NSString *)ns defaultNamespace:(NSString *)nsdefault;
{
    OFXMLMakerElement *result;
    
    OBPRECONDITION(currentElt == self);
    OBPRECONDITION(currentEltTree == topNode);
    
    result = [super openElement:elementName xmlns:ns defaultNamespace:nsdefault];
        
    OBPOSTCONDITION(openChild == currentElt);
    
    return result;
}

- (void)close;
{
    OBPRECONDITION(currentEltTree == topNode);
    OBPRECONDITION(openChild == nil);
    
    currentEltTree = NULL;
}

- (OFXMLMaker *)addEOL
{
    CFXMLNodeRef attrs = CFXMLNodeCreate(kCFAllocatorDefault,
                                         kCFXMLNodeTypeWhitespace, CFSTR("\n"),
                                         NULL, kCFXMLNodeCurrentVersion);
    [self addCFXMLNode:attrs];
    CFRelease(attrs);
    return self;
}

/* XMLSink API */

- (void)addXMLDeclaration
{
    NSMutableString *piAttributes = [[NSMutableString alloc] initWithString:@"version=\"1.0\""];
    
    /* CFXMLTreeCreateXMLData() actually parses out the PI content to determine what encoding to use for the output doc...! */
    if (encodingName)
        [piAttributes appendStrings:@" encoding=\"", encodingName, @"\"", nil];
    
    if (flags.knowsStandalone) {
        [piAttributes appendString:@" standalone=\""];
        [piAttributes appendString:( flags.isStandalone? @"yes" : @"no" )];
        [piAttributes appendString:@"\""];
    }
    
    CFXMLProcessingInstructionInfo attributes = { (CFStringRef)[piAttributes copy] };
    [piAttributes release];
    
    CFXMLNodeRef attrs = CFXMLNodeCreate(kCFAllocatorDefault,
                                         kCFXMLNodeTypeProcessingInstruction, CFSTR("xml"),
                                         &attributes, kCFXMLNodeCurrentVersion);
    [self addCFXMLNode:attrs];
    CFRelease(attrs);
    [(NSString *)(attributes.dataString) release];
    
    [self addEOL];
}

- (void)addDoctype:(NSString *)rootElement identifiers:(NSString *)publicIdentifier :(NSString *)systemIdentifier;
{
    CFXMLDocumentTypeInfo attributes;
    
    CFURLRef systemID = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)systemIdentifier, NULL);
    attributes = (CFXMLDocumentTypeInfo){
        .externalID = {
            .systemID = systemID,
            .publicID = (CFStringRef)publicIdentifier,
        }
    };
    
    CFXMLNodeRef attrs = CFXMLNodeCreate(kCFAllocatorDefault,
                                         kCFXMLNodeTypeDocumentType, (CFStringRef)rootElement,
                                         &attributes, kCFXMLNodeCurrentVersion);
    CFRelease(systemID);
    
    [self addCFXMLNode:attrs];
    
    CFRelease(attrs);
    
    [self addEOL];
}

#ifdef DEBUG
- (void)beginOpenChild:(OFXMLMakerElement *)child of:(OFXMLMaker *)parent;
{
    OBPRECONDITION(currentElt == parent);
    currentElt = child;
}
#endif

- (void)finishOpenChild:(OFXMLMakerElement *)child attributes:(NSArray *)attributes values:(NSArray *)attributeValues empty:(BOOL)isEmpty;
{
    OBINVARIANT(child == currentElt);
    
    CFXMLElementInfo nodeInfo = { .attributes = NULL, .attributeOrder = NULL, .isEmpty = isEmpty };
    
    unsigned attributeCount = [attributes count], attributeIndex;
    if (attributeCount > 0) {
        NSMutableArray *fixedAttributeValues = [attributeValues mutableCopy];
        // Note: This isn't abstracted out because the particular quoting we're doing depends on the (undocumented, sigh) behavior of the CoreFoundation XML writer.
        for(attributeIndex = 0; attributeIndex < attributeCount; attributeIndex ++) {
            NSString *unquotedValue = [fixedAttributeValues objectAtIndex:attributeIndex];
            if ([unquotedValue rangeOfCharacterFromSet:attributeDangerChars].location == NSNotFound)
                continue;
            NSMutableString *buf = [unquotedValue mutableCopy];
            [buf replaceAllOccurrencesOfString:@"&" withString:@"&amp;"];
            if([buf containsString:@"'"] && [buf containsString:@"\""]) {
                // CFXML will choose single- or double- quoting based on the value, but will emit malformed XML if the value has both kinds of quotes in it
                [buf replaceAllOccurrencesOfString:@"\"" withString:@"&quot;"];
            }
            [fixedAttributeValues replaceObjectAtIndex:attributeIndex withObject:buf];
            [buf release];
        }
        nodeInfo.attributes = (CFDictionaryRef)[[NSDictionary alloc] initWithObjects:fixedAttributeValues forKeys:attributes];
        nodeInfo.attributeOrder = (CFArrayRef)attributes;
        [fixedAttributeValues release];
    }
    
    CFXMLNodeRef newNode = CFXMLNodeCreate(kCFAllocatorDefault,
                                           kCFXMLNodeTypeElement, (CFStringRef)[child name],
                                           &nodeInfo, kCFXMLNodeCurrentVersion);
    
    [(id)(nodeInfo.attributes) release];
    
    CFXMLTreeRef newTree = CFXMLTreeCreateWithNode(kCFAllocatorDefault, newNode);
    CFRelease(newNode);
    
    CFTreeAppendChild(currentEltTree, newTree);
    CFRelease(newTree);  // Retained by parent.
    
    if (isEmpty) {
        // If isEmpty is YES, _closeOpenChild won't be called separately.
#ifdef DEBUG
        currentElt = [child parent]; // finish up what _beginOpenChild:of: did
#endif
    } else {
        // We may get some other nodes, which will be children of this node. Eventually followed by a _closeOpenChild for this node. Keep track of the node which will be the intervening nodes' parent.
        currentEltTree = newTree;
    }
}

- (void)closeOpenChild:(OFXMLMakerElement *)child;
{
    OBPRECONDITION(child == currentElt);
    currentEltTree = CFTreeGetParent(currentEltTree);
#ifdef DEBUG
    currentElt = [child parent];
#endif
}

static NSString *simpleXMLEscape(NSString *str, NSRange *where, void *dummy)
{
    OBASSERT(where->length == 1);
    unichar ch = [str characterAtIndex:where->location];
    
    switch(ch) {
        case '&':
            return @"&amp;";
        case '<':
            return @"&lt;";
        case '>':
            return @"&gt;";
        case '"':
            return @"&quot;";
        default:
            return [NSString stringWithFormat:@"&#%u;", (unsigned int)ch];
    }
}

- (void)addString:(NSString *)aString of:(OFXMLMaker *)container asComment:(BOOL)isComment;
{
    OBASSERT(container == currentElt);

    NSString *escapedString = [aString stringByPerformingReplacement:simpleXMLEscape onCharacters:textDangerChars]; 
                
    CFXMLNodeRef newValueNode = CFXMLNodeCreate(kCFAllocatorDefault,
                                                isComment? kCFXMLNodeTypeComment : kCFXMLNodeTypeText,
                                                (CFStringRef)escapedString, NULL,
                                                kCFXMLNodeCurrentVersion);
    CFXMLTreeRef newValueTree = CFXMLTreeCreateWithNode(kCFAllocatorDefault, newValueNode);
    CFRelease(newValueNode);
    CFTreeAppendChild(currentEltTree, newValueTree);
    CFRelease(newValueTree);
}

static void learnNamespace(const void *attributeName, const void *attributeValue, void *context)
{
    CFStringRef name = attributeName;
    NSString *ns = (NSString *)attributeValue;
    OFXMLCFXMLTreeSink *sink = context;
    
    if (CFStringCompare(name, CFSTR("xmlns"), 0) == kCFCompareEqualTo) {
        /* Default namespace declaration */
        [sink learnAncestralNamespace:ns prefix:@""];
    } else if (CFStringHasPrefix(name, CFSTR("xmlns:"))) {
        CFStringRef namespacePrefix = CFStringCreateWithSubstring(kCFAllocatorDefault,
                                                                  name, 
                                                                  (CFRange){6, CFStringGetLength(name)-6});
        OBASSERT(CFStringGetLength(namespacePrefix) > 0);
        [sink learnAncestralNamespace:ns prefix:(NSString *)namespacePrefix];
        CFRelease(namespacePrefix);
    }
}

@end


