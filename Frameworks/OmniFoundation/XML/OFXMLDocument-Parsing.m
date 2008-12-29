// Copyright 2003-2005, 2007, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLDocument-Parsing.h>

#import <libxml/SAX2.h>
#import <libxml/parser.h>
#import <OmniFoundation/CFArray-OFExtensions.h>

#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniFoundation/OFXMLUnparsedElement.h>

RCS_ID("$Id$");


typedef struct _OFMLDocumentParseState {
    xmlParserCtxtPtr ctxt;
    OFXMLDocument  *doc;
    NSMutableArray *whitespaceBehaviorStack;
    BOOL rootElementFinished;
    NSCharacterSet *nonWhitespaceCharacterSet;
    NSError *error;
    NSMutableArray *loadWarnings;
//    NSMutableDictionary *namespaceStringToURL; // cache
    CFMutableDictionaryRef utf8StringToInternedString;

    // Support for unparsed blocks
    off_t unparsedBlockStart; // < 0 if we aren't in an unparsed block.
    unsigned int unparsedBlockElementNesting;
} OFMLDocumentParseState;

static void InternedStringKeyRelease(CFAllocatorRef allocator, const void *value)
{
    free((xmlChar *)value);
}

static Boolean InternedStringKeyEqual(const void *value1, const void *value2)
{
    return strcmp((const char *)value1, (const char *)value2) == 0;
}

static CFHashCode InternedStringKeyHash(const void *value)
{
    const xmlChar *str = (const xmlChar *)value;
    
    // We don't expect to get long strings, so use the whole thing
    CFHashCode hash = 0;
    xmlChar c;
    while ((c = *str)) {
        hash = hash * 257 + c;
        str++;
    }
    
    return hash;
}

static NSString *CreateInternedString(OFMLDocumentParseState *state, const xmlChar *str)
{
    NSString *interned = (NSString *)CFDictionaryGetValue(state->utf8StringToInternedString, str);
    if (interned)
        return [interned retain];
    
    const char *key = strdup((const char *)str); // caller owns the input.
    interned = [[NSString alloc] initWithUTF8String:key]; // the extra ref here is the 'create' returned to the caller
    CFDictionarySetValue(state->utf8StringToInternedString, key, interned); // dictionary retains the intered string for the life of 'state' too.
    
    //NSLog(@"XML: Interned string '%@'", interned);
    
    return interned;
}

#if 0
static NSURL *OFMLDocumentParseStateURLForString(OFMLDocumentParseState *state, NSString *urlString)
{
    NSURL *url = [state->namespaceStringToURL objectForKey:urlString];
    if (!url) {
        url = [[NSURL alloc] initWithString:urlString];
        if (!url) {
            NSLog(@"Invalid namespace URL string '%@' isn't a URL.", urlString);
            url = (id)[[NSNull null] retain]; // cache failure
        }
        [state->namespaceStringToURL setObject:url forKey:urlString];
    }
    
    if (OFISNULL(url))
        return nil;
    return url;
}
#endif

@interface OFXMLDocument (XMLReadingSupport)
- (void)_setEncoding:(CFStringEncoding)encoding;
- (void)_setLoadWarnings:(NSArray *)warnings;
- (void)_setSystemID:(CFURLRef)systemID publicID:(CFStringRef)publicID;
- (void)_elementStarted:(OFXMLElement *)element;
- (BOOL)_elementEnded;
- (void)_addString:(NSString *)str;
#ifdef OMNI_ASSERTIONS_ON
- (unsigned int)_elementStackDepth;
#endif
@end

@implementation OFXMLDocument (XMLReadingSupport)

- (void)_setEncoding:(CFStringEncoding)encoding;
{
    _stringEncoding = encoding;
}

- (void)_setLoadWarnings:(NSArray *)warnings;
{
    [_loadWarnings release];
    _loadWarnings = nil;
    
    if (warnings)
        _loadWarnings = [[NSArray alloc] initWithArray:warnings];
}

- (void)_setSystemID:(CFURLRef)systemID publicID:(CFStringRef)publicID;
{
    // TODO: What happens if we read a fragment: we should default to having a non-nil processing instructions in which case these assertions are invalid
    OBPRECONDITION(!_dtdSystemID);
    OBPRECONDITION(!_dtdPublicID);
    
    if (systemID)
        _dtdSystemID = CFRetain(systemID);
    _dtdPublicID = [(id)publicID copy];
}

- (void)_elementStarted:(OFXMLElement *)element;
{
    if (!_rootElement) {
        _rootElement = [element retain];
        OBASSERT([_elementStack count] == 0);
        [_elementStack addObject: _rootElement];
    } else {
        OBASSERT([_elementStack count] != 0);
        [[_elementStack lastObject] appendChild: element];
        [_elementStack addObject: element];
    }
}

- (BOOL)_elementEnded;
{
    OBPRECONDITION([_elementStack count] != 0);
    
    OFXMLElement *element = [_elementStack lastObject];
    if (_rootElement == element)
        return YES;

    [_elementStack removeLastObject];
    return NO;
}

// If the last child of the top element is a string, replace it with the concatenation of the two strings.
// TODO: Later we should have OFXMLString be an array of strings that is lazily concatenated to avoid slow degenerate cases (and then replace the last string with a OFXMLString with the two elements).  Actually, it might be better to just stick in an NSMutableArray of strings and then clean it up when the element is finished.
- (void)_addString:(NSString *)str;
{
    OFXMLElement *top      = [self topElement];
    NSArray      *children = [top children];
    unsigned int  count    = [children count];
    
    if (count) {
        id lastChild = [children objectAtIndex: count - 1];
        if ([lastChild isKindOfClass: [NSString class]]) {
            NSString *newString = [[NSString alloc] initWithFormat: @"%@%@", lastChild, str];
            [top removeChildAtIndex: count - 1];
            [top appendChild: newString];
            [newString release];
            return;
        }
    }
    
    [top appendChild: str];
}

#ifdef OMNI_ASSERTIONS_ON
- (unsigned int)_elementStackDepth;
{
    return [_elementStack count];
}
#endif

@end

#if 0
static void *createXMLStructure(CFXMLParserRef parser, CFXMLNodeRef nodeDesc, void *_info)
{
    OFMLDocumentParseState *state = _info;
    OFXMLDocument *doc = state->doc;
    
    CFXMLNodeTypeCode  typeCode = CFXMLNodeGetTypeCode(nodeDesc);
    NSString          *str      = (NSString *)CFXMLNodeGetString(nodeDesc);
    const void        *data     = CFXMLNodeGetInfoPtr(nodeDesc);
    
    switch (typeCode) {
//        case kCFXMLNodeTypeDocument: {
//            const CFXMLDocumentInfo *docInfo = data;
//            //NSLog(@"document: sourceURL:%@ encoding:0x%08x", docInfo->sourceURL, docInfo->encoding);
//            [doc _setEncoding: docInfo->encoding];
//            return doc;
//        }
//        case kCFXMLNodeTypeProcessingInstruction: {
//            const CFXMLProcessingInstructionInfo *procInstr = data;
//            NSString *value = (NSString *)procInstr->dataString ? (NSString *)procInstr->dataString : @"";
//            [doc addProcessingInstructionNamed:str value:value];
//            //NSLog(@"proc instr: %@ value=%@", str, value);
//            return nil;  // This has no children
//        }
//        case kCFXMLNodeTypeElement: {
//            const CFXMLElementInfo *elementInfo = data;
//            
//            OBINVARIANT([state->whitespaceBehaviorStack count] == [doc _elementStackDepth] + 1); // always have the default behavior on the stack!
//            
//            // -initWithName:elementInfo: takes the CFXMLParser memory usage issues 
//            OFXMLElement *element;
//            element = [[OFXMLElement alloc] initWithName: str elementInfo: elementInfo];
//            [doc _elementStarted: element];
//            
//            OFXMLWhitespaceBehaviorType oldBehavior = (OFXMLWhitespaceBehaviorType)[state->whitespaceBehaviorStack lastObject];
//            OFXMLWhitespaceBehaviorType newBehavior = [[doc whitespaceBehavior] behaviorForElementName: str];
//            
//            if (newBehavior == OFXMLWhitespaceBehaviorTypeAuto)
//                newBehavior = oldBehavior;
//            
//            [state->whitespaceBehaviorStack addObject:(id)newBehavior];
//            
//            
//            OBINVARIANT([state->whitespaceBehaviorStack count] == [doc _elementStackDepth] + 1); // always have the default behavior on the stack!
//            
//            [element release]; // document will be retaining it for us one way or another
//            return element;
//        }
        case kCFXMLNodeTypeDocumentType: {
            const CFXMLDocumentTypeInfo *docType = data;
            //NSLog(@"dtd: %@ systemID=%@ publicIDs=%@", str, docType->externalID.systemID, docType->externalID.publicID);
            [doc _setRootElementName: str systemID: docType->externalID.systemID publicID: docType->externalID.publicID];
            return nil;  // This has no children that we care about
        }
//        case kCFXMLNodeTypeWhitespace: {
//            OBINVARIANT([state->whitespaceBehaviorStack count] == [doc _elementStackDepth] + 1); // always have the default behavior on the stack!
//            
//            // Only add the whitespace if our current behavior dictates that we do so (and we are actually inside the root element)
//            OFXMLWhitespaceBehaviorType currentBehavior = (OFXMLWhitespaceBehaviorType)[state->whitespaceBehaviorStack lastObject];
//            
//            if (currentBehavior == OFXMLWhitespaceBehaviorTypePreserve) {
//                OFXMLElement *root = [doc rootElement];
//                if (root && !state->rootElementFinished) {
//                    // -appendChild normally just retains the input, but we need to copy it to avoid CFXMLParser stomping on it
//                    // Note that we are not calling -_addString: here since that does string merging but whitespace should (I think) only be reported in cases where we don't want it merged or it can't be merged.  This needs more investigation and test cases, etc.
//                    NSString *copy = [str copy];
//                    [[doc topElement] appendChild: copy];
//                    [copy release];
//                    return nil;
//                }
//            }
//            
//            return nil; // No children
//        }
//        case kCFXMLNodeTypeText:
//        case kCFXMLNodeTypeCDATASection: {
//            // Ignore text outside of the root element
//            OFXMLElement *root = [doc rootElement];
//            if (root && !state->rootElementFinished) {
//                // -_addString: might just retain the input, but we need to copy it to avoid CFXMLParser stomping on it
//                NSString *copy = [str copy];
//                [doc _addString: copy];
//                [copy release];
//            }
//            return nil; // No children
//        }
        case kCFXMLNodeTypeEntityReference: {
            const CFXMLEntityReferenceInfo *entityInfo = data;
            NSString *replacement = nil;
            
            OFXMLElement *root = [doc rootElement];
            
            if (entityInfo->entityType == kCFXMLEntityTypeParsedInternal) {
                // Ignore text outside of the root element
                if (!root || state->rootElementFinished)
                    return nil;
                replacement = [[entityReplacements objectForKey: str] retain];
            } else if (entityInfo->entityType == kCFXMLEntityTypeCharacter) {
                // Ignore text outside of the root element
                if (!root || state->rootElementFinished)
                    return nil;
                
                // We expect something like '#35' or '#xab'.  Maximum Unicode value is 65535 (5 digits decimal) 
                unsigned int characterIndex, length = [str length];
                
                // CFXML should have already caught these, but it is easy to do ourselves, so...
                if (length <= 1 || [str characterAtIndex: 0] != '#') {
                    CFXMLParserAbort(parser, kCFXMLErrorMalformedCharacterReference, (CFStringRef)[NSString stringWithFormat: @"Malformed character reference '%@'", str]);
                    return nil;
                }
                
                UnicodeScalarValue sum = 0;  // this is a full 32-bit Unicode value
                if ([str characterAtIndex: 1] == 'x') {
                    if (length <= 2 || length > 10) { // Max is '#xFFFFFFFF' for 32-bit Unicode characters.
                        CFXMLParserAbort(parser, kCFXMLErrorMalformedCharacterReference, (CFStringRef)[NSString stringWithFormat: @"Malformed character reference '%@'", str]);
                        return nil;
                    }
                    
                    for (characterIndex = 2; characterIndex < length; characterIndex++) {
                        unichar x = [str characterAtIndex: characterIndex];
                        if (x >= '0' && x <= '9')
                            sum = 16*sum + (x - '0');
                        else if (x >= 'a' && x <= 'f')
                            sum = 16*sum + (x - 'a') + 0xa;
                        else if (x >= 'A' && x <= 'F')
                            sum = 16*sum + (x - 'A') + 0xA;
                        else {
                            CFXMLParserAbort(parser, kCFXMLErrorMalformedCharacterReference, (CFStringRef)[NSString stringWithFormat: @"Malformed character reference '%@'", str]);
                            return nil;
                        }
                    }
                } else {
                    if (length > 11) { // Max is '#4294967295' for 32-bit Unicode characters.
                        CFXMLParserAbort(parser, kCFXMLErrorMalformedCharacterReference, (CFStringRef)[NSString stringWithFormat: @"Malformed character reference '%@'", str]);
                        return nil;
                    }
                    for (characterIndex = 1; characterIndex < length; characterIndex++) {
                        unichar x = [str characterAtIndex: characterIndex];
                        if (x >= '0' && x <= '9')
                            sum = 10*sum + (x - '0');
                        else {
                            CFXMLParserAbort(parser, kCFXMLErrorMalformedCharacterReference, (CFStringRef)[NSString stringWithFormat: @"Malformed character reference '%@'", str]);
                            return nil;
                        }
                    }
                }
                
                if (sum <= 65535) {
                    unichar ch = sum;
                    replacement = [[NSString alloc] initWithCharacters: &ch length: 1];
                } else {
                    unichar utf16[2];
                    OFCharacterToSurrogatePair(sum, utf16);
                    if (OFCharacterIsSurrogate(utf16[0]) == OFIsSurrogate_HighSurrogate &&
                        OFCharacterIsSurrogate(utf16[1]) == OFIsSurrogate_LowSurrogate)
                        replacement = [[NSString alloc] initWithCharacters:utf16 length:2];
                    else {
                        CFXMLParserAbort(parser, kCFXMLErrorMalformedCharacterReference, (CFStringRef)[NSString stringWithFormat: @"Malformed character reference '%@'", str]);
                        return nil;
                    }
                }
            } else {
#ifdef DEBUG
                NSLog(@"typeCode:%d entityType=%d string:%@", typeCode, entityInfo->entityType, str);
                OBASSERT(NO); // We should opt out on this on a case by case basis
#endif
            }
            
            [doc _addString: replacement];
            [replacement release];
            return nil; // No children
        }
        case kCFXMLNodeTypeComment:
            // Ignore
            return nil;
        default:
#ifdef DEBUG
            NSLog(@"typeCode:%d nodeDesc:0x%08x string:%@", typeCode, (int)nodeDesc, str);
            OBASSERT(NO); // We should opt out on this on a case by case basis
#endif
            return nil; // Ignore stuff we don't understand
    }
}

static void addChild(CFXMLParserRef parser, void *parent, void *child, void *_info)
{
    // We don't actually use this callback.  We have our own stack stuff.
}

static void endXMLStructure(CFXMLParserRef parser, void *xmlType, void *_info)
{
//    OFMLDocumentParseState *state = _info;
//    OFXMLDocument *doc = state->doc;
//    id value = (id)xmlType;
//    
//    if ([value isKindOfClass: [OFXMLElement class]]) {
//        OBINVARIANT([state->whitespaceBehaviorStack count] == [doc _elementStackDepth] + 1); // always have the default behavior on the stack!
//        state->rootElementFinished = [doc _elementEnded: value];
//        if (!state->rootElementFinished)
//            // Leave the behavior for the root element on the stack to keep our invariant alive
//            [state->whitespaceBehaviorStack removeLastObject];
//        OBINVARIANT([state->whitespaceBehaviorStack count] == [doc _elementStackDepth] + 1); // always have the default behavior on the stack!
//    } else {
//#ifdef DEBUG
//        NSLog(@"%s: xmlType=0x%08x", __FUNCTION__, (int)xmlType);
//        OBASSERT(NO);
//#endif
//    }
}

static CFDataRef resolveExternalEntity(CFXMLParserRef parser, CFXMLExternalID *extID, void *_info)
{
#ifdef DEBUG
    NSLog(@"%s:", __FUNCTION__);
    OBASSERT(NO);
#endif
    return NULL;
}

static Boolean handleError(CFXMLParserRef parser, CFXMLParserStatusCode error, void *_info)
{
#ifdef DEBUG
    NSLog(@"%s:", __FUNCTION__);
#endif
    
    return false; // stops parsing
}
#endif

@implementation OFXMLDocument (Parsing)

#if 0
static void *createXMLStructure(CFXMLParserRef parser, CFXMLNodeRef nodeDesc, void *_info);
static void addChild(CFXMLParserRef parser, void *parent, void *child, void *_info);
static void endXMLStructure(CFXMLParserRef parser, void *xmlType, void *_info);
static CFDataRef resolveExternalEntity(CFXMLParserRef parser, CFXMLExternalID *extID, void *_info);
static Boolean handleError(CFXMLParserRef parser, CFXMLParserStatusCode error, void *_info);
#endif

static void _setDocumentLocatorSAXFunc(void *ctx, xmlSAXLocatorPtr loc)
{
    // Not currently used; lets us look up line numer info, apparently.
}

static void _startDocumentSAXFunc(void *ctx)
{
    // CFXML passes the source URL and encoding here, but we don't have it.
}

// CFXML only has one callback for this; not sure why there are two.
static void _internalSubsetSAXFunc(void *ctx, const xmlChar *name, const xmlChar *ExternalID, const xmlChar *SystemID)
{
    //NSLog(@"_internalSubsetSAXFunc name:'%s' ExternalID:'%s' SystemID:'%s'", name, ExternalID, SystemID);
}

static void _externalSubsetSAXFunc(void *ctx, const xmlChar *name, const xmlChar *ExternalID, const xmlChar *SystemID)
{
    //NSLog(@"_externalSubsetSAXFunc name:'%s' ExternalID:'%s' SystemID:'%s'", name, ExternalID, SystemID);

    OFMLDocumentParseState *state = ctx;
    OFXMLDocument *doc = state->doc;
    
    // We pick up the root element name when it is opened (curently assume that it matches the name in the DOCTYPE).
    
    CFURLRef systemID = NULL;
    if (SystemID) {
        CFStringRef systemIDString = CFStringCreateWithCString(kCFAllocatorDefault, (const char *)SystemID, kCFStringEncodingUTF8);
        systemID = CFURLCreateWithString(kCFAllocatorDefault, systemIDString, NULL);
        CFRelease(systemIDString);
        
        if (!systemID)
            NSLog(@"Unable to create URL from system id '%s'.", SystemID);
    }
    CFStringRef publicID = NULL;
    if (ExternalID)
        publicID = CFStringCreateWithCString(kCFAllocatorDefault, (const char *)ExternalID, kCFStringEncodingUTF8);
        
    [doc _setSystemID:systemID publicID:publicID];
}

static void _startElementNsSAX2Func(void *ctx, const xmlChar *localname, const xmlChar *prefix, const xmlChar *URI, int nb_namespaces, const xmlChar **namespaces, int nb_attributes, int nb_defaulted, const xmlChar **attributes)
{
    OFMLDocumentParseState *state = ctx;
    OFXMLDocument *doc = state->doc;
    
    OBINVARIANT([state->whitespaceBehaviorStack count] == [doc _elementStackDepth] + 1); // always have the default behavior on the stack!
    
    // Unparsed element support
    if (state->unparsedBlockStart >= 0) {
        // Already in an unparsed block.  Increment our counter and bail.
        state->unparsedBlockElementNesting++;
        //fprintf(stderr, " ## start nested unparsed element '%s'; depth now %d\n", localname, state->unparsedBlockElementNesting);
        return;
    }
    
    // This gets called after the input pointer has scanned up to the end of the attributes.  For <foo bar="x" /> the input will be pointing at the '/'.  Find the starting byte of this element by scanning backwards looking for '<'.  Since we get called while inside the element, we don't have to worry about '<' in CDATA blocks.  Not sure if libxml2 handles non-conforming documents with '<' in attributes.
    if ([state->doc shouldLeaveElementAsUnparsedBlock:(const char *)localname]) {
        const xmlChar *p = state->ctxt->input->cur;
        const xmlChar *base = state->ctxt->input->base;
        while (p >= base) {
            if (*p == '<')
                break;
            p--;
        }
        if (*p == '<') {
            state->unparsedBlockStart = p - base;
            state->unparsedBlockElementNesting = 0;
            //fprintf(stderr, "unparsed element '%s' starts at offset %qd\n", localname, state->unparsedBlockStart);
            return;
        }
    }
    
    // Ignoring namespace issues for now.  We'd need to unique the namespace string->URL mapping, prefix mappings (can sub-elements override mappings set up on parents -- I think so) and namespaces on *attributes*.
    NSMutableArray *attributeOrder = nil;
    NSMutableDictionary *attributeKeyToValue = nil;
    
    // Note: the segregation of namespace and attibutes will force us to reorder xmlns attributes to the beginning when round-tripping.
    if (nb_namespaces) {
        if (!attributeOrder)
            attributeOrder = [[NSMutableArray alloc] init];
        if (!attributeKeyToValue)
            attributeKeyToValue = [[NSMutableDictionary alloc] init];
        
        // We don't have real namespace support, so map namespace declarations back to attributes so we at least don't lose them in round-tripping.
        int namespaceIndex;
        for (namespaceIndex = 0; namespaceIndex < nb_namespaces; namespaceIndex++) {
            // Each namespace is given by two elements, a prefix and URI
            
            NSString *prefix;
            if (namespaces[0])
                prefix = CreateInternedString(state, namespaces[0]);
            else
                prefix = nil;
            
            NSString *URIString;
            if (namespaces[1])
                URIString = CreateInternedString(state, namespaces[1]);
            else {
                NSLog(@"Bogus namespace; no URI string");
                continue;
            }
            
            NSString *key;
            if (prefix) {
                key = [[NSString alloc] initWithFormat:@"xmlns:%@", prefix];
                [prefix release];
            } else
                key = @"xmlns";
            
            [attributeOrder addObject:key];
            [attributeKeyToValue setObject:URIString forKey:key];
            [key release];
            [URIString release];
        }
    }
    
    if (nb_attributes) {
        if (!attributeOrder)
            attributeOrder = [[NSMutableArray alloc] init];
        if (!attributeKeyToValue)
            attributeKeyToValue = [[NSMutableDictionary alloc] init];
        
        // Each attribute is given by 5 elements, localname, prefix, URI, value start and value end.
        while (nb_attributes--) {
            // TODO: Intern the values or not?  Don't have a great way to do it with the current setup since we want NULL terminated strings.
            NSString *key = CreateInternedString(state, attributes[0]);
            NSString *value = [[NSString alloc] initWithBytes:attributes[3] length:attributes[4]-attributes[3] encoding:NSUTF8StringEncoding];

            // We specify XML_PARSE_NOENT so entities are already parsed up front.  Clients of the framework should thus always get nice Unicode strings w/o worrying about this muck.
            
            [attributeOrder addObject:key];
            [attributeKeyToValue setObject:value forKey:key];
            
            [value release];
            [key release];
            
            attributes += 5;
        }
    }
    
    NSString *elementName = CreateInternedString(state, localname);
    OFXMLElement *element = [[OFXMLElement alloc] initWithName:elementName attributeOrder:attributeOrder attributes:attributeKeyToValue];
    
    [attributeOrder release];
    [attributeKeyToValue release];
    
    [doc _elementStarted:element];
    
    OFXMLWhitespaceBehaviorType oldBehavior = (OFXMLWhitespaceBehaviorType)[state->whitespaceBehaviorStack lastObject];
    OFXMLWhitespaceBehaviorType newBehavior = [[doc whitespaceBehavior] behaviorForElementName:elementName];
    
    if (newBehavior == OFXMLWhitespaceBehaviorTypeAuto)
        newBehavior = oldBehavior;
    
    [state->whitespaceBehaviorStack addObject:(id)newBehavior];
    
    
    OBINVARIANT([state->whitespaceBehaviorStack count] == [doc _elementStackDepth] + 1); // always have the default behavior on the stack!
    
    [elementName release];
    [element release]; // document will be retaining it for us one way or another
    
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

    OFMLDocumentParseState *state = ctx;
    OFXMLDocument *doc = state->doc;

    // See if we've finished an unparsed block
    if (state->unparsedBlockStart >= 0) {
        if (state->unparsedBlockElementNesting == 0) {
            // This gets called right after the closing '>'.  This is the end of our unparsed block.
            const xmlChar *p = state->ctxt->input->cur;
            const xmlChar *base = state->ctxt->input->base;
            OBASSERT(p > base);
            OBASSERT(p[-1] == '>');
            
            off_t end = p - base;
            //fprintf(stderr, "unparsed element '%s' at %qd extended for %qd\n", localname, state->unparsedBlockStart, end - state->unparsedBlockStart);
            
            NSData *data = [[NSData alloc] initWithBytes:state->ctxt->input->base + state->unparsedBlockStart length:end - state->unparsedBlockStart];
            NSString *name = CreateInternedString(state, localname);
            OFXMLUnparsedElement *element = [[OFXMLUnparsedElement alloc] initWithName:name data:data];
            [data release];
            [name release];
            
            [[doc topElement] appendChild:element];
            [element release];
            
            state->unparsedBlockStart = -1; // end of the unparsed block
            return;
        } else {
            state->unparsedBlockElementNesting--;
            //fprintf(stderr, " ## end nested unparsed element '%s'; depth now %d\n", localname, state->unparsedBlockElementNesting);
            return;
        }
    }
    
    OBINVARIANT([state->whitespaceBehaviorStack count] == [doc _elementStackDepth] + 1); // always have the default behavior on the stack!
    state->rootElementFinished = [doc _elementEnded];
    if (!state->rootElementFinished)
        // Leave the behavior for the root element on the stack to keep our invariant alive
        [state->whitespaceBehaviorStack removeLastObject];
    OBINVARIANT([state->whitespaceBehaviorStack count] == [doc _elementStackDepth] + 1); // always have the default behavior on the stack!
}

static void _charactersSAXFunc(void *ctx, const xmlChar *ch, int len)
{
    OFMLDocumentParseState *state = ctx;
    OFXMLDocument *doc = state->doc;

    // Unparsed element support; if we are in the middle of an unparsed element, ignore characters
    if (state->unparsedBlockStart >= 0)
        return;
    
    NSString *str = [[NSString alloc] initWithBytes:ch length:len encoding:NSUTF8StringEncoding];
    //NSLog(@"characters: '%@'", str);

    if ([str rangeOfCharacterFromSet:state->nonWhitespaceCharacterSet].length == 0) {
        OBINVARIANT([state->whitespaceBehaviorStack count] == [doc _elementStackDepth] + 1); // always have the default behavior on the stack!
        
        // Only add the whitespace if our current behavior dictates that we do so (and we are actually inside the root element)
        OFXMLWhitespaceBehaviorType currentBehavior = (OFXMLWhitespaceBehaviorType)[state->whitespaceBehaviorStack lastObject];
        
        if (currentBehavior == OFXMLWhitespaceBehaviorTypePreserve) {
            OFXMLElement *root = [doc rootElement];
            if (root && !state->rootElementFinished) {
                // Note that we are not calling -_addString: here since that does string merging but whitespace should (I think) only be reported in cases where we don't want it merged or it can't be merged.  This needs more investigation and test cases, etc.
                [[doc topElement] appendChild:str];
            }
        }
    } else {
        // Ignore text outside of the root element
        OFXMLElement *root = [doc rootElement];
        if (root && !state->rootElementFinished) {
            //NSLog(@"_addString:%@", str);
            [doc _addString:str];
        }
    }
    
    [str release];
}

static xmlEntityPtr _getEntitySAXFunc(void *ctx, const xmlChar *name)
{
    //NSLog(@"Looking for entity '%s'", name);
    //OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
    return NULL;
}

static void _endDocumentSAXFunc(void *ctx)
{
}

// Uncalled so far
static xmlParserInputPtr _resolveEntitySAXFunc(void *ctx, const xmlChar *publicId, const xmlChar *systemId)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
    return NULL;
}

static xmlEntityPtr _getParameterEntitySAXFunc(void *ctx, const xmlChar *name)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
    return NULL;
}

static void _entityDeclSAXFunc(void *ctx, const xmlChar *name, int type, const xmlChar *publicId, const xmlChar *systemId, xmlChar *content)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}

static void _notationDeclSAXFunc(void *ctx, const xmlChar *name, const xmlChar *publicId, const xmlChar *systemId)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}

static void _attributeDeclSAXFunc(void *ctx, const xmlChar *elem, const xmlChar *fullname, int type, int def, const xmlChar *defaultValue, xmlEnumerationPtr tree)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}

static void _elementDeclSAXFunc(void *ctx, const xmlChar *name, int type, xmlElementContentPtr content)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}

static void _unparsedEntityDeclSAXFunc(void *ctx, const xmlChar *name, const xmlChar *publicId, const xmlChar *systemId, const xmlChar *notationName)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}

static void _referenceSAXFunc(void *ctx, const xmlChar *name)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}

static void _ignorableWhitespaceSAXFunc(void *ctx, const xmlChar *ch, int len)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}

static void _processingInstructionSAXFunc(void *ctx, const xmlChar *target, const xmlChar *data)
{
    OFMLDocumentParseState *state = ctx;
    OFXMLDocument *doc = state->doc;

    NSString *name = CreateInternedString(state, target);
    NSString *value = data ? CreateInternedString(state, data) : @"";
    
    [doc addProcessingInstructionNamed:name value:value];
    [name release];
    [value release];
}

/*
static void _commentSAXFunc(void *ctx, const xmlChar *value)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}
*/

static void _cdataBlockSAXFunc(void *ctx, const xmlChar *value, int len)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}

static void _warningSAXFunc(void *ctx, const char *msg, ...)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}

static void _errorSAXFunc(void *ctx, const char *msg, ...)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}

static void _fatalErrorSAXFunc(void *ctx, const char *msg, ...)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
}

static int _isStandaloneSAXFunc(void *ctx)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
    return 0;
}

static int _hasInternalSubsetSAXFunc(void *ctx)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
    return 0;
}

static int _hasExternalSubsetSAXFunc(void *ctx)
{
    OBASSERT_NOT_REACHED(__PRETTY_FUNCTION__);
    return 0;
}

static void _xmlStructuredErrorFunc(void *userData, xmlErrorPtr error)
{
    OFMLDocumentParseState *state = userData;

    // When parsing WebDAV results, we get a hojillion complaints that 'DAV:' is not a valid URI.  Nothing we can do about this as that's what Apache sends.  Sorry!
    if (error->domain == XML_FROM_PARSER && error->code == XML_WAR_NS_URI)
        return;
    
    // libxml2 has its own notion of domain/code -- put those in the user info.
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                     [NSNumber numberWithInt:error->domain], @"libxml_domain",
                                     [NSNumber numberWithInt:error->code], @"libxml_code",
                                     [NSString stringWithUTF8String:error->message], NSLocalizedFailureReasonErrorKey,
                                     NSLocalizedStringFromTableInBundle(@"Warning encountered while loading XML.", @"OmniFoundation", OMNI_BUNDLE, @"error description"), NSLocalizedDescriptionKey,
                                     nil];
    
    if (error->file) {
        [userInfo setObject:[NSString stringWithUTF8String:error->file] forKey:@"libxml_file"];
        [userInfo setObject:[NSNumber numberWithInt:error->line] forKey:@"libxml_file_line"];
    }
    if (error->str1)
        [userInfo setObject:[NSString stringWithUTF8String:error->str1] forKey:@"libxml_str1"];
    if (error->str2)
        [userInfo setObject:[NSString stringWithUTF8String:error->str1] forKey:@"libxml_str2"];
    if (error->str3)
        [userInfo setObject:[NSString stringWithUTF8String:error->str1] forKey:@"libxml_str3"];
    if (error->int1)
        [userInfo setObject:[NSNumber numberWithInt:error->int1] forKey:@"libxml_int1"];
    if (error->int2)
        [userInfo setObject:[NSNumber numberWithInt:error->int2] forKey:@"libxml_int2"];

    NSError *errorObject = [[NSError alloc] initWithDomain:OMNI_BUNDLE_IDENTIFIER code:OFXMLDocumentLoadWarning userInfo:userInfo];
    [userInfo release];
    
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


static void _OFMLDocumentParseStateCleanUp(OFMLDocumentParseState *state)
{
    OBPRECONDITION(state->ctxt == NULL); // we don't clean this up
    OBPRECONDITION(state->error == nil); // the caller should have taken ownership and cleaned this up
    
    [state->whitespaceBehaviorStack release];
    [state->nonWhitespaceCharacterSet release];
    [state->loadWarnings release];

    if (state->utf8StringToInternedString)
        CFRelease(state->utf8StringToInternedString);
    
    memset(state, 0, sizeof(*state));
}

- (BOOL)_parseData:(NSData *)xmlData defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior error:(NSError **)outError;
{
    LIBXML_TEST_VERSION

    OFMLDocumentParseState state;
    memset(&state, 0, sizeof(state));
    state.doc = self;
    state.whitespaceBehaviorStack = OFCreateIntegerArray();
    state.rootElementFinished = NO;
    state.nonWhitespaceCharacterSet = [[[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet] copy];
    state.loadWarnings = [[NSMutableArray alloc] init];

    // Map NUL terminated UTF-8 byte strings to NSString instances that wrap them to avoid creating lots of copies of the same string.
    CFDictionaryKeyCallBacks keyCallbacks;
    memset(&keyCallbacks, 0, sizeof(keyCallbacks));
    keyCallbacks.release = InternedStringKeyRelease;
    keyCallbacks.equal = InternedStringKeyEqual;
    keyCallbacks.hash = InternedStringKeyHash;
    state.utf8StringToInternedString = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallbacks, &OFNSObjectDictionaryValueCallbacks);
    
    state.unparsedBlockStart = -1;

    //state.namespaceStringToURL = [[NSMutableDictionary alloc] init];
    
    // Set up default whitespace behavior
    [state.whitespaceBehaviorStack addObject:(id)defaultWhitespaceBehavior];
    
    
    // TODO: Add support for passing along the source URL
    // We want whitespace reported since we may or may not keep it depending on our whitespaceBehavior input.
    
    xmlSAXHandler sax;
    memset(&sax, 0, sizeof(sax));
    
    sax.initialized = XML_SAX2_MAGIC; // Use the SAX2 callbacks
    
    sax.internalSubset = _internalSubsetSAXFunc;
    sax.isStandalone = _isStandaloneSAXFunc;
    sax.hasInternalSubset = _hasInternalSubsetSAXFunc;
    sax.hasExternalSubset = _hasExternalSubsetSAXFunc;
    sax.resolveEntity = _resolveEntitySAXFunc;
    sax.getEntity = _getEntitySAXFunc;
    sax.entityDecl = _entityDeclSAXFunc;
    sax.notationDecl = _notationDeclSAXFunc;
    sax.attributeDecl = _attributeDeclSAXFunc;
    sax.elementDecl = _elementDeclSAXFunc;
    sax.unparsedEntityDecl = _unparsedEntityDeclSAXFunc;
    sax.setDocumentLocator = _setDocumentLocatorSAXFunc;
    sax.startDocument = _startDocumentSAXFunc;
    sax.endDocument = _endDocumentSAXFunc;
    sax.reference = _referenceSAXFunc;
    sax.characters = _charactersSAXFunc;
    sax.ignorableWhitespace = _ignorableWhitespaceSAXFunc;
    sax.processingInstruction = _processingInstructionSAXFunc;
    //sax.comment = _commentSAXFunc;
    sax.warning = _warningSAXFunc;
    sax.error = _errorSAXFunc;
    sax.fatalError = _fatalErrorSAXFunc; /* unused error() get all the errors */
    sax.getParameterEntity = _getParameterEntitySAXFunc;
    sax.cdataBlock = _cdataBlockSAXFunc;
    sax.externalSubset = _externalSubsetSAXFunc;
    sax.startElementNs = _startElementNsSAX2Func;
    sax.endElementNs = _endElementNsSAX2Func;
    sax.serror = _xmlStructuredErrorFunc;
    
    // xmlSAXUserParseMemory hides the xmlParserCtxtPtr.  But, this means we can't get the source encoding, so we use the push approach.
    state.ctxt = xmlCreatePushParserCtxt(&sax, &state/*user data*/, [xmlData bytes], [xmlData length], NULL);

    int options = XML_PARSE_NOENT; // Turn entities into content
    options |= XML_PARSE_NONET; // don't allow network access
    options |= XML_PARSE_NSCLEAN; // remove redundant namespace declarations
    options |= XML_PARSE_NOCDATA; // merge CDATA as text nodes
    options = xmlCtxtUseOptions(state.ctxt, options);
    if (options != 0)
        NSLog(@"unsupported options %d", options);
    
    // Encoding isn't set until after the terminate.
    int rc = xmlParseChunk(state.ctxt, NULL, 0, TRUE/*terminate*/);
    
    OBASSERT((rc == 0) == (state.error == nil));
    
    BOOL result = YES;
    if (rc != 0 || state.error) {
        *outError = [state.error autorelease];
        state.error = nil; // we've dealt with cleaning up the erorr portion of the state
        result = NO;
    } else {
        CFStringEncoding encoding = kCFStringEncodingUTF8;
        if (state.ctxt->encoding) {
            CFStringRef encodingName = CFStringCreateWithCString(kCFAllocatorDefault, (const char *)state.ctxt->encoding, kCFStringEncodingUTF8);
            CFStringEncoding parsedEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName);
            CFRelease(encodingName);
            if (parsedEncoding == kCFStringEncodingInvalidId) {
#ifdef DEBUG
                NSLog(@"No string encoding found for '%s'.", state.ctxt->encoding);
#endif
            } else
                encoding = parsedEncoding;
        }
        [self _setEncoding:encoding];
        [self _setLoadWarnings:state.loadWarnings];
    
        // CFXML reports the <?xml...?> as a PI, but libxml2 doesn't.  It has the information we need in the context structure.  But, if there were other PIs, they'll be first in the list now.  So, we store this information out of the PIs now.
        if (state.ctxt->version && *state.ctxt->version)
            _versionString = CreateInternedString(&state, state.ctxt->version);
        else
            _versionString = @"1.0";
        _standalone = state.ctxt->standalone;

        OBASSERT(_rootElement);
        OBASSERT(state.rootElementFinished);
        OBASSERT([state.whitespaceBehaviorStack count] == 2); // The default and the one for the root element
    }
    
    xmlFreeParserCtxt(state.ctxt);
    state.ctxt = NULL;
    
    _OFMLDocumentParseStateCleanUp(&state);
    
    return result;
}

@end
