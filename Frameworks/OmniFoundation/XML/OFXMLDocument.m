// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLDocument.h>

#import <OmniBase/NSError-OBExtensions.h>
#import <OmniFoundation/OFXMLParser.h>
#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/OFXMLBuffer.h>
#import <OmniFoundation/OFXMLUnparsedElement.h>
#import <OmniFoundation/OFXMLQName.h>
#import <OmniFoundation/OFErrors.h>

RCS_ID("$Id$");

@interface OFXMLDocument (/*Private*/)
- (void)_preInit;
- (id)_initCommonSuffix:(NSError **)outError;
- (BOOL)_parseData:(NSData *)xmlData defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior error:(NSError **)outError;
@end

@implementation OFXMLDocument

static NSDictionary *entityReplacements; // amp -> &, etc.

+ (void) initialize;
{
    OBINITIALIZE;

    entityReplacements = [[NSDictionary alloc] initWithObjectsAndKeys:
        @"&", @"amp",
        @"<", @"lt",
        @">", @"gt",
        @"'", @"apos",
        @"\"", @"quot",
        nil];
}

- initWithRootElement:(OFXMLElement *)rootElement
          dtdSystemID:(CFURLRef)dtdSystemID
          dtdPublicID:(NSString *)dtdPublicID
   whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior
       stringEncoding:(CFStringEncoding)stringEncoding
                error:(NSError **)outError;
{
    OBPRECONDITION(rootElement);
    
    if (!(self = [super init]))
        return nil;
    [self _preInit];

    if (!whitespaceBehavior)
        whitespaceBehavior = [OFXMLWhitespaceBehavior autoWhitespaceBehavior];
    
    NSString *encodingName = (NSString *)CFStringConvertEncodingToIANACharSetName(stringEncoding);
    if (!encodingName) {
        OBASSERT_NOT_REACHED("Unable to determine the IANA character set name for the given CFStringEncoding");
        stringEncoding = kCFStringEncodingUTF8;
    }

    _versionString = @"1.0";
    _standalone = NO;

    if (dtdSystemID)
        _dtdSystemID = CFRetain(dtdSystemID);
    _dtdPublicID = [dtdPublicID copy];
    
    _stringEncoding = stringEncoding;
    _rootElement = [rootElement retain];
    _whitespaceBehavior = [whitespaceBehavior retain];
    
    [_elementStack addObject:_rootElement];
    
    return [self _initCommonSuffix:outError];
}

- initWithRootElementName:(NSString *)rootElementName
              dtdSystemID:(CFURLRef)dtdSystemID
              dtdPublicID:(NSString *)dtdPublicID
       whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior
           stringEncoding:(CFStringEncoding)stringEncoding
                    error:(NSError **)outError;
{
    OFXMLElement *element = [[OFXMLElement alloc] initWithName:rootElementName];
    self = [self initWithRootElement:element
                         dtdSystemID:dtdSystemID
                         dtdPublicID:dtdPublicID
                  whitespaceBehavior:whitespaceBehavior
                      stringEncoding:stringEncoding
                               error:outError];
    [element release];
    return self;
}

- initWithRootElementName:(NSString *)rootElementName
             namespaceURL:(NSURL *)rootElementNameSpace
       whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior
           stringEncoding:(CFStringEncoding)stringEncoding
                    error:(NSError **)outError;
{
    OFXMLElement *element = [[OFXMLElement alloc] initWithName:rootElementName];
    if (rootElementNameSpace)
        [element setAttribute:@"xmlns" string:[rootElementNameSpace absoluteString]];
    self = [self initWithRootElement:element dtdSystemID:NULL dtdPublicID:nil whitespaceBehavior:whitespaceBehavior stringEncoding:stringEncoding error:outError];
    [element release];
    return self;
}

- initWithContentsOfFile:(NSString *)path whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior error:(NSError **)outError;
{
    return [self initWithData:[NSData dataWithContentsOfFile:path] whitespaceBehavior:whitespaceBehavior error:outError];
}

- initWithData:(NSData *)xmlData whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior error:(NSError **)outError;
{
    // Preserve whitespace by default
    return [self initWithData:xmlData whitespaceBehavior:whitespaceBehavior defaultWhitespaceBehavior:OFXMLWhitespaceBehaviorTypePreserve error:outError];
}

- initWithData:(NSData *)xmlData whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior error:(NSError **)outError;
{
    if (!(self = [super init]))
        return nil;
    [self _preInit];
    
    if (!whitespaceBehavior)
        whitespaceBehavior = [OFXMLWhitespaceBehavior autoWhitespaceBehavior];

    _whitespaceBehavior = [whitespaceBehavior retain];

    if (![self _parseData:xmlData defaultWhitespaceBehavior:defaultWhitespaceBehavior error:outError]) {
        [self release];
        return nil;
    }
        
    return [self _initCommonSuffix:outError];
}

- (void) dealloc;
{
    [_versionString release];
    [_processingInstructions release];
    if (_dtdSystemID)
        CFRelease(_dtdSystemID);
    [_dtdPublicID release];
    [_rootElement release];
    [_loadWarnings release];
    [_elementStack release];
    [_whitespaceBehavior release];
    [_userObjects release];
    [super dealloc];
}

- (OFXMLWhitespaceBehavior *) whitespaceBehavior;
{
    return _whitespaceBehavior;
}

- (CFURLRef) dtdSystemID;
{
    return _dtdSystemID;
}

- (NSString *) dtdPublicID;
{
    return _dtdPublicID;
}

- (CFStringEncoding) stringEncoding;
{
    return _stringEncoding;
}

- (NSArray *)loadWarnings;
{
    return _loadWarnings;
}

- (NSData *)xmlData:(NSError **)outError;
{
    return [self xmlDataForElements:[NSArray arrayWithObjects: _rootElement, nil] asFragment:NO error:outError];
}

- (NSData *)xmlDataWithDefaultWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhiteSpaceBehavior error:(NSError **)outError;
{
    return [self xmlDataForElements:[NSArray arrayWithObjects: _rootElement, nil] asFragment:NO defaultWhiteSpaceBehavior:defaultWhiteSpaceBehavior startingLevel:0 error:outError];
}

- (NSData *)xmlDataAsFragment:(NSError **)outError;
{
    return [self xmlDataForElements:[NSArray arrayWithObjects: _rootElement, nil] asFragment:YES error:outError];
}

- (NSData *)xmlDataForElements:(NSArray *)elements asFragment:(BOOL)asFragment error:(NSError **)outError;
{
    return [self xmlDataForElements:elements asFragment:asFragment defaultWhiteSpaceBehavior:OFXMLWhitespaceBehaviorTypePreserve startingLevel:0 error:outError];
}

- (NSData *)xmlDataForElements:(NSArray *)elements asFragment:(BOOL)asFragment defaultWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhiteSpaceBehavior startingLevel:(unsigned int)level error:(NSError **)outError;
{
    // This is not true if we are on 10.3, and Keynote files don't have a DOCTYPE definition
    //OBPRECONDITION(asFragment || (_dtdSystemID && _dtdPublicID)); // Otherwise CFXMLParser will generate an error on load (which we'll ignore, but still...)
    OBPRECONDITION([_elementStack count] == 1); // should just have the root element -- i.e., all nested push/pops have finished
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    OFXMLBuffer xml = OFXMLBufferCreate();
    
    if (!asFragment) {
        
        // The initial <?xml...?> PI isn't in the _processingInstructions; it's stored as other ivars
        OFXMLBufferAppendUTF8CString(xml, "<?xml version=\"");
        OFXMLBufferAppendString(xml, (CFStringRef)_versionString);
        OFXMLBufferAppendUTF8CString(xml, "\" encoding=\"");
        
        // Convert the encoding name to lowercase for compatibility with an older version of OFXMLDocument (regression tests...)
        CFStringRef encodingName = (CFStringRef)[(NSString *)CFStringConvertEncodingToIANACharSetName(_stringEncoding) lowercaseString];
        if (!encodingName) {
            OBASSERT_NOT_REACHED("No encoding name found");
            encodingName = CFSTR("utf-8");            
        }
        OFXMLBufferAppendString(xml, encodingName);

        OFXMLBufferAppendUTF8CString(xml, "\" standalone=\"");
        if (_standalone)
            OFXMLBufferAppendUTF8CString(xml, "yes");
        else
            OFXMLBufferAppendUTF8CString(xml, "no");
        OFXMLBufferAppendUTF8CString(xml, "\"?>\n");
        
        // Add processing instructions.
        {
            NSCharacterSet *nonWhitespaceCharacterSet = [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet];
            unsigned int piIndex, piCount = [_processingInstructions count];
            for (piIndex = 0; piIndex < piCount; piIndex++) {
                NSArray *processingInstruction = [_processingInstructions objectAtIndex:piIndex];
                NSString *name = [processingInstruction objectAtIndex:0];
                NSString *value = [processingInstruction objectAtIndex:1];
                
                OFXMLBufferAppendUTF8CString(xml, "<?");
                OFXMLBufferAppendString(xml, (CFStringRef)name);
                
                if ([value rangeOfCharacterFromSet:nonWhitespaceCharacterSet].length > 0) {
                    OFXMLBufferAppendUTF8CString(xml, " ");
                    OFXMLBufferAppendString(xml, (CFStringRef)[processingInstruction objectAtIndex:1]);
                }
                OFXMLBufferAppendUTF8CString(xml, "?>\n");
            }
        }

	if (_dtdPublicID || _dtdSystemID) {
	    OFXMLBufferAppendUTF8CString(xml, "<!DOCTYPE ");
	    OFXMLBufferAppendString(xml, (CFStringRef)[_rootElement name]);
	    if (_dtdPublicID) { // Both required in this case; TODO: Raise if _dtdSystemID isn't set in this case
		OFXMLBufferAppendUTF8CString(xml, " PUBLIC \"");
		OFXMLBufferAppendString(xml, (CFStringRef)_dtdPublicID);
		OFXMLBufferAppendUTF8CString(xml, "\" \"");
		OFXMLBufferAppendString(xml, CFURLGetString(_dtdSystemID));
		OFXMLBufferAppendUTF8CString(xml, "\">\n");
	    } else {
		OFXMLBufferAppendUTF8CString(xml, " SYSTEM \"");
		OFXMLBufferAppendString(xml, CFURLGetString(_dtdSystemID));
		OFXMLBufferAppendUTF8CString(xml, "\">\n");
	    }
	}
    }
    
    // Add elements
    unsigned int elementIndex, elementCount;
    elementCount = [elements count];
    for (elementIndex = 0; elementIndex < elementCount; elementIndex++) {
        // TJW: Should try to unify this with the copy of this logic for children in OFXMLElement
        if (![[elements objectAtIndex: elementIndex] appendXML:xml withParentWhiteSpaceBehavior:defaultWhiteSpaceBehavior document:self level:level error:outError]) {
            if (outError)
                [*outError retain]; // in the pool
            [pool release];
            if (outError)
                [*outError autorelease];
            return nil;
        }
    }

    if (!asFragment)
        OFXMLBufferAppendUTF8CString(xml, "\n");

    NSData *data = (NSData *)OFXMLBufferCopyData(xml, _stringEncoding);
    OFXMLBufferDestroy(xml);
    
    [pool release];
    return [data autorelease];
}

- (BOOL)writeToFile:(NSString *)path error:(NSError **)outError;
{
    NSData *data = [self xmlData:outError];
    if (!data)
        return NO;
    
    return [data writeToFile:path options:NSAtomicWrite error:outError];
}

- (unsigned int)processingInstructionCount;
{
    return [_processingInstructions count];
}

- (NSString *)processingInstructionNameAtIndex:(unsigned int)piIndex;
{
    return [[_processingInstructions objectAtIndex:piIndex] objectAtIndex:0];
}

- (NSString *)processingInstructionValueAtIndex:(unsigned int)piIndex;
{
    return [[_processingInstructions objectAtIndex:piIndex] objectAtIndex:1];
}

- (void)addProcessingInstructionNamed:(NSString *)piName value:(NSString *)piValue;
{
    if (!piName || !piValue)
        // Have to check ourselves since -initWithObjects: would just make a short array otherwise
        [NSException raise:NSInvalidArgumentException format:@"Both the name and value of a processing instruction must be non-nil."];
    
    NSArray *processingInstruction = [[NSArray alloc] initWithObjects:piName, piValue, nil];
    [_processingInstructions addObject:processingInstruction];
    [processingInstruction release];
}

- (OFXMLElement *) rootElement;
{
    return _rootElement;
}

//
// User objects
//
- (id)userObjectForKey:(NSString *)key;
{
    return [_userObjects objectForKey:key];
}

- (void)setUserObject:(id)object forKey:(NSString *)key;
{
    if (!_userObjects && object)
        _userObjects = [[NSMutableDictionary alloc] init];
    if (object)
        [_userObjects setObject:object forKey:key];
    else
        [_userObjects removeObjectForKey:key];
}

//
// Writing conveniences
//
- (OFXMLElement *) pushElement: (NSString *) elementName;
{
    OFXMLElement *child, *top;

    child  = [[OFXMLElement alloc] initWithName: elementName];
    top = [_elementStack lastObject];
    OBASSERT([top isKindOfClass: [OFXMLElement class]]);
    [top appendChild: child];
    [_elementStack addObject: child];
    [child release];

    return child;
}

- (void) popElement;
{
    OBPRECONDITION([_elementStack count] > 1);  // can't pop the root element
    [_elementStack removeLastObject];
}

- (OFXMLElement *) topElement;
{
    return [_elementStack lastObject];
}

- (void) appendString: (NSString *) string;
{
    OFXMLElement *top = [self topElement];
    OBASSERT([top isKindOfClass: [OFXMLElement class]]);
    [top appendChild: string];
}

- (void) appendString: (NSString *) string quotingMask: (unsigned int) quotingMask newlineReplacment: (NSString *) newlineReplacment;
{
    OFXMLElement *top = [self topElement];
    OBASSERT([top isKindOfClass: [OFXMLElement class]]);

    OFXMLString *xmlString = [[OFXMLString alloc] initWithString:string quotingMask:quotingMask newlineReplacment:newlineReplacment];
    [top appendChild: xmlString];
    [xmlString release];
}

- (OFXMLElement *)appendElement:(NSString *)elementName;
{
    OFXMLElement *element = [self pushElement: elementName];
    [self popElement];
    return element;
}

- (void) setAttribute: (NSString *) name string: (NSString *) value;
{
    [[self topElement] setAttribute: name string: value];
}

- (void) setAttribute: (NSString *) name value: (id) value;
{
    [[self topElement] setAttribute: name value: value];
}

- (void) setAttribute: (NSString *) name integer: (int) value;
{
    [[self topElement] setAttribute: name integer: value];
}

- (void) setAttribute: (NSString *) name real: (float) value;  // "%g"
{
    [[self topElement] setAttribute: name real: value format: @"%g"];
}

- (void) setAttribute: (NSString *) name real: (float) value format: (NSString *) formatString;
{
    [[self topElement] setAttribute: name real: value format: formatString];
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingString:(NSString *)contents;
{
    return [[self topElement] appendElement:elementName containingString:contents];
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingInteger:(int)contents;
{
    return [[self topElement] appendElement:elementName containingInteger:contents];
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingReal:(float)contents; // "%g"
{
    return [[self topElement] appendElement:elementName containingReal:contents];
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingReal:(float) contents format:(NSString *) formatString;
{
    return [[self topElement] appendElement:elementName containingReal:contents format:formatString];
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingDate:(NSDate *)date;
{
    return [[self topElement] appendElement:elementName containingDate:date];
}

// Reading conveniences

- (OFXMLCursor *)cursor;
/*.doc. Returns a autoreleased cursor on the receiver.  As with most enumerator classes, it is not valid to access the cursor after having modified the document.  In this case, since the cursor doesn't care about the attributes, you can modify the attributes; just not the element tree. */
{
    return [[[OFXMLCursor alloc] initWithDocument:self] autorelease];
}

#pragma mark Partial OFXMLParserTarget

- (void)parser:(OFXMLParser *)parser setSystemID:(NSURL *)systemID publicID:(NSString *)publicID;
{
    // TODO: What happens if we read a fragment: we should default to having a non-nil processing instructions in which case these assertions are invalid
    OBPRECONDITION(!_dtdSystemID);
    OBPRECONDITION(!_dtdPublicID);
    
    _dtdSystemID = (CFURLRef)[systemID retain];
    _dtdPublicID = [publicID copy];
}

- (void)parser:(OFXMLParser *)parser addProcessingInstructionNamed:(NSString *)piName value:(NSString *)piValue;
{
    [self addProcessingInstructionNamed:piName value:piValue];
}

- (void)parser:(OFXMLParser *)parser startElementWithQName:(OFXMLQName *)qname attributeQNames:(NSMutableArray *)attributeQNames attributeValues:(NSMutableArray *)attributeValues;
{
    OBPRECONDITION(qname);
    OBPRECONDITION([attributeQNames count] == [attributeValues count]);

    // For now, OFXMLDocument and OFXMLElement are oblivious to namespaces.  Until they are, preserve the previous behavior.
    NSMutableArray *attributeOrder = nil;
    NSMutableDictionary *attributeDictionary = nil;
    if (attributeQNames) {
        attributeOrder = [[NSMutableArray alloc] init];
        attributeDictionary = [[NSMutableDictionary alloc] init];
        NSUInteger attributeIndex, attributeCount = [attributeQNames count];
        for (attributeIndex = 0; attributeIndex < attributeCount; attributeIndex++) {
            OFXMLQName *qname = [attributeQNames objectAtIndex:attributeIndex];
            NSString *value = [attributeValues objectAtIndex:attributeIndex];
            
            // Keep the xmlns prefix for namespace attributes so we can avoid losing it on round-trips
            NSString *key = qname.name;
            
            if (OFISEQUAL(qname.namespace, OFXMLNamespaceXMLNS)) {
                NSString *localName = key;
                if ([NSString isEmptyString:localName]) // Default namespace
                    key = @"xmlns";
                else
                    key = [NSString stringWithFormat:@"xmlns:%@", localName];
            }
            
            [attributeOrder addObject:key];
            [attributeDictionary setObject:value forKey:key];
        }
    }
    
    OFXMLElement *element = [[OFXMLElement alloc] initWithName:qname.name attributeOrder:attributeOrder attributes:attributeDictionary];
    [attributeOrder release];
    [attributeDictionary release];
    
    if (!_rootElement) {
        _rootElement = [element retain];
        OBASSERT([_elementStack count] == 0);
        [_elementStack addObject: _rootElement];
    } else {
        OBASSERT([_elementStack count] != 0);
        [[_elementStack lastObject] appendChild: element];
        [_elementStack addObject: element];
    }
    [element release];
    
    OBPOSTCONDITION([_elementStack count] == parser.elementDepth);
}

// Should only be called if the whitespace behavior indicates we wanted it and we are inside the root element.
- (void)parser:(OFXMLParser *)parser addWhitespace:(NSString *)whitespace;
{
    OBPRECONDITION(_rootElement);

    // Note that we are not calling -_addString: here since that does string merging but whitespace should (I think) only be reported in cases where we don't want it merged or it can't be merged.  This needs more investigation and test cases, etc.
    [self.topElement appendChild:whitespace];
}

// If the last child of the top element is a string, replace it with the concatenation of the two strings.
// TODO: Later we should have OFXMLString be an array of strings that is lazily concatenated to avoid slow degenerate cases (and then replace the last string with a OFXMLString with the two elements).  Actually, it might be better to just stick in an NSMutableArray of strings and then clean it up when the element is finished.
- (void)parser:(OFXMLParser *)parser addString:(NSString *)string;
{
    OFXMLElement *top = self.topElement;
    NSArray *children = top.children;
    NSUInteger count = [children count];
    
    if (count) {
        id lastChild = [children lastObject];
        if ([lastChild isKindOfClass:[NSString class]]) {
            NSString *newString = [[NSString alloc] initWithFormat: @"%@%@", lastChild, string];
            [top removeChildAtIndex:count - 1];
            [top appendChild:newString];
            [newString release];
            return;
        }
    }
    
    [top appendChild:string];
}

- (void)parserEndElement:(OFXMLParser *)parser;
{
    OBPRECONDITION([_elementStack count] != 0);
    
    OFXMLElement *element = [_elementStack lastObject];
    if (_rootElement == element)
        return;
    
    [_elementStack removeLastObject];
    
    OBPOSTCONDITION([_elementStack count] == parser.elementDepth);
}

- (void)parser:(OFXMLParser *)parser endUnparsedElementWithQName:(OFXMLQName *)qname contents:(NSData *)contents;
{
    OBPRECONDITION(_rootElement);
    
    OFXMLUnparsedElement *element = [[OFXMLUnparsedElement alloc] initWithName:qname.name data:contents];
    [self.topElement appendChild:element];
    [element release];
    
    OBPOSTCONDITION([_elementStack count] == parser.elementDepth);
}

//
// Debugging
//

- (NSMutableDictionary *) debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (_processingInstructions)
        [debugDictionary setObject: _processingInstructions forKey: @"_processingInstructions"];
    if (_dtdSystemID)
        [debugDictionary setObject: (NSString *)CFURLGetString(_dtdSystemID) forKey: @"_dtdSystemID"];
    if (_dtdPublicID)
        [debugDictionary setObject: _dtdPublicID forKey: @"_dtdPublicID"];


    // Really only want the element addresses to be displayed here.
    [debugDictionary setObject: _elementStack forKey: @"_elementStack"];

    [debugDictionary setObject: _rootElement forKey: @"_rootElement"];

    [debugDictionary setObject: [NSString stringWithFormat: @"0x%08x", _stringEncoding] forKey: @"_stringEncoding"];

    if (_whitespaceBehavior)
        [debugDictionary setObject: _whitespaceBehavior forKey: @"_whitespaceBehavior"];

    return debugDictionary;
}

#pragma mark Private

- (void) _preInit;
{
    OBPRECONDITION(![self respondsToSelector:@selector(shouldLeaveElementAsUnparsedBlock:)]); // Deprecated for -parser:shouldLeaveElementAsUnparsedBlock:
    
    _elementStack = [[NSMutableArray alloc] init];
    _processingInstructions = [[NSMutableArray alloc] init];
}

- (id)_initCommonSuffix:(NSError **)outError;
{
    if (!_rootElement) {
        OBError(outError, OFXMLDocumentNoRootElementError, NSLocalizedStringFromTableInBundle(@"No root element was found", @"OmniFoundation", OMNI_BUNDLE, @"error reason"));
        [self release];
        return nil;
    }
    
    OBASSERT([_elementStack count] == 1);
    OBASSERT([_elementStack objectAtIndex: 0] == _rootElement);
    return self;
}

- (BOOL)_parseData:(NSData *)xmlData defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior error:(NSError **)outError;
{
    OFXMLParser *parser = [[OFXMLParser alloc] initWithData:xmlData whitespaceBehavior:[self whitespaceBehavior] defaultWhitespaceBehavior:defaultWhitespaceBehavior target:self error:outError];
    if (!parser)
        return NO;
    
    OBASSERT(_rootElement);
    
    _stringEncoding = parser.encoding;
    
    [_loadWarnings release];
    _loadWarnings = nil;
    
    NSArray *warnings = parser.loadWarnings;
    if (warnings)
        _loadWarnings = [[NSArray alloc] initWithArray:warnings];
    
    _standalone = parser.standalone;
    _versionString = [parser.versionString copy];
    
    [parser release];
    return YES;    
}

@end
