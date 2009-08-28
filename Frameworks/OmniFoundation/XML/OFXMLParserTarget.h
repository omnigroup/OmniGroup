// Copyright 2003-2005, 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFXMLInternedStringTable.h>

@class OFXMLParser, OFXMLQName;

typedef enum {
    OFXMLParserElementBehaviorParse, // Descend into this element as normal
    OFXMLParserElementBehaviorUnparsed, // Return this entire element as an unparsed data block
    OFXMLParserElementBehaviorSkip, // Skip this entire element.  No start/end callbacks will occur.
} OFXMLParserElementBehavior;

@protocol OFXMLParserTarget
@optional

// If this returns NULL, the parser will create and free its own.  Otherwise, it will use this and not free it.
- (OFXMLInternedNameTable)internedNameTableForParser:(OFXMLParser *)parser;

- (void)parser:(OFXMLParser *)parser setSystemID:(NSURL *)systemID publicID:(NSString *)publicID;
- (void)parser:(OFXMLParser *)parser addProcessingInstructionNamed:(NSString *)piName value:(NSString *)piValue;

// Hook to allow for unparsed elements.  Everything from the "<foo>...</foo>" will be wrapped up into the unparsed element.
- (OFXMLParserElementBehavior)parser:(OFXMLParser *)parser behaviorForElementWithQName:(OFXMLQName *)name attributeQNames:(NSMutableArray *)attributeQNames attributeValues:(NSMutableArray *)attributeValues;
- (void)parser:(OFXMLParser *)parser startElementWithQName:(OFXMLQName *)qname attributeQNames:(NSMutableArray *)attributeQNames attributeValues:(NSMutableArray *)attributeValues;

- (void)parserEndElement:(OFXMLParser *)parser;
- (void)parser:(OFXMLParser *)parser endUnparsedElementWithQName:(OFXMLQName *)qname contents:(NSData *)contents;

- (void)parser:(OFXMLParser *)parser addWhitespace:(NSString *)whitespace;
- (void)parser:(OFXMLParser *)parser addString:(NSString *)string;

@end
