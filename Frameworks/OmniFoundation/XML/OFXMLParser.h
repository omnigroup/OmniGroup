// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <OmniFoundation/OFXMLParserTarget.h>

/*
 A SAX-based parser interface.
 */

@interface OFXMLParser : OFObject <NSProgressReporting>

+ (NSUInteger)maximumParseChunkSize; // in bytes

- (id)init NS_UNAVAILABLE;
- (id)initWithWhitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior target:(NSObject <OFXMLParserTarget> *)target NS_DESIGNATED_INITIALIZER;
- (id)initWithData:(NSData *)xmlData whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior target:(NSObject <OFXMLParserTarget> *)target error:(NSError **)outError NS_DEPRECATED(10_0, 10_11, 2_0, 10_0);

- (BOOL)parseData:(NSData *)xmlData error:(NSError **)outError;

@property(nonatomic,readonly) CFStringEncoding encoding;
@property(nonatomic,readonly) NSString *versionString;
@property(nonatomic,readonly) BOOL standalone;
@property(nonatomic,readonly) NSArray *loadWarnings;

@property(nonatomic,readonly) NSUInteger elementDepth;

@end
