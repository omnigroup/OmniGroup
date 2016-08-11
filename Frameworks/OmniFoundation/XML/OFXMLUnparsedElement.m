// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLUnparsedElement.h>

#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <OmniFoundation/OFXMLBuffer.h>
#import <OmniFoundation/OFXMLQName.h>

RCS_ID("$Id$")

@implementation OFXMLUnparsedElement

// The data is always UTF-8 right now.
- initWithQName:(OFXMLQName *)qname identifier:(NSString *)identifier data:(NSData *)data; 
{
    if (!(self = [super init]))
        return nil;
    _qname = [qname copy];
    _identifier = [identifier copy];
    _data = [data copy];
    return self;
}

- (void)dealloc;
{
    [_qname release];
    [_identifier release];
    [_data release];
    [super dealloc];
}

// Needed for -[OFXMLElement firstChildNamed:]
- (NSString *)name;
{
    return [_qname name];
}

- (BOOL)appendXML:(struct _OFXMLBuffer *)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
{
    OFXMLBufferAppendUTF8Data(xml, (__bridge CFDataRef)_data);
    return YES;
}

- (BOOL)xmlRepresentationCanContainChildren;
{
    return YES;
}

#pragma mark -
#pragma mark Comparison

- (BOOL)isEqual:(id)otherObject;
{
    // This means we don't consider OFXMLElement and OFXMLUnparsedElement the same, even if they would produce the same output. Not sure if this is a bug; let's catch this case here to see if it ever hits.
    OBPRECONDITION([otherObject isKindOfClass:[OFXMLUnparsedElement class]]);
    if (![otherObject isKindOfClass:[OFXMLUnparsedElement class]])
        return NO;
    
    OFXMLUnparsedElement *otherElement = otherObject;

    return OFISEQUAL(_qname, otherElement->_qname) && OFISEQUAL(_identifier, otherElement->_identifier) && OFISEQUAL(_data, otherElement->_data); // data contains the qname and id too, but the id can be an early out.
}

@end
