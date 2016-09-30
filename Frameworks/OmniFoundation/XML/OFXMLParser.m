// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLParser.h>
#import <OmniFoundation/OFXMLParser-Internal.h>

#import <libxml/SAX2.h>
#import <libxml/parser.h>
#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFXMLInternedStringTable.h>
#import <OmniFoundation/OFXMLQName.h>
#import <OmniBase/assertions.h>

#import "OFXMLError.h"

RCS_ID("$Id$");

#if OB_ARC
#error Do not convert this to ARC w/o re-checking performance. Last time it was tried, it was noticably slower.
#endif

@interface OFXMLParserState : NSObject <OFXMLParserMultipleAttributeGenerator, OFXMLParserSingleAttributeGenerator>
{
@public
    xmlParserCtxtPtr ctxt;
    OFXMLParser *parser;
    NSObject <OFXMLParserTarget> *target;
    
    struct {
        void (*setSystemID)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, NSURL *systemID, NSString *publicID);
        void (*addProcessingInstruction)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, NSString *piName, NSString *piValue);
        
        OFXMLParserElementBehavior (*behaviorForElementWithQName)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, OFXMLQName *name, id <OFXMLParserMultipleAttributeGenerator> multipleAttributeGenerator, id <OFXMLParserSingleAttributeGenerator> singleAttributeGenerator);

        void (*startElementWithQName)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, OFXMLQName *elementQName, id <OFXMLParserMultipleAttributeGenerator> multipleAttributeGenerator, id <OFXMLParserSingleAttributeGenerator> singleAttributeGenerator);

        void (*endElement)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser);
        void (*endUnparsedElementWithQName)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, OFXMLQName *elementName, NSString *identifier, NSData *contents);
        
        void (*addWhitespace)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, NSString *whitespace);
        void (*addString)(NSObject <OFXMLParserTarget> *target, SEL _cmd, OFXMLParser *parser, NSString *string);
    } targetImp;
    
    NSUInteger elementDepth;
    BOOL rootElementFinished;
    
    NSCharacterSet *nonWhitespaceCharacterSet;
    OFXMLWhitespaceBehavior *whitespaceBehavior;
    NSMutableArray *whitespaceBehaviorStack;
    
    NSError *error;
    NSMutableArray *loadWarnings;
    
    BOOL ownsNameTable;
    OFXMLInternedNameTable nameTable;
    
    // Support for unparsed/skipped blocks
    OFXMLParserElementBehavior unparsedBlockBehavior;
    off_t unparsedBlockStart; // < 0 if we aren't in an unparsed block; absolute value in the byte stream being processed
    unsigned int unparsedBlockElementNesting;
    NSString *unparsedElementID; // The value of the xml:id attribute, if any
    NSMutableData *unparsedElementData;

    // Temporarily stashed pointers passed to _startElementNsSAX2Func
    int nb_namespaces;
    const xmlChar **namespaces;
    int nb_attributes;
    const xmlChar **attributes;
}
@end

@interface OFXMLParser ()
{
@private
    OFXMLParserState *_state; // Only set while parsing.
}

@property (nonatomic, strong) NSProgress *progress;

@end

@implementation OFXMLParserState

#pragma mark - OFXMLParserMultipleAttributeGenerator

- (void)generateAttributesWithQNames:(void (^ NS_NOESCAPE)(NSMutableArray <OFXMLQName *> *qnames, NSMutableArray <NSString *> *values))receiver;
{
    OBPRECONDITION(nb_namespaces + nb_attributes > 1, "Otherwise nil should have been passed for the multiple-attribute generator");

    NSMutableArray <OFXMLQName *> *attributeQNames = [[NSMutableArray alloc] init];
    NSMutableArray <NSString *> *attributeValues = [[NSMutableArray alloc] init];

    // For the plain-name based paths.

    // Note: the segregation of namespace and attibutes will force us to reorder xmlns attributes to the beginning when round-tripping (since we map namespaces to attributes to avoid losing them).
    int namespaceIndex;
    for (namespaceIndex = 0; namespaceIndex < nb_namespaces; namespaceIndex++) {
        // Each namespace is given by two elements, a prefix and URI.
        const char *prefixCString = (const char *)namespaces[2*namespaceIndex + 0];
        const char *uriCString = (const char *)namespaces[2*namespaceIndex + 1];

        OFXMLQName *qname = OFXMLInternedNameTableGetInternedName(nameTable, OFXMLNamespaceXMLNSCString, prefixCString);

        NSString *URIString;
        if (uriCString)
            URIString = [[NSString alloc] initWithUTF8String:uriCString];
        else {
            NSLog(@"Bogus namespace; no URI string");
            continue;
        }

        [attributeQNames addObject:qname];
        [attributeValues addObject:URIString];
        [URIString release];
    }

    // Each attribute is given by 5 elements, localname, prefix, URI, value start and value end.
    int attributeIndex;
    for (attributeIndex = 0; attributeIndex < nb_attributes; attributeIndex++) {
        // Intern the values or not?  Don't have a great way to do it with the current setup since we want NULL terminated strings.  Some attribute values may be the same over and over; maybe we could intern if the length is small enough?
        //
        // Update 8/10/2016
        //
        // Small values already benefit from being tagged pointers.
        // Overall, de-duplicating attribute values doesn't seem like a huge win given the frequency analysis done in the following bug for a representative large, real-world OmniFocus root transaction file.
        // See bug:///132530 (Frameworks-Mac Performance: Measure whether de-duplicating attribute values, unparsed elements, or strings in OFXMLParser is a win)

        const char *attributeLocalname = (const char *)attributes[5*attributeIndex + 0];
        //const char *prefix = (const char *)attributes[5*attributeIndex + 1];
        const char *attributeNsURI = (const char *)attributes[5*attributeIndex + 2];
        const char *valueStart = (const char *)attributes[5*attributeIndex + 3];
        const char *valueEnd = (const char *)attributes[5*attributeIndex + 4];

        OFXMLQName *qname = OFXMLInternedNameTableGetInternedName(nameTable, attributeNsURI, attributeLocalname);
        NSString *value = [[NSString alloc] initWithBytes:valueStart length:valueEnd - valueStart encoding:NSUTF8StringEncoding];

        // We specify XML_PARSE_NOENT so entities are already parsed up front.  Clients of the framework should thus always get nice Unicode strings w/o worrying about this muck.

        [attributeQNames addObject:qname];
        [attributeValues addObject:value];

        [value release];
    }

    receiver(attributeQNames, attributeValues);
    [attributeQNames release];
    [attributeValues release];
}

- (void)generateAttributesWithPlainNames:(void (^ NS_NOESCAPE)(NSMutableArray <NSString *> *names, NSMutableDictionary <NSString *, NSString *> *values))receiver;
{
    OBPRECONDITION(nb_namespaces + nb_attributes > 1, "Otherwise nil should have been passed for the multiple-attribute generator");

    NSMutableArray <NSString *> *attributeNames = [[NSMutableArray alloc] init];
    NSMutableDictionary <NSString *, NSString *> *attributeValues = [[NSMutableDictionary alloc] init];

    // For the plain-name based paths.

    // Note: the segregation of namespace and attibutes will force us to reorder xmlns attributes to the beginning when round-tripping (since we map namespaces to attributes to avoid losing them).
    int namespaceIndex;
    for (namespaceIndex = 0; namespaceIndex < nb_namespaces; namespaceIndex++) {
        // Each namespace is given by two elements, a prefix and URI.
        const char *prefixCString = (const char *)namespaces[2*namespaceIndex + 0];
        const char *uriCString = (const char *)namespaces[2*namespaceIndex + 1];

        NSString *URIString;
        if (uriCString)
            URIString = [[NSString alloc] initWithUTF8String:uriCString];
        else {
            NSLog(@"Bogus namespace; no URI string");
            continue;
        }

        NSString *attributeName;
        if (!prefixCString || *prefixCString == '\0') {
            attributeName = @"xmlns";
        } else {
            // Probably shouldn't assume %s is UTF-8... it may be something else based on the locale environment variables...
            NSString *prefixString = [[NSString alloc] initWithCString:prefixCString encoding:NSUTF8StringEncoding];
            attributeName = [[NSString alloc] initWithFormat:@"xmlns:%@", prefixString];
            [prefixString release];
        }

        [attributeNames addObject:attributeName];
        attributeValues[attributeName] = URIString;

        [attributeName release];
        [URIString release];
    }

    // Each attribute is given by 5 elements, localname, prefix, URI, value start and value end.
    int attributeIndex;
    for (attributeIndex = 0; attributeIndex < nb_attributes; attributeIndex++) {
        // TODO: Intern the values or not?  Don't have a great way to do it with the current setup since we want NULL terminated strings.  Some attribute values may be the same over and over; maybe we could intern if the length is small enough?

        const char *attributeLocalname = (const char *)attributes[5*attributeIndex + 0];
        //const char *prefix = (const char *)attributes[5*attributeIndex + 1];
        //const char *attributeNsURI = (const char *)attributes[5*attributeIndex + 2];
        const char *valueStart = (const char *)attributes[5*attributeIndex + 3];
        const char *valueEnd = (const char *)attributes[5*attributeIndex + 4];

        NSString *name = [[NSString alloc] initWithCString:attributeLocalname encoding:NSUTF8StringEncoding];
        NSString *value = [[NSString alloc] initWithBytes:valueStart length:valueEnd - valueStart encoding:NSUTF8StringEncoding];

        // We specify XML_PARSE_NOENT so entities are already parsed up front.  Clients of the framework should thus always get nice Unicode strings w/o worrying about this muck.

        [attributeNames addObject:name];
        attributeValues[name] = value;

        [name release];
        [value release];
    }

    receiver(attributeNames, attributeValues);
    [attributeNames release];
    [attributeValues release];
}

#pragma mark - OFXMLParserSingleAttributeGenerator

- (void)generateAttributeWithQName:(void (^ NS_NOESCAPE)(OFXMLQName *qnames, NSString *value))receiver;
{
    OBPRECONDITION(nb_namespaces + nb_attributes == 1, "Otherwise nil should have been passed for the single-attribute generator");
    
    OFXMLQName *attributeQName;
    NSString *attributeValue;

    if (nb_namespaces) {
        // Each namespace is given by two elements, a prefix and URI.
        const char *prefixCString = (const char *)namespaces[0];
        const char *uriCString = (const char *)namespaces[1];
        
        attributeQName = OFXMLInternedNameTableGetInternedName(nameTable, OFXMLNamespaceXMLNSCString, prefixCString);
        
        if (uriCString)
            attributeValue = [[NSString alloc] initWithUTF8String:uriCString];
        else {
            NSLog(@"Bogus namespace; no URI string");
            return;
        }
    } else if (nb_attributes) {
        const char *attributeLocalname = (const char *)attributes[0];
        //const char *prefix = (const char *)attributes[1];
        const char *attributeNsURI = (const char *)attributes[2];
        const char *valueStart = (const char *)attributes[3];
        const char *valueEnd = (const char *)attributes[4];
        
        attributeQName = OFXMLInternedNameTableGetInternedName(nameTable, attributeNsURI, attributeLocalname);
        attributeValue = [[NSString alloc] initWithBytes:valueStart length:valueEnd - valueStart encoding:NSUTF8StringEncoding];
    } else {
        OBASSERT_NOT_REACHED("Should have exactly one attribute");
        return;
    }
    
    receiver(attributeQName, attributeValue);
    [attributeValue release];
}

- (void)generateAttributeWithPlainName:(void (^ NS_NOESCAPE)(NSString *name, NSString *value))receiver;
{
    OBPRECONDITION(nb_namespaces + nb_attributes == 1, "Otherwise nil should have been passed for the single-attribute generator");
    
    NSString *attributeName, *attibuteValue;

    if (nb_namespaces) {
        // Each namespace is given by two elements, a prefix and URI.
        const char *prefixCString = (const char *)namespaces[0];
        const char *uriCString = (const char *)namespaces[1];
        
        if (uriCString)
            attibuteValue = [[NSString alloc] initWithUTF8String:uriCString];
        else {
            NSLog(@"Bogus namespace; no URI string");
            return;
        }
        
        if (!prefixCString || *prefixCString == '\0') {
            attributeName = @"xmlns";
        } else {
            // Probably shouldn't assume %s is UTF-8... it may be something else based on the locale environment variables...
            NSString *prefixString = [[NSString alloc] initWithCString:prefixCString encoding:NSUTF8StringEncoding];
            attributeName = [[NSString alloc] initWithFormat:@"xmlns:%@", prefixString];
            [prefixString release];
        }
    } else if (nb_attributes) {
        // Each attribute is given by 5 elements, localname, prefix, URI, value start and value end.
        // TODO: Intern the values or not?  Don't have a great way to do it with the current setup since we want NULL terminated strings.  Some attribute values may be the same over and over; maybe we could intern if the length is small enough?
        
        const char *attributeLocalname = (const char *)attributes[0];
        //const char *prefix = (const char *)attributes[1];
        //const char *attributeNsURI = (const char *)attributes[2];
        const char *valueStart = (const char *)attributes[3];
        const char *valueEnd = (const char *)attributes[4];
        
        attributeName = [[NSString alloc] initWithCString:attributeLocalname encoding:NSUTF8StringEncoding];
        attibuteValue = [[NSString alloc] initWithBytes:valueStart length:valueEnd - valueStart encoding:NSUTF8StringEncoding];
    } else {
        OBASSERT_NOT_REACHED("Should have exactly one attribute");
        return;
    }
    
    receiver(attributeName, attibuteValue);
    [attributeName release];
    [attibuteValue release];
}

@end

// CFXML only has one callback for this; not sure why there are two.
static void _internalSubsetSAXFunc(void *ctx, const xmlChar *name, const xmlChar *ExternalID, const xmlChar *SystemID)
{
    //NSLog(@"_internalSubsetSAXFunc name:'%s' ExternalID:'%s' SystemID:'%s'", name, ExternalID, SystemID);
}

static void _externalSubsetSAXFunc(void *ctx, const xmlChar *name, const xmlChar *ExternalID, const xmlChar *SystemID)
{
    //NSLog(@"_externalSubsetSAXFunc name:'%s' ExternalID:'%s' SystemID:'%s'", name, ExternalID, SystemID);
    
    OFXMLParserState *state = (__bridge OFXMLParserState *)ctx;
    OFXMLParser *parser = state->parser;
    
    // We pick up the root element name when it is opened (curently assume that it matches the name in the DOCTYPE).
    
    if (state->targetImp.setSystemID) {
        NSURL *systemID = NULL;
        if (SystemID) {
            CFStringRef systemIDString = CFStringCreateWithCString(kCFAllocatorDefault, (const char *)SystemID, kCFStringEncodingUTF8);
            systemID = CFBridgingRelease(CFURLCreateWithString(kCFAllocatorDefault, systemIDString, NULL));
            CFRelease(systemIDString);
            
            if (!systemID)
                NSLog(@"Unable to create URL from system id '%s'.", SystemID);
        }
        NSString *publicID = nil;
        if (ExternalID)
            publicID = CFBridgingRelease(CFStringCreateWithCString(kCFAllocatorDefault, (const char *)ExternalID, kCFStringEncodingUTF8));
        
        state->targetImp.setSystemID(state->target, @selector(parser:setSystemID:publicID:), parser, systemID, publicID);
    }
}

// Returns YES if the target wants to treat this element as unparsed.
static BOOL _checkForUnparsedElement(OFXMLParserState *state, OFXMLQName *elementQName)
{
    OFXMLParser *parser = state->parser;

    // This gets called after the input pointer has scanned up to the end of the attributes.  For <foo bar="x" /> the input will be pointing at the '/'.  Find the starting byte of this element by scanning backwards looking for '<'.  Since we get called while inside the element, we don't have to worry about '<' in CDATA blocks.  Not sure if libxml2 handles non-conforming documents with '<' in attributes.
    OFXMLParserElementBehavior behavior = OFXMLParserElementBehaviorParse;
    if (state->targetImp.behaviorForElementWithQName) {
        id <OFXMLParserMultipleAttributeGenerator> multipleGenerator = nil;
        id <OFXMLParserSingleAttributeGenerator> singleGenerator = nil;
        if (state->nb_namespaces + state->nb_attributes > 1) {
            multipleGenerator = state;
        } else if (state->nb_namespaces + state->nb_attributes == 1) {
            singleGenerator = state;
        }
        
        behavior = state->targetImp.behaviorForElementWithQName(state->target, @selector(parser:behaviorForElementWithQName:multipleAttributeGenerator:singleAttributeGenerator:), parser, elementQName, multipleGenerator, singleGenerator);
    }
    if (behavior != OFXMLParserElementBehaviorParse) {
        const xmlChar *p = state->ctxt->input->cur;
        const xmlChar *base = state->ctxt->input->base;

        if (behavior == OFXMLParserElementBehaviorUnparsedReturnContentsOnly) {
            // do not include the element, just the data
            OBASSERT(*p == '/' || *p == '>');
            if (*p == '/')
                p++;
            if (*p == '>')
                p++;
        } else {
            while (p >= base) {
                if (*p == '<')
                    break;
                p--;
            }
        }

        if (*p == '<' || behavior == OFXMLParserElementBehaviorUnparsedReturnContentsOnly) {
            state->unparsedBlockBehavior = behavior;
            state->unparsedBlockStart = p - base + state->ctxt->input->consumed;
            state->unparsedBlockElementNesting = 0;

            OBASSERT(state->unparsedElementData == nil);
            state->unparsedElementData = [[NSMutableData alloc] init];
            //fprintf(stderr, "unparsed element '%s' starts at offset %qd\n", localname, state->unparsedBlockStart);

            // Store the xml:id of the element, if it has one, so we can pass it to the end hook.  We could pass the entire set of attributes, but I only need the id right now.
            OBASSERT(state->unparsedElementID == nil);

            // Avoid loading the full set of attributes -- looking at the internal state we store for our OFXMLAttributeGenerator protocol.

            // Each attribute is given by 5 elements, localname, prefix, URI, value start and value end.
            int attributeIndex;
            for (attributeIndex = 0; attributeIndex < state->nb_attributes; attributeIndex++) {
                const char *attributeLocalname = (const char *)state->attributes[5*attributeIndex + 0];
                //const char *prefix = (const char *)state->attributes[5*attributeIndex + 1];
                const char *attributeNsURI = (const char *)state->attributes[5*attributeIndex + 2];
                const char *valueStart = (const char *)state->attributes[5*attributeIndex + 3];
                const char *valueEnd = (const char *)state->attributes[5*attributeIndex + 4];

                if (attributeLocalname && strcmp(attributeLocalname, "id") == 0 &&
                    (!attributeNsURI || strcmp(attributeNsURI, OFXMLNamespaceXMLCString) == 0)) {
                    state->unparsedElementID = [[NSString alloc] initWithBytes:valueStart length:valueEnd - valueStart encoding:NSUTF8StringEncoding];
                    break;
                }
            }

            return YES;
        } else {
            OBASSERT_NOT_REACHED("Didn't find element open.");
        }
    }

    return NO;
}

static void _startElementNsSAX2Func(void *ctx, const xmlChar *localname, const xmlChar *prefix, const xmlChar *URI, int nb_namespaces, const xmlChar **namespaces, int nb_attributes, int nb_defaulted, const xmlChar **attributes)
{
    OFXMLParserState *state = (__bridge OFXMLParserState *)ctx;

    OBINVARIANT([state->whitespaceBehaviorStack count] == state->elementDepth + 1); // always have the default behavior on the stack!
    
    // Unparsed element support
    if (state->unparsedBlockStart >= 0) {
        // Already in an unparsed block.  Increment our counter and bail.
        state->unparsedBlockElementNesting++;
        //fprintf(stderr, " ## start nested unparsed element '%s'; depth now %d\n", localname, state->unparsedBlockElementNesting);
        return;
    }

    // Depending in the implemented callbacks, we need different sets of state. We stash pointers temporarily and let the target decide what format of attributes it wants (or maybe none at all!)
    state->nb_namespaces = nb_namespaces;
    state->namespaces = namespaces;
    state->nb_attributes = nb_attributes;
    state->attributes = attributes;


    OFXMLQName *elementQName = OFXMLInternedNameTableGetInternedName(state->nameTable, (const char *)URI, (const char *)localname);

    if (_checkForUnparsedElement(state, elementQName)) {
        state->nb_namespaces = 0;
        state->namespaces = NULL;
        state->nb_attributes = 0;
        state->attributes = NULL;
        return;
    }

    // TODO: Maintain our own stack of return values from startElement and pass them to the end call?  Or require all the targets to maintain their own stack if they need it?
    state->elementDepth++;
    
    if (state->targetImp.startElementWithQName) {
        id <OFXMLParserMultipleAttributeGenerator> multipleGenerator = nil;
        id <OFXMLParserSingleAttributeGenerator> singleGenerator = nil;
        if (state->nb_namespaces + state->nb_attributes > 1) {
            multipleGenerator = state;
        } else if (state->nb_namespaces + state->nb_attributes == 1) {
            singleGenerator = state;
        }
        state->targetImp.startElementWithQName(state->target, @selector(parser:startElementWithQName:multipleAttributeGenerator:singleAttributeGenerator:), state->parser, elementQName, multipleGenerator, singleGenerator);
    }
    
    state->nb_namespaces = 0;
    state->namespaces = NULL;
    state->nb_attributes = 0;
    state->attributes = NULL;

    // TODO: Make OFXMLWhitespaceBehaviorType QName aware.
    OFXMLWhitespaceBehaviorType oldBehavior = (OFXMLWhitespaceBehaviorType)[[state->whitespaceBehaviorStack lastObject] unsignedIntegerValue];
    OFXMLWhitespaceBehaviorType newBehavior = [state->whitespaceBehavior behaviorForElementName:elementQName.name];
    
    if (newBehavior == OFXMLWhitespaceBehaviorTypeAuto)
        newBehavior = oldBehavior;
    
    [state->whitespaceBehaviorStack addObject:@(newBehavior)];
    
    
    OBINVARIANT([state->whitespaceBehaviorStack count] == state->elementDepth + 1); // always have the default behavior on the stack!
        
#if 0
    NSLog(@"start element localname:'%s' prefix:'%s' URI:'%s'", localname, prefix, URI);
    
    // Each namespace is given by two elements, a prefix and URI
    while (nb_namespaces--) {
        NSLog(@"  namespace: prefix:'%s' uri:'%s'", namespaces[0], namespaces[1]);
        namespaces += 2;
    }
    
    // Each attribute is given by 5 elements, localname, prefix, URI, value start and value end.
    while (nb_attributes--) {
        NSString *value = [[NSString alloc] initWithBytes:attributes[3] length:attributes[4]-attributes[3] encoding:NSUTF8StringEncoding];
        NSLog(@"  attribute: localname:'%s' prefix:'%s' URI:'%s' value:'%@'", attributes[0], attributes[1], attributes[2], value);
        [value release];
        attributes += 5;
    }
#endif
}

static void _endElementNsSAX2Func(void *ctx, const xmlChar *localname, const xmlChar *prefix, const xmlChar *URI)
{
    //NSLog(@"end element localname:'%s' prefix:'%s' URI:'%s'", localname, prefix, URI);
    
    OFXMLParserState *state = (__bridge OFXMLParserState *)ctx;
    OFXMLParser *parser = state->parser;
    
    // See if we've finished an unparsed block
    if (state->unparsedBlockStart >= 0) {
        if (state->unparsedBlockElementNesting == 0) {
            // Don't call back (or create the contents data) if we just wanted to skip it.
            if ((state->unparsedBlockBehavior == OFXMLParserElementBehaviorUnparsed || state->unparsedBlockBehavior == OFXMLParserElementBehaviorUnparsedReturnContentsOnly) && state->targetImp.endUnparsedElementWithQName) {
                // This gets called right after the closing '>'.  This is the end of our unparsed block.
                const xmlChar *p = state->ctxt->input->cur;
                const xmlChar *base = state->ctxt->input->base;
                
                if (state->unparsedBlockBehavior == OFXMLParserElementBehaviorUnparsedReturnContentsOnly) {
                    // do not include the element in the data passed to -endUnparsedElementWithQName    
                    while (p >= base) {
                        if (*p == '<')
                            break;
                        p--;
                    }
                }
                
                OBASSERT(p > base);
                const xmlChar *bytes = (base + state->unparsedBlockStart - state->ctxt->input->consumed);
                size_t length = (size_t)(p - bytes);

                OBASSERT(state->unparsedElementData != nil);
                [state->unparsedElementData appendBytes:bytes length:length];
                
                // Immediately make a copy of the accumulated unparsed element data.
                // In the case that the target processes this data immediately and discards it, we have one unnecessary temporary copy.
                // In the case that the target holds onto this data, we have zero extra copies and have defended against clients which incorrectly have -retain semantics instead of -copy semantics.
                NSData *unparsedElementData = [state->unparsedElementData copy];
                OFXMLQName *qname = OFXMLInternedNameTableGetInternedName(state->nameTable, (const char *)URI, (const char *)localname);
                
                state->targetImp.endUnparsedElementWithQName(state->target, @selector(parser:endUnparsedElementWithQName:identifier:contents:), parser, qname, state->unparsedElementID, unparsedElementData);
                
                [unparsedElementData release];
                unparsedElementData = nil;

                [state->unparsedElementData release];
                state->unparsedElementData = nil;
                
                [state->unparsedElementID release];
                state->unparsedElementID = nil;
            }
            
            state->unparsedBlockStart = -1; // end of the unparsed block
            return;
        } else {
            state->unparsedBlockElementNesting--;
            //fprintf(stderr, " ## end nested unparsed element '%s'; depth now %d\n", localname, state->unparsedBlockElementNesting);
            return;
        }
    }
    
    OBINVARIANT([state->whitespaceBehaviorStack count] == state->elementDepth + 1); // always have the default behavior on the stack!
    
    OBASSERT(state->elementDepth > 0);
    if (state->elementDepth > 0) {
        state->elementDepth--;
        if (state->elementDepth == 0)
            state->rootElementFinished = YES;
    }
    
    if (state->targetImp.endElement)
        state->targetImp.endElement(state->target, @selector(parserEndElement:), parser);

    [state->whitespaceBehaviorStack removeLastObject];
    
    OBINVARIANT([state->whitespaceBehaviorStack count] == state->elementDepth + 1); // always have the default behavior on the stack!
}

typedef NS_ENUM(NSInteger, OFXMLStringClassification) {
    OFXMLStringClassificationAllWhitespace,
    OFXMLStringClassificationSomeNonWhitespace,
    OFXMLStringClassificationUnknown
};

// The vast majority of the time, we'll get simple ASCII input. The NSString method spends a lot of time doing composed character checking...
static OFXMLStringClassification _classifyString(const xmlChar *ch, int len)
{
    for (int idx = 0; idx < len; idx++) {
        xmlChar c = ch[idx];

        if (isspace(c)) {
            continue;
        }

        if (isgraph(c)) {
            return OFXMLStringClassificationSomeNonWhitespace;
        }

        return OFXMLStringClassificationUnknown;
    }

    return OFXMLStringClassificationAllWhitespace;
}


// Slow path...
static OFXMLStringClassification _classifyNSString(NSString *str, NSCharacterSet *nonWhitespaceCharacterSet)
{
    if ([str rangeOfCharacterFromSet:nonWhitespaceCharacterSet].length == 0) {
        return OFXMLStringClassificationAllWhitespace;
    }
    return OFXMLStringClassificationSomeNonWhitespace;
}


static void _charactersSAXFunc(void *ctx, const xmlChar *ch, int len)
{
    OFXMLParserState *state = (__bridge OFXMLParserState *)ctx;
    OFXMLParser *parser = state->parser;
    
    // Unparsed element support; if we are in the middle of an unparsed element, ignore characters
    if (state->unparsedBlockStart >= 0)
        return;
    
    // Ignore whitespace and text outside the root element.
    if (state->elementDepth == 0)
        return;

    // Do nothing w/o callbacks...
    typeof(state->targetImp.addWhitespace) addWhitespace = state->targetImp.addWhitespace;
    typeof(state->targetImp.addString) addString = state->targetImp.addString;

    if (addWhitespace == NULL && addString == NULL) {
        return;
    }

    OBASSERT(len > 0); // Should we early out or still call -parser:addString: in this case?

    NSString *str = nil;
    OFXMLStringClassification classification = _classifyString(ch, len);

    if (classification == OFXMLStringClassificationUnknown) {
        str = [[NSString alloc] initWithBytes:ch length:len encoding:NSUTF8StringEncoding];
        classification = _classifyNSString(str, state->nonWhitespaceCharacterSet);
    }

    //NSLog(@"characters: '%@'", str);


    switch (classification) {
        case OFXMLStringClassificationAllWhitespace: {
            OBINVARIANT([state->whitespaceBehaviorStack count] == state->elementDepth + 1); // always have the default behavior on the stack!

            // Only add the whitespace if our current behavior dictates that we do so (and we are actually inside the root element)
            OFXMLWhitespaceBehaviorType currentBehavior = (OFXMLWhitespaceBehaviorType)[[state->whitespaceBehaviorStack lastObject] unsignedIntegerValue];

            if (currentBehavior == OFXMLWhitespaceBehaviorTypePreserve) {
                if (addWhitespace) {
                    if (!str) {
                        str = [[NSString alloc] initWithBytes:ch length:len encoding:NSUTF8StringEncoding];
                    }
                    addWhitespace(state->target, @selector(parser:addWhitespace:), parser, str);
                }
            }
            break;
        }

        case OFXMLStringClassificationSomeNonWhitespace:
            //NSLog(@"_addString:%@", str);
            if (addString) {
                if (!str) {
                    str = [[NSString alloc] initWithBytes:ch length:len encoding:NSUTF8StringEncoding];
                }
                addString(state->target, @selector(parser:addString:), parser, str);
            }
            break;

        default:
            OBASSERT_NOT_REACHED("Should resolve to a known state before entering the switch");
    }

    [str release];
}

static void _processingInstructionSAXFunc(void *ctx, const xmlChar *target, const xmlChar *data)
{
    OFXMLParserState *state = (__bridge OFXMLParserState *)ctx;
    OFXMLParser *parser = state->parser;
    
    if (state->targetImp.addProcessingInstruction) {
        NSString *name = [[NSString alloc] initWithUTF8String:(const char *)target];
        NSString *value = data ? [[NSString alloc] initWithUTF8String:(const char *)data] : @"";
    
        state->targetImp.addProcessingInstruction(state->target, @selector(parser:addProcessingInstructionNamed:value:), parser, name, value);
        
        [name release];
        [value release];
    }
}

static void _xmlStructuredErrorFunc(void *userData, xmlErrorPtr error)
{
    OFXMLParserState *state = (__bridge OFXMLParserState *)userData;
    
    NSError *errorObject = OFXMLCreateError(error);
    if (errorObject == nil)
        return; // should be ignored.
    
    if (error->level == XML_ERR_WARNING)
        [state->loadWarnings addObject:errorObject];
    else {
        OBASSERT(error->level == XML_ERR_ERROR || error->level == XML_ERR_FATAL);
        
        // Error or fatal.  We don't ask for recovery, so for now anything that isn't a warning is fatal.
        OBASSERT(state->error == nil);
        state->error = [errorObject retain];
        xmlStopParser(state->ctxt);
    }
    [errorObject release];
}


static void _OFXMLParserStateCleanUp(OFXMLParserState *state)
{
    OBPRECONDITION(state->ctxt == NULL); // we don't clean this up
    OBPRECONDITION(state->error == nil); // the caller should have taken ownership and cleaned this up
    
    [state->whitespaceBehaviorStack release];
    [state->nonWhitespaceCharacterSet release];
    [state->loadWarnings release];
    
    if (state->ownsNameTable && state->nameTable)
        OFXMLInternedNameTableFree(state->nameTable);
}

#pragma mark -

@implementation OFXMLParser

+ (NSUInteger)defaultMaximumParseChunkSize;
{
    return 1024 * 1024 * 4;
}

- (id)initWithData:(NSData *)xmlData whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior target:(NSObject<OFXMLParserTarget> *)target error:(NSError **)outError;
{
    if (!(self = [self initWithWhitespaceBehavior:whitespaceBehavior defaultWhitespaceBehavior:defaultWhitespaceBehavior target:target])) {
        return nil;
    }
    
    if (![self parseData:xmlData error:outError]) {
        return nil;
    }
    
    return self;
}

- (id)initWithWhitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior target:(NSObject <OFXMLParserTarget> *)target;
{
    if (!(self = [super init]))
        return nil;

    OBPRECONDITION(whitespaceBehavior);
    
    _maximumParseChunkSize = [[self class] defaultMaximumParseChunkSize];
    _encoding = kCFStringEncodingInvalidId;
    
    LIBXML_TEST_VERSION
    
    _state = [[OFXMLParserState alloc] init];
    
    _state->parser = self;
    _state->whitespaceBehaviorStack = [[NSMutableArray alloc] init];
    _state->nonWhitespaceCharacterSet = [[[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet] copy];
    _state->loadWarnings = [[NSMutableArray alloc] init];
    _state->whitespaceBehavior = whitespaceBehavior;

    _state->target = target;
    
    // Assert on deprecated target methods.
    OBASSERT_NOT_IMPLEMENTED(target, parser:shouldLeaveElementAsUnparsedBlock:); // Takes a OFXMLQName and attribute names/values now.
    OBASSERT_NOT_IMPLEMENTED(target, parser:startElementNamed:attributeOrder:attributeValues:); // QName aware version now.
    OBASSERT_NOT_IMPLEMENTED(target, parser:endUnparsedElementNamed:contents:); // QName aware version now.
    OBASSERT_NOT_IMPLEMENTED(target, parser:endUnparsedElementWithQName:contents:); // And we pass the xml:id now.
    
    // -methodForSelector returns _objc_msgForward
#define GET_IMP(slot, sel) do { \
    if ([target respondsToSelector:sel]) \
        _state->targetImp.slot = (typeof(_state->targetImp.slot))[target methodForSelector:sel]; \
} while (0)
    GET_IMP(setSystemID, @selector(parser:setSystemID:publicID:));
    GET_IMP(addProcessingInstruction, @selector(parser:addProcessingInstructionNamed:value:));
    GET_IMP(behaviorForElementWithQName, @selector(parser:behaviorForElementWithQName:multipleAttributeGenerator:singleAttributeGenerator:));
    GET_IMP(startElementWithQName, @selector(parser:startElementWithQName:multipleAttributeGenerator:singleAttributeGenerator:));
    GET_IMP(endElement, @selector(parserEndElement:));
    GET_IMP(endUnparsedElementWithQName, @selector(parser:endUnparsedElementWithQName:identifier:contents:));
    GET_IMP(addWhitespace, @selector(parser:addWhitespace:));
    GET_IMP(addString, @selector(parser:addString:));
#undef GET_IMP

    if ([target respondsToSelector:@selector(internedNameTableForParser:)]) {
        _state->nameTable = [target internedNameTableForParser:self];
        _state->ownsNameTable = NO;
    }
    if (!_state->nameTable) {
        _state->nameTable = OFXMLInternedNameTableCreate(NULL);
        _state->ownsNameTable = YES;
    }
    
    _state->unparsedBlockStart = -1;
    
    // Set up default whitespace behavior
    [_state->whitespaceBehaviorStack addObject:@(defaultWhitespaceBehavior)];

    _progress = [[NSProgress alloc] init];
    
    return self;
}

- (void)dealloc;
{
    [_versionString release];
    [_loadWarnings release];
    [_progress release];
    [super dealloc];
}

- (BOOL)parseData:(NSData *)xmlData error:(NSError **)outError;
{
    // This method is annotated nonnull, but let's also generate an error at runtime if necessary.
    if (xmlData == nil || xmlData.length == 0) {
        OFError(outError, OFXMLInvalidateInputError, nil, nil);
        return NO;
    }

    NSInputStream *inputStream = [[NSInputStream alloc] initWithData:xmlData];
    BOOL success = [self parseInputStream:inputStream expectedStreamLength:xmlData.length error:outError];
    [inputStream release];
    return success;
}

- (BOOL)parseInputStream:(NSInputStream *)inputStream error:(NSError **)outError;
{
    return [self parseInputStream:inputStream expectedStreamLength:NSNotFound error:outError];
}

- (BOOL)parseInputStream:(NSInputStream *)inputStream expectedStreamLength:(NSUInteger)expectedStreamLength error:(NSError **)outError;
{
    // TODO: Add support for passing along the source URL
    // We want whitespace reported since we may or may not keep it depending on our whitespaceBehavior input.

    xmlSAXHandler sax;
    memset(&sax, 0, sizeof(sax));
    
    sax.initialized = XML_SAX2_MAGIC; // Use the SAX2 callbacks
    
    sax.internalSubset = _internalSubsetSAXFunc;
    sax.characters = _charactersSAXFunc;
    sax.processingInstruction = _processingInstructionSAXFunc;
    sax.externalSubset = _externalSubsetSAXFunc;
    sax.startElementNs = _startElementNsSAX2Func;
    sax.endElementNs = _endElementNsSAX2Func;
    sax.serror = _xmlStructuredErrorFunc;
    
    // xmlSAXUserParseMemory hides the xmlParserCtxtPtr.  But, this means we can't get the source encoding, so we use the push approach.
    
    _state->ctxt = xmlCreatePushParserCtxt(&sax, (__bridge void *)_state/*user data*/, NULL, 0, NULL);
    
    // Set the options on our XML parser instance.
    // We set XML_PARSE_HUGE to bypass any hardcoded internal parser limits, such as 10000000 byte input length limit.
    //
    // Those limits are enforced by default with the version of libxml2 that ships with iOS 7 and OS X 10.9.
    // rdar://problem/14280255 and rdar://problem/14280241 asks them to reconsider this default configuration because it breaks binary compatibilty for existing libxml2 clients.
    //
    // N.B. Setting XML_PARSE_HUGE is no longer necessary unless we wish to use a chunk size larger than the internal parser limit of 10000000.
    
    int options = 0;
    options |= XML_PARSE_NOENT;     // Turn entities into content
    options |= XML_PARSE_NONET;     // Don't allow network access
    options |= XML_PARSE_NSCLEAN;   // Remove redundant namespace declarations
    options |= XML_PARSE_NOCDATA;   // Merge CDATA as text nodes
    options |= XML_PARSE_HUGE;      // Relax any hardcoded limit from the parser
    
    options = xmlCtxtUseOptions(_state->ctxt, options);
    if (options != 0) {
        NSLog(@"Unsupported xml parser options: 0x%08x", options);
    }
    
    [inputStream open];
    if (inputStream.streamStatus == NSStreamStatusError) {
        OBASSERT(inputStream.streamError != nil);
        if (outError != NULL) {
            *outError = [[inputStream.streamError copy] autorelease];
        }
        return NO;
    }
    
    // Encoding isn't set until after the terminate.

    if (expectedStreamLength != NSNotFound) {
        _progress.totalUnitCount = expectedStreamLength;
    } else {
        _progress.totalUnitCount = -1;
    }

    int rc = 0;
    
    NSUInteger maxChunkSize = self.maximumParseChunkSize;
    OBASSERT(maxChunkSize > 0);
    
    uint8_t *buffer = malloc(maxChunkSize);
    
    do @autoreleasepool {
        NSInteger bytesRead = [inputStream read:buffer maxLength:maxChunkSize];
        if (bytesRead > 0) {
            rc = xmlParseChunk(_state->ctxt, (const char *)buffer, (int)bytesRead, FALSE);
            if (rc != 0 && rc != XML_ERR_USER_STOP) {
                [_progress cancel];
                break;
            }
            
            // If we are in the middle of processing an unparsed element, copy the rest of this chunk into unparsedElementData and advance unparsedBlockStart
            if (_state->unparsedBlockStart >= (off_t)_state->ctxt->input->consumed) {
                OBASSERT(_state->unparsedElementData != nil);
                const xmlChar *unparsedElementPtr = _state->ctxt->input->base + _state->unparsedBlockStart - _state->ctxt->input->consumed;
                NSUInteger length = _state->ctxt->input->end - unparsedElementPtr;
                [_state->unparsedElementData appendBytes:unparsedElementPtr length:length];
                _state->unparsedBlockStart += length;
            }
            
            _progress.completedUnitCount += bytesRead;
        }
    } while (inputStream.streamStatus == NSStreamStatusOpen);
    
    if (rc == 0) {
        xmlParseChunk(_state->ctxt, NULL, 0, TRUE);
    }
    
    free(buffer);
    OBASSERT((rc == 0) == (_state->error == nil));
    
    BOOL result = YES;
    if (inputStream.streamStatus == NSStreamStatusError) {
        OBASSERT(inputStream.streamError != nil);
        if (outError != NULL) {
            *outError = [[inputStream.streamError copy] autorelease];
        }
        [_progress cancel];
        result = NO;
    } else if (rc != 0 || _state->error) {
        if (outError) {
            *outError = [[_state->error retain] autorelease];
        }
        [_state->error release];
        _state->error = nil; // we've dealt with cleaning up the error portion of the state
        [_progress cancel];
        result = NO;
    } else {
        CFStringEncoding encoding = kCFStringEncodingUTF8;
        if (_state->ctxt->encoding) {
            CFStringRef encodingName = CFStringCreateWithCString(kCFAllocatorDefault, (const char *)_state->ctxt->encoding, kCFStringEncodingUTF8);
            CFStringEncoding parsedEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName);
            CFRelease(encodingName);
            if (parsedEncoding == kCFStringEncodingInvalidId) {
#ifdef DEBUG
                NSLog(@"No string encoding found for '%s'.", _state->ctxt->encoding);
#endif
            } else {
                encoding = parsedEncoding;
            }
        }
        _encoding = encoding;
        if (_state->loadWarnings) {
            _loadWarnings = [[NSArray alloc] initWithArray:_state->loadWarnings];
        }
        
        // CFXML reports the <?xml...?> as a PI, but libxml2 doesn't.  It has the information we need in the context structure.  But, if there were other PIs, they'll be first in the list now.  So, we store this information out of the PIs now.
        if (_state->ctxt->version && *_state->ctxt->version) {
            _versionString = [[NSString alloc] initWithUTF8String:(const char *)_state->ctxt->version];
        } else {
            _versionString = @"1.0";
        }
        _standalone = _state->ctxt->standalone? YES : NO;
        
        OBASSERT(_state->elementDepth == 0); // should have finished the root element.
        OBASSERT(_state->rootElementFinished);
        OBASSERT([_state->whitespaceBehaviorStack count] == 1); // The default one should be one the stack.
        OBASSERT(![NSString isEmptyString:_versionString]);
    }
    
    [inputStream close];
    if (inputStream.streamStatus == NSStreamStatusError) {
        NSLog(@"Error closing input stream in %s: %@", __func__, inputStream.streamError);
    }
    
    xmlFreeParserCtxt(_state->ctxt);
    _state->ctxt = NULL;
    
    _OFXMLParserStateCleanUp(_state);
    [_state release];
    _state = nil;
    
    return result;
}

- (NSUInteger)elementDepth;
{
    return _state ? _state->elementDepth : 0;
}

@end
