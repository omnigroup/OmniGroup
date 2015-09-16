// Copyright 2003-2015 Omni Development, Inc. All rights reserved.
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

@interface OFXMLParser : OFObject

- (id)initWithData:(NSData *)xmlData whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior target:(NSObject <OFXMLParserTarget> *)target error:(NSError **)outError;

@property(nonatomic,readonly) CFStringEncoding encoding;
@property(nonatomic,readonly) NSString *versionString;
@property(nonatomic,readonly) BOOL standalone;
@property(nonatomic,readonly) NSArray *loadWarnings;

@property(nonatomic,readonly) NSUInteger elementDepth;

@end
