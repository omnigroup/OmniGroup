// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

#import <Foundation/NSStream.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <OmniFoundation/OFXMLParserTarget.h>

/*
 A SAX-based parser interface.
 */

NS_ASSUME_NONNULL_BEGIN

@interface OFXMLParser : OFObject <NSProgressReporting>

@property (class, nonatomic, readonly) NSUInteger defaultMaximumParseChunkSize; // in bytes

- (id)init NS_UNAVAILABLE;
- (id)initWithWhitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior target:(id <OFXMLParserTarget>)target NS_DESIGNATED_INITIALIZER;
- (id)initWithData:(NSData *)xmlData whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior target:(id <OFXMLParserTarget>)target error:(NSError **)outError NS_DEPRECATED(10_0, 10_11, 2_0, 10_0);

- (OFXMLQName *)getQNameWithNamespace:(NSString *)namespaceString name:(NSString *)nameString;

- (BOOL)parseData:(NSData *)xmlData error:(NSError **)outError;
- (BOOL)parseInputStream:(NSInputStream *)inputStream error:(NSError **)outError;
- (BOOL)parseInputStream:(NSInputStream *)inputStream expectedStreamLength:(NSUInteger)expectedStreamLength error:(NSError **)outError;

// During the parse, the target can be replaced with a different objects specialized for parsing different portions of the document.
@property(nonatomic,assign) id <OFXMLParserTarget> target;

@property (nonatomic) BOOL parseComments;
@property (nonatomic, readonly) NSUInteger maximumParseChunkSize; // in bytes

@property(nonatomic, readonly) CFStringEncoding encoding;
@property(nonatomic, nullable, readonly) NSString *versionString;
@property(nonatomic, readonly) BOOL standalone;
@property(nonatomic, nullable, readonly) NSArray *loadWarnings;

@property(nonatomic, readonly) NSUInteger elementDepth;

@end

NS_ASSUME_NONNULL_END
