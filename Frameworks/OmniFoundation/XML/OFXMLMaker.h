// Copyright 2004-2005,2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// http://www.omnigroup.com/DeveloperResources/OmniSourceLicense.html.
//
// $Id$

#import <Foundation/Foundation.h>

@class OFXMLMakerElement, OFXMLSink;

@interface OFXMLMaker : NSObject
{
    OFXMLMakerElement *openChild; /* The currently open child-element, or nil */
    NSDictionary *namespaceBindings;  /* Maps namespace strings to namespace prefixes */
}

// API

/* Creating child elements */
- (OFXMLMakerElement *)openElement:(NSString *)elementName;
- (OFXMLMakerElement *)openElement:(NSString *)elementName xmlns:(NSString *)ns;
- (OFXMLMakerElement *)openElement:(NSString *)elementName xmlns:(NSString *)ns defaultNamespace:(NSString *)ns;
- (void)close;

/* Creating child strings. These all return self for convenience. */
- (OFXMLMaker *)addString:(NSString *)cdata;
- (OFXMLMaker *)addEOL;
- (OFXMLMaker *)addComment:(NSString *)cdata;
- (OFXMLMaker *)addBase64Data:(NSData *)bytes;  // A convenience

/* Managing namespaces */
- (NSString *)prefixForNamespace:(NSString *)ns hint:(NSString *)prefixHint;
- (NSDictionary *)namespaceBindings;

/* Where all this generated XML is going */
- (OFXMLSink *)target;

@end

@interface OFXMLMakerElement : OFXMLMaker
{
    OFXMLMaker *nonretainedParent;
    OFXMLSink *target;
    
    NSString *elementName;
    NSMutableArray *attributeNames, *attributeValues;
}

// API
- (OFXMLMakerElement *)addAttribute:(NSString *)elementName value:(NSString *)attValue;
- (OFXMLMakerElement *)addAttribute:(NSString *)elementName xmlns:(NSString *)ns value:(NSString *)attValue;
- (NSString *)name;
- (OFXMLMaker *)parent;

@end

@interface OFXMLSink : OFXMLMaker
{
    unsigned namespacePrefixNextUniqueID;           // Next ID to use when generating a namespace prefix
    NSMutableSet *knownNamespacePrefixes;           // Namespace prefixes already in use somewhere
    NSMutableDictionary *knownNamespaceBindings;    // Namespace bindings to reuse for readability's sake
    
    NSString *encodingName;
    struct {
        unsigned freeWhenDone      :1;  // Not used by this class; subclasses tend to want a flag like this though
        unsigned isStandalone      :1;  // Is this a standalone XML document?
        unsigned knowsStandalone   :1;  // Has the isStandalone flag been explicitly set?
    } flags;    
}

/* Returns a string suitable for use as a namespace prefix. prefixHint is a suggested return value, or nil */
- (NSString *)assignPrefixForNamespace:(NSString *)ns hint:(NSString *)prefixHint;

/* perhaps these should be on OFXMLMaker? */
- (void)setIsStandalone:(BOOL)isStandalone;
- (void)setEncodingName:(NSString *)encodingName;
- (void)addXMLDeclaration;
- (void)addDoctype:(NSString *)rootElement identifiers:(NSString *)publicIdentifier :(NSString *)systemIdentifier;

/* Methods called by OFXMLMaker instances on their target. Users of this class cluster shouldn't call these methods themselves; that's the whole point of the class cluster */

/* Indicates that a new child element is being created */
- (void)beginOpenChild:(OFXMLMakerElement *)child of:(OFXMLMaker *)parent;
/* Indicates that a new child element's name and attributes have been finalized. If isEmpty is NO, then -closeOpenChild: will eventually be called for this child. */
- (void)finishOpenChild:(OFXMLMakerElement *)child attributes:(NSArray *)attributes values:(NSArray *)attributeValues empty:(BOOL)isEmpty;
/* Called after -finishOpenChild:attributes:values:empty:NO */
- (void)closeOpenChild:(OFXMLMakerElement *)child;
/* For adding a string node as a child of the currently-open element */
- (void)addString:(NSString *)aString of:(OFXMLMaker *)container asComment:(BOOL)stringIsComment;
/* For writing base64 data. OFXMLMaker has a default implementation which calls -addString:. */
- (void)addBase64Data:(NSData *)someBytes of:(OFXMLMaker *)container;

/* Called by -[OFXMLCFXMLTreeSink learnAncestralNamespaces] */
- (void)learnAncestralNamespace:(NSString *)ns prefix:(NSString *)nsPrefix;

@end
