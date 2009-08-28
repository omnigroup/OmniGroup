// Copyright 2003-2005, 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLReader.h>

RCS_ID("$Id$");

#import <Foundation/NSStream.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFXMLBuffer.h>
#import <OmniFoundation/OFXMLQName.h>
#import <OmniFoundation/OFXMLInternedStringTable.h>
#import <OmniFoundation/NSDate-OFExtensions.h>
#import <libxml/xmlIO.h>
#import <libxml/xmlreader.h>
#import "OFXMLError.h"

@implementation OFXMLReader

static void _addError(OFXMLReader *self, NSError *error)
{
    OBPRECONDITION(error);
    if (error) {
#ifdef DEBUG
        NSLog(@"%@ adding error %@", [self shortDescription], [error toPropertyList]);
#endif
        [self->_errors addObject:error];
    }
}

static NSError *_errorToUse(OFXMLReader *self)
{
    OBPRECONDITION([self->_errors count] > 0);
    if ([self->_errors count] == 0)
        return nil;
    return [[[self->_errors objectAtIndex:0] retain] autorelease];
}
#define _fillUnderlyingError(self, outError) do { \
    if (outError) \
        *outError = _errorToUse(self); \
} while(0)

// Returns the number of bytes read or -1 in case of error
static int _readFromInput(void * context, char * buffer, int len)
{
    OBPRECONDITION(len >= 0);
    
    OFXMLReader *self = context;

    if (len <= 0)
        return 0; // -read:maxLength: takes NSUInteger.
    
    NSInteger bytesRead = [self->_inputStream read:(uint8_t *)buffer maxLength:len];
    if (bytesRead > 0)
        return bytesRead;
    
    if (bytesRead == 0 && [self->_inputStream streamStatus] == NSStreamStatusAtEnd) {
        return 0;
    }
    
    _addError(self, [self->_inputStream streamError]);

    return -1;
}


// Returns 0 or -1 in case of error
static int _closeInput(void * context)
{
    OFXMLReader *self = context;
    
    switch ([self->_inputStream streamStatus]) {
        case NSStreamStatusNotOpen:
        case NSStreamStatusClosed:
            OBASSERT_NOT_REACHED("Shouldn't happen...");
            break;
        default:
            [self->_inputStream close];
            OBASSERT([self->_inputStream streamStatus] == NSStreamStatusClosed);
            break;
    }
    
    return 0;
}

static BOOL _stepReader(OFXMLReader *self, NSError **outError)
{
    OBPRECONDITION(self->_inEmptyElement == NO);  // Nothing to step to while inside an empty element.
    
    xmlTextReaderPtr reader = self->_reader;
    if (xmlTextReaderRead(reader) != 1) {
        // Was there an actual error?  Or just at the end of the document?
        if ([self->_errors count] > 0) {
            _fillUnderlyingError(self, outError);
            return NO;
        } else {
            OBASSERT(xmlTextReaderNodeType(reader) == XML_READER_TYPE_NONE);
        }
    }
    
    self->_currentNodeType = xmlTextReaderNodeType(reader);
    return YES;
}

static BOOL _skipPastEndOfElement(OFXMLReader *self, NSUInteger endTagsLeft, NSError **outError)
{
    xmlTextReaderPtr reader = self->_reader;
    
    while (YES) {
        switch (self->_currentNodeType) {
            case XML_READER_TYPE_ELEMENT:
                // Hit another start; it might also be an implied end if it is empty.
                if (!xmlTextReaderIsEmptyElement(reader))
                    endTagsLeft++;
                break;
            case XML_READER_TYPE_END_ELEMENT:
                OBASSERT(endTagsLeft > 0);
                endTagsLeft--;
                break;
            default:
                // Some random other cruft we don't care about.
                break;
        }
        if (!_stepReader(self, outError))
            return NO;
        
        // This has to be here instead of in the XML_READER_TYPE_END_ELEMENT case so that skipping over an empty element will work.
        if (endTagsLeft == 0) {
            // Now done skipping the element, but we need to skip the end itself.
            return YES;
        }
    }
}

static void _errorHandler(void *userData, xmlErrorPtr error)
{
    OFXMLReader *self = userData;

    NSError *errorObject = OFXMLCreateError(error);
    if (!errorObject)
        return; // should be ignored

    _addError(self, errorObject);
}

- initWithInputStream:(NSInputStream *)inputStream startingInternedNames:(OFXMLInternedNameTable)startingInternedNames error:(NSError **)outError;
{
    if (!(self = [super init]))
        return nil;
    
    LIBXML_TEST_VERSION

    _inputStream = [inputStream retain];
    _errors = [[NSMutableArray alloc] init];
    
    //_inputStream.delegate = self;
    
    // TODO: Check for errors.
    [_inputStream open];
    
    _inputBuffer = xmlParserInputBufferCreateIO(_readFromInput, _closeInput, self, XML_CHAR_ENCODING_NONE/* no encoding detected */);
    if (!_inputBuffer) {
        OBError(outError, OFXMLReaderCannotCreateXMLInputBuffer, @"Unable to create XML input buffer.");
        [self release];
        return nil;
    }
    
    _reader = xmlNewTextReader(_inputBuffer, [[_url absoluteString] UTF8String]);
    if (!_reader) {
        OBError(outError, OFXMLReaderCannotCreateXMLReader, @"Unable to create XML reader.");
        [self release];
        return nil;
    }
    
    xmlTextReaderSetStructuredErrorHandler(_reader, _errorHandler, self);
    
    _nameTable = OFXMLInternedNameTableCreate(startingInternedNames);
    
    // Prime our look ahead.
    if (!_stepReader(self, outError)) {
        [self release];
        return nil;
    }
    _currentNodeType = xmlTextReaderNodeType(_reader);
    
    // Should have found a top-level element.
    // TODO: Test leading whitespace between the XML PI and the top element.
    if (_currentNodeType != XML_READER_TYPE_ELEMENT) {
        if ([_errors count] > 0)
            _fillUnderlyingError(self, outError);
        else {
            OBASSERT_NOT_REACHED("Really should have an error from the stream or libxml2.");
            OBError(outError, OFXMLReaderCannotCreateXMLReader, @"Missing top level element.");
        }
        [self release];
        return nil;
    }
    
#if 0
    NSLog(@"first read");
    NSLog(@"xmlTextReaderConstXmlVersion = %s", xmlTextReaderConstXmlVersion(_reader)); // will return NULL until we hit the first element and the 'xml' PI has been read.
    NSLog(@"xmlTextReaderStandalone = %d", xmlTextReaderStandalone(_reader)); // will return NULL until we hit the first element and the 'xml' PI has been read.
    NSLog(@"xmlTextReaderConstEncoding = %s", xmlTextReaderConstEncoding(_reader));
    
    while (ret == 1) {
        NSLog(@"depth:%d type:%d name:%s empty:%d value:%s",
              xmlTextReaderDepth(_reader),
              xmlTextReaderNodeType(_reader),
              xmlTextReaderConstName(_reader),
              xmlTextReaderIsEmptyElement(_reader),
              xmlTextReaderConstValue(_reader));
        
        ret = xmlTextReaderRead(_reader);
    }
#endif
    
    return self;
}

- initWithData:(NSData *)data startingInternedNames:(OFXMLInternedNameTable)startingInternedNames error:(NSError **)outError;
{
    return [self initWithInputStream:[NSInputStream inputStreamWithData:data] startingInternedNames:startingInternedNames error:outError];
}

- initWithData:(NSData *)data error:(NSError **)outError;
{
    return [self initWithData:data startingInternedNames:NULL error:outError];
}

- initWithURL:(NSURL *)url startingInternedNames:(OFXMLInternedNameTable)startingInternedNames error:(NSError **)outError;
{
    OBPRECONDITION(url);

    _url = [url copy];
    
    NSInputStream *inputStream;
    if ([_url isFileURL]) {
        inputStream = [NSInputStream inputStreamWithFileAtPath:[_url path]];
    } else {
        OBError(outError, OFXMLReaderCannotCreateInputStream, @"Only supporting files right now.");
        [self release];
        return nil;
    }
    return [self initWithInputStream:inputStream startingInternedNames:startingInternedNames error:outError];
}

- initWithURL:(NSURL *)url error:(NSError **)outError;
{
    return [self initWithURL:url startingInternedNames:nil error:outError];
}

- (void)dealloc;
{
    [_url release];
    
    if (_reader) {
        xmlFreeTextReader(_reader);
        _reader = NULL;
    }
    if (_inputBuffer) {
        xmlFreeParserInputBuffer(_inputBuffer);
        _inputBuffer = NULL;
    }
    
    // This will likely get closed by destroying the reader.
    //_inputStream.delegate = nil;
    switch ([_inputStream streamStatus]) {
        case NSStreamStatusNotOpen:
        case NSStreamStatusClosed:
            break;
        default:
            [_inputStream close];
            OBASSERT([self->_inputStream streamStatus] == NSStreamStatusClosed);
            break;
    }
    [_errors release];
    [_inputStream release];
    
    if (_nameTable) {
        OFXMLInternedNameTableFree(_nameTable);
        _nameTable = NULL;
    }
        
    [super dealloc];
}

@synthesize url = _url;

- (OFXMLQName *)elementQName; // If on an elemenet, return it's name.  Otherwise, nil.
{    
    if (_currentNodeType != XML_READER_TYPE_ELEMENT)
        return nil;
    if (_inEmptyElement) {
        // We've "opened" an empty element.  libxml2 reader API doesn't have a separate open/close in this case.
        return nil;
    }
    
    return OFXMLInternedNameTableGetInternedName(_nameTable, (const char *)xmlTextReaderConstNamespaceUri(_reader), (const char *)xmlTextReaderConstLocalName(_reader));
}

- (BOOL)openElement:(NSError **)outError;
{
    if (_currentNodeType != XML_READER_TYPE_ELEMENT) {
        OBASSERT_NOT_REACHED("Write an error or change the API");
        return NO;
    }

    if (_inEmptyElement) {
        OBASSERT_NOT_REACHED("Write an error or change the API");
        return NO; // Already in an empty element; can't open any more.
    }
    
    if (xmlTextReaderIsEmptyElement(_reader)) {
        // The element we are on is empty; there is no further token read for such elements, so we fake up support for opening them.
        _inEmptyElement = YES;
        return YES;
    }

    return _stepReader(self, outError);
}

- (BOOL)closeElement:(NSError **)outError;
{
    if (_inEmptyElement) {
        // We are on the virtual end for an empty element.  Turn off this flag and skip past the start.
        _inEmptyElement = NO;
        return _stepReader(self, outError);
    }
    
    // Look forward until we hit the next unbalanced end (matching the start for the previous call to -openElement:).
    return _skipPastEndOfElement(self, 1/*endTagsLeft*/, outError);
}

// Reads forward until the start of an element is hit.  If the reader is currently on an element, no advance will be done.
- (BOOL)findNextElement:(OFXMLQName **)outElementName error:(NSError **)outError;
{
    // No elements are contained in an empty element.
    if (_inEmptyElement) {
        if (outElementName)
            *outElementName = nil;
        return YES;
    }
    
    while (YES) {
        if (_currentNodeType == XML_READER_TYPE_ELEMENT) {
            if (outElementName)
                *outElementName = OFXMLInternedNameTableGetInternedName(_nameTable, (const char *)xmlTextReaderConstNamespaceUri(_reader), (const char *)xmlTextReaderConstLocalName(_reader));
            return YES;
        }
        if (_currentNodeType == XML_READER_TYPE_END_ELEMENT) {
            // We are at the end of the current element.  No further element will be found.
            if (outElementName)
                *outElementName = nil;
            return YES;
        }
        
        if (!_stepReader(self, outError))
            return NO;
    }
}

- (BOOL)skipCurrentElement:(NSError **)outError;
{
    OBPRECONDITION(_currentNodeType == XML_READER_TYPE_ELEMENT);
    OBPRECONDITION(_inEmptyElement == NO); // If this is YES we are pointing at a virtual 'end' for the empty element.
    
    if (_currentNodeType != XML_READER_TYPE_ELEMENT || _inEmptyElement) {
        return YES;
    }
    
    // We are on a start, so this should get bumped to 1 on the first loop.
    return _skipPastEndOfElement(self, 0/*endTagsLeft*/, outError);
}

- (BOOL)copyStringContentsToEndOfElement:(NSString **)outString error:(NSError **)outError;
{
    OBPRECONDITION(outString);
    OBPRECONDITION(_currentNodeType == XML_READER_TYPE_ELEMENT); // We expect to be at the start of <foo>string</foo>.  The caller shouldn't open the element.  Later we may need to handle strings starting after we've just finished reading something, like <foo><bar>str1</bar>str2</foo>.
    
    if (_inEmptyElement) {
        if (outString)
            *outString = nil; // Unclear whether we should return @"" or nil here.
        return YES;
    }
    
    // We'll add some support for reading not starting at the beginning of an element, but we do assume that if you are at the start of an element, you want the stuff inside that element, and not its following peer strings or strings in following peer elements.
    NSUInteger endTagsLeft = 0;
    if (_currentNodeType == XML_READER_TYPE_ELEMENT) {
        if (xmlTextReaderIsEmptyElement(_reader)) {
            // No text in the empty element, but we want to step past it and consume it (like we would with a non-empty element).
            if (outString)
                *outString = nil;
            return _stepReader(self, outError);
        } else {
            // Not empty; step inside this element and not that we have a end tag expected.
            if (!_stepReader(self, outError))
                return NO;
            endTagsLeft++;
        }
    }
    
    // Now, read to the end of the *current* element. So if we encounter a new starting element, we have to continue past its ending tag.
    NSString *str = nil;
    while (YES) {
        switch (_currentNodeType) {
            case XML_READER_TYPE_ELEMENT:
                // Hit another start; ignore it text-wise, but expect another ending marker, unless this is an empty element.
                if (!xmlTextReaderIsEmptyElement(_reader))
                    endTagsLeft++;
                break;
            case XML_READER_TYPE_END_ELEMENT:
                OBASSERT(endTagsLeft > 0);
                endTagsLeft--;
                if (endTagsLeft == 0) {
                    // Now done reading the string, but we need to skip the end itself.
                    if (outString)
                        *outString = str;
                    else
                        [str release];
                    return _stepReader(self, outError);
                }
                break;
            case XML_READER_TYPE_TEXT:
            case XML_READER_TYPE_CDATA: {
                NSString *text = [[NSString alloc] initWithUTF8String:(const char *)xmlTextReaderConstValue(_reader)];
                if (str) {
                    // Should be rare, but if we get multiple CDATA sections in a row, it could maybe happen.
                    NSString *concat = [[NSString alloc] initWithFormat:@"%@%@", str, text];
                    [str release];
                    [text release];
                    str = concat;
                } else {
                    str = text;
                }
                break;
            }
            default:
                OBError(outError, OFXMLReaderUnexpectedNodeType, ([NSString stringWithFormat:@"Hit node type %d while reading string.", _currentNodeType]));
                OBASSERT_NOT_REACHED("Handle this node type");
                [str release];
                return NO;
        }
        
        // Handled this node; step to the next.
        if (!_stepReader(self, outError)) {
            [str release];
            return NO;
        }
    }
}

- (BOOL)copyValueOfAttribute:(NSString **)outString named:(OFXMLQName *)name error:(NSError **)outError;
{
    OBPRECONDITION(outString);
    OBPRECONDITION(name);
    OBPRECONDITION(_currentNodeType == XML_READER_TYPE_ELEMENT);
    OBPRECONDITION(_inEmptyElement == NO); // If this is YES we are pointing at a virtual 'end' for the empty element.

    if (_currentNodeType != XML_READER_TYPE_ELEMENT || _inEmptyElement) {
        if (outString)
            *outString = nil;
        return YES; // we didn't fill outError, but this is bad usage.
    }

    // We own the return value; inform CFString it should free() it.  Will return NULL on not-found.
    const xmlChar *attributeName = (const xmlChar *)[name.name UTF8String];
    const xmlChar *attributeNamespace = (const xmlChar *)[name.namespace UTF8String];
    
    xmlChar *value = xmlTextReaderGetAttributeNs(_reader, attributeName, attributeNamespace);
    if (!value) {
        // as below, libxml handles attributes w/o a namespace prefix as having no namespace.  So, if the namespace being queried is the element's namespace, look for the NULL version.
        const xmlChar *elementNamespace = xmlTextReaderConstNamespaceUri(_reader);
        if (attributeNamespace && elementNamespace && (xmlStrcmp(attributeNamespace, elementNamespace) == 0))
            value = xmlTextReaderGetAttributeNs(_reader, attributeName, NULL);
    }
    
    if (!value) {
        if ([_errors count] > 0) {
            _fillUnderlyingError(self, outError);
            return NO;
        }
        // Just not found; that's OK.
        if (outString)
            *outString = nil;
        return YES;
    }

    if (outString)
        *outString = (NSString *)CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, (const char *)value, kCFStringEncodingUTF8, kCFAllocatorMalloc);
    else
        free(value); // outString is required, but if they don't supply it, don't leak, at least.
    
    return YES;
}

- (BOOL)copyAttributes:(NSDictionary **)outAttributes error:(NSError **)outError;
{
    OBPRECONDITION(_currentNodeType == XML_READER_TYPE_ELEMENT);
    OBPRECONDITION(_inEmptyElement == NO); // If this is YES we are pointing at a virtual 'end' for the empty element.

    if (_currentNodeType != XML_READER_TYPE_ELEMENT || _inEmptyElement) {
        if (outAttributes)
            *outAttributes = [[NSDictionary alloc] init];
        return YES; // we didn't fill outError, but this is bad usage.
    }
    
    int attributeCount = xmlTextReaderAttributeCount(_reader);
    if (attributeCount == 0) {
        // TODO: shared empty dict.
        if (outAttributes)
            *outAttributes = [[NSDictionary alloc] init];
        return YES;
    }

    // libxml2 returns NULL from xmlTextReaderConstNamespaceUri() for attributes w/o an explicit namespace.  I'd expect them to take on the namespace of the enclosing element, so that's what we'll do for now.
    /*
     From <http://www.w3.org/TR/REC-xml-names/#scoping-defaulting>:
     
     "Default namespace declarations do not apply directly to attribute names; the interpretation of unprefixed attributes is determined by the element on which they appear."
     
     and also:
     
     "The namespace name for an unprefixed attribute name always has no value."
     
     So... it seems reasonable for libxml2 to return NULL, but it also seems reasonable for us (or them) to use the namespace of the containing element.  Really it seems unclear to me which is right.
     */
    
    OFXMLQName *elementName = [self elementQName];
    OBASSERT(elementName);
    const char *elementNamespace = [elementName.namespace UTF8String];
    
    // Not preserving order of attributes and whether they are duplicated.  Hopefully never significant and we won't need to care.
    NSMutableDictionary *attributes = [[NSMutableDictionary alloc] init];
    for (int attributeIndex = 0; attributeIndex < attributeCount; attributeIndex++) {
        // 1 on success, 0 on not found, -1 on error.  We checked the count so should really only get 1, but check anyway...
        if (xmlTextReaderMoveToAttributeNo(_reader, attributeIndex) != 1) {
            _fillUnderlyingError(self, outError);
            [attributes release];
            xmlTextReaderMoveToElement(_reader); // Move back to the element; ignore errors here.
            return NO;
        }
        
        // See above; libxml2 returns NULL for the namespace of unqualified attributes instead of the namespace of the containing element.
        const char *attributeNamespace = (const char *)xmlTextReaderConstNamespaceUri(_reader);
        if (!attributeNamespace)
            attributeNamespace = elementNamespace;

        OFXMLQName *attributeName = OFXMLInternedNameTableGetInternedName(_nameTable, attributeNamespace, (const char *)xmlTextReaderConstLocalName(_reader));
        NSString *value = [[NSString alloc] initWithUTF8String:(const char *)xmlTextReaderConstValue(_reader)];
        if (!value) {
            OBASSERT_NOT_REACHED("Attribute with no value?"); // Assuming this will never happen since we are enumerating the attributes.
            value = @"";
        }
        [attributes setObject:value forKey:attributeName];
        [value release];
    }
    
    if (xmlTextReaderMoveToElement(_reader) != 1) {
        // Move back to the element now that we are done with all the attributes.
        _fillUnderlyingError(self, outError);
        [attributes release];
        return NO;
    }
    
    if (outAttributes)
        *outAttributes = attributes;
    else
        [attributes release];
    
    return YES;
}

// For the current element, return a dictionary of all the namespace mappings defined on this element (has nothing to do with all the namespace mappings in effect from enclosing elements).
- (BOOL)copyNamespaceDeclarations:(NSDictionary **)outPrefixToNamespaceURLString error:(NSError **)outError;
{
    OBPRECONDITION(_currentNodeType == XML_READER_TYPE_ELEMENT);
    OBPRECONDITION(_inEmptyElement == NO); // If this is YES we are pointing at a virtual 'end' for the empty element.
    
    if (_currentNodeType != XML_READER_TYPE_ELEMENT || _inEmptyElement) {
        *outPrefixToNamespaceURLString = [[NSDictionary alloc] init];
        return YES; // we didn't fill outError, but this is bad usage.
    }
    
    int attributeCount = xmlTextReaderAttributeCount(_reader);
    if (attributeCount == 0) {
        // TODO: shared empty dict.
        *outPrefixToNamespaceURLString = [[NSDictionary alloc] init];
        return YES;
    }

    NSMutableDictionary *prefixToNamespaceURLString = [[NSMutableDictionary alloc] init];
    for (int attributeIndex = 0; attributeIndex < attributeCount; attributeIndex++) {
        // 1 on success, 0 on not found, -1 on error.  We checked the count so should really only get 1, but check anyway...
        if (xmlTextReaderMoveToAttributeNo(_reader, attributeIndex) != 1) {
            _fillUnderlyingError(self, outError);
            [prefixToNamespaceURLString release];
            xmlTextReaderMoveToElement(_reader); // Move back to the element; ignore errors here.
            return NO;
        }
        
        int rc = xmlTextReaderIsNamespaceDecl(_reader);
        if (rc < 0) {
            _fillUnderlyingError(self, outError);
            [prefixToNamespaceURLString release];
            xmlTextReaderMoveToElement(_reader); // Move back to the element; ignore errors here.
            return NO;
        }
        if (rc == 0) {
            // Not a namespace declaration
            continue;
        }
        
        // TODO: The default namespace will be like xmlns="url", so the key in the dictionary will just be "xmlns".  Not sure if we should do that or use "" to better indicate no prefix.
        NSString *prefix = [[NSString alloc] initWithUTF8String:(const char *)xmlTextReaderConstLocalName(_reader)];
        NSString *value = [[NSString alloc] initWithUTF8String:(const char *)xmlTextReaderConstValue(_reader)];
        
        [prefixToNamespaceURLString setObject:value forKey:prefix];
        [prefix release];
        [value release];
    }
    
    if (xmlTextReaderMoveToElement(_reader) != 1) {
        // Move back to the element now that we are done with all the attributes.
        _fillUnderlyingError(self, outError);
        [prefixToNamespaceURLString release];
        return NO;
    }
    
    *outPrefixToNamespaceURLString = prefixToNamespaceURLString;
    return YES;
}

// Expects to be called with the reader pointing at an element. Reads the entire element into a new data and returns it, or returns and empty data if not pointing an an element.
- (NSData *)copyUTF8ElementData:(NSError **)outError;
{
    if (_currentNodeType != XML_READER_TYPE_ELEMENT || _inEmptyElement) {
        OBASSERT_NOT_REACHED("Caller probably didn't mean for this to happen.");
        return [[NSData alloc] init];
    }

    // With our SAX interface in OFXMLParser, we can grab the buffer directly.  The reader interface in libxml2 has functions for reading the inner/outer XML, but they just log a 'not implemented' message when called in the version that ships with 10.5.  Looking at the latest libxml2 sources, they are implemented, but they just expand the tree node at the currenct parse position and then reserialize it. Both of these make me think stabby thoughts.
    
    // TODO: Allow the caller to specify that we should copy the in-effect namespace declarations to the root of the copied XML.  Maybe also have a flag for whether to copy as a full XML document or a fragment.  This currently drops all prefixes, rendering any xmlns attributes meaningless or wrong.
    
    OFXMLBuffer buffer = OFXMLBufferCreate();
    NSData *result = nil;
    @try {
        NSUInteger endTagsLeft = 0;
        
        while (YES) {
            switch (_currentNodeType) {
                case XML_READER_TYPE_ELEMENT: {
                    OFXMLBufferAppendUTF8CString(buffer, "<");
                    OFXMLBufferAppendUTF8CString(buffer, (const char *)xmlTextReaderConstLocalName(_reader));

                    int attributeIndex, attributeCount = xmlTextReaderAttributeCount(_reader);
                    if (attributeCount > 0) {
                        for (attributeIndex = 0; attributeIndex < attributeCount; attributeIndex++) {
                            
                            if (xmlTextReaderMoveToAttributeNo(_reader, attributeIndex) != 1) {
                                _fillUnderlyingError(self, outError);
                                xmlTextReaderMoveToElement(_reader); // Move back to the element; ignore errors here.
                                return nil;
                            }
                            
                            OFXMLBufferAppendUTF8CString(buffer, " ");
                            OFXMLBufferAppendUTF8CString(buffer, (const char *)xmlTextReaderConstLocalName(_reader));
                            OFXMLBufferAppendUTF8CString(buffer, "=\"");
                            
                            const char *value = (const char *)xmlTextReaderConstValue(_reader);
                            if (value)
                                // We have de-quoted the string when reading; need to requote.
                                OFXMLBufferAppendQuotedUTF8CString(buffer, value);
                            OFXMLBufferAppendUTF8CString(buffer, "\"");
                        }
                        
                        // Move back to the element after handling the attributes
                        if (xmlTextReaderMoveToElement(_reader) != 1) {
                            // Move back to the element now that we are done with all the attributes.
                            _fillUnderlyingError(self, outError);
                            return nil;
                        }
                    }
                        
                    // Hit another start; it might also be an implied end if it is empty.
                    if (!xmlTextReaderIsEmptyElement(_reader)) {
                        OFXMLBufferAppendUTF8CString(buffer, ">");
                        endTagsLeft++;
                    } else {
                        OFXMLBufferAppendUTF8CString(buffer, "/>");
                    }
                    break;
                }
                case XML_READER_TYPE_TEXT:
                case XML_READER_TYPE_SIGNIFICANT_WHITESPACE:
                    // We have de-quoted the string when reading; need to requote.
                    OFXMLBufferAppendQuotedUTF8CString(buffer, (const char *)xmlTextReaderConstValue(_reader));
                    break;
                case XML_READER_TYPE_END_ELEMENT:
                    OFXMLBufferAppendUTF8CString(buffer, "</");
                    OFXMLBufferAppendUTF8CString(buffer, (const char *)xmlTextReaderConstLocalName(_reader));
                    OFXMLBufferAppendUTF8CString(buffer, ">");
                    endTagsLeft--;
                    break;
                case XML_READER_TYPE_CDATA: // Wrap in a CDATA block?
                default:
                    OBASSERT_NOT_REACHED("Unhandled node type");
                    return nil;
            }

            if (!_stepReader(self, outError))
                return nil;

            // All the way past the top level element?
            // This has to be here instead of in the XML_READER_TYPE_END_ELEMENT case so that skipping over an empty element will work.
            if (endTagsLeft == 0)
                break;
        }

        result = (NSData *)OFXMLBufferCopyData(buffer, kCFStringEncodingUTF8);
        OBASSERT(result);

#if 0 && defined(DEBUG)
        NSString *xmlString = [(id)CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)result, kCFStringEncodingUTF8) autorelease];
        NSLog(@"copied xml node data: %@ %@", result, xmlString);
        OBASSERT(xmlString);
#endif
    } @finally {
        OFXMLBufferDestroy(buffer);
    }
    return result;
}

#pragma mark -
#pragma mark Simple value readers

/*
 These all expect to be called with the reader on an element that contains a single string within it, though they should correctly step past one single element if they get something like <foo>a<bar/>b</foo>, they may return undefined results.  These avoid the expense of copying out the string contents, only to interpret and immediately deallocating it.
 */

// Declare the simpleString local and make sure we are somewhere that we can get a string.
#define SIMPLE_READ_PREFIX \
const char *simpleString = NULL; \
do { \
    if (_currentNodeType != XML_READER_TYPE_ELEMENT || _inEmptyElement) { \
        OBASSERT_NOT_REACHED("should only be called on an element"); \
        if (outValue) \
            *outValue = defaultValue; \
        return YES; \
    } \
    if (xmlTextReaderIsEmptyElement(_reader)) { \
        if (!_stepReader(self, outError)) \
            return NO; \
        if (outValue) \
            *outValue = defaultValue; \
        return YES; \
    } \
    if (!_prepareSimpleValueReader(self, &simpleString, outError)) { \
        OBASSERT(!outError || *outError); \
        return NO; \
    } \
} while (0)

// Skip past the end of the element we entered in _prepareSimpleValueReader.
#define SIMPLE_READ_SUFFIX return _skipPastEndOfElement(self, 1, outError)

static BOOL _prepareSimpleValueReader(OFXMLReader *self, const char **outString, NSError **outError)
{
    OBPRECONDITION(self->_currentNodeType == XML_READER_TYPE_ELEMENT);
    OBPRECONDITION(self->_inEmptyElement == NO);
    
    if (!_stepReader(self, outError))
        return NO;

    switch (self->_currentNodeType) {
        case XML_READER_TYPE_TEXT:
        case XML_READER_TYPE_CDATA:
            *outString = (const char *)xmlTextReaderConstValue(self->_reader);
            return YES;
        case XML_READER_TYPE_END_ELEMENT:
            *outString = NULL;
            return YES;
        case XML_READER_TYPE_WHITESPACE:
        case XML_READER_TYPE_SIGNIFICANT_WHITESPACE:
            *outString = NULL; // <foo> </foo>
            return YES;
        default:
            OBASSERT_NOT_REACHED("Unexpected node type.");
            *outString = NULL;
            return YES;
    }
}

// XMLSchema for boolean allows 'true', 'false', '1', or '0'.  We allow exactly "true" or "1" to mean true and anything else is false.
- (BOOL)readBoolContentsOfElement:(out BOOL *)outValue defaultValue:(BOOL)defaultValue error:(NSError **)outError;
{
    SIMPLE_READ_PREFIX;
    
    // Look at the contents of the const string returned before stepping futher, since it might go away!
    if (!simpleString || !*simpleString)
        *outValue = defaultValue;
    else
        *outValue = (strcmp(simpleString, "true") == 0) || (strcmp(simpleString, "1") == 0);
    
    SIMPLE_READ_SUFFIX;
}

- (BOOL)readLongContentsOfElement:(out long *)outValue defaultValue:(long)defaultValue error:(NSError **)outError;
{
    SIMPLE_READ_PREFIX;
    
    // Look at the contents of the const string returned before stepping futher, since it might go away!
    if (!simpleString || !*simpleString)
        *outValue = defaultValue;
    else {
        // Could warn if there are unused bytes.
        // TODO: strtol supports hex and octal; should we document/test those?
        *outValue = strtol(simpleString, NULL, 0);
    }

    SIMPLE_READ_SUFFIX;
}

- (BOOL)readDoubleContentsOfElement:(out double *)outValue defaultValue:(double)defaultValue error:(NSError **)outError;
{
    SIMPLE_READ_PREFIX;
    
    // Look at the contents of the const string returned before stepping futher, since it might go away!
    if (!simpleString)
        *outValue = defaultValue;
    else {
        // Could warn if there are unused bytes.
        *outValue = strtod(simpleString, NULL);
    }
    
    SIMPLE_READ_SUFFIX;
}

- (BOOL)copyDateContentsOfElement:(out NSDate **)outValue error:(NSError **)outError;
{
    NSDate *defaultValue = nil;
    
    SIMPLE_READ_PREFIX;
    
    // Look at the contents of the const string returned before stepping futher, since it might go away!
    if (!simpleString) {
        if (outValue)
            *outValue = defaultValue;
    } else {
        if (outValue)
            *outValue = [[NSDate alloc] initWithXMLCString:simpleString];
    }
    
    SIMPLE_READ_SUFFIX;
}

@end
