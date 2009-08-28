// Copyright 2003-2005, 2007-2009 Omni Development, Inc.  All rights reserved.
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
{
@private
    CFStringEncoding _encoding;
    NSString *_versionString;
    BOOL _standalone;
    NSArray *_loadWarnings;
    
    struct _OFMLParserState *_state; // Only set while parsing.
}

- (id)initWithData:(NSData *)xmlData whitespaceBehavior:(OFXMLWhitespaceBehavior *)whitespaceBehavior defaultWhitespaceBehavior:(OFXMLWhitespaceBehaviorType)defaultWhitespaceBehavior target:(NSObject <OFXMLParserTarget> *)target error:(NSError **)outError;

@property(readonly) CFStringEncoding encoding;
@property(readonly) NSString *versionString;
@property(readonly) BOOL standalone;
@property(readonly) NSArray *loadWarnings;

@property(readonly) NSUInteger elementDepth;

@end
