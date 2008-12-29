// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLDocument.h>

#import <OmniBase/NSError-OBExtensions.h>
#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/OFXMLDocument-Parsing.h>
#import <OmniFoundation/OFXMLBuffer.h>
#import <OmniFoundation/OFErrors.h>

RCS_ID("$Id$");

@interface OFXMLDocument (PrivateAPI)
- (void)_preInit;
- (id)_postInit:(NSError **)outError;
@end

@implementation OFXMLDocument (PrivateAPI)
- (void) _preInit;
{
    _elementStack = [[NSMutableArray alloc] init];
    _processingInstructions = [[NSMutableArray alloc] init];
}

- (id)_postInit:(NSError **)outError;
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
    
    return [self _postInit:outError];
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
    
    _whitespaceBehavior = [whitespaceBehavior retain];

    if (![self _parseData:xmlData defaultWhitespaceBehavior:defaultWhitespaceBehavior error:outError]) {
        [self release];
        return nil;
    }
        
    return [self _postInit:outError];
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
        OFXMLBufferAppendASCIICString(xml, "<?xml version=\"");
        OFXMLBufferAppendString(xml, (CFStringRef)_versionString);
        OFXMLBufferAppendASCIICString(xml, "\" encoding=\"");
        
        // Convert the encoding name to lowercase for compatibility with an older version of OFXMLDocument (regression tests...)
        CFStringRef encodingName = (CFStringRef)[(NSString *)CFStringConvertEncodingToIANACharSetName(_stringEncoding) lowercaseString];
        if (!encodingName) {
            OBASSERT_NOT_REACHED("No encoding name found");
            encodingName = CFSTR("utf-8");            
        }
        OFXMLBufferAppendString(xml, encodingName);

        OFXMLBufferAppendASCIICString(xml, "\" standalone=\"");
        if (_standalone)
            OFXMLBufferAppendASCIICString(xml, "yes");
        else
            OFXMLBufferAppendASCIICString(xml, "no");
        OFXMLBufferAppendASCIICString(xml, "\"?>\n");
        
        // Add processing instructions.
        {
            NSCharacterSet *nonWhitespaceCharacterSet = [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet];
            unsigned int piIndex, piCount = [_processingInstructions count];
            for (piIndex = 0; piIndex < piCount; piIndex++) {
                NSArray *processingInstruction = [_processingInstructions objectAtIndex:piIndex];
                NSString *name = [processingInstruction objectAtIndex:0];
                NSString *value = [processingInstruction objectAtIndex:1];
                
                OFXMLBufferAppendASCIICString(xml, "<?");
                OFXMLBufferAppendString(xml, (CFStringRef)name);
                
                if ([value rangeOfCharacterFromSet:nonWhitespaceCharacterSet].length > 0) {
                    OFXMLBufferAppendASCIICString(xml, " ");
                    OFXMLBufferAppendString(xml, (CFStringRef)[processingInstruction objectAtIndex:1]);
                }
                OFXMLBufferAppendASCIICString(xml, "?>\n");
            }
        }

	if (_dtdPublicID || _dtdSystemID) {
	    OFXMLBufferAppendASCIICString(xml, "<!DOCTYPE ");
	    OFXMLBufferAppendString(xml, (CFStringRef)[_rootElement name]);
	    if (_dtdPublicID) { // Both required in this case; TODO: Raise if _dtdSystemID isn't set in this case
		OFXMLBufferAppendASCIICString(xml, " PUBLIC \"");
		OFXMLBufferAppendString(xml, (CFStringRef)_dtdPublicID);
		OFXMLBufferAppendASCIICString(xml, "\" \"");
		OFXMLBufferAppendString(xml, CFURLGetString(_dtdSystemID));
		OFXMLBufferAppendASCIICString(xml, "\">\n");
	    } else {
		OFXMLBufferAppendASCIICString(xml, " SYSTEM \"");
		OFXMLBufferAppendString(xml, CFURLGetString(_dtdSystemID));
		OFXMLBufferAppendASCIICString(xml, "\">\n");
	    }
	}
    }
    
    // Add elements
    unsigned int elementIndex, elementCount;
    elementCount = [elements count];
    for (elementIndex = 0; elementIndex < elementCount; elementIndex++) {
        // TJW: Should try to unify this with the copy of this logic for children in OFXMLElement
        if (![[elements objectAtIndex: elementIndex] appendXML:xml withParentWhiteSpaceBehavior:defaultWhiteSpaceBehavior document:self level:level error:outError]) {
            [*outError retain]; // in the pool
            [pool release];
            [*outError autorelease];
            return nil;
        }
    }

    if (!asFragment)
        OFXMLBufferAppendASCIICString(xml, "\n");

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

- (OFXMLCursor *) createCursor;
/*.doc. Returns a new retained cursor on the receiver.  As with most enumerator classes, it is not valid to access the cursor after having modified the document.  In this case, since the cursor doesn't care about the attributes, you can modify the attributes; just not the element tree. */
{
    return [[OFXMLCursor alloc] initWithDocument: self];
}

// For subclasses.
- (BOOL)shouldLeaveElementAsUnparsedBlock:(const char *)utf8Name;
{
    return NO;
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

@end
