// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLInternedStringTable.h>
#import <OmniBase/OBUtilities.h>

@class OFXMLParser, OFXMLQName;
@class NSData, NSMutableArray, NSURL;

// This is passed to some methods in OFXMLParserTarget which may or may not want attributes (and which may want them in different formats), when there are multiple arguments. If there are zero or one arguments, nil is passed.
@protocol OFXMLParserMultipleAttributeGenerator

// In the QName case, an attribute of "xmlns:ns=someurl" is reported as an attribute with a name of "ns", a namespace of "http://www.w3.org/2000/xmlns/" and a value of "someurl". If ":ns" isn't present, the name is the empty string.
- (void)generateAttributesWithQNames:(void (^ NS_NOESCAPE)(NSMutableArray <OFXMLQName *> *qnames, NSMutableArray <NSString *> *values))receiver;

// Like -generateAttributesWithQNames:, but no arrays are generated. Instead, the block is called once for each pair.
- (void)generateAttributeQNamePairs:(void (^ NS_NOESCAPE)(OFXMLQName *attributeQName, NSString *attributeValue))receiver;

// In the plain name case, an attribute of "xmlns:ns=someurl" is reported with the name "xmlns:ns" with a value of "someurl". If ":ns" isn't present, the name is just "xmlns". The namespace on attributes is lost (though we could report "<ns:a>" or "ns:b=foo" with the prefix intact, but the prefix is open to change. Ideally everything should move toward the QName interface, but this gives a higher performance backwards compatibility path for OFXMLDocument.
- (void)generateAttributesWithPlainNames:(void (^ NS_NOESCAPE)(NSMutableArray <NSString *> *names, NSMutableDictionary <NSString *, NSString *> *values))receiver;

@end

// For the case of a single attribute, where we can potentially avoid building collections, this is passed.
@protocol OFXMLParserSingleAttributeGenerator

- (void)generateAttributeWithQName:(void (^ NS_NOESCAPE)(OFXMLQName *qname, NSString *value))receiver;
- (void)generateAttributeWithPlainName:(void (^ NS_NOESCAPE)(NSString *name, NSString *value))receiver;

@end

typedef enum {
    OFXMLParserElementBehaviorParse, // Descend into this element as normal
    OFXMLParserElementBehaviorUnparsed, // Return this entire element as an unparsed data block
    OFXMLParserElementBehaviorUnparsedReturnContentsOnly, // Return this entire element as an unparsed data block; excludes the open and close element from the data passed to -endUnparsedElementWithQName
    OFXMLParserElementBehaviorSkip, // Skip this entire element.  No start/end callbacks will occur.
} OFXMLParserElementBehavior;

@protocol OFXMLParserTarget <NSObject>
@optional

// If this returns NULL, the parser will create and free its own.  Otherwise, it will use this and not free it.
- (OFXMLInternedNameTable)internedNameTableForParser:(OFXMLParser *)parser;

- (void)parser:(OFXMLParser *)parser setSystemID:(NSURL *)systemID publicID:(NSString *)publicID;
- (void)parser:(OFXMLParser *)parser addProcessingInstructionNamed:(NSString *)piName value:(NSString *)piValue;

// Hook to allow for unparsed elements.  Everything from the "<foo>...</foo>" will be wrapped up into the unparsed element.
- (OFXMLParserElementBehavior)parser:(OFXMLParser *)parser behaviorForElementWithQName:(OFXMLQName *)name multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;

- (void)parser:(OFXMLParser *)parser startElementWithQName:(OFXMLQName *)qname multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;

- (void)parser:(OFXMLParser *)parser endElementWithQName:(OFXMLQName *)qname;
- (void)parser:(OFXMLParser *)parser endUnparsedElementWithQName:(OFXMLQName *)qname identifier:(NSString *)identifier contents:(NSData *)contents;

- (void)parser:(OFXMLParser *)parser addWhitespace:(NSString *)whitespace;
- (void)parser:(OFXMLParser *)parser addString:(NSString *)string;

// If neither -parser:addWhitespace: nor -parser:addString: are implemented and this is, then it will be called for any string content (without regard for the whitespace behavior for the current element, since the content won't have been classified as whitespace or non-whitespace yet).
- (void)parser:(OFXMLParser *)parser addCharacterBytes:(const void *)bytes length:(NSUInteger)length;

- (void)parser:(OFXMLParser *)parser addComment:(NSString *)string;

// Deprecated
- (OFXMLParserElementBehavior)parser:(OFXMLParser *)parser behaviorForElementWithQName:(OFXMLQName *)name attributeQNames:(NSMutableArray *)attributeQNames attributeValues:(NSMutableArray *)attributeValues OB_DEPRECATED_ATTRIBUTE;
- (void)parser:(OFXMLParser *)parser startElementWithQName:(OFXMLQName *)qname attributeQNames:(NSMutableArray <OFXMLQName *> *)attributeQNames attributeValues:(NSMutableArray <NSString *> *)attributeValues OB_DEPRECATED_ATTRIBUTE;

@end


@interface NSObject (OFXMLParserTargetDeprecated)
- (void)parserEndElement:(OFXMLParser *)parser OB_DEPRECATED_ATTRIBUTE;
@end
