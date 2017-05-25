// Copyright 2003-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLDocument.h>

#import <Foundation/Foundation.h>

#import <OmniFoundation/OFXMLParser.h>
#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/OFXMLComment.h>
#import <OmniFoundation/OFXMLBuffer.h>
#import <OmniFoundation/OFXMLUnparsedElement.h>
#import <OmniFoundation/OFXMLQName.h>

#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>
#import <OmniBase/OBUtilities.h>

RCS_ID("$Id$");

#if OB_ARC
#error Do not convert this to ARC w/o re-checking performance. Last time it was tried, it was noticably slower.
#endif

NS_ASSUME_NONNULL_BEGIN

@implementation OFXMLDocument
{
    // For the initial XML PI
    NSString *_versionString;
    BOOL _standalone;

    // Custom PIs
    NSMutableArray *_processingInstructions;

    // Building
    NSMutableArray *_elementStack;

    // Support for callers to squirrel away state and then extract it again.
    NSMutableDictionary *_userObjects;

    // Set while we are parsing, in order to read the root element.
    OFXMLElementParser *_elementParser;
}

+ (Class)elementParserClass;
{
    return [OFXMLElementParser class];
}

- (nullable instancetype)initWithRootElement:(OFXMLElement *)rootElement
                                 dtdSystemID:(nullable CFURLRef)dtdSystemID
                                 dtdPublicID:(nullable NSString *)dtdPublicID
                                    schemaID:(nullable CFURLRef)schemaID
                             schemaNamespace:(nullable NSString *)schemaNamespace
                          whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior
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

    if (schemaID)
        _schemaID = CFRetain(schemaID);
    _schemaNamespace = [schemaNamespace copy];

    _stringEncoding = stringEncoding;
    _rootElement = [rootElement retain];
    _whitespaceBehavior = [whitespaceBehavior retain];

    [_elementStack addObject:_rootElement];

    return [self _commonSetupSuffix:outError];
}

- (nullable instancetype)initWithRootElement:(OFXMLElement *)rootElement
          dtdSystemID:(nullable CFURLRef)dtdSystemID
          dtdPublicID:(nullable NSString *)dtdPublicID
   whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior
       stringEncoding:(CFStringEncoding)stringEncoding
                error:(NSError **)outError;
{
    return [self initWithRootElement:rootElement dtdSystemID:dtdSystemID dtdPublicID:dtdPublicID schemaID:NULL schemaNamespace:nil whitespaceBehavior:whitespaceBehavior stringEncoding:stringEncoding error:outError];
}

- (nullable instancetype)initWithRootElementName:(NSString *)rootElementName
              dtdSystemID:(nullable CFURLRef)dtdSystemID
              dtdPublicID:(nullable NSString *)dtdPublicID
       whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior
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

- (nullable instancetype)initWithRootElementName:(NSString *)rootElementName
                                        schemaID:(nullable CFURLRef)schemaID
                                 schemaNamespace:(nullable NSString *)schemaNamespace
                                    namespaceURL:(nullable NSURL *)rootElementNameSpace
                              whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior
                                  stringEncoding:(CFStringEncoding)stringEncoding
                                           error:(NSError **)outError;
{
    OFXMLElement *element = [[OFXMLElement alloc] initWithName:rootElementName];
    if (rootElementNameSpace)
        [element setAttribute:@"xmlns" string:[rootElementNameSpace absoluteString]];
    self = [self initWithRootElement:element dtdSystemID:NULL dtdPublicID:nil schemaID:schemaID schemaNamespace:schemaNamespace whitespaceBehavior:whitespaceBehavior stringEncoding:stringEncoding error:outError];
    [element release];
    return self;
}

- (nullable instancetype)initWithRootElementName:(NSString *)rootElementName
             namespaceURL:(nullable NSURL *)rootElementNameSpace
       whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior
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

- (nullable instancetype)initWithContentsOfFile:(NSString *)path whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior error:(NSError **)outError;
{
    return [self initWithData:[NSData dataWithContentsOfFile:path] whitespaceBehavior:whitespaceBehavior error:outError];
}

- (nullable instancetype)initWithData:(NSData *)xmlData whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior error:(NSError **)outError;
{
    return [self initWithData:xmlData whitespaceBehavior:whitespaceBehavior prepareParser:nil error:outError];
}

- (nullable instancetype)initWithData:(NSData *)xmlData whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior prepareParser:(nullable NS_NOESCAPE OFXMLDocumentPrepareParser)prepareParser error:(NSError **)outError;
{
    // Preserve whitespace by default
    return [self initWithData:xmlData whitespaceBehavior:whitespaceBehavior defaultWhitespaceBehavior:OFXMLWhitespaceBehaviorTypePreserve prepareParser:prepareParser error:outError];
}


- (nullable instancetype)initWithData:(NSData *)xmlData whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior error:(NSError **)outError;
{
    return [self initWithData:xmlData whitespaceBehavior:whitespaceBehavior defaultWhitespaceBehavior:defaultWhitespaceBehavior prepareParser:nil error:outError];
}

- (nullable instancetype)initWithData:(NSData *)xmlData whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior prepareParser:(nullable NS_NOESCAPE OFXMLDocumentPrepareParser)prepareParser error:(NSError **)outError;
{
    // NSInputStream crashes on 10.12.x with a nil input.
    if (!xmlData) {
        OFError(outError, OFXMLDocumentEmptyInputError, @"Cannot create XML document.", @"Nil data passed to create XML document.");
        [self release];
        return nil;
    }
    
    NSInputStream *inputStream = [[[NSInputStream alloc] initWithData:xmlData] autorelease];
    return [self initWithInputStream:inputStream whitespaceBehavior:whitespaceBehavior defaultWhitespaceBehavior:defaultWhitespaceBehavior prepareParser:prepareParser error:outError];
}


- (nullable instancetype)initWithInputStream:(NSInputStream *)inputStream whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior error:(NSError **)outError;
{
    // Preserve whitespace by default
    return [self initWithInputStream:inputStream whitespaceBehavior:whitespaceBehavior defaultWhitespaceBehavior:OFXMLWhitespaceBehaviorTypePreserve error:outError];
}

- (nullable instancetype)initWithInputStream:(NSInputStream *)inputStream whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior error:(NSError **)outError;
{
    return [self initWithInputStream:inputStream whitespaceBehavior:whitespaceBehavior defaultWhitespaceBehavior:defaultWhitespaceBehavior prepareParser:nil error:outError];
}

- (nullable instancetype)initWithInputStream:(NSInputStream *)inputStream whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior prepareParser:(nullable NS_NOESCAPE OFXMLDocumentPrepareParser)prepareParser error:(NSError **)outError;
{
    if (!(self = [super init]))
        return nil;
    [self _preInit];

    if (!whitespaceBehavior)
        whitespaceBehavior = [OFXMLWhitespaceBehavior autoWhitespaceBehavior];

    _whitespaceBehavior = [whitespaceBehavior retain];

    if (![self _parseInputStream:inputStream defaultWhitespaceBehavior:defaultWhitespaceBehavior prepareParser:prepareParser error:outError]) {
        [self release];
        return nil;
    }

    return [self _commonSetupSuffix:outError];
}

- (void) dealloc;
{
    [_versionString release];
    [_processingInstructions release];
    if (_dtdSystemID)
        CFRelease(_dtdSystemID);
    if (_schemaID) {
        CFRelease(_schemaID);
    }
    [_dtdPublicID release];
    [_rootElement release];
    [_loadWarnings release];
    [_elementStack release];
    [_whitespaceBehavior release];
    [_userObjects release];
    [super dealloc];
}

- (__kindof OFXMLElementParser *)makeElementParser;
{
    return [[[OFXMLElementParser alloc] init] autorelease];
}

- (nullable NSData *)xmlData:(NSError **)outError;
{
    return [self xmlDataForElements:[NSArray arrayWithObjects: _rootElement, nil] asFragment:NO error:outError];
}

- (nullable NSData *)xmlDataWithDefaultWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhiteSpaceBehavior error:(NSError **)outError;
{
    return [self xmlDataForElements:[NSArray arrayWithObjects: _rootElement, nil] asFragment:NO defaultWhiteSpaceBehavior:defaultWhiteSpaceBehavior startingLevel:0 error:outError];
}

- (nullable NSData *)xmlDataAsFragment:(NSError **)outError;
{
    return [self xmlDataForElements:[NSArray arrayWithObjects: _rootElement, nil] asFragment:YES error:outError];
}

- (nullable NSData *)xmlDataForElements:(NSArray *)elements asFragment:(BOOL)asFragment error:(NSError **)outError;
{
    return [self xmlDataForElements:elements asFragment:asFragment defaultWhiteSpaceBehavior:OFXMLWhitespaceBehaviorTypePreserve startingLevel:0 error:outError];
}

- (nullable NSData *)xmlDataForElements:(NSArray *)elements asFragment:(BOOL)asFragment defaultWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhiteSpaceBehavior startingLevel:(unsigned int)level error:(NSError **)outError;
{
    // This is not true if we are on 10.3, and Keynote files don't have a DOCTYPE definition
    //OBPRECONDITION(asFragment || (_dtdSystemID && _dtdPublicID)); // Otherwise CFXMLParser will generate an error on load (which we'll ignore, but still...)
    OBPRECONDITION([_elementStack count] == 1); // should just have the root element -- i.e., all nested push/pops have finished
    
    OFXMLBuffer xml = OFXMLBufferCreate();
    
    @autoreleasepool {
        if (!asFragment) {
            
            // The initial <?xml...?> PI isn't in the _processingInstructions; it's stored as other ivars
            OFXMLBufferAppendUTF8CString(xml, "<?xml version=\"");
            OFXMLBufferAppendString(xml, (__bridge CFStringRef)_versionString);
            OFXMLBufferAppendUTF8CString(xml, "\" encoding=\"");
            
            // XML spec wants uppercase names, but we should match case insensitively.
            CFStringRef encodingName = (CFStringRef)[(NSString *)CFStringConvertEncodingToIANACharSetName(_stringEncoding) uppercaseString];
            if (!encodingName) {
                OBASSERT_NOT_REACHED("No encoding name found");
                encodingName = CFSTR("UTF-8");
            }
            OFXMLBufferAppendString(xml, encodingName);

            OFXMLBufferAppendUTF8CString(xml, "\"");
            // the standalone pseudo-attribute is only really necessary for DTD declarations not schema or relax ng.
            if (_dtdPublicID || _dtdSystemID) {
                OFXMLBufferAppendUTF8CString(xml, " standalone=\"");
                if (_standalone)
                    OFXMLBufferAppendUTF8CString(xml, "yes\"");
                else
                    OFXMLBufferAppendUTF8CString(xml, "no\"");
            }
            OFXMLBufferAppendUTF8CString(xml, "?>\n");

            // Add processing instructions.
            {
                NSCharacterSet *nonWhitespaceCharacterSet = [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet];
                for (NSArray *processingInstruction in _processingInstructions) {
                    NSString *name = [processingInstruction objectAtIndex:0];
                    NSString *value = [processingInstruction objectAtIndex:1];
                    
                    OFXMLBufferAppendUTF8CString(xml, "<?");
                    OFXMLBufferAppendString(xml, (__bridge CFStringRef)name);
                    
                    if ([value rangeOfCharacterFromSet:nonWhitespaceCharacterSet].length > 0) {
                        OFXMLBufferAppendUTF8CString(xml, " ");
                        OFXMLBufferAppendString(xml, (CFStringRef)[processingInstruction objectAtIndex:1]);
                    }
                    OFXMLBufferAppendUTF8CString(xml, "?>\n");
                }
            }
            if (_schemaID && _schemaNamespace) {
                OFXMLBufferAppendUTF8CString(xml, "<?xml-model href=\"");
                OFXMLBufferAppendString(xml, CFURLGetString(_schemaID));
                OFXMLBufferAppendUTF8CString(xml, "\" type=\"application/xml\" schematypens=\"");
                OFXMLBufferAppendString(xml, (__bridge CFStringRef)_schemaNamespace);
                OFXMLBufferAppendUTF8CString(xml, "?>\n");
            }
            if (_dtdPublicID || _dtdSystemID) {
                OFXMLBufferAppendUTF8CString(xml, "<!DOCTYPE ");
                OFXMLBufferAppendString(xml, (CFStringRef)[_rootElement name]);
                if (_dtdPublicID) { // Both required in this case; TODO: Raise if _dtdSystemID isn't set in this case
                    OFXMLBufferAppendUTF8CString(xml, " PUBLIC \"");
                    OFXMLBufferAppendString(xml, (__bridge CFStringRef)_dtdPublicID);
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
    }
    
    // Add elements
    for (id element in elements) {
        // TJW: Should try to unify this with the copy of this logic for children in OFXMLElement

        NSError *strongError = nil; // strong reference outside the pool
        BOOL success;
        @autoreleasepool {
            __autoreleasing NSError *error = nil;
            success = [element appendXML:xml withParentWhiteSpaceBehavior:defaultWhiteSpaceBehavior document:self level:level error:&error];
            if (!success) {
                strongError = [error retain];
            }
        }
        if (!success) {
            if (outError)
                *outError = [strongError autorelease];
            return nil;
        }
    }

    if (!asFragment)
        OFXMLBufferAppendUTF8CString(xml, "\n");

    CFDataRef data = OFXMLBufferCopyData(xml, _stringEncoding);
    OFXMLBufferDestroy(xml);
    
    return CFBridgingRelease(data);
}

- (BOOL)writeToFile:(NSString *)path error:(NSError **)outError;
{
    NSData *data = [self xmlData:outError];
    if (!data)
        return NO;
    
    return [data writeToFile:path options:NSDataWritingAtomic error:outError];
}

- (NSUInteger)processingInstructionCount;
{
    return [_processingInstructions count];
}

- (NSString *)processingInstructionNameAtIndex:(NSUInteger)piIndex;
{
    return [[_processingInstructions objectAtIndex:piIndex] objectAtIndex:0];
}

- (NSString *)processingInstructionValueAtIndex:(NSUInteger)piIndex;
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

#pragma mark - User objects

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

#pragma mark - Writing conveniences

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

- (void) addElement:(NSString *)elementName childBlock:(void (^)(void))block;
{
    [self pushElement:elementName];
    block();
    [self popElement];
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

- (void) appendString: (NSString *) string quotingMask: (unsigned int) quotingMask newlineReplacment: (nullable NSString *) newlineReplacment;
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

- (void) setAttribute: (NSString *) name string: (nullable NSString *) value;
{
    [[self topElement] setAttribute: name string: value];
}

- (void) setAttribute: (NSString *) name value: (nullable id) value;
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

- (void) setAttribute: (NSString *) name double: (double) value;  // "%.15g"
{
    OBASSERT(DBL_DIG == 15);
    [[self topElement] setAttribute: name double: value format: @"%.15g"];
}

- (void) setAttribute: (NSString *) name double: (double) value format: (NSString *) formatString;
{
    [[self topElement] setAttribute: name double: value format: formatString];
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

- (OFXMLElement *)appendElement:(NSString *)elementName containingDouble:(double) contents; // "%.15g"
{
    return [[self topElement] appendElement:elementName containingDouble:contents];
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingDouble:(double) contents format:(NSString *) formatString;
{
    return [[self topElement] appendElement:elementName containingDouble:contents format:formatString];
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

#pragma mark - Partial OFXMLParserTarget

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

- (void)parser:(OFXMLParser *)parser startElementWithQName:(OFXMLQName *)qname multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;
{
    OBPRECONDITION(_elementParser);

    // Delegate parsing for the root element.
    parser.target = _elementParser;
    [_elementParser parser:parser startElementWithQName:qname multipleAttributeGenerator:multipleAttributeGenerator singleAttributeGenerator:singleAttributeGenerator];
}

#pragma mark - OFXMLElementParserDelegate

- (OFXMLParserElementBehavior)elementParser:(OFXMLElementParser *)elementParser behaviorForElementWithQName:(OFXMLQName *)name multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;
{
    // We could maybe call the optional OFXMLParserTarget method on ourselves, but that's a bit odd since if this gets called, we aren't the target. Instead, subclasses can override this required delegate method.
    return OFXMLParserElementBehaviorParse;
}

- (void)elementParser:(OFXMLElementParser *)elementParser parser:(OFXMLParser *)parser parsedElement:(OFXMLElement *)element;
{
    OBPRECONDITION(_rootElement == nil);

    _rootElement = [element retain];

    OBASSERT([_elementStack count] == 0);
    [_elementStack addObject: _rootElement];
}

#pragma mark - Debugging

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
    [debugDictionary setObject: [_elementStack arrayByPerformingSelector:@selector(shortDescription)] forKey: @"_elementStack"];

    [debugDictionary setObject: [_rootElement shortDescription] forKey: @"_rootElement"];

    [debugDictionary setObject: [NSString stringWithFormat: @"0x%08lx", (unsigned long)_stringEncoding] forKey: @"_stringEncoding"];

    if (_whitespaceBehavior)
        [debugDictionary setObject: _whitespaceBehavior forKey: @"_whitespaceBehavior"];

    return debugDictionary;
}

#pragma mark - Private

- (void) _preInit;
{
    OBASSERT_NOT_IMPLEMENTED(self, shouldLeaveElementAsUnparsedBlock:); // Deprecated for -parser:shouldLeaveElementAsUnparsedBlock:
    
    _elementStack = [[NSMutableArray alloc] init];
    _processingInstructions = [[NSMutableArray alloc] init];
}

- (nullable id)_commonSetupSuffix:(NSError **)outError NS_REPLACES_RECEIVER;
{
    if (!_rootElement) {
        OFError(outError, OFXMLDocumentNoRootElementError, NSLocalizedStringFromTableInBundle(@"No root element was found", @"OmniFoundation", OMNI_BUNDLE, @"error reason"), nil);
        [self release];
        return nil;
    }
    
    OBASSERT([_elementStack count] == 1);
    OBASSERT([_elementStack objectAtIndex: 0] == _rootElement);
    return self;
}

- (BOOL)_parseInputStream:(NSInputStream *)inputStream defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior prepareParser:(nullable NS_NOESCAPE OFXMLDocumentPrepareParser)prepareParser error:(NSError **)outError;
{
    OFXMLParser *parser = [[OFXMLParser alloc] initWithWhitespaceBehavior:[self whitespaceBehavior] defaultWhitespaceBehavior:defaultWhitespaceBehavior target:self];

    _elementParser = [[self makeElementParser] retain];
    _elementParser.delegate = self;

    if (prepareParser) {
        prepareParser(self, parser);
    }

    if (![parser parseInputStream:inputStream error:outError]) {
        [parser release];
        return NO;
    }
    
    OBASSERT(_rootElement);
    
    _stringEncoding = parser.encoding;

    [_elementParser release];
    _elementParser = nil;

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

NS_ASSUME_NONNULL_END
