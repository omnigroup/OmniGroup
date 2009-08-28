// Copyright 2004-2005,2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// http://www.omnigroup.com/DeveloperResources/OmniSourceLicense.html.

#import <OmniFoundation/OFXMLMaker.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/OFXMLQName.h>

RCS_ID("$Id$");

@interface OFXMLMaker (Private)

- (void)bindNamespace:(NSString *)ns toPrefix:(NSString *)aPrefix; /* usually clients shouldn't call this, call -prefixForNamespace:hint: instead */

- (BOOL)_maybeFinishOpening:(BOOL)willBeEmpty;  // Indicates that no more attributes will be set on this element. Returns YES if the element wasn't finished opening before the call.

- (void)_closeChild:(OFXMLMakerElement *)elt;     // Called on parent by currently-open child node when it's closed

@end

@interface OFXMLMakerElement (Private)

- initWithParent:(OFXMLMaker *)parentElement target:(OFXMLSink *)aTarget;
- (void)setName:(NSString *)elementName;

@end

@implementation OFXMLMaker

// Creation and destruction

// Both of our instance variables start out nil, so we don't need an -init method

- (void)dealloc
{
    [openChild release];
    [namespaceBindings release];
    [super dealloc];
}

// API
- (OFXMLMakerElement *)openElement:(NSString *)elementName;
{
    return [self openElement:elementName xmlns:nil defaultNamespace:nil];
}

- (OFXMLMakerElement *)openElement:(NSString *)elementName xmlns:(NSString *)ns;
{
    return [self openElement:elementName xmlns:ns defaultNamespace:nil];
}

- (OFXMLMakerElement *)openElement:(NSString *)elementName xmlns:(NSString *)ns defaultNamespace:(NSString *)nsdefault;
{
    NSString *nsPrefix;
    
    OBPRECONDITION(openChild == nil);
    
    if (openChild != nil) {
        [NSException raise:NSGenericException format:@"Attempting to open new child of %@ while old child is still open (old=<%@>, new=<%@>)", self, [openChild name], elementName];
    }
    
    // Try to get a namespace before we open the child, in case we can still bind it ourselves
    if (ns == nil || (nsdefault != nil && [nsdefault isEqual:ns]))
        nsPrefix = nil;
    else
        nsPrefix = [self prefixForNamespace:ns hint:nil];
    
    [self _maybeFinishOpening:NO];
    openChild = [[OFXMLMakerElement alloc] initWithParent:self target:[self target]];
    
    // (Re)declare the default namespace, if requested
    if (nsdefault != nil) {
        // Is the requested default the same as the current default?
        if ([[[self namespaceBindings] objectForKey:nsdefault] isEqual:@""]) {
            // Yes, don't do anything
        } else {
            // No, declare the default namespace
            [openChild addAttribute:@"xmlns" value:nsdefault];
            [openChild bindNamespace:nsdefault toPrefix:@""];
        }
    }
    
    // Get a prefix for our namespace if we haven't already
    if (nsPrefix == nil && ns != nil) {
        // Hooray for XML's weird namespace scoping rules. We can declare the namespace in the same element that uses it.
        nsPrefix = [openChild prefixForNamespace:ns hint:nil];
    }

    if (nsPrefix == nil || /* No namespace specified */
        [nsPrefix isEqualToString:@""] /* Default namespace specified, no prefix needed */)
        [openChild setName:elementName];  
    else {
        NSString *prefixedName = [[NSString alloc] initWithFormat:@"%@:%@", nsPrefix, elementName];
        [openChild setName:prefixedName];
        [prefixedName release];
    }
    
    OBPOSTCONDITION(openChild);

    return openChild;
}

- (void)close;
{
    BOOL isEmpty;
    
    isEmpty = [self _maybeFinishOpening:YES];
    if (openChild) {
        OBASSERT(!isEmpty); // Can't be empty if we have a child element!
        [openChild close];
    }
    
    if (!isEmpty) {
        OBASSERT([self isKindOfClass:[OFXMLMakerElement class]]);
        [[self target] closeOpenChild:(OFXMLMakerElement *)self];
    }
}

- (OFXMLMaker *)addString:(NSString *)cdata;
{
    OBPRECONDITION(openChild == nil);

    if (openChild != nil) {
        [NSException raise:NSGenericException format:@"Attempting to add content to %@ while child <%@> is open", self, [openChild name]];
    }

    [self _maybeFinishOpening:NO];
    [[self target] addString:cdata of:self asComment:NO];
    return self;
}

- (OFXMLMaker *)addEOL
{
    return [self addString:@"\n"];
}

- (OFXMLMaker *)addComment:(NSString *)cdata;
{
    OBPRECONDITION(openChild == nil);
    
    if (openChild != nil) {
        [NSException raise:NSGenericException format:@"Attempting to add content to %@ while child <%@> is open", self, [openChild name]];
    }
    
    [self _maybeFinishOpening:NO];
    [[self target] addString:cdata of:self asComment:YES];
    return self;
}

- (OFXMLMaker *)addBase64Data:(NSData *)bytes;
{
    OBPRECONDITION(openChild == nil);
    
    if (openChild != nil) {
        [NSException raise:NSGenericException format:@"Attempting to add content to %@ while child <%@> is open", self, [openChild name]];
    }
    
    [self _maybeFinishOpening:NO];
    [[self target] addBase64Data:bytes of:self];
    return self;
}

- (NSString *)prefixForNamespace:(NSString *)ns hint:(NSString *)prefixHint;
{
    return [namespaceBindings objectForKey:ns];
}

- (void)bindNamespace:(NSString *)newNamespace toPrefix:(NSString *)newPrefix
{
    if (namespaceBindings == nil)
        namespaceBindings = [[NSDictionary alloc] initWithObjectsAndKeys:newPrefix, newNamespace, nil];
    else {
        NSDictionary *newBindings = [namespaceBindings dictionaryWithObject:newPrefix forKey:newNamespace];
        [newBindings retain];
        [namespaceBindings release];
        namespaceBindings = newBindings;
    }
}

- (NSDictionary *)namespaceBindings
{
    return namespaceBindings;
}

- (BOOL)_maybeFinishOpening:(BOOL)willBeEmpty
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (OFXMLSink *)target
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)_closeChild:(OFXMLMakerElement *)elt
{
    OBINVARIANT(elt == openChild);
    [openChild release];
    openChild = nil;
}

@end

@implementation OFXMLMakerElement : OFXMLMaker

- initWithParent:(OFXMLMaker *)parentMaker target:(OFXMLSink *)parentTarget
{
    [super init];
    nonretainedParent = parentMaker;
    target = [parentTarget retain];
    attributeNames = [[NSMutableArray alloc] init];
    attributeValues = [[NSMutableArray alloc] init];
    
    [target beginOpenChild:self of:nonretainedParent];
    
    return self;
}

- (void)dealloc
{
    [elementName release];
    OBPRECONDITION(nonretainedParent == nil);
    nonretainedParent = nil;
    [target release];
    [attributeNames release];
    [attributeValues release];
    [super dealloc];
}

// API
- (OFXMLMakerElement *)addAttribute:(NSString *)attName value:(NSString *)attValue;
{
    OBPRECONDITION(attributeNames != nil);
    OBINVARIANT(attName != nil);
    OBINVARIANT(![NSString isEmptyString:attName]);
    OBINVARIANT(attValue != nil);
    
    attName = [attName copy];
    attValue = [attValue copy];
    
    [attributeNames addObject:attName];
    [attributeValues addObject:attValue];
    
    [attName release];
    [attValue release];
    
    return self;
}

- (OFXMLMakerElement *)addAttribute:(NSString *)attributeName xmlns:(NSString *)ns value:(NSString *)attValue;
{
    NSString *nsPrefix;

    OBASSERT(ns != nil);
    
    nsPrefix = [self prefixForNamespace:ns hint:nil];
    OBASSERT(nsPrefix != nil);
    if ([nsPrefix isEqualToString:@""]) {
        return [self addAttribute:attributeName value:attValue];
    } else {
        NSString *prefixedName = [[NSString alloc] initWithFormat:@"%@:%@", nsPrefix, attributeName];
        [self addAttribute:prefixedName value:attValue];
        [prefixedName release];
        return self;
    }
}

- (NSString *)name;
{
    return elementName;
}

- (void)setName:(NSString *)aName;
{
    OBPRECONDITION(elementName == nil);
    elementName = [aName copy];
    OBPOSTCONDITION(elementName != nil);
}

- (OFXMLSink *)target
{
    return target;
}

- (OFXMLMaker *)parent;
{
    return nonretainedParent;
}

- (void)close;
{
    OBPRECONDITION(nonretainedParent != nil);
    [super close];
    OFXMLMaker *parent = nonretainedParent;
    nonretainedParent = nil;
    [parent _closeChild:self];  // This will release and probably dealloc us.
}

- (NSString *)prefixForNamespace:(NSString *)ns hint:(NSString *)prefixHint;
{
    NSString *nsPrefix;
    
    /* Copy down our parent's scope if we haven't yet */
    if (namespaceBindings == nil)
        namespaceBindings = [[[self parent] namespaceBindings] retain];
    
    /* do we have a cached binding for this namespace? */
    nsPrefix = [super prefixForNamespace:ns hint:prefixHint];
    if (nsPrefix != nil)
        return nsPrefix;
    
    if (attributeNames != nil) {
        /* There isn't binding for that namespace in scope, but we haven't closed our open-tag yet, so we can declare the namespace ourselves. */
        nsPrefix = [target assignPrefixForNamespace:ns hint:prefixHint];
        
        [self addAttribute:[@"xmlns:" stringByAppendingString:nsPrefix] value:ns];
        [self bindNamespace:ns toPrefix:nsPrefix];
    } else {
        /* The given namespace isn't in scope, and it's too late for us to declare it, so return nil */
        nsPrefix = nil;
    }
    
    return nsPrefix;
}

- (void)bindNamespace:(NSString *)newNamespace toPrefix:(NSString *)newPrefix
{
    /* Copy down our parent's scope if we haven't yet */
    if (namespaceBindings == nil)
        namespaceBindings = [[[self parent] namespaceBindings] retain];
    /* parent has no bindings? start out with an empty scope */
    if (namespaceBindings == nil)
        namespaceBindings = [[NSDictionary alloc] init];
    [super bindNamespace:newNamespace toPrefix:newPrefix];
}

- (NSDictionary *)namespaceBindings
{
    if (namespaceBindings == nil) {
        namespaceBindings = [[[self parent] namespaceBindings] retain];
    }
    return namespaceBindings;
}

- (BOOL)_maybeFinishOpening:(BOOL)willBeEmpty
{
    if (attributeNames != nil) {
        // Write out our begin-tag.
        [target finishOpenChild:self attributes:attributeNames values:attributeValues empty:willBeEmpty];
        [attributeNames release];
        attributeNames = nil;
        [attributeValues release];
        attributeValues = nil;
        return YES;
    } else 
        return NO;
}

@end

@implementation OFXMLSink

- init
{
    if (![super init])
        return nil;
    
    namespacePrefixNextUniqueID = 1;
    knownNamespacePrefixes = [[NSMutableSet alloc] init];
    knownNamespaceBindings = [[NSMutableDictionary alloc] init];
    
    /* The XML Namespaces specification specifies that some namespace prefixes are bound by default */
    /* ( see, eg, REC-xml-names-20060816 [3] ) */
    [knownNamespaceBindings setObject:@"xml"   forKey:OFXMLNamespaceXML];
    [knownNamespaceBindings setObject:@"xmlns" forKey:OFXMLNamespaceXMLNS];
    [knownNamespacePrefixes addObject:OFXMLNamespaceXML];
    [knownNamespacePrefixes addObject:OFXMLNamespaceXMLNS];
    
    return self;
}

- (void)dealloc
{
    [knownNamespaceBindings release];
    [knownNamespacePrefixes release];
    [super dealloc];
}

/* XMLMaker API */

- (OFXMLSink *)target
{
    return self;
}

- (NSString *)prefixForNamespace:(NSString *)ns hint:(NSString *)prefixHint;
{
    return nil;
}

- (BOOL)_maybeFinishOpening:(BOOL)willBeEmpty;
{
    return NO;
}


/* OFXMLSink API */

- (NSString *)assignPrefixForNamespace:(NSString *)ns hint:(NSString *)prefixHint
{
    NSString *nsPrefix;
    
    // We maintain a global table of namespace prefixes. This is unneccessary from XML's point of view, but it makes the file easier for a human to read if the prefix usage is consistent across the file; and it's an easy way to ensure that prefixes don't collide. It would also be valid to return a unique string each time, or something keyed off the node depth and attribute count, etc.
    
    nsPrefix = [knownNamespaceBindings objectForKey:ns];
    if (nsPrefix)
        return nsPrefix;
    
    if ([knownNamespacePrefixes containsObject:prefixHint]) {
        // Can't use the hint; that prefix is already in use somewhere.
        prefixHint = nil;
    }
    
    if (prefixHint == nil) {
        nsPrefix = [NSString stringWithFormat:@"ns%d", namespacePrefixNextUniqueID ++];
        OBASSERT(![knownNamespacePrefixes containsObject:nsPrefix]);
    } else {
        nsPrefix = prefixHint;
    }
    
    // Record this in our tables for later reuse
    [knownNamespacePrefixes addObject:nsPrefix];
    [knownNamespaceBindings setObject:nsPrefix forKey:ns];
    
    return nsPrefix;
}

- (void)learnAncestralNamespace:(NSString *)ns prefix:(NSString *)nsPrefix
{
    if (![NSString isEmptyString:nsPrefix]) {
        if (![knownNamespacePrefixes containsObject:nsPrefix]) {
            [knownNamespaceBindings setObject:nsPrefix forKey:ns];
            [knownNamespacePrefixes addObject:nsPrefix];
        } else {
            // TODO: We should remove the prefix from our list of known bindings if it's different.
        }
    }
    
    /* We learn ancestral namespaces from the bottom up. Since it's legal to rebind a namespace (in particular, it's legal to rebind the default namespace) we don't want to override any bindings we've learned. */
    
    NSEnumerator *spaces = [namespaceBindings keyEnumerator];
    NSString *aNamespace;
    while( (aNamespace = [spaces nextObject]) != nil ) {
        if ([nsPrefix isEqualToString:[namespaceBindings objectForKey:aNamespace]])
            return;
    }
    
    /* If this namespace is already bound to some other prefix, use the closer binding */
    if ([namespaceBindings objectForKey:ns] != nil)
        return;

    /* Record this binding so we can use it */
    [self bindNamespace:ns toPrefix:nsPrefix];
}

- (void)setIsStandalone:(BOOL)isStandalone;
{
    flags.knowsStandalone = 1;
    flags.isStandalone = isStandalone? 1 : 0;
}

- (void)setEncodingName:(NSString *)str;
{
    [encodingName autorelease];
    encodingName = [str copy];
}

/* OFXMLSink API to be implemented by concrete subclasses */

- (void)beginOpenChild:(OFXMLMakerElement *)child of:(OFXMLMaker *)parent;
{ /* Unlike the rest of the API calls, it's OK if the subclass doesn't do anything here */ }

- (void)finishOpenChild:(OFXMLMakerElement *)child attributes:(NSArray *)attributes values:(NSArray *)attributeValues empty:(BOOL)isEmpty;
{ OBRequestConcreteImplementation(self, _cmd); }

- (void)closeOpenChild:(OFXMLMakerElement *)child;
{ OBRequestConcreteImplementation(self, _cmd); }

- (void)addString:(NSString *)aString of:(OFXMLMaker *)container asComment:(BOOL)asComment;
{ OBRequestConcreteImplementation(self, _cmd); }

- (void)addXMLDeclaration
{ OBRequestConcreteImplementation(self, _cmd); }

- (void)addDoctype:(NSString *)rootElement identifiers:(NSString *)publicIdentifier :(NSString *)systemIdentifier;
{ OBRequestConcreteImplementation(self, _cmd); }

/* OFXMLSink API which can optionally be overridden with a more efficient implementation */
- (void)addBase64Data:(NSData *)someBytes of:(OFXMLMaker *)container;
{
    [self addString:[someBytes base64String] of:container asComment:NO];
}

@end

