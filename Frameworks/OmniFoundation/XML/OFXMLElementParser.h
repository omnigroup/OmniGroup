// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <OmniFoundation/OFXMLParserTarget.h>

@class OFXMLElement, OFXMLElementParser;

NS_ASSUME_NONNULL_BEGIN

// OFXMLElementParser can be used to parse a sub-tree of an XML document into generic OFXMLElement instances.

@protocol OFXMLElementParserDelegate <NSObject>
- (void)elementParser:(OFXMLElementParser *)elementParser parser:(OFXMLParser *)parser parsedElement:(OFXMLElement *)element;
- (OFXMLParserElementBehavior)elementParser:(OFXMLElementParser *)elementParser behaviorForElementWithQName:(OFXMLQName *)name multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;
@end

@interface OFXMLElementParser : NSObject <OFXMLParserTarget>

// This is strong since it gets looked up many times during a parse, and each lookup of a weak variable introduces a -retain and -autorelease.
@property(nonatomic,nullable,strong) id <OFXMLElementParserDelegate> delegate;

// Partial OFXMLParserTarget
- (void)parser:(OFXMLParser *)parser startElementWithQName:(OFXMLQName *)qname multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;
- (void)parser:(OFXMLParser *)parser addWhitespace:(NSString *)whitespace;
- (void)parser:(OFXMLParser *)parser addString:(NSString *)string;
- (void)parser:(OFXMLParser *)parser addComment:(NSString *)string;
- (void)parser:(OFXMLParser *)parser endElementWithQName:(OFXMLQName *)qname;

- (OFXMLParserElementBehavior)parser:(OFXMLParser *)parser behaviorForElementWithQName:(OFXMLQName *)name multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;
- (void)parser:(OFXMLParser *)parser endUnparsedElementWithQName:(OFXMLQName *)qname identifier:(NSString *)identifier contents:(NSData *)contents;

@end

NS_ASSUME_NONNULL_END
