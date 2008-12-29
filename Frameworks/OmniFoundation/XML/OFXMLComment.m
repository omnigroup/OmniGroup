// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLComment.h>

#import <OmniBase/rcsid.h>

#import <OmniFoundation/OFXMLBuffer.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/NSString-OFUnicodeCharacters.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSString-OFReplacement.h>

RCS_ID("$Id$")

// OFXMLDocument currently doesn't generate these when reading documents, though that could be done.  Currently this is just intended to allow writers to emit comments.

@implementation OFXMLComment

- initWithString:(NSString *)unquotedString;
{
    // XML comments can't contain '--' since that ends a comment.
    if ([unquotedString containsString:@"--"])
        // Replace any double-dashes with an m-dash.  Cutesy, but it'll at least be valid.
        _quotedString  = [[unquotedString stringByReplacingAllOccurrencesOfString:@"--" withString:[NSString emdashString]] copy];
    else
        _quotedString = [unquotedString copy];

    return self;
}

- (void)dealloc;
{
    [_quotedString release];
    [super dealloc];
}

#pragma mark -
#pragma mark NSObject (OFXMLWriting)

- (BOOL)appendXML:(struct _OFXMLBuffer *)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
{
    OFXMLBufferAppendString(xml, CFSTR("<!-- "));

    // Don't need to quote anything but "--" (done in initializer) and characters not representable in the target encoding.  Of course, if we do turn a character into an entity, it wouldn't get turned back when reading into a comment.
    NSString *encoded = OFXMLCreateStringInCFEncoding(_quotedString, [doc stringEncoding]);
    if (encoded) {
        OFXMLBufferAppendString(xml, (CFStringRef)encoded);
        [encoded release];
    }
    
    OFXMLBufferAppendString(xml, CFSTR(" -->"));
    return YES;
}

#pragma mark -
#pragma mark Comparison

- (BOOL)isEqual:(id)otherObject;
{
    OBPRECONDITION([otherObject isKindOfClass:[OFXMLComment class]]);
    if (![otherObject isKindOfClass:[OFXMLComment class]])
        return NO;
    OFXMLComment *otherComment = otherObject;
    
    return OFISEQUAL(_quotedString, otherComment->_quotedString);
}

@end
