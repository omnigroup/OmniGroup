// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

#import <OmniFoundation/OFXMLInternedStringTable.h>

@class NSURL, NSInputStream;
@class OFXMLQName;

@interface OFXMLReader : OFObject
{
    NSURL *_url;
    NSInputStream *_inputStream;
    struct _xmlParserInputBuffer *_inputBuffer;
    struct _xmlTextReader *_reader;
    OFXMLInternedNameTable _nameTable;
    
    int _currentNodeType; // xmlReaderTypes
    BOOL _inEmptyElement; // Allow 'opening' a empty element
    
    NSMutableArray *_errors; // Accumulated from the input stream and structured error handler.
}

- initWithInputStream:(NSInputStream *)inputStream startingInternedNames:(OFXMLInternedNameTable)startingInternedNames error:(NSError **)outError;

- initWithData:(NSData *)data startingInternedNames:(OFXMLInternedNameTable)startingInternedNames error:(NSError **)outError;
- initWithData:(NSData *)data error:(NSError **)outError;

- initWithURL:(NSURL *)url startingInternedNames:(OFXMLInternedNameTable)startingInternedNames error:(NSError **)outError;
- initWithURL:(NSURL *)url error:(NSError **)outError;

@property (nonatomic,readonly) NSURL *url;

- (OFXMLQName *)elementQName; // If on an element, return it's name.  Otherwise, nil.

- (BOOL)openElement:(NSError **)outError; // If on an element, skip to its first child
- (BOOL)closeElement:(NSError **)outError; // Skip the remaining children of an element and its closing mark.

// Skips peers of the current read point until the beginning of an element is hit.  Returns its name in *outElementName if outElementName is non-NULL.  If no element is found before the end of the containing block, YES will be returned, but with a nil *outElementName.  If there is an error, NO will be returned and the error indicated in *outError.
- (BOOL)findNextElement:(OFXMLQName **)outElementName error:(NSError **)outError;

// Expects to be called with the reader pointing at an element.  If it isn't, this will return YES without doing anything but asserting.  Otherwise, this skips the entire element and all its children, or returns an error.
- (BOOL)skipCurrentElement:(NSError **)outError;

// Skips the current and any immediately following readable string nodes (text, CDATA, or whitespace), returning them as a single plain text string by reference if outString is non-NULL. If outElementEnded is non-NULL, additionally returns by reference whether the text reading placed the reader at the end of an element.
- (BOOL)copyString:(__strong NSString **)outString endingElement:(BOOL *)outElementEnded error:(NSError **)outError;

// Skips past the string to the the end of the element, returning it by reference if outString is non-NULL
- (BOOL)copyStringContentsToEndOfElement:(__strong NSString **)outString error:(NSError **)outError;

// Attributes.
- (BOOL)copyValueOfAttribute:(__strong NSString **)outString named:(OFXMLQName *)name error:(NSError **)outError;
- (BOOL)copyAttributes:(__strong NSDictionary **)outAttributes error:(NSError **)outError;
- (BOOL)copyNamespaceDeclarations:(__strong NSDictionary **)outPrefixToNamespaceURLString error:(NSError **)outError;

// Expects to be called with the reader pointing at an element. Reads the entire element into a new data and returns it, or returns and empty data if not pointing an an element.
- (NSData *)copyUTF8ElementData:(NSError **)outError;


// Simple value readers

// Reads the string contents of the element as the given type.  Returns the default value if there is no string content.
- (BOOL)readBoolContentsOfElement:(out BOOL *)outValue defaultValue:(BOOL)defaultValue error:(NSError **)outError;
- (BOOL)readLongContentsOfElement:(out long *)outValue defaultValue:(long)defaultValue error:(NSError **)outError;
- (BOOL)readDoubleContentsOfElement:(out double *)outValue defaultValue:(double)defaultValue error:(NSError **)outError;

- (BOOL)copyDateContentsOfElement:(out __strong NSDate **)outDate error:(NSError **)outError;

@end
