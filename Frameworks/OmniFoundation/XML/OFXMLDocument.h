// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFXMLIdentifierRegistry.h>

#import <CoreFoundation/CFURL.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <OmniFoundation/OFXMLParserTarget.h>

NS_ASSUME_NONNULL_BEGIN

@class OFXMLCursor, OFXMLElement, OFXMLWhitespaceBehavior;
@class NSArray, NSMutableArray, NSDate, NSData, NSURL, NSError, NSInputStream;

@interface OFXMLDocument : OFXMLIdentifierRegistry <OFXMLParserTarget>

- (instancetype)init NS_UNAVAILABLE;
- (id)initWithRegistry:(OFXMLIdentifierRegistry *)registry NS_UNAVAILABLE;

- (nullable instancetype)initWithRootElement:(OFXMLElement *)rootElement
          dtdSystemID:(nullable CFURLRef)dtdSystemID
          dtdPublicID:(nullable NSString *)dtdPublicID
   whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior
       stringEncoding:(CFStringEncoding)stringEncoding
                error:(NSError **)outError NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithRootElementName:(NSString *)rootElementName
              dtdSystemID:(nullable CFURLRef)dtdSystemID
              dtdPublicID:(nullable NSString *)dtdPublicID
       whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior
           stringEncoding:(CFStringEncoding)stringEncoding
                    error:(NSError **)outError;

- (nullable instancetype)initWithRootElementName:(NSString *)rootElementName
             namespaceURL:(nullable NSURL *)rootElementNameSpace
       whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior
           stringEncoding:(CFStringEncoding)stringEncoding
                    error:(NSError **)outError;

- (nullable instancetype)initWithContentsOfFile:(NSString *)path whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior error:(NSError **)outError;

// xmlData marked nullable for testing purposes. This will return a nil document.
- (nullable instancetype)initWithData:(NSData *)xmlData whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior error:(NSError **)outError;
- (nullable instancetype)initWithData:(NSData *)xmlData whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior error:(NSError **)outError;
- (nullable instancetype)initWithInputStream:(NSInputStream *)inputStream whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior error:(NSError **)outError;
- (nullable instancetype)initWithInputStream:(NSInputStream *)inputStream whitespaceBehavior:(nullable OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior error:(NSError **)outError NS_DESIGNATED_INITIALIZER;

@property(nonatomic,readonly) OFXMLWhitespaceBehavior *whitespaceBehavior;
@property(nonatomic,readonly,nullable) CFURLRef dtdSystemID;
@property(nonatomic,readonly,nullable) NSString *dtdPublicID;
@property(nonatomic,readonly) CFStringEncoding stringEncoding;

@property(nonatomic,nullable,readonly) NSArray *loadWarnings;

- (nullable NSData *)xmlData:(NSError **)outError;
- (nullable NSData *)xmlDataWithDefaultWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhiteSpaceBehavior error:(NSError **)outError;
- (nullable NSData *)xmlDataAsFragment:(NSError **)outError;
- (nullable NSData *)xmlDataForElements:(NSArray *)elements asFragment:(BOOL)asFragment error:(NSError **)outError;
- (nullable NSData *)xmlDataForElements:(NSArray *)elements asFragment:(BOOL)asFragment defaultWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhiteSpaceBehavior startingLevel:(unsigned int)level error:(NSError **)outError;

- (BOOL)writeToFile:(NSString *)path error:(NSError **)outError;

@property(nonatomic,readonly) NSUInteger processingInstructionCount;
- (NSString *)processingInstructionNameAtIndex:(NSUInteger)piIndex;
- (NSString *)processingInstructionValueAtIndex:(NSUInteger)piIndex;
- (void)addProcessingInstructionNamed:(NSString *)piName value:(NSString *)piValue;

@property(nonatomic,readonly) OFXMLElement *rootElement;

// User objects
- (id)userObjectForKey:(NSString *)key;
- (void)setUserObject:(id)object forKey:(NSString *)key;

// Writing conveniences
- (OFXMLElement *) pushElement: (NSString *) elementName;
- (void) popElement;
- (void) addElement:(NSString *)elementName childBlock:(void (^)(void))block;

@property(nonatomic,readonly) OFXMLElement *topElement;
- (void) appendString: (NSString *) string;
- (void) appendString: (NSString *) string quotingMask: (unsigned int) quotingMask newlineReplacment: (NSString *) newlineReplacment;
- (void) setAttribute: (NSString *) name string: (nullable NSString *) value;
- (void) setAttribute: (NSString *) name value: (nullable id) value;
- (void) setAttribute: (NSString *) name integer: (int) value;
- (void) setAttribute: (NSString *) name real: (float) value;  // "%g"
- (void) setAttribute: (NSString *) name real: (float) value format: (NSString *) formatString;
- (void) setAttribute: (NSString *) name double: (double) value;  // "%.15g"
- (void) setAttribute: (NSString *) name double: (float) value format: (NSString *) formatString;
- (OFXMLElement *)appendElement:(NSString *)elementName;
- (OFXMLElement *)appendElement:(NSString *)elementName containingString:(NSString *) contents;
- (OFXMLElement *)appendElement:(NSString *)elementName containingInteger:(int) contents;
- (OFXMLElement *)appendElement:(NSString *)elementName containingReal:(float) contents; // "%g"
- (OFXMLElement *)appendElement:(NSString *)elementName containingReal:(float) contents format:(NSString *)formatString;
- (OFXMLElement *)appendElement:(NSString *)elementName containingDouble:(double) contents; // "%.15g"
- (OFXMLElement *)appendElement:(NSString *)elementName containingDouble:(double) contents format:(NSString *) formatString;
- (OFXMLElement *)appendElement:(NSString *)elementName containingDate:(NSDate *)date; // XML Schema / ISO 8601.

// Reading conveniences
- (OFXMLCursor *)cursor;

// Partial OFXMLParserTarget
- (void)parser:(OFXMLParser *)parser setSystemID:(NSURL *)systemID publicID:(NSString *)publicID;
- (void)parser:(OFXMLParser *)parser addProcessingInstructionNamed:(NSString *)piName value:(NSString *)piValue;
- (void)parser:(OFXMLParser *)parser startElementWithQName:(OFXMLQName *)qname multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;
- (void)parser:(OFXMLParser *)parser addWhitespace:(NSString *)whitespace;
- (void)parser:(OFXMLParser *)parser addString:(NSString *)string;
- (void)parserEndElement:(OFXMLParser *)parser;
- (void)parser:(OFXMLParser *)parser endUnparsedElementWithQName:(OFXMLQName *)qname identifier:(NSString *)identifier contents:(NSData *)contents;

@end

NS_ASSUME_NONNULL_END
